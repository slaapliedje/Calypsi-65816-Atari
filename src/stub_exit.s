;;; ---------------------------------------------------------------------------
;;; stub_exit.s -- _Stub_exit: back to DOS
;;;
;;; exit() ends here after the atexit handlers have run and the streams
;;; have been flushed (or straight away, with --rtattr exit=simplified).
;;; What is left is the CPU's own state: put it back the way DOS handed
;;; it to the startup and return through the RTS DOS is waiting on.
;;;
;;; A plain return goes to whatever loaded the program, and that is right
;;; for a DOS whose command processor is resident -- both SpartaDOSes,
;;; DOS XL, MyDOS with its menu in memory.  It is wrong for an Atari DOS 2
;;; whose menu is a separate file: DUP.SYS lives at $1D00-$3306, which is
;;; memory this program has just been running in, so the return address
;;; points into wreckage.  There, DOSVEC -- the vector every DOS keeps
;;; pointing at its own re-entry -- reloads the menu first.  A program
;;; that knows it has been loaded over DUP sets __atari_exit_dosvec to
;;; something non-zero; the default is the return.
;;;
;;; The screen is left alone.  A program that took over the display list
;;; puts the OS's back before it exits (the shadows are enough: the VBI
;;; that runs after `cli` below does the rest).
;;; ---------------------------------------------------------------------------

              .rtmodel version, "1"
              .rtmodel core, "*"

              .extern __atari_sp, __atari_pokmsk    ; atari-startup.s
              .public _Stub_exit, __atari_exit_dosvec

#include "atari.i"

              .section code
_Stub_exit:   sei
              rep     #0x30
              lda     ##0
              tcd                     ; D = $0000: the OS's page zero again
              sep     #0x30
              lda     #0
              pha
              plb                     ; DB = $00
              sec
              xce                     ; 6502 emulation mode; S is $01xx again
              ldx     __atari_sp
              txs                     ; DOS's stack, its return address on top
              lda     __atari_pokmsk
              sta     POKMSK
              sta     IRQEN           ; POKEY sources as DOS had them
              lda     #0x40
              sta     NMIEN           ; the VBI: RTCLOK and the shadows again
              cli
              lda     __atari_exit_dosvec
              beq     1$
              jmp     (DOSVEC)
1$:           rts                     ; to DOS's own loader

;;; Set from C to leave through DOSVEC (see above).  In `code`: bank $00,
;;; loaded as zero with every run.
__atari_exit_dosvec:
              .byte   0
