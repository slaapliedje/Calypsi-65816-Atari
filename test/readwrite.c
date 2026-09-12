/* readwrite.c -- the file stubs, through stdio, against a device that
 * behaves like a DOS: text and binary files, every fopen mode, seeking
 * in both directions, rename and remove.  Built by `make test` in the
 * large code model; run-altirra.py runs it against Altirra's H: host
 * device, whose NOTE/POINT cookies are the DOS 2 kind, which is the
 * hard case for the seek code (see src/stub_lseek.c).  -DRW_DEVICE='"D:"'
 * points it at a DOS disk instead.
 *
 * Page 6 carries the verdict for the harness:
 *   0-1  "RW"    everything ran and the counts are in
 *   2    passed
 *   3    total
 *   4    the key, after RETURN (as in hello.c) */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdint.h>
#include <atari/atari.h>

#ifndef RW_DEVICE
#define RW_DEVICE "H:"
#endif
#define TEXT   RW_DEVICE "RWTEST.TXT"
#define MOVED  RW_DEVICE "RWDONE.TXT"
#define BIN    RW_DEVICE "RWTEST.BIN"
#define PLUS   RW_DEVICE "RWPLUS.TXT"

#define MARK ((volatile uint8_t *)0x0600)

static const char *lines[] = { "alpha\n", "beta  gamma\n", "delta\n" };
#define L0 6            /* strlen(lines[0]) */
#define L1 12
#define L2 6

static int passed, total;

/* A dot per pass, a line per failure: forty columns and twenty-four
 * rows do not hold a line per check. */
static void check(const char *what, int ok)
{
    total++;
    if (ok) {
        passed++;
        putchar('.');
    } else {
        printf("\nFAIL %s (errno %d)\n", what, errno);
    }
}

static int same_line(FILE *f, const char *want)
{
    char buf[40];
    if (fgets(buf, sizeof buf, f) == NULL)
        return 0;
    return strcmp(buf, want) == 0;
}

static void text_files(void)
{
    FILE *f;
    char buf[40];
    fpos_t pos;
    int i, n;

    f = fopen(TEXT, "w");
    check("fopen w", f != NULL);
    if (f == NULL)
        return;
    for (i = 0; i < 3; i++)
        fputs(lines[i], f);
    check("fclose after write", fclose(f) == 0);

    f = fopen(TEXT, "r");
    check("fopen r", f != NULL);
    if (f == NULL)
        return;
    check("line 1", same_line(f, lines[0]));
    /* The library's fgetpos() reports where the file descriptor is, not
     * where the stream is: unlike ftell() it does not subtract the
     * read-ahead still in the buffer (Calypsi 5.18, lib_fgetpos.c).
     * The fseek() drops the read-ahead first, so the two agree. */
    fseek(f, 0, SEEK_CUR);
    fgetpos(f, &pos);
    check("line 2", same_line(f, lines[1]));
    check("line 3", same_line(f, lines[2]));
    check("eof after 3", fgets(buf, sizeof buf, f) == NULL && feof(f));
    check("ftell at end", ftell(f) == L0 + L1 + L2);

    rewind(f);
    check("rewind, line 1", same_line(f, lines[0]));
    check("fseek set", fseek(f, L0 + L1, SEEK_SET) == 0 && same_line(f, lines[2]));
    check("fseek end", fseek(f, -L2, SEEK_END) == 0 && same_line(f, lines[2]));
    check("fseek cur back", fseek(f, -(L1 + L2), SEEK_CUR) == 0 && same_line(f, lines[1]));
    check("fsetpos", fsetpos(f, &pos) == 0 && same_line(f, lines[1]));
    fclose(f);

    f = fopen(TEXT, "r+");
    check("fopen r+", f != NULL);
    if (f != NULL) {
        fseek(f, L0, SEEK_SET);
        fputs("BETA  GAMMA\n", f);
        fclose(f);
        f = fopen(TEXT, "r");
        check("r+ rewrote line 2", f != NULL && same_line(f, lines[0])
              && same_line(f, "BETA  GAMMA\n") && same_line(f, lines[2]));
        if (f != NULL)
            fclose(f);
    }

    f = fopen(TEXT, "a");
    check("fopen a", f != NULL);
    if (f != NULL) {
        fputs("epsilon\n", f);
        fclose(f);
        f = fopen(TEXT, "r");
        n = 0;
        while (f != NULL && fgets(buf, sizeof buf, f) != NULL)
            n++;
        check("a added a 4th line", n == 4 && strcmp(buf, "epsilon\n") == 0);
        if (f != NULL)
            fclose(f);
    }

    f = fopen(PLUS, "w+");
    check("fopen w+", f != NULL);
    if (f != NULL) {
        fputs("plus\n", f);
        rewind(f);
        check("w+ reads back", same_line(f, "plus\n"));
        fclose(f);
        check("remove w+ file", remove(PLUS) == 0);
    }
}

static void binary_file(void)
{
    FILE *f;
    static uint8_t buf[256];
    int i, bad = 0;

    f = fopen(BIN, "wb");
    check("fopen wb", f != NULL);
    if (f == NULL)
        return;
    for (i = 0; i < 256; i++)
        buf[i] = (uint8_t)i;
    check("fwrite 256", fwrite(buf, 1, 256, f) == 256);
    fclose(f);

    f = fopen(BIN, "rb");
    check("fopen rb", f != NULL);
    if (f == NULL)
        return;
    memset(buf, 0xAA, sizeof buf);
    check("fread 256", fread(buf, 1, 256, f) == 256);
    for (i = 0; i < 256; i++)
        if (buf[i] != i)
            bad++;
    check("every byte, $9B and $0A too", bad == 0);
    check("eof after 256", fgetc(f) == EOF);
    check("ftell 256", ftell(f) == 256);
    check("seek back 100", fseek(f, 100, SEEK_SET) == 0 && fgetc(f) == 100);
    check("seek fwd 200", fseek(f, 200, SEEK_SET) == 0 && fgetc(f) == 200);
    check("seek cur -50", fseek(f, -50, SEEK_CUR) == 0 && fgetc(f) == 151);
    check("seek end -1", fseek(f, -1, SEEK_END) == 0 && fgetc(f) == 255);
    fclose(f);
    check("remove bin", remove(BIN) == 0);
}

static void rename_remove(void)
{
    FILE *f;

    check("rename", rename(TEXT, MOVED) == 0);
    f = fopen(TEXT, "r");
    check("old name gone", f == NULL && errno == ENOENT);
    if (f != NULL)
        fclose(f);
    f = fopen(MOVED, "r");
    check("new name reads", f != NULL && same_line(f, lines[0]));
    if (f != NULL)
        fclose(f);
    check("remove", remove(MOVED) == 0);
    f = fopen(MOVED, "r");
    check("removed", f == NULL && errno == ENOENT);
    if (f != NULL)
        fclose(f);
    check("remove missing fails", remove(MOVED) != 0);
}

int main(void)
{
    int c;

    MARK[0] = MARK[1] = MARK[4] = 0;
    printf("readwrite on %s\n", RW_DEVICE);
    text_files();
    binary_file();
    rename_remove();
    printf("\nreadwrite: %d/%d passed\n", passed, total);
    printf("Press RETURN to exit.\n");
    MARK[2] = (uint8_t)passed;
    MARK[3] = (uint8_t)total;
    MARK[0] = 'R';
    MARK[1] = 'W';
    c = getchar();
    MARK[4] = (uint8_t)c;
    return 0;
}
