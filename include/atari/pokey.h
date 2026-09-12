/* pokey.h -- POKEY, $D200-$D20F */
#ifndef ATARI_POKEY_H
#define ATARI_POKEY_H

#include <stdint.h>

#define AUDF1    (*(volatile uint8_t *)0xD200)
#define AUDC1    (*(volatile uint8_t *)0xD201)
#define AUDF2    (*(volatile uint8_t *)0xD202)
#define AUDC2    (*(volatile uint8_t *)0xD203)
#define AUDF3    (*(volatile uint8_t *)0xD204)
#define AUDC3    (*(volatile uint8_t *)0xD205)
#define AUDF4    (*(volatile uint8_t *)0xD206)
#define AUDC4    (*(volatile uint8_t *)0xD207)
#define AUDCTL   (*(volatile uint8_t *)0xD208)
#define STIMER   (*(volatile uint8_t *)0xD209)
#define SKRES    (*(volatile uint8_t *)0xD20A)
#define POTGO    (*(volatile uint8_t *)0xD20B)
#define SEROUT   (*(volatile uint8_t *)0xD20D)
#define IRQEN    (*(volatile uint8_t *)0xD20E)
#define SKCTL    (*(volatile uint8_t *)0xD20F)

#define POT0     ((volatile uint8_t *)0xD200)    /* read: [0..7] */
#define ALLPOT   (*(volatile uint8_t *)0xD208)
#define KBCODE   (*(volatile uint8_t *)0xD209)
#define RANDOM   (*(volatile uint8_t *)0xD20A)
#define SERIN    (*(volatile uint8_t *)0xD20D)
#define IRQST    (*(volatile uint8_t *)0xD20E)
#define SKSTAT   (*(volatile uint8_t *)0xD20F)

#endif /* ATARI_POKEY_H */
