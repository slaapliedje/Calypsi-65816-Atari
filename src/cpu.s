;;; ---------------------------------------------------------------------------
;;; cpu.s -- is this a 65C816?  If not, can it become one?
;;;
;;; A .xex loads on any Atari, and a 6502 executes a 65816 program as
;;; nonsense: `xce` is a one-byte NOP on a 65C02 and an unstable
;;; undocumented opcode on an NMOS 6502, and the long store the far loader
;;; uses ($9F) is another.  So the CPU is identified before the first 65816
;;; instruction runs, with nothing but 6502 instructions, and a machine
;;; that cannot run the program is told so and given back unchanged.
;;;
;;; The one accelerator that Altirra emulates, the Rapidus, ALWAYS comes
;;; up as a 6502 (the card's FPGA resets that way; Altirra's rapidus.cpp
;;; does the same in ColdReset), so a 65816 program on a Rapidus machine
;;; would need a person to switch the CPU first, every boot.  Instead the
;;; card is looked for and switched here.  The switch resets the CPU, so
;;; the program has to be loaded again, and the OS is told to treat that
;;; reset as a cold start so that a DOS runs its start-up file again.
;;;
;;; __atari_require_816 is called from the startup (atari-startup.s) and
;;; from the far loader's first INITAD call (farload.s), whichever comes
;;; first.  It returns only on a 65816.
;;; ---------------------------------------------------------------------------

              .rtmodel version, "1"
              .rtmodel core, "*"

              .public __atari_require_816

#include "atari.i"

;;; The Rapidus, from the 6502 side.  Its registers are mapped only while
;;; its PBI device is SELECTED, so PDVS comes first, and $D190/$D191 read
;;; open bus until it does.  With the card's slot selected, $D190 (the
;;; FPGA bank register) reads $00 and $D191 (FPGA config) reads $40 --
;;; bit 6 set: the 6502 is running.  Every other slot, and a machine with
;;; no Rapidus in it, reads $FF at both.
RAPBANK:      .equ    0xd190
RAPCFG:       .equ    0xd191
RAPCFG_6502:  .equ    0x40

              .section code, root

;;; 0 = not looked yet, 1 = a 65816.  Kept in `code` so that DOS loads
;;; the zero afresh with every run.
cpu_known:    .byte   0

__atari_require_816:
              lda     cpu_known
              bne     is816

;;; 1. NMOS or CMOS?  Decimal-mode ADC sets N and Z from the BINARY result
;;;    on an NMOS 6502 and from the decimal result on everything later, so
;;;    $99 + $01 = $00 is reported as non-zero by a 6502 alone.  This is
;;;    the only test that is safe to run first: $FB (XCE) is an unstable
;;;    read-modify-write on NMOS, so it cannot be the one that goes first.
              sed
              lda     #0x99
              clc
              adc     #0x01
              cld
              bne     no816

;;; 2. CMOS -- but a 65C02 or a 65816?  On a 65816 `clc xce` returns the
;;;    old E flag in carry; on a 65C02 $FB is a one-byte NOP and carry
;;;    stays clear.  The machine is in native mode for the three
;;;    instructions in between, where the interrupt vectors move to
;;;    $FFEA/$FFEE and the Atari OS has never filled them -- so ANTIC's
;;;    NMI is switched off across the window (atari-startup.s has the
;;;    whole story).
              lda     NMIEN
              pha
              lda     #0
              sta     NMIEN
              clc
              xce
              php                     ; carry now says what the CPU is
              sec
              xce                     ; ...back to emulation mode at once
              plp
              pla
              sta     NMIEN
              bcc     no816

              lda     #1
              sta     cpu_known
is816:        rts

