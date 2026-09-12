#include <errno.h>
#include <stdio.h>
#include <calypsi/stubs.h>
#include "lib.h"

/* The stubs count bytes, so a position is a byte offset under every
 * DOS.  Where the DOS counts bytes too (SpartaDOS) a seek is a POINT.
 * Where it hands out sector/byte cookies (DOS 2, MyDOS, Altirra's H:)
 * a seek forward reads and discards, and a seek back POINTs to the
 * nearest place a cookie was taken -- the start of the last transfer,
 * or the start of the file -- and reads forward from there.  Slow for
 * a long way back in a big file, but right.  SEEK_END reads to the
 * end: no DOS tells CIO a file's length. */

static long point(int iocb, long pos)
{
    volatile IOCB *io = &CIO_IOCB[iocb];
    int status;

    io->iccom = CIO_POINT;
    io->icax3 = (uint8_t)pos;
    io->icax4 = (uint8_t)(pos >> 8);
    io->icax5 = (uint8_t)(pos >> 16);
    status = __atari_cio(iocb);
    if (status >= 0x80)
        return __atari_cioerr(status);
    return pos;
}

static long seek_to(int iocb, long n)
{
    struct atari_pos *ps = &__atari_pos[iocb];
    long r;

    if (n < 0 || n > 0xFFFFFFL)
        return -EINVAL;
    if (ps->kind == POS_NONE)
        return -ESPIPE;
    if (n < ps->pos && ps->kind != POS_BYTES) {
        int last = n >= ps->pos_last;   /* the last transfer's start will do */
        r = point(iocb, last ? ps->note_last : ps->note0);
        if (r < 0)
            return r;
        if (!last) {
            ps->note_last = ps->note0;
            ps->pos_last = 0;
        }
        ps->pos = ps->pos_last;
    }
    while (ps->pos != n) {
        if (ps->kind == POS_BYTES) {
            r = point(iocb, n);
            if (r < 0)
                return r;
            ps->pos = n;
            break;
        }
        {
            long left = n - ps->pos;
            unsigned want = left < IOBUF_SIZE ? (unsigned)left : IOBUF_SIZE;
            int got = __atari_cioxfer(iocb, CIO_GETCHR, __atari_iobuf, want);
            if (got < 0)
                return got;
            if (got == 0)
                return -EINVAL;     /* the end came first */
        }
    }
    return n;
}

long __atari_seek(int iocb, long offset, int whence)
{
    struct atari_pos *ps = &__atari_pos[iocb];

    if (iocb == 0)
        return -ESPIPE;
    switch (whence) {
    case SEEK_SET:
        return seek_to(iocb, offset);
    case SEEK_CUR:
        if (offset == 0)
            return ps->pos;
        return seek_to(iocb, ps->pos + offset);
    case SEEK_END:
        if (ps->kind == POS_NONE)
            return -ESPIPE;
        for (;;) {
            int got = __atari_cioxfer(iocb, CIO_GETCHR, __atari_iobuf, IOBUF_SIZE);
            if (got < 0)
                return got;
            if (got == 0)
                break;
        }
        return seek_to(iocb, ps->pos + offset);
    default:
        return -EINVAL;
    }
}

long _Stub_lseek(int fd, long offset, int whence)
{
    int iocb = __atari_fd_iocb(fd);

    if (iocb < 0)
        return -EBADF;
    return __atari_seek(iocb, offset, whence);
}

int _Stub_fgetpos(int fd, fpos_t *pos)
{
    long r = _Stub_lseek(fd, 0, SEEK_CUR);
    if (r < 0)
        return (int)r;
    *pos = r;
    return 0;
}

int _Stub_fsetpos(int fd, const fpos_t *pos)
{
    long r = _Stub_lseek(fd, (long)*pos, SEEK_SET);
    return r < 0 ? (int)r : 0;
}
