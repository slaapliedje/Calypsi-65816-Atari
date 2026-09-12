#!/usr/bin/env python3
"""ELF -> Atari executable (.xex), for Calypsi's 65816 linker output.

ln65816 emits ELF with DWARF and has no Atari output format.  This walks
the program headers and writes the Atari segmented binary:

    $FFFF                       the file magic, once
    <start> <end> <data...>     one per loadable segment; the end is INCLUSIVE
    $02E2 $02E3 <addr>          INITAD: DOS calls here after loading the segment
    $02E0 $02E1 <addr>          RUNAD:  DOS jumps here when the load is complete

Only PT_LOAD segments with bytes in the file are written; a segment with
p_filesz == 0 is bss, and the startup zeroes it.

FAR SEGMENTS

A .xex segment header is two 16-bit addresses, so a DOS loader cannot put
anything above $FFFF -- and a program linked with linker-files/atari-far.scm
has its code in banks $01 and up.  Those segments travel as CHUNKS: each is
aimed at a staging buffer in bank $00 and followed by a two-byte segment
that writes INITAD, which makes the DOS call the copier in src/farload.s.
The copier moves the chunk to its real home and returns.  When the DOS
reaches the run vector the far image is in place.

The staging buffer is the program's stack block: RAM nothing touches until
the startup sets S.  farload.s exports its address and size as data, the
two words at _fl_layout, and this script reads them out of the image
rather than restating the choice.  The first four bytes of the buffer
are the chunk's header -- a 24-bit destination and a length in pages --
and the payload follows.

Every chunk is a whole number of 256-byte pages, which is what lets the
copier be a flat page loop.  The tail of a segment is made whole by sliding
the last chunk BACKWARDS onto a page boundary, recopying a few bytes that
the previous chunk already placed.  Padding forwards would write past the
segment's end into whatever is next.

INITAD is rewritten after every chunk rather than once, because DOSes
disagree about whether it is called after every segment or only after one
that writes to it; per chunk is correct under both readings, and the copier
zeroes the length field when it is done, so an extra call does nothing.
The very first segment of the file zeroes that header, in case INITAD is
still pointing at the copier from a previous run of the same program.

Usage: mkxex.py in.elf out.xex [--entry SYMBOL] [--syms out.sym]

--syms writes "NAME ADDR" lines for every symbol, for a test harness that
wants to find things by name.
"""
import struct
import sys

PT_LOAD = 1
RUNAD, INITAD = 0x02E0, 0x02E2


