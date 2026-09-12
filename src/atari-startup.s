;;; ---------------------------------------------------------------------------
;;; atari-startup.s -- Calypsi C startup for the Atari XL/XE with a 65C816
;;;
;;; DOS jumps here through the run vector of the .xex ($02E0), in 6502
;;; emulation mode, on its own stack, with the OS's interrupts running.
;;;
;;; The library's own cstartup begins `clc; xce`.  That is fatal on an
;;; Atari: the 65816 takes its interrupts through DIFFERENT vectors in
;;; native mode --
;;;
;;;     emulation mode   NMI $FFFA   RESET $FFFC   IRQ/BRK $FFFE
;;;     native mode      NMI $FFEA   BRK $FFE6     IRQ     $FFEE
;;;
;;; -- and the Atari OS ROM fills only the emulation-mode ones.  The first
;;; vertical blank after the `xce` (within 20 ms, always) goes through
;;; $FFEA, reads whatever bytes are there, and the machine is gone.
;;;
;;; So, while still in emulation mode and on the OS's vectors, this
;;; startup switches every interrupt source off, and only then goes
;;; native.  The program runs with no interrupts at all; the OS gets them
;;; back for the length of every CIO call (cio.s) and for good when the
;;; program exits (stub_exit.s).  A program that wants its own interrupt
;;; handlers has to provide native-mode vectors first -- on a Rapidus that
;;; means a RAM copy of the OS under the ROM -- and that is outside what
;;; this package does.
;;;
;;; Before any of it, the CPU is checked: a .xex loads on any Atari, and
;;; on a 6502 the first 65816 instruction is a silent no-op or worse.
;;; ---------------------------------------------------------------------------

              .rtmodel cstartup,"atari"

              .rtmodel version, "1"
              .rtmodel core, "*"

              .section stack
              .section cstack
              .section heap
              .section data_init_table

              .extern main, exit
              .extern _Dp, _Vfp
              .extern _DirectPageStart
              .extern __atari_require_816   ; cpu.s
              .extern _fl_copy              ; farload.s, see below
              .public __atari_sp, __atari_pokmsk

#ifndef __CALYPSI_DATA_MODEL_SMALL__
              .extern _NearBaseAddress
#endif

#include "atari.i"

;;; ***************************************************************************
;;;
;;; __program_root_section - this is what the linker pulls in first
;;; __program_start - the run address of the .xex (tools/mkxex.py)
;;;
;;; ***************************************************************************

              .section code, noreorder
              .pubweak __program_root_section, __program_start
__program_root_section:
__program_start:
;;; 6502 code, on DOS's stack, until the CPU is known.  Does not return on
;;; a 6502: it says so and goes back to DOS.
              jsr     __atari_require_816

              tsx
              stx     __atari_sp      ; DOS's S, for _Stub_exit and cio.s
              lda     POKMSK
              sta     __atari_pokmsk  ; and the IRQs DOS ran with
              sei
              lda     #0
              sta     IRQEN           ; POKEY: no keyboard, timer, serial IRQs
              sta     POKMSK          ; keep the OS's shadow honest
              sta     NMIEN           ; ANTIC: no VBI, no DLI

              clc
              xce                   ; native 16-bit mode
              rep     #0x38         ; 16-bit registers, no decimal mode
              ldx     ##.sectionEnd stack
              txs                   ; set stack
              lda     ##_DirectPageStart
              tcd                   ; set direct page
#ifdef __CALYPSI_DATA_MODEL_SMALL__
              lda     ##0
#else
              lda     ##.word2 _NearBaseAddress
#endif
              stz     dp:.tiny(_Vfp+2)
              xba                   ; A upper half = data bank
              pha
              plb                   ; pop 8 dummy
              plb                   ; set data bank

              call    __low_level_init

;;; **** Initialize data sections if needed.
              .section code, noroot, noreorder
              .pubweak __data_initialization_needed
              .extern __initialize_sections
__data_initialization_needed:
              lda     ##.word2 (.sectionEnd data_init_table)
              sta     dp:.tiny(_Dp+6)
              lda     ##.word0 (.sectionEnd data_init_table)
              sta     dp:.tiny(_Dp+4)
              lda     ##.word2 (.sectionStart data_init_table)
              sta     dp:.tiny(_Dp+2)
              lda     ##.word0 (.sectionStart data_init_table)
              sta     dp:.tiny(_Dp+0)
              call    __initialize_sections

;;; **** Initialize streams if needed.
              .section code, noroot, noreorder
              .pubweak __call_initialize_global_streams
              .extern __initialize_global_streams
__call_initialize_global_streams:
              call    __initialize_global_streams

;;; **** Initialize heap if needed.
              .section code, noroot, noreorder
              .pubweak __call_heap_initialize
              .extern __heap_initialize, __default_heap
__call_heap_initialize:
#ifdef __CALYPSI_DATA_MODEL_SMALL__
              lda     ##.sectionSize heap
              sta     dp:.tiny(_Dp+2)
              lda     ##.sectionStart heap
              sta     dp:.tiny(_Dp+0)
              lda     ##__default_heap
#else
              lda     ##.word2 (.sectionStart heap)
              sta     dp:.tiny(_Dp+6)
              lda     ##.word0 (.sectionStart heap)
              sta     dp:.tiny(_Dp+4)
              lda     ##.word2 __default_heap
              sta     dp:.tiny(_Dp+2)
              lda     ##.word0 __default_heap
              sta     dp:.tiny(_Dp+0)
              ldx     ##.word2 (.sectionSize heap)
              lda     ##.word0 (.sectionSize heap)
#endif
              call    __heap_initialize

              .section code, root, noreorder
              lda     ##0           ; argc = 0
              call    main
              jump    exit

;;; What DOS handed us, kept for the way back.  In `code` so that they are
;;; in bank $00 whatever the data model, and loaded fresh with every run.
__atari_sp:   .byte   0             ; S: DOS's return address is above it
__atari_pokmsk:
              .byte   0             ; POKMSK: the IRQ sources DOS ran with

;;; The far loader is referenced from here so that it is always linked:
;;; nothing in the program calls it -- DOS does, through INITAD, and
;;; tools/mkxex.py finds it by name -- so without this the librarian
;;; would never pull it in.  Four bytes, and every program can then have
;;; parts above bank $00.
              .word   _fl_copy

;;; ***************************************************************************
;;;
;;; __low_level_init - custom low level initialization
;;;
;;; This default routine just returns doing nothing. You can provide your own
;;; routine, either in C or assembly for doing custom low leve initialization.
;;;
;;; ***************************************************************************

              .section libcode
              .pubweak __low_level_init
__low_level_init:
              return
