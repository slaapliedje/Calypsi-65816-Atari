;;; atari.i -- the few OS addresses the package's assembly needs.
;;; The C side has include/atari/atari.h; keep the two in step.

#define DOSVEC 0x000A                 /* the DOS's own re-entry point */
#define POKMSK 0x0010                 /* OS shadow of IRQEN */
#define COLDST 0x0244                 /* non-zero at RESET: cold start */
#define CH     0x02FC                 /* the last key pressed, $FF if none */
#define ICHID  0x0340                 /* IOCB #0; sixteen bytes each */
#define ICCOM  0x0342
#define ICBAL  0x0344
#define ICBLL  0x0348
#define ICAX1  0x034A
#define ICAX2  0x034B
#define IOCB1  0x0010                 /* IOCB #1 relative to #0 */
#define NMIEN  0xD40E                 /* ANTIC: VBI / DLI enable */
#define IRQEN  0xD20E                 /* POKEY: IRQ enable */
#define PDVS   0xD1FF                 /* PBI device select */
#define CIOV   0xE456
#define EOL    0x9B

#define CIO_OPEN   3
#define CIO_PUTREC 9
#define CIO_CLOSE  12

;;; The code-model-dependent call, return and jump, and the tags that let
;;; the linker refuse an object assembled for the wrong models.  The same
;;; three macros as the library's own macros.h.
#ifdef __CALYPSI_CODE_MODEL_SMALL__
#define libcode code
call          .macro  dest
              jsr     \dest
              .endm
return        .macro
              rts
              .endm
jump          .macro  dest
              jmp     \dest
              .endm
              .rtmodel codeModel,"small"
#else
#define libcode farcode
call          .macro  dest
              jsl     \dest
              .endm
return        .macro
              rtl
              .endm
jump          .macro  dest
              jmp     long:\dest
              .endm
              .rtmodel codeModel,"large"
#endif
              .rtmodel dataModel,"small"
