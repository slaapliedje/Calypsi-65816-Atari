;;; ---------------------------------------------------------------------------
;;; farload.s -- load-time copy-up of 65816 far code into the banks above $00
;;;
;;; An Atari DOS loader has no idea of 65816 banks: a .xex segment header
;;; is two 16-bit addresses, so nothing can be loaded above $FFFF.  A
;;; program whose code the linker placed in bank $01 and up (linker-files/
;;; atari-far.scm) therefore travels in the .xex as a series of CHUNKS
;;; aimed at a staging buffer in bank $00.  After each one DOS calls the
;;; address in INITAD ($02E2), and this is what it calls: it copies the
;;; chunk from the buffer to its real home and returns.  By the time DOS
;;; reaches the run address the far image is assembled.
;;;
;;; tools/mkxex.py builds the chunks and is the other half of this file.
;;; The two agree on the layout through the symbols this file exports:
;;;
;;;   _fl_copy     what INITAD points at
;;;   _fl_layout   two words: where the staging buffer is, and its size
;;;
;;; THE STAGING BUFFER IS THE STACK.  The program's stack block is bank $00
;;; RAM that nothing uses until the startup sets S -- DOS runs on page 1 --
;;; so borrowing it at load time costs no memory at all, and a bigger
;;; stack simply means fewer, bigger chunks.  The first four bytes of it
;;; hold the chunk's header (24-bit destination, then the length in
;;; pages); the payload follows, a whole number of 256-byte pages, which
;;; is what lets the copier be a flat page loop.
;;;
;;; WHAT IT REFUSES TO DO
;;;
;;; Writing above bank $00 needs a 65816 (cpu.s runs first), and RAM where
;;; a chunk is going is probed rather than assumed -- a 65816 with nothing
;;; where a chunk is going is just as fatal and much less obvious, so
;;; EVERY chunk's destination is probed before it is written.  A machine
;;; without the RAM is told which bank is missing and given back.
;;; ---------------------------------------------------------------------------

              .rtmodel version, "1"
              .rtmodel core, "*"

              .section stack                ; the block the linker reserves

              .extern __atari_require_816   ; cpu.s
              .public _fl_copy, _fl_layout, _fl_top

#include "atari.i"

