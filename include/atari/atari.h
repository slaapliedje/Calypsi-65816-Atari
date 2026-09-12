/* atari.h -- the Atari XL/XE OS, as a C program with Calypsi sees it.
 *
 * Addresses are the OS's own (the Atari XL/XE OS listings and the
 * Altirra Hardware Reference Manual agree on all of them).  Everything
 * here is in bank $00, which is where the small data model's plain
 * pointers point; a __far pointer is needed to reach them from a
 * program built with a larger data model.
 */
#ifndef ATARI_ATARI_H
#define ATARI_ATARI_H

#include <stdint.h>

/* ---- page zero and the OS variables ---------------------------------- */
#define DOSVEC   (*(volatile uint16_t *)0x000A)  /* the DOS's re-entry */
#define DOSINI   (*(volatile uint16_t *)0x000C)
#define POKMSK   (*(volatile uint8_t  *)0x0010)  /* IRQEN's shadow */
#define RTCLOK   ((volatile uint8_t  *)0x0012)   /* [0] high .. [2] low */
#define SDMCTL   (*(volatile uint8_t  *)0x022F)  /* DMACTL shadow */
#define SDLSTL   (*(volatile uint16_t *)0x0230)  /* display list shadow */
#define COLDST   (*(volatile uint8_t  *)0x0244)
#define MEMTOP   (*(volatile uint16_t *)0x02E5)
#define MEMLO    (*(volatile uint16_t *)0x02E7)
#define CHBAS    (*(volatile uint8_t  *)0x02F4)
#define CH       (*(volatile uint8_t  *)0x02FC)  /* last key; $FF = none */
#define COLOR0   ((volatile uint8_t  *)0x02C4)   /* COLPF0.. shadows, 5 */
#define SAVMSC   (*(volatile uint16_t *)0x0058)  /* the screen's address */
#define RUNAD    (*(volatile uint16_t *)0x02E0)
#define INITAD   (*(volatile uint16_t *)0x02E2)

/* ---- CIO --------------------------------------------------------------- */
#define CIOV     0xE456

/* The IOCB the OS lays out at $0340: eight of them, sixteen bytes each.
 * IOCB 0 is the OS's own, open on E:. */
typedef struct {
    uint8_t  ichid;             /* $FF when free */
    uint8_t  icdno;
    uint8_t  iccom;
    uint8_t  icsta;
    uint16_t icbal;             /* buffer address */
    uint16_t icptl;
    uint16_t icbll;             /* buffer length; bytes moved on return */
    uint8_t  icax1, icax2, icax3, icax4, icax5, icax6;
} IOCB;

#define CIO_IOCBS   8
#define CIO_IOCB    ((volatile IOCB *)0x0340)

/* ICCOM */
#define CIO_OPEN     0x03
#define CIO_GETREC   0x05
#define CIO_GETCHR   0x07
#define CIO_PUTREC   0x09
#define CIO_PUTCHR   0x0B
#define CIO_CLOSE    0x0C
#define CIO_STATUS   0x0D
#define CIO_RENAME   0x20       /* XIO: "OLD,NEW" */
#define CIO_DELETE   0x21
#define CIO_LOCK     0x23
#define CIO_UNLOCK   0x24
#define CIO_POINT    0x25       /* ICAX3..5: the position */
#define CIO_NOTE     0x26

/* ICAX1 at open */
#define CIO_A_READ   0x04
#define CIO_A_DIR    0x06       /* the directory, as lines */
#define CIO_A_WRITE  0x08
#define CIO_A_APPEND 0x09
#define CIO_A_UPDATE 0x0C

/* ICSTA */
#define CIO_OK       0x01
#define CIO_OK_EOF   0x03       /* success, and the next read would not be */
#define CIO_E_BREAK  0x80
#define CIO_E_INUSE  0x81
#define CIO_E_NODEV  0x82
#define CIO_E_NOTOPEN 0x85
#define CIO_E_EOF    0x88
#define CIO_E_TRUNC  0x89       /* a record longer than the buffer */
#define CIO_E_NOTFOUND 0xAA

#define CIO_EOL      0x9B

/* Call CIO on IOCB `iocb` (0-7), which the caller has filled in.  The
 * program runs in native mode with interrupts off; this is the round
 * trip into the machine the OS expects (src/cio.s).  Returns the status
 * the OS left in Y. */
__attribute__((simple_call)) int __atari_cio(int iocb);

/* ---- the package's own knobs ----------------------------------------- */
/* Non-zero: exit() leaves through DOSVEC rather than returning to the
 * loader.  For a DOS 2 whose DUP.SYS the program has loaded over. */
extern uint8_t __atari_exit_dosvec;

/* S and POKMSK as DOS handed them to the startup. */
extern uint8_t __atari_sp, __atari_pokmsk;

#endif /* ATARI_ATARI_H */
