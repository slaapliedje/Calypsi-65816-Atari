;;; ---------------------------------------------------------------------------
;;; cio.s -- calling the Atari OS's CIO from 65816 native mode
;;;
;;; The program runs native, with its own direct page, data bank and a
;;; 16-bit stack, and with every interrupt source off (atari-startup.s).
;;; CIOV is 6502 code: it wants emulation mode, D = 0, a stack in page 1,
;;; and the OS's interrupt handlers -- the keyboard is an IRQ, a disk read
;;; is SIO, and SIO is driven by POKEY's serial IRQs and timed by the VBI.
;;; In emulation mode the CPU takes its vectors from $FFFA-$FFFF again, so
;;; the OS's handlers come back the moment E is set.
;;;
;;; So one CIO call is a round trip: save our machine, become the machine
;;; DOS was running on, JSR CIOV, come back.  In detail --
;;;
;;;   D = $0000, DB = $00     the OS's zero page and page 2/3 tables
;;;   POKMSK = IRQEN          what DOS ran with (__atari_pokmsk)
;;;   S = $01xx               DOS's stack, at the depth DOS left it:
;;;                           above it are DOS's frames, below it is free.
;;;                           Set BEFORE xce, so that an NMI arriving
;;;                           between the two lands on it
;;;   sec, xce                emulation mode; the OS's vectors
;;;   NMIEN = $40             the VBI: RTCLOK, the OS's shadow registers,
;;;                           SIO's timeouts, keyboard repeat
;;;   cli, jsr CIOV
;;;   sei, everything off, clc, xce      back, in that order
;;;
;;; The OS's VBI runs during the call, so anything the program has done to
;;; ANTIC and GTIA directly is overwritten from the OS's shadows, exactly
;;; as it would be under DOS.  A program that owns the display sets the
;;; shadows (SDMCTL, SDLSTL, COLOR0.., CHBAS) rather than the chips.
;;;
;;; The whole routine is bank-$00 `code`: an interrupt taken in emulation
;;; mode returns to a 16-bit address in bank $00, so the instruction after
;;; `xce` has to be there.  From C (lib.h) it is
;;;
;;;     __attribute__((simple_call)) int __atari_cio(int iocb);
;;;
;;; the IOCB number (0-7) in A, the OS's status (its Y) back in A.  The
;;; caller fills the IOCB in first.
;;; ---------------------------------------------------------------------------

              .rtmodel version, "1"
              .rtmodel core, "*"

              .extern __atari_sp, __atari_pokmsk    ; atari-startup.s
              .public __atari_cio

#include "atari.i"

              .section zdata, bss
cio_sp:       .space  2               ; our S across the call
cio_x:        .space  1               ; iocb * 16, for X

              .section code
__atari_cio:  php                     ; the caller's flags: register widths, I
              phb
              phd
              rep     #0x30
              asl     a
              asl     a
              asl     a
              asl     a               ; IOCB * 16
              sep     #0x20
              sta     long:cio_x
              lda     #0
              pha
              plb                     ; DB = $00
              rep     #0x20
              tsc
              sta     abs:cio_sp      ; the 16-bit stack, to come back to
              lda     ##0
              tcd                     ; D = $0000
              sep     #0x20
              sei
              lda     abs:__atari_pokmsk
              sta     POKMSK
              sta     IRQEN           ; DOS's sources: keyboard, break
              lda     #1
              xba                     ; B = $01 ...
              lda     abs:__atari_sp  ; ... A = DOS's S
              rep     #0x20
              tcs                     ; S = $01xx while still native
              sec
              xce                     ; emulation mode: 8-bit everything
              lda     #0x40
              sta     NMIEN           ; the VBI
              cli
              ldx     cio_x
              jsr     CIOV
              sei
              lda     #0
              sta     NMIEN
              sta     IRQEN
              sta     POKMSK
              tya                     ; the status
              clc
              xce                     ; native
              rep     #0x30
              and     ##0x00ff        ; B holds leftovers; C wants 16 bits
              tax
              lda     abs:cio_sp
              tcs
              txa
              pld
              plb
              plp
              return