;;; The copier's pointers live in the OS's zero page, in the floating-point
;;; package's FR0/FRE ($D4-$DF), which nothing touches during a binary
;;; load.  NOT in a direct page of its own: INITAD is called in emulation
;;; mode with the OS's interrupts running, and the OS's VBI and IRQ
;;; handlers address zero page through D -- a `tcd` here would send
;;; RTCLOK's increments and the keyboard's bookkeeping into whatever the
;;; copier pointed D at (found the hard way: the VBI wrote RTCLOK over
;;; the copier's own first instruction).  With D left at $0000, the OS
;;; sees the machine it expects and nothing has to be masked.
DP_SRC:       .equ    0xd4            ; 24-bit source pointer
DP_DST:       .equ    0xd8            ; 24-bit destination pointer
DP_HDR:       .equ    0xdc            ; 24-bit pointer to the chunk header
DP_CNT:       .equ    0xdf            ; pages remaining

              .section code, root

;;; Where the chunks are staged, for tools/mkxex.py: it reads these two
;;; words out of the image rather than repeating the choice.
_fl_layout:   .word   .sectionStart stack
              .word   .sectionSize stack

;;; _fl_top -- one past the highest far address written so far, 24-bit
;;; little-endian, for a program that wants to put a far heap after its
;;; own image.  The linker cannot say where a section that is spread over
;;; several banks ends; the loader records where it actually put things.
;;; In `code`, so DOS loads the zeros fresh with every run.
_fl_top:      .byte   0, 0, 0


;;; ---------------------------------------------------------------------------
;;; _fl_copy -- DOS calls this through INITAD after each chunk segment.
;;; 6502 code until the CPU is confirmed.
;;; ---------------------------------------------------------------------------
_fl_copy:
              jsr     __atari_require_816   ; does not return on a 6502

              php
              lda     _fl_layout
              sta     dp:DP_HDR
              sta     dp:DP_SRC
              lda     _fl_layout+1
              sta     dp:DP_HDR+1
              sta     dp:DP_SRC+1
              lda     #0
              sta     dp:DP_HDR+2     ; the buffer is always in bank $00
              sta     dp:DP_SRC+2
              ldy     #3
              lda     [dp:DP_HDR],y   ; the length, in pages
              beq     fl_done         ; nothing staged (the priming call)
              sta     dp:DP_CNT
              ldy     #0
              lda     [dp:DP_HDR],y
              sta     dp:DP_DST
              iny
              lda     [dp:DP_HDR],y
              sta     dp:DP_DST+1
              iny
              lda     [dp:DP_HDR],y
              sta     dp:DP_DST+2
              clc
              lda     dp:DP_SRC
              adc     #4              ; the payload follows the header
              sta     dp:DP_SRC
              bcc     fl_probe
              inc     dp:DP_SRC+1

;;; Is there RAM where this chunk is going?  Probe the destination itself
;;; -- the copy is about to overwrite it, so the test costs nothing and
;;; asks exactly the right question.
fl_probe:     ldy     #0
              lda     #0xa5
              sta     [dp:DP_DST],y
              cmp     [dp:DP_DST],y
              bne     fl_noram
              lda     #0x5a
              sta     [dp:DP_DST],y
              cmp     [dp:DP_DST],y
              bne     fl_noram

;;; Both pointers are dereferenced long, so neither the source nor the
;;; destination depends on what DOS left in the data bank register.
fl_page:      ldy     #0
fl_byte:      lda     [dp:DP_SRC],y
              sta     [dp:DP_DST],y
              iny
              bne     fl_byte
              inc     dp:DP_SRC+1     ; += 256; the buffer never crosses a bank
              inc     dp:DP_DST+1
              bne     fl_nowrap
              inc     dp:DP_DST+2
fl_nowrap:    dec     dp:DP_CNT
              bne     fl_page

;;; DP_DST is now one past the chunk; raise _fl_top to it if it is higher.
;;; Chunks arrive in address order, but the tail of a segment is slid
;;; BACKWARDS to a page boundary (tools/mkxex.py), so "the last chunk" and
;;; "the highest chunk" are not the same thing, and a maximum is wanted.
              sec
              lda     dp:DP_DST
              sbc     long:_fl_top
              lda     dp:DP_DST+1
              sbc     long:_fl_top+1
              lda     dp:DP_DST+2
              sbc     long:_fl_top+2
              bcc     fl_nottop       ; DP_DST < _fl_top
              lda     dp:DP_DST
              sta     long:_fl_top
              lda     dp:DP_DST+1
              sta     long:_fl_top+1
              lda     dp:DP_DST+2
              sta     long:_fl_top+2
fl_nottop:
;;; Consume the chunk.  DOS may call INITAD again after a segment that
;;; carries no chunk -- the run vector, for one -- and this is what makes
;;; that a no-op.
              lda     #0
              ldy     #3
              sta     [dp:DP_HDR],y
fl_done:      plp
              rts

;;; ---------------------------------------------------------------------------
;;; fl_noram -- a chunk's destination is not RAM.  The bank goes into the
;;; message so that the user learns WHERE the machine stops, not just that
;;; it does.  Then the same abandon-the-load exit as cpu.s: close the
;;; DOS's load channel, wait for a key, DOSVEC.
;;; ---------------------------------------------------------------------------
fl_noram:     lda     dp:DP_DST+2
              pha
              lsr     a
              lsr     a
              lsr     a
              lsr     a
              jsr     fl_hex
              sta     msg_bank
              pla
              and     #0x0f
              jsr     fl_hex
              sta     msg_bank+1
              plp
              ldx     #.byte0 msg_noram
              ldy     #.byte1 msg_noram
              jsr     fl_print
              ldx     #.byte0 msg_key
              ldy     #.byte1 msg_key
              jsr     fl_print
              lda     #0xff
              sta     CH
fl_anykey:    lda     CH
              cmp     #0xff
              beq     fl_anykey
              lda     #0xff
              sta     CH
              lda     ICHID+IOCB1
              cmp     #0xff
              beq     fl_gone
              lda     #CIO_CLOSE
              sta     ICCOM+IOCB1
              ldx     #IOCB1
              jsr     CIOV
fl_gone:      ldx     #0xff
              txs
              jmp     (DOSVEC)

fl_hex:       cmp     #10
              bcc     fl_hex_d
              adc     #6               ; carry is set: +7, so 10 -> 'A'
fl_hex_d:     adc     #'0'
              rts

fl_print:     stx     ICBAL
              sty     ICBAL+1
              lda     #0xff
              sta     ICBLL
              lda     #0
              sta     ICBLL+1
              lda     #CIO_PUTREC
              sta     ICCOM
              ldx     #0
              jmp     CIOV

msg_noram:    .byte   "No RAM in bank $"
msg_bank:     .byte   "xx: this program needs it.", EOL
msg_key:      .byte   "Nothing was changed.  Press a key.", EOL
