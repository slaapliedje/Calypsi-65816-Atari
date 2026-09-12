#!/usr/bin/env python3
"""Run a test .xex on an emulated Atari with a Rapidus, headlessly.

    python3 test/run-altirra.py obj/hello-sc.xex [obj/hello-lc.xex ...]

Needs AltirraSDL (https://github.com/ilmenit/AltirraSDL) with its bridge;
ALTIRRASDL names the binary if it is not on PATH.  No DOS disk: the
emulator's own loader runs the .xex at boot (--run), the script then
switches the Rapidus to its 65C816 through the PBI registers -- which
resets the machine, exactly as the startup would have done itself -- and
the loader runs the program again, on the '816 this time.

What passes: the program's mark at $0600 -- "OK" and the sum for hello,
"RW" and matching pass/total counts for readwrite -- its text on the
screen, a CPU that HWSTATE reports as a 65C816, and a clean return to
the OS after RETURN.  A screenshot goes next to the .xex.

The emulator's H: host device is mounted on the .xex's .run directory,
so readwrite needs no DOS disk either: its files appear there.
"""
import base64
import glob
import json
import os
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import mkxex  # noqa: E402  the packer: it knows which bytes went far

ALTIRRA = os.environ.get("ALTIRRASDL", "AltirraSDL")
MACHINE = ["--pal", "--hardware", "800xl", "--nobasic", "--nofastboot",
           "--cleardevices", "--adddevice", "rapidus"]
MARKS = (b"OK", b"RW")


class Bridge:
    def __init__(self, run_dir, timeout=60):
        t0 = time.time()
        addr = tok = None
        while time.time() - t0 < timeout and not addr:
            for f in glob.glob(os.path.join(run_dir, "*bridge*.token")):
                lines = open(f, errors="ignore").read(512).splitlines()
                if len(lines) >= 2 and lines[0].startswith("unix:"):
                    addr, tok = lines[0].strip(), lines[1].strip()
            time.sleep(0.3)
        if not addr:
            raise RuntimeError(f"no bridge token in {run_dir}")
        while True:
            try:
                self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.s.settimeout(600)
                self.s.connect(addr[5:])
                break
            except OSError:
                if time.time() - t0 > timeout:
                    raise
                time.sleep(0.5)
        self.f = self.s.makefile("rwb")
        if not self.cmd(f"HELLO {tok}").get("ok"):
            raise RuntimeError("the bridge refused the token")

    def cmd(self, line):
        self.f.write((line + "\n").encode())
        self.f.flush()
        resp = self.f.readline().decode().strip()
        try:
            return json.loads(resp)
        except json.JSONDecodeError:
            return {"ok": False, "raw": resp}

    def ok(self, line):
        r = self.cmd(line)
        if not r.get("ok"):
            raise RuntimeError(f"{line} -> {r}")
        return r

    def frames(self, n):
        while n > 0:
            step = min(n, 250)
            self.ok(f"FRAME {step}")
            n -= step

    def memdump(self, addr, length):
        return base64.b64decode(self.ok(f"MEMDUMP ${addr:04X} {length}")["data"])

    def poke(self, addr, value):
        self.ok(f"POKE ${addr:04X} ${value:02X}")


def screen_text(b, rows=24):
    """The E: screen as text: SAVMSC points at 40-column rows of ANTIC's
    internal character codes, which are ATASCII with the first two 64-blocks
    swapped.  Inverse video is dropped."""
    sm = b.memdump(0x58, 2)
    base = sm[0] | sm[1] << 8
    raw = b.memdump(base, 40 * rows)
    out = []
    for r in range(rows):
        row = ""
        for c in raw[r * 40:(r + 1) * 40]:
            c &= 0x7F
            if c < 64:
                row += chr(c + 32)
            elif c < 96:
                row += "."          # a control character in ATASCII
            else:
                row += chr(c)
        out.append(row.rstrip())
    return out


def far_image(xex):
    """The far segments of the ELF the .xex was packed from, if it is there:
    [(address, bytes)], empty for a bank-$00-only program."""
    elf = os.path.splitext(xex)[0] + ".elf"
    if not os.path.exists(elf):
        return []
    segs, _ = mkxex.read_elf(elf)
    return [(a, d) for a, d in segs if a > 0xFFFF]


