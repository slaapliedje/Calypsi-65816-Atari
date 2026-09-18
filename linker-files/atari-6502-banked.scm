;;; Atari XL/XE, 6502, with code banked through the PORTB window.
;;;
;;; THE MACHINE.  One switchable window, $4000-$7FFF, 16 KB, at a fixed
;;; address -- every RAM expansion for the XL/XE uses that same one.  It is
;;; controlled by PORTB ($D301), which on the XL/XE is an output register
;;; (on the 400/800 it was an input port for joystick ports 3 and 4):
;;;
;;;   bit 0  OS ROM at $C000-$CFFF and $D800-$FFFF; 0 = RAM
;;;   bit 1  BASIC: 0 = enabled, 1 = disabled
;;;   bit 2,3  130XE bank select
;;;   bit 4  CPU Bank Enable, active low
;;;   bit 5  Video (ANTIC) Bank Enable, active low
;;;   bit 7  self-test ROM at $5000-$57FF; normally 1
;;;
;;; Which bits are bank-select depends on the board -- 130XE 2,3; 1 MB
;;; RAMBO 1,2,3,5,6,7 -- and the big boards steal bits 1 and 7, so BASIC
;;; and self-test cannot be enabled at all on a megabyte machine.  THE MAP
;;; IS THEREFORE PROBED AT BOOT AND A BANK NUMBER IS NOT A CONSTANT: the
;;; startup builds a table and the trampolines index it.  (Mapping the
;;; Atari, Revised Edition, appendices 12 and 16; Altirra's mmu.cpp.)
;;;
;;; BANK $00 AS A DOS LEAVES IT, BASIC OFF:
;;;
;;;   $0000-$007F  the OS's
;;;   $0080-$00FF  OURS.  SpartaDOS X's programming guide: "the loaded
;;;                program can use the area $80-$FF for own purposes".
;;;                Calypsi's register file wants 54 bytes of it.
;;;   $0100-$01FF  the 6502 stack
;;;   $0200-$06FF  the OS's, and page 6 is yours by tradition
;;;   $0700-$1FFF  a resident DOS; MEMLO says where it really ends
;;;   $2000-$3FFF  RESIDENT: what is always mapped
;;;   $4000-$7FFF  THE WINDOW: banked code, one bank at a time
;;;   $8000-$9BFF  resident too -- but see the warning below
;;;   $9C00-$9FFF  SpartaDOS X's screen from a cartridge (MEMTOP $9C1F)
;;;   $A000-$BFFF  NOT OURS: SpartaDOS X is a cartridge and this is it
;;;   $C000-$FFFF  the OS ROM and the hardware
;;;
;;; ** $8000-$9BFF IS CONTENDED ON A MACHINE WITHOUT A VBXE. ** That is
;;; where the ANTIC driver puts its display list and framebuffer (168 lines
;;; of 40 bytes, 6,720 of the 7,168 bytes there), because ANTIC fetches with
;;; 16-bit addresses and cannot see the banked window -- which a DOS would
;;; switch out from under it anyway.  So a VBXE build may put the C stack
;;; and the data heap here; an ANTIC build may not, and must fit them in
;;; $2000-$3FFF with everything else.  Two maps, or one with the stack
;;; sized for the tighter case.
;;;
;;; The .xex is entered through RUNAD; there is no reset vector.  Loading
;;; the banks is not the linker's problem and not the .xex format's either:
;;; the image carries each bank as a chunk aimed at the window, with an
;;; INITAD copier that sets PORTB between them.
(define memories
  '(;; The program's zero page.  `registers` is Calypsi's pseudo-register
    ;; file -- 54 bytes measured, not assumed -- and what is left is for
    ;; __attribute__((zpage)) variables, which on a 6502 are worth having.
    (memory ZeroPage (address (#x80 . #xff)) (type ram) (qualifier zpage)
            (section (registers #x80)))

    (memory StackPage (address (#x100 . #x1ff)) (type ram))

    ;; The compiler emits a `reset` vector section.  An .xex has no reset
    ;; vector -- the OS ROM owns $FFFC and the program is entered through
    ;; RUNAD -- so it is given two deliberate bytes here rather than left
    ;; to land in whatever memory had room.  (--no-vector-sections on the
    ;; compiler removes it instead, if you would rather not spend them.)
    (memory Vector (address (#x3ffe . #x3fff))
            (section reset))

    ;; Resident: the dispatcher, the bank trampolines, the argument bounce
    ;; buffers, and anything a banked routine may be holding a pointer to
    ;; while the window is switched out from under it.
    (memory Resident (address (#x2000 . #x3ffd)) (type any)
            (section startup code cdata idata data data_init_table switch))

    ;; The window.  `bankedcode` scatters into as many 16 KB instances as
    ;; it needs; each instance is relocated to $4000 because that is where
    ;; it runs.  NOTHING HERE MAY CALL ANYTHING IN ANOTHER INSTANCE
    ;; DIRECTLY -- the linker will not say so, and two functions in
    ;; different banks can even share an address.  Cross-bank calls go
    ;; through the resident trampolines.
    (memory BankWindow (address (#x4000 . #x7fff))
            (scatter-to Banks)
            :generate-instances
            (section bankedcode))

    ;; Where those instances are STORED, as opposed to where they run.
    ;; One bank per 16 KB; the packer turns each into a chunk plus the
    ;; PORTB value that maps it.  64 banks is the 1 MB ceiling.
    (memory BankedRAM (address (#x10000 . #x10ffff))
            (section Banks))

    ;; The C stack and the heap, on a machine whose screen is elsewhere.
    ;; See the warning above before believing this is free.
    (memory HighRAM (address (#x8000 . #x9bff)) (type any)
            (section cstack zdata heap))

    ;; Sized on purpose.  Calypsi's default C stack is 4 KB, which is a
    ;; quarter of the window and more than half of $2000-$3FFF -- fine
    ;; while it lives in HighRAM, impossible if the screen is there and it
    ;; has to move down.  2 KB is what the 65C816 build of gem4xe actually
    ;; uses, measured at its low-water mark, with the AES recursing.
    (block cstack (size #x0800))))
