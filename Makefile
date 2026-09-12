# Calypsi board support for the Atari XL/XE with a 65C816.
#
# Builds two libraries, one per code model, both with the small data
# model (data in bank $00, where the Atari's OS, DOS and hardware are):
#
#   atari-sc-sd.a   --code-model=small   everything in bank $00
#   atari-lc-sd.a   --code-model=large   code in banks $01 and up
#
# and the .xex packer needs nothing built.  `make test` builds the test
# programs; `make check` runs them under AltirraSDL (see test/run-altirra.py).

VPATH = src

CALYPSI ?= $(dir $(shell which cc65816 2>/dev/null))
AS   = $(CALYPSI)as65816
CC   = $(CALYPSI)cc65816
LN   = $(CALYPSI)ln65816
NLIB = $(CALYPSI)nlib

CFLAGS = --core=65816 --data-model=small --always-inline -Iinclude

ASM_SOURCES = atari-startup.s cpu.s farload.s cio.s stub_exit.s
C_SOURCES   = fdtab.c stub_open.c stub_close.c stub_read.c stub_write.c \
              stub_lseek.c stub_remove.c stub_misc.c fdopen.c

# The stubs and the startup carry attributes that the linker matches
# against --rtattr stubs=atari / --rtattr cstartup=atari.
STUB_CFLAGS = --rtattr stubs=atari

SC_OBJS = $(addprefix obj/, $(ASM_SOURCES:%.s=%-sc.o) $(C_SOURCES:%.c=%-sc.o))
LC_OBJS = $(addprefix obj/, $(ASM_SOURCES:%.s=%-lc.o) $(C_SOURCES:%.c=%-lc.o))

ALL_LIBS = atari-sc-sd.a atari-lc-sd.a

all: $(ALL_LIBS)

obj/%-sc.o: %.s
	$(AS) --core=65816 --code-model=small --data-model=small --debug -Isrc \
	      --list-file=$(@:%.o=%.lst) -o $@ $<

obj/%-lc.o: %.s
	$(AS) --core=65816 --code-model=large --data-model=small --debug -Isrc \
	      --list-file=$(@:%.o=%.lst) -o $@ $<

obj/%-sc.o: %.c
	$(CC) $(CFLAGS) $(STUB_CFLAGS) --code-model=small --debug -Isrc \
	      --list-file=$(@:%.o=%.lst) -o $@ $<

obj/%-lc.o: %.c
	$(CC) $(CFLAGS) $(STUB_CFLAGS) --code-model=large --debug -Isrc \
	      --list-file=$(@:%.o=%.lst) -o $@ $<

atari-sc-sd.a: $(SC_OBJS)
	(cd obj ; $(NLIB) ../$@ $(notdir $^))

atari-lc-sd.a: $(LC_OBJS)
	(cd obj ; $(NLIB) ../$@ $(notdir $^))

# ---- the tests ---------------------------------------------------------
# hello: stdio through the console, in both layouts.  readwrite: the
# file stubs, against the emulator's H: host device by default (build
# with -DRW_DEVICE='"D:"' for a DOS disk).  No DOS is needed for either:
# test/run-altirra.py boots the .xex through the emulator's own loader
# and mounts a scratch directory as H:.

TEST_LDFLAGS = --rtattr cstartup=atari --rtattr stubs=atari --hosted \
               --list-file=$(@:%.elf=%.map)

test: obj/hello-sc.xex obj/hello-lc.xex obj/readwrite-lc.xex

obj/hello-sc.elf: test/hello.c atari-sc-sd.a
	$(CC) $(CFLAGS) --code-model=small -o obj/hello-sc-main.o test/hello.c
	$(LN) $(TEST_LDFLAGS) -o $@ obj/hello-sc-main.o atari-sc-sd.a clib-sc-sd.a \
	      linker-files/atari-plain.scm

obj/hello-lc.elf: test/hello.c atari-lc-sd.a
	$(CC) $(CFLAGS) --code-model=large -o obj/hello-lc-main.o test/hello.c
	$(LN) $(TEST_LDFLAGS) -o $@ obj/hello-lc-main.o atari-lc-sd.a clib-lc-sd.a \
	      linker-files/atari-far.scm

obj/readwrite-lc.elf: test/readwrite.c atari-lc-sd.a
	$(CC) $(CFLAGS) --code-model=large -o obj/readwrite-lc-main.o test/readwrite.c
	$(LN) $(TEST_LDFLAGS) -o $@ obj/readwrite-lc-main.o atari-lc-sd.a clib-lc-sd.a \
	      linker-files/atari-far.scm

%.xex: %.elf
	python3 tools/mkxex.py $< $@

check: test
	python3 test/run-altirra.py obj/hello-sc.xex obj/hello-lc.xex obj/readwrite-lc.xex

clean:
	rm -rf obj/*.o obj/*.lst obj/*.map obj/*.elf obj/*.xex obj/*.run $(ALL_LIBS)

.PHONY: all test check clean
