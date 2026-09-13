# Calypsi board support for the Atari XL/XE with a 65C816

Startup, linker files, C library stubs and an executable packer for
running C built with the [Calypsi 65816 tool chain](https://www.calypsi.cc)
on an Atari 8-bit computer fitted with a 65C816 accelerator.  The
Rapidus is what it has been developed and tested on (Altirra emulates
it); the package looks for the card and switches the CPU itself, so a
program boots straight from a DOS on a machine that came up as a 6502.
The CPU is identified first, and a plain 6502 machine is told what it
needs and handed back rather than crashed.

Two libraries are built, for the two code models, both with the small
data model -- the Atari's OS, DOS and hardware are all in bank `$00`,
and that is where a small-model program's plain pointers point:

    atari-sc-sd.a    --code-model=small    everything in bank $00
    atari-lc-sd.a    --code-model=large    code in banks $01 and up

The large model is for an accelerator with RAM above bank `$00`.  The
`.xex` format cannot load there, so the far code travels as chunks that
a small copier moves up during the load; see *Far code* below.

## Requirements

- Calypsi 65816, 5.18 or later.  `make` finds it on `PATH`, or
  `make CALYPSI=/path/to/calypsi-65816/bin/`.
- Python 3 for `tools/mkxex.py`.
- To run the tests: [AltirraSDL](https://github.com/ilmenit/AltirraSDL)
  with its bridge, `main` from 46567a14 or later (the 65C816 native-mode
  fixes from pull requests #88 and #90 are in by then).  `ALTIRRASDL`
  names the binary if it is not on `PATH`.  The file test writes through
  the emulator's H: host device, which on Linux needs one more fix,
  sent as [#91](https://github.com/ilmenit/AltirraSDL/pull/91) and
  carried here as `test/altirra-sdl-hostfs-posix-paths.patch` until it
  lands (the emulator joins host paths with a backslash).

No DOS disk, OS ROM or other firmware is needed for the tests: the
emulator boots its own OS and runs the `.xex` through its own loader.

## Usage

    make            # the two libraries
    make test       # the test programs, as .xex
    make check      # ...run under AltirraSDL

Compile with `--core=65816 --data-model=small` and either code model,
link with the matching library, the matching linker file and the
runtime attributes that select this package's startup and stubs, then
pack the ELF into an Atari executable:

    cc65816 --core=65816 --code-model=large --data-model=small -Iinclude -O2 -o main.o main.c
    ln65816 --rtattr cstartup=atari --rtattr stubs=atari --hosted \
            -o prog.elf main.o atari-lc-sd.a clib-lc-sd.a linker-files/atari-far.scm
    python3 tools/mkxex.py prog.elf PROG.XEX

For the small code model use `atari-sc-sd.a`, `clib-sc-sd.a` and
`linker-files/atari-plain.scm`.  The package's library must come before
`clib-*.a` on the link line (see *Known tool chain issues*).

`include/atari/` has the OS variables and CIO as C sees them
(`atari.h`), the chips (`antic.h gtia.h pokey.h pia.h`) and the Rapidus
(`rapidus.h`).  Addresses are the OS's own.

## Startup module

`src/atari-startup.s` is entered by the DOS through the run vector, in
6502 emulation mode, on the DOS's stack, with the OS's interrupts
running.  It does not begin with `clc; xce`, because that is fatal on an
Atari: the 65C816 takes its interrupts through different vectors in
native mode (`$FFEA`/`$FFEE`) and the Atari OS fills only the
emulation-mode ones, so the first vertical blank after the switch would
go through whatever bytes the ROM has there.  The startup switches every
interrupt source off first, then goes native, sets S, D and DB, runs
the library's section, stream and heap initialisation, and calls `main`.

**The program runs with no interrupts.**  The OS gets them back for the
length of every CIO call (`src/cio.s`, below) and for good when the
program exits.  A program that wants its own interrupt handlers has to
provide native-mode vectors first -- on a Rapidus that means a RAM copy
of the OS under the ROM -- and that is outside what this package does.

Before any of it, `src/cpu.s` identifies the CPU with 6502-only
instructions (decimal `ADC` separates NMOS from CMOS; `xce` is then safe
to try).  On a 65C816 it returns.  On a 6502 it looks for a Rapidus on
each PBI slot, and if it finds one switches it to the 65C816.  The switch
resets the machine, so the startup first sets `COLDST` to make the OS
treat that reset as a cold start: a DOS then runs its start-up file again
and the program comes back, on the 65C816 this time.  (Altirra's own
`--run` loader fires once and does not, which is why the test runner
switches the CPU itself before the load.)  A machine with no 65C816 and
no Rapidus is told so on the screen and returned to DOS with nothing
written.

## Stub interface

The stubs implement the host interface of Calypsi's C library over the
OS's CIO.  The hosted stdio (`--hosted`) therefore works: `printf` and
`getchar` on the console, `fopen` and friends on whatever devices the
DOS provides.

- **Console.**  fd 0-2 are IOCB 0, the E: the OS opened.  stdin is line
  input -- E: hands back a whole typed line however it is asked --
  translated EOL to `'\n'` in text mode.
- **Files.**  fd 3-9 are IOCB 1-7, opened with CIO open modes mapped
  from the `O_*` flags (`"r"` 4, `"w"` 8, `"a"` 9, `"r+"` 12; `"w+"` and
  `"a+"` are opened for update after creating or checking the file).
  Names are device names, `D:FILE.EXT`, `D2:>DIR>FILE`, `H:FILE`,
  exactly as the DOS takes them, through a bank-`$00` bounce buffer.
  `remove()` and `rename()` are XIO 33 and 32.
- **Seeking.**  A position is a byte offset under every DOS.  Where the
  DOS counts bytes too (SpartaDOS) a seek is a POINT.  Where it hands out
  sector/byte cookies (DOS 2, MyDOS, Altirra's H:) a seek forward reads
  and discards, and a seek back POINTs to the nearest place a cookie was
  taken -- the start of the last transfer, or the start of the file --
  and reads forward from there.  Slow for a long way back in a big file,
  but right.  `SEEK_END` reads to the end: no DOS tells CIO a file's
  length.  The cost is only paid on the cookie DOSes.
- **CIO from native mode.**  `src/cio.s` is the round trip: save the
  program's machine, become the machine the DOS was running on (D = 0,
  DB = 0, the DOS's stack at the depth it was left, emulation mode, the
  VBI on, `cli`), `JSR CIOV`, and back.  The OS's VBI runs during the
  call, so anything the program did to ANTIC and GTIA directly is
  overwritten from the OS's shadows, exactly as under DOS: a program
  that owns the display sets the shadows, not the chips.  It is public
  for programs that want CIO for something the stubs do not cover:
  `__attribute__((simple_call)) int __atari_cio(int iocb)` in
  `atari/atari.h`, the IOCB filled in by the caller.
- **Exit.**  `exit()` puts the CPU back as the DOS handed it over and
  returns through the DOS's `RTS`.  That is right for a DOS whose
  command processor is resident (both SpartaDOSes, DOS XL, MyDOS with
  its menu loaded).  Under an Atari DOS 2 whose `DUP.SYS` the program
  has just been running over, set `__atari_exit_dosvec = 1` and the exit
  goes through `DOSVEC` instead, which reloads the menu.

`_Stub_environ` returns an empty environment; `_Stub_assert` prints and
exits.  No clock, no `system()`.

## Memory

Bank `$00` as a DOS leaves it, with BASIC off:

    $0000-$06FF  the OS's; page 6 is yours by tradition
    $0700-$1FFF  a resident DOS (MEMLO says where it really ends)
    $2000-$20FF  the direct page            <- the program
    $2100-$9BFF  code, data, stack, heap    <- the program
    $9C00-$9FFF  SpartaDOS X's screen when it runs from a cartridge
                 (MEMTOP $9C1F); under a disk DOS the top is $BC1F
    $A000-$BFFF  a cartridge, or RAM without one
    $C000-$FFFF  the OS ROM and the hardware

`linker-files/atari-plain.scm` puts everything in `$2000-$9BFF`, which
fits under every DOS this has been tried with; raise `LoRAM`'s top to
`$BBFF` if there is no cartridge and no SDX.  The stack block is 2 KB
and the heap 2 KB; change them in the linker file.

The direct page is the program's own (`$2000`), not the OS's zero page.
The OS's interrupt handlers address zero page through D, so everything
that calls into the OS (`cio.s`, `farload.s`) runs with D = `$0000`.

## Far code

`linker-files/atari-far.scm` lays out bank `$00` as above and places
`farcode`, `far`, `cfar` and `switch` in banks `$01`-`$0F` -- the 1 MB
of SRAM a Rapidus has; extend the list for more.  One memory per bank,
because the program counter wraps inside its bank and the linker never
splits a function across memories.  The `$D5` page of each bank is left
out: emulators that do the 6502's page-crossing dummy read in bank
`$00` (Altirra proper still does as of 4.50-test20; AltirraSDL is fixed)
would put `$D5xx` -- cartridge control -- on the bus.

A `.xex` segment header is two 16-bit addresses, so nothing can be
loaded above `$FFFF`.  `tools/mkxex.py` writes the far segments as
chunks aimed at a staging buffer in bank `$00` -- the program's stack
block, which nothing uses until the startup sets S -- each followed by
an `INITAD` that makes the DOS call `_fl_copy` in `src/farload.s`, which
moves the chunk up.  The copier probes every destination for RAM before
writing it and refuses, by bank, a machine without it.  What the packer
needs to know about the buffer it reads out of the image, from the
symbols `farload.s` exports.

## Tests

`make check` builds three programs and runs each on an emulated 800XL
with a Rapidus, headlessly, through AltirraSDL's bridge:

- `hello`, in both code models: stdio in both directions and a clean
  return to the OS.
- `readwrite`, large model: the file stubs through stdio against the
  emulator's H: device -- text and binary files, every `fopen` mode,
  seeking both ways, `rename`, `remove`; 38 checks.  `-DRW_DEVICE='"D:"'`
  points it at a DOS disk instead.

`test/run-altirra.py` boots the `.xex` through the emulator's loader,
switches the Rapidus through the PBI registers exactly as the startup
would, reads the verdict the program leaves in page 6, checks the
screen, reads the far image back from the banks and compares it with
the ELF, and proves stdin by pressing RETURN.  A screenshot is left next
to each `.xex`.

## Known tool chain issues

- **cc65816 5.18 miscompiles `p->a = p->b OP x` (and `p[i] = p[j] OP x`)
  when the pointer is in a stack slot** (small data model): the load
  takes the destination's offset, so the statement is `p->a OP= x`.
  The shipped `clib-*-sd.a` has the bug in `__fs_fdopen`, where it
  leaves every stream's `fs_bufend` wrong, and an `fwrite` longer than
  the 64-byte buffer then overwrites the heap.  `src/fdopen.c` replaces
  that function; it is why this library must precede `clib-*.a` on the
  link line.  The exact trigger, what does not trigger it, and two
  smaller library notes (`fgetpos` ignores read-ahead, `fs_next` is
  never initialised) are in `docs/cc65816-bug.md`.  Your own code is
  affected too: take `p->b` into a local first, until a fixed compiler
  is the minimum version.

## Licence

MIT No Attribution; see `LICENSE`.  The code was written for gem4xe, a
port of GEM to the same machine, and is also part of that project under
the GPL.
