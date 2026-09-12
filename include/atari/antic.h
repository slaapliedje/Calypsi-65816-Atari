/* antic.h -- ANTIC, $D400-$D40F */
#ifndef ATARI_ANTIC_H
#define ATARI_ANTIC_H

#include <stdint.h>

#define DMACTL   (*(volatile uint8_t  *)0xD400)
#define CHACTL   (*(volatile uint8_t  *)0xD401)
#define DLISTL   (*(volatile uint16_t *)0xD402)
#define HSCROL   (*(volatile uint8_t  *)0xD404)
#define VSCROL   (*(volatile uint8_t  *)0xD405)
#define PMBASE   (*(volatile uint8_t  *)0xD407)
#define CHBASE   (*(volatile uint8_t  *)0xD409)
#define WSYNC    (*(volatile uint8_t  *)0xD40A)
#define VCOUNT   (*(volatile uint8_t  *)0xD40B)
#define PENH     (*(volatile uint8_t  *)0xD40C)
#define PENV     (*(volatile uint8_t  *)0xD40D)
#define NMIEN    (*(volatile uint8_t  *)0xD40E)
#define NMIRES   (*(volatile uint8_t  *)0xD40F)
#define NMIST    (*(volatile uint8_t  *)0xD40F)

#define NMIEN_VBI 0x40
#define NMIEN_DLI 0x80

#endif /* ATARI_ANTIC_H */
