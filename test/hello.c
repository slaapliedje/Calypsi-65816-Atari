/* hello.c -- the smallest program that proves the package: stdio through
 * the OS's E: in both directions, a word for the test harness at $0600,
 * and a clean return to the DOS.  Built in both code models by `make test`.
 *
 * The program waits for RETURN before it leaves, for two reasons.  A
 * person running it from a DOS gets to read the screen before the DOS
 * redraws it; and the harness (run-altirra.py) gets a window in which
 * the output is still on the screen, then proves stdin by pressing the
 * key itself.  stdin is E:, and E: is line input: getchar() returns the
 * first character of the line typed, which for a bare RETURN is the
 * EOL -- translated to '\n' by the text-mode read. */
#include <stdio.h>
#include <stdint.h>
#include <atari/atari.h>

#ifdef __CALYPSI_CODE_MODEL_LARGE__
#define MODEL "large"
#else
#define MODEL "small"
#endif

/* Page 6, which every DOS leaves alone: the harness reads it back.
 *   0-1  "OK"          the computation is done and the text is up
 *   2-3  the sum       385, little-endian
 *   4    the key       what getchar() returned, after RETURN */
#define MARK ((volatile uint8_t *)0x0600)

static int square(int n)
{
    return n * n;
}

int main(void)
{
    int i, c, sum = 0;

    MARK[0] = MARK[1] = MARK[4] = 0;
    printf("Hello from Calypsi (%s code model)\n", MODEL);
    for (i = 1; i <= 10; i++)
        sum += square(i);
    printf("1^2 + ... + 10^2 = %d\n", sum);
    printf("MEMLO $%04X  MEMTOP $%04X\n", MEMLO, MEMTOP);
    printf("Press RETURN to exit.\n");

    MARK[2] = (uint8_t)sum;
    MARK[3] = (uint8_t)(sum >> 8);
    MARK[0] = 'O';
    MARK[1] = 'K';

    c = getchar();
    MARK[4] = (uint8_t)c;
    return 0;
}