def read_elf(path):
    """Return (list of (vaddr, bytes), {symbol: value}) from a 32-bit LE ELF."""
    with open(path, "rb") as f:
        d = f.read()
    if d[:4] != b"\x7fELF":
        raise SystemExit(f"{path}: not an ELF file")
    if d[4] != 1 or d[5] != 1:
        raise SystemExit(f"{path}: expected a 32-bit little-endian ELF")

    e_shoff, = struct.unpack_from("<I", d, 0x20)
    e_phoff, = struct.unpack_from("<I", d, 0x1C)
    e_phentsize, e_phnum = struct.unpack_from("<HH", d, 0x2A)
    e_shentsize, e_shnum, _shstrndx = struct.unpack_from("<HHH", d, 0x2E)

    segs = []
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        p_type, p_offset, p_vaddr, _pa, p_filesz, _memsz = struct.unpack_from("<6I", d, o)
        if p_type == PT_LOAD and p_filesz > 0:
            segs.append((p_vaddr, d[p_offset:p_offset + p_filesz]))

    syms = {}
    for i in range(e_shnum):
        o = e_shoff + i * e_shentsize
        sh_type, = struct.unpack_from("<I", d, o + 4)
        if sh_type != 2:                                  # SHT_SYMTAB
            continue
        sh_offset, sh_size, sh_link, _info, _align, sh_entsize = struct.unpack_from(
            "<6I", d, o + 16)
        stro = e_shoff + sh_link * e_shentsize
        str_off, str_size = struct.unpack_from("<II", d, stro + 16)
        strtab = d[str_off:str_off + str_size]
        for j in range(sh_size // sh_entsize):
            so = sh_offset + j * sh_entsize
            st_name, st_value = struct.unpack_from("<II", d, so)
            end = strtab.find(b"\0", st_name)
            name = strtab[st_name:end].decode("ascii", "replace")
            if name:
                syms.setdefault(name, st_value)
    return segs, syms


def seg(addr, data):
    """One .xex segment: start, INCLUSIVE end, bytes."""
    return struct.pack("<HH", addr, addr + len(data) - 1) + data


def image_bytes(segs, addr, n):
    """The n bytes at addr, out of whichever loaded segment holds them."""
    for vaddr, data in segs:
        if vaddr <= addr and addr + n <= vaddr + len(data):
            return data[addr - vaddr:addr - vaddr + n]
    raise SystemExit(f"${addr:06X} is not inside any loaded segment")


def far_chunks(vaddr, data, chunk):
    """Split a far segment into whole-page pieces no bigger than chunk."""
    n = len(data)
    off = 0
    while off < n:
        rem = n - off
        if rem >= chunk:
            yield vaddr + off, data[off:off + chunk]
            off += chunk
            continue
        take = (rem + 255) & ~0xFF
        if take <= n:
            start = n - take
            yield vaddr + start, data[start:]
        else:
            # Shorter than one page in all: nothing to slide back into.
            # Pad, and let the caller police the overrun.
            yield vaddr + off, data[off:] + b"\x00" * (take - rem)
        off = n


def stage_far(far, segs, syms):
    """Chunk the far image into staging segments plus INITAD triggers."""
    for name in ("_fl_layout", "_fl_copy"):
        if name not in syms:
            raise SystemExit(
                f"far segments need src/farload.s linked in; {name} is missing")
    buf, size = struct.unpack("<HH", image_bytes(segs, syms["_fl_layout"], 4))
    copier = syms["_fl_copy"]
    chunk = (size - 4) & ~0xFF
    if chunk < 256:
        raise SystemExit(
            f"the stack block is {size} bytes; the staging buffer needs 260 or more")

    starts = sorted(a for a, _ in far)
    out = bytearray()
    for vaddr, data in far:
        for dst, piece in far_chunks(vaddr, data, chunk):
            over = dst + len(piece)
            if over > vaddr + len(data):
                clash = [a for a in starts if vaddr + len(data) <= a < over]
                if clash:
                    raise SystemExit(
                        f"padding ${vaddr:06X} would overwrite ${clash[0]:06X}")
            out += seg(buf, struct.pack("<HBB", dst & 0xFFFF, dst >> 16,
                                        len(piece) // 256) + piece)
            out += seg(INITAD, struct.pack("<H", copier))
    return bytes(out), buf, chunk


def build_xex(segs, entry, syms):
    near, far = [], []
    for vaddr, data in sorted(segs):
        end = vaddr + len(data) - 1
        if end <= 0xFFFF:
            near.append((vaddr, data))
        elif vaddr > 0xFFFF:
            far.append((vaddr, data))
        else:
            raise SystemExit(
                f"segment ${vaddr:06X}-${end:06X} straddles the bank $00 boundary")

    out = bytearray(b"\xff\xff")
    staged, buf, chunk = b"", None, 0
    if far:
        staged, buf, chunk = stage_far(far, near, syms)
        out += seg(buf, b"\x00" * 4)       # a clean header before anything else
    for vaddr, data in near:
        out += seg(vaddr, data)
    out += staged
    out += seg(RUNAD, struct.pack("<H", entry))
    return bytes(out), near, far, buf, chunk


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__.strip().splitlines()[-4])
    src, dst = argv[0], argv[1]
    want = "__program_start"
    if "--entry" in argv:
        want = argv[argv.index("--entry") + 1]

    segs, syms = read_elf(src)
    if want not in syms:
        raise SystemExit(f"{src}: entry symbol {want!r} not found")
    if syms[want] > 0xFFFF:
        raise SystemExit(
            f"{src}: {want!r} is at ${syms[want]:06X}; the DOS's run vector is "
            f"16-bit, so the entry point has to be in bank $00")
    entry = syms[want]

    xex, near, far, buf, chunk = build_xex(segs, entry, syms)
    with open(dst, "wb") as f:
        f.write(xex)

    if "--syms" in argv:
        path = argv[argv.index("--syms") + 1]
        with open(path, "w") as f:
            for name in sorted(syms):
                f.write(f"{name} {syms[name]:06X}\n")

    print(f"{dst}: {len(xex)} bytes, run ${entry:04X} ({want})")
    for vaddr, data in near:
        print(f"    ${vaddr:04X}-${vaddr + len(data) - 1:04X}  {len(data):6d} bytes")
    for vaddr, data in far:
        print(f"  ${vaddr:06X}-${vaddr + len(data) - 1:06X}  {len(data):6d} bytes  "
              f"staged through ${buf:04X}")
    if far:
        farb = sum(len(d) for _, d in far)
        print(f"    {farb} bytes copied up in {-(-farb // chunk)} chunk(s) of {chunk}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