def far_samples(far):
    """Addresses to read back: the first and last byte of every chunk-sized
    stretch -- the seams are where a copier goes wrong -- and a spread of
    the rest.  EVAL reads one far byte per round trip, so a sweep is out."""
    out = []
    for base, data in far:
        end = base + len(data)
        step = max(256, len(data) // 24)
        a = base
        while a < end:
            out.append(a)
            out.append(min(end, a + step) - 1)
            a += step
        out.append(end - 1)
    return sorted(set(out))


def run_one(xex):
    xex = os.path.abspath(xex)
    far = far_image(xex)
    run_dir = os.path.splitext(xex)[0] + ".run"
    os.makedirs(run_dir, exist_ok=True)
    for f in glob.glob(os.path.join(run_dir, "*")):
        os.remove(f)
    sock = os.path.join(run_dir, "emu.sock")
    env = dict(os.environ, SDL_VIDEODRIVER="offscreen", SDL_AUDIODRIVER="dummy",
               TMPDIR=run_dir)
    args = [ALTIRRA, f"--bridge=unix:{sock}", *MACHINE,
            "--adddevice", f"hostfs,readonly=false,path1={run_dir}"]
    log = open(os.path.join(run_dir, "altirra.log"), "w")
    proc = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT, cwd=run_dir)
    try:
        b = Bridge(run_dir)
        # Nothing is left to real time: the emulator runs only when FRAME
        # says so.  BOOT is the emulator's own .xex loader (what --run does),
        # armed by a cold reset and fired once the OS has booted.  Between
        # the two the Rapidus is switched to its 65C816 through the PBI
        # registers, exactly as the startup does when it finds itself on
        # the 6502 -- that resets the CPU, the OS boots again, and the
        # loader runs the program on the 65C816.  Switched by the program
        # itself instead, the reset would come after the loader's one
        # shot, and a DOS is what would run the program a second time.
        b.ok("PAUSE")
        b.ok(f"BOOT {xex}")
        b.frames(2)
        b.poke(0xD1FF, 1)
        b.poke(0xD191, 0)
        b.frames(1)
        cpu = b.ok("HWSTATE").get("cpu", {})

        mark = b""
        for _ in range(40):
            b.frames(25)
            mark = b.memdump(0x0600, 5)
            if mark[:2] in MARKS:
                break
        lines = screen_text(b)
        b.ok(f"SCREENSHOT path={os.path.join(run_dir, 'screen.png')}")
        # The far image, read back from the banks the copier wrote.
        far_bad = []
        for a in far_samples(far):
            want = next(d[a - base] for base, d in far if base <= a < base + len(d))
            got = b.ok(f"EVAL db(${a:06x})").get("value")
            if got != want:
                far_bad.append((a, want, got))
        # stdin: the program is inside E:'s line editor, keyboard IRQ on.
        b.ok("KEY RETURN")
        b.frames(10)
        key = b.memdump(0x0604, 1)[0]
        # The exit stub's rts lands in the loader, which hands the machine
        # back to the OS: no DOS here, so that is the memo pad, a second
        # or two later.
        after = ""
        for _ in range(8):
            b.frames(25)
            after = screen_text(b, 2)[0]
            if "MEMO PAD" in after:
                break
        b.cmd("QUIT")
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    text = "\n".join(l for l in lines if l)
    print(f"--- {os.path.basename(xex)}")
    print(text)
    print(f"    mark at $0600: {mark.hex(' ')}   key: ${key:02X}   cpu: {cpu}")
    print(f"    after exit: {after!r}")
    if far:
        n = sum(len(d) for _, d in far)
        print(f"    far image: {n} bytes in {len(far)} segment(s), "
              f"{len(far_samples(far))} bytes sampled, {len(far_bad)} wrong")
    problems = []
    if mark[:2] == b"OK":
        if mark[2] | mark[3] << 8 != 385:
            problems.append(f"the sum came out as {mark[2] | mark[3] << 8}, not 385")
        if "Hello from Calypsi" not in text:
            problems.append("the greeting is not on the screen")
        if "= 385" not in text:
            problems.append("the sum is not on the screen")
    elif mark[:2] == b"RW":
        if mark[2] != mark[3] or mark[3] == 0:
            problems.append(f"readwrite: {mark[2]}/{mark[3]} checks passed")
        if f"readwrite: {mark[2]}/{mark[3]} passed" not in text:
            problems.append("the readwrite summary is not on the screen")
    else:
        problems.append("no OK/RW mark at $0600")
    if cpu.get("mode") != "65C816":
        problems.append(f"HWSTATE does not report a 65C816: {cpu}")
    if key != 0x0A:
        problems.append(f"getchar() returned ${key:02X}, not '\\n' for RETURN")
    if "MEMO PAD" not in after:
        problems.append("the program did not return to the OS after RETURN")
    for a, want, got in far_bad[:5]:
        problems.append(f"far byte ${a:06X} is {got!r}, the image says ${want:02X}")
    for p in problems:
        print(f"    FAIL: {p}")
    print("    PASS" if not problems else "")
    return not problems


def main(argv):
    if not argv:
        raise SystemExit(__doc__.strip().splitlines()[2])
    results = [run_one(x) for x in argv]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
