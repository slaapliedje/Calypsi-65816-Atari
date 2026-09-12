/* gtia.h -- GTIA, $D000-$D01F */
#ifndef ATARI_GTIA_H
#define ATARI_GTIA_H

#include <stdint.h>

#define HPOSP0   ((volatile uint8_t *)0xD000)    /* [0..3] players, write */
#define HPOSM0   ((volatile uint8_t *)0xD004)    /* [0..3] missiles */
#define SIZEP0   ((volatile uint8_t *)0xD008)
#define SIZEM    (*(volatile uint8_t *)0xD00C)
#define GRAFP0   ((volatile uint8_t *)0xD00D)
#define GRAFM    (*(volatile uint8_t *)0xD011)
#define COLPM0   ((volatile uint8_t *)0xD012)    /* [0..3] */
#define COLPF0   ((volatile uint8_t *)0xD016)    /* [0..3] */
#define COLBK    (*(volatile uint8_t *)0xD01A)
#define PRIOR    (*(volatile uint8_t *)0xD01B)
#define VDELAY   (*(volatile uint8_t *)0xD01C)
#define GRACTL   (*(volatile uint8_t *)0xD01D)
#define HITCLR   (*(volatile uint8_t *)0xD01E)
#define CONSOL   (*(volatile uint8_t *)0xD01F)

#define M0PF     ((volatile uint8_t *)0xD000)    /* read: collisions */
#define P0PF     ((volatile uint8_t *)0xD004)
#define M0PL     ((volatile uint8_t *)0xD008)
#define P0PL     ((volatile uint8_t *)0xD00C)
#define TRIG0    ((volatile uint8_t *)0xD010)    /* [0..3] */
#define PAL      (*(volatile uint8_t *)0xD014)

#endif /* ATARI_GTIA_H */
