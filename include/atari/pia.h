/* pia.h -- the 6520 PIA, $D300-$D303: joystick ports, PORTB banking */
#ifndef ATARI_PIA_H
#define ATARI_PIA_H

#include <stdint.h>

#define PORTA    (*(volatile uint8_t *)0xD300)
#define PORTB    (*(volatile uint8_t *)0xD301)
#define PACTL    (*(volatile uint8_t *)0xD302)
#define PBCTL    (*(volatile uint8_t *)0xD303)

/* PORTB on an XL/XE */
#define PORTB_OSROM   0x01      /* 1: the OS ROM is in at $C000-$FFFF */
#define PORTB_BASIC   0x02      /* 0: BASIC is in at $A000-$BFFF */
#define PORTB_SELFTEST 0x80     /* 0: the self test is in at $5000-$57FF */

#endif /* ATARI_PIA_H */