;;; ---------------------------------------------------------------------------
;;; no816 -- not a 65816.  Before saying so, look for a Rapidus that has
;;; simply cold-booted as a 6502.
;;;
;;; What is written, in the order it is written:
;;;
;;;   PDVS         the slot, because the card's registers are mapped only
;;;                while its PBI device is selected
;;;   COLDST = 1   the switch RESETS the CPU, and the OS treats that reset
;;;                as a WARM start -- which is exactly when a DOS does not
;;;                run its start-up file.  Without this the machine comes
;;;                back to a prompt instead of loading the program again.
;;;   RAPCFG = 0   bit 6 clear: the 65816.  The CPU resets HERE.
;;;
;;; The slot is not assumed.  Every one of the eight is tried -- one bit
;;; each, so the mask is shifted left and the eighth shift leaves $00,
;;; which is also "nothing selected" -- and the card must answer with BOTH
;;; of the bytes above, so a machine with something else on the bus is
;;; left alone.  The select is put back either way, which is the PBI
;;; convention: a driver selects for the length of its own call and
;;; deselects after.
;;; ---------------------------------------------------------------------------
no816:        lda     #1              ; PBI device 1, then 2, 4, ...
slot:         sta     PDVS            ; select it; the registers appear
              pha
              lda     RAPBANK
              bne     next            ; open bus, or not in 6502 mode
              lda     RAPCFG
              and     #RAPCFG_6502
              beq     next            ; a 65816 already: not our business
              lda     #1
              sta     COLDST
              lda     #0
              sta     RAPCFG          ; ...and the CPU resets here
;;; Still running, so nothing took the write: try the next slot.
next:         pla
              asl     a
              bcc     slot
              sta     PDVS            ; $00: nothing selected, as it was

;;; ---------------------------------------------------------------------------
;;; refuse -- say why, wait to be read, and give the machine back.
;;;
;;; This may be running from INITAD, inside the DOS's own load loop, and
;;; the DOS would go on reading the rest of the file whatever we do.  So
;;; the load is ABANDONED: the DOS's file is closed (IOCB #1, the channel
;;; every DOS 2 and SpartaDOS loads a binary on; $FF in ICHID when it is
;;; not open, which is the case when we got here from the run address
;;; instead) and DOSVEC takes the machine back to its prompt.
;;;
;;; The message is WAITED ON, because coming back is what wipes it: a
;;; DOS 2 redraws its menu over the top and a SpartaDOS prints its banner.
;;; A key -- read from the OS's own CH, so no IOCB has to be opened at a
;;; moment when the DOS owns them -- is what says it has been read.
;;; ---------------------------------------------------------------------------
refuse:       ldx     #.byte0 msg_no816
              ldy     #.byte1 msg_no816
              jsr     print
              ldx     #.byte0 msg_key
              ldy     #.byte1 msg_key
              jsr     print
              lda     #0xff
              sta     CH              ; drop whatever was already typed
anykey:       lda     CH
              cmp     #0xff
              beq     anykey
              lda     #0xff
              sta     CH
              lda     ICHID+IOCB1     ; $FF when the channel is not open
              cmp     #0xff
              beq     gone
              lda     #CIO_CLOSE
              sta     ICCOM+IOCB1
              ldx     #IOCB1
              jsr     CIOV
gone:         ldx     #0xff
              txs                     ; the DOS's own re-entry wants its stack
              jmp     (DOSVEC)

;;; One line on IOCB #0 (E:), which DOS keeps open.  PUT RECORD stops at
;;; the EOL whatever length it was given, so the length is just "enough".
print:        stx     ICBAL
              sty     ICBAL+1
              lda     #0xff
              sta     ICBLL
              lda     #0
              sta     ICBLL+1
              lda     #CIO_PUTREC
              sta     ICCOM
              ldx     #0
              jmp     CIOV

;;; Two lines, forty columns.  The second is the one that matters: the
;;; machine was not damaged by being asked.
msg_no816:    .byte   "This program needs a 65C816.", EOL
msg_key:      .byte   "Nothing was changed.  Press a key.", EOL
