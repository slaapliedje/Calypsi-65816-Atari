/* rapidus.h -- the Rapidus 65C816 accelerator
 *
 * Two register files.  The first is on the motherboard bus, mapped only
 * while the card's PBI device is selected through PDVS ($D1FF), and is
 * what the 6502 side sees; the startup uses it to switch the CPU
 * (src/cpu.s).  The second is in bank $FF and exists only for the 65816.
 * Semantics as Altirra's rapidus.cpp implements them; there is no public
 * register document.
 *
 * The board comes up with every 16 KB window of bank $00 on the 1.79 MHz
 * motherboard bus.  A program that wants its bank-$00 data fast switches
 * the card's SRAM in over it through the MCR; the Rapidus copies with
 * write-through, so the motherboard stays coherent unless CMCR bit 6 is
 * set for window 0.  Nothing in this package does that for you: which
 * windows can go fast depends on what else is on the bus (a VBXE's MEMAC
 * window, for one, is invisible from a fast window).
 */
#ifndef ATARI_RAPIDUS_H
#define ATARI_RAPIDUS_H

#include <stdint.h>

/* From the 6502 side, with the card's PBI slot selected. */
#define PDVS       (*(volatile uint8_t *)0xD1FF)
#define RAP_BANK   (*(volatile uint8_t *)0xD190)  /* FPGA bank register */
#define RAP_CFG    (*(volatile uint8_t *)0xD191)  /* FPGA config */
#define RAP_CFG_6502  0x40      /* bit 6: the 6502 is the CPU */

/* The bank $FF register file (65816 only). */
#define RAP_SIG    ((const volatile char __far *)0xFF0000UL)  /* "6S9038E " */
#define RAP_MCR    (*(volatile uint8_t __far *)0xFF0080UL)    /* Memory Control */
#define RAP_CMCR   (*(volatile uint8_t __far *)0xFF0081UL)    /* Complementary MCR */
#define RAP_SCR    (*(volatile uint8_t __far *)0xFF0082UL)    /* bit 7: cache off */
#define RAP_6502CR (*(volatile uint8_t __far *)0xFF0084UL)    /* bit 1: back to the 6502 */

#define MCR_SLOW0    0x01       /* $0000-$3FFF on the motherboard bus */
#define MCR_SLOW1    0x02       /* $4000-$7FFF */
#define MCR_SLOW2    0x04       /* $8000-$BFFF */
#define MCR_SLOW3    0x08       /* $C000-$FFFF */
#define MCR_SLOWALL  0x0F
#define MCR_WRTHRU   0x20       /* fast windows write through to the bus */
#define MCR_IO       0x40       /* $D000-$D7FF is hardware */
#define MCR_BASEOS   0x80
#define CMCR_FAST0   0x40       /* window 0 writes stay in SRAM */

#endif /* ATARI_RAPIDUS_H */
