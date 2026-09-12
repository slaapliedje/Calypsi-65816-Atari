#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <calypsi/stubs.h>
#include "lib.h"

/* CIO's idea of a mode.  The OS opens a device; a DOS opens a file, and
 * a DOS's write (8) creates or truncates, append (9) extends, update
 * (12) reads and writes a file that exists already.  So "w+" is a write
 * open to make the file, closed, then an update open; "a+" is update
 * positioned at the end. */
static uint8_t cio_mode(int oflag)
{
    int rw = oflag & O_RDWR;
    if (rw == O_RDWR)
        return CIO_A_UPDATE;
    if (rw == O_WRONLY)
        return (oflag & O_APPEND) ? CIO_A_APPEND : CIO_A_WRITE;
    return CIO_A_READ;
}

static int cio_open(int iocb, unsigned namelen, uint8_t mode)
{
    volatile IOCB *io = &CIO_IOCB[iocb];
    int status;

    io->iccom = CIO_OPEN;
    io->icbal = (uint16_t)__atari_iobuf;
    io->icbll = namelen;
    io->icax1 = mode;
    io->icax2 = 0;
    status = __atari_cio(iocb);
    if (status >= 0x80) {
        int err = __atari_cioerr(status);
        return err ? err : -EIO;
    }
    return 0;
}

static void cio_close(int iocb)
{
    CIO_IOCB[iocb].iccom = CIO_CLOSE;
    __atari_cio(iocb);
}

int _Stub_open(const char *path, int oflag, ...)
{
    int iocb, r, rw = oflag & O_RDWR;
    unsigned n;
    struct atari_pos *ps;

    for (iocb = 1; iocb <= 7; iocb++)
        if (CIO_IOCB[iocb].ichid == 0xFF && !(__atari_fd_open & (1 << iocb)))
            break;
    if (iocb > 7)
        return -EMFILE;

    for (n = 0; path[n] != 0; n++) {
        if (n >= IOBUF_SIZE - 1)
            return -EINVAL;
        __atari_iobuf[n] = (uint8_t)path[n];
    }
    __atari_iobuf[n++] = CIO_EOL;

    if ((oflag & (O_CREAT | O_EXCL)) == (O_CREAT | O_EXCL)) {
        r = cio_open(iocb, n, CIO_A_READ);
        if (r == 0) {
            cio_close(iocb);
            return -EEXIST;
        }
    }
    if (rw == O_RDWR && (oflag & O_TRUNC)) {
        r = cio_open(iocb, n, CIO_A_WRITE);
        if (r < 0)
            return r;
        cio_close(iocb);
    }
    r = cio_open(iocb, n, cio_mode(oflag));
    if (r == -ENOENT && rw == O_RDWR && (oflag & O_CREAT)) {
        r = cio_open(iocb, n, CIO_A_WRITE);
        if (r < 0)
            return r;
        cio_close(iocb);
        r = cio_open(iocb, n, CIO_A_UPDATE);
    }
    if (r < 0)
        return r;

    __atari_fd_open |= 1 << iocb;
    if (oflag & O_BINARY)
        __atari_fd_text &= ~(1 << iocb);
    else
        __atari_fd_text |= 1 << iocb;

    ps = &__atari_pos[iocb];
    ps->pos = ps->pos_last = 0;
    ps->kind = POS_UNKNOWN;
    ps->note0 = __atari_note(iocb);
    if (ps->note0 < 0)
        ps->kind = POS_NONE;
    ps->note_last = ps->note0;

    if (rw == O_RDWR && (oflag & O_APPEND)) {
        long e = __atari_seek(iocb, 0, SEEK_END);
        if (e < 0) {
            cio_close(iocb);
            __atari_fd_open &= ~(1 << iocb);
            return (int)e;
        }
    }
    return iocb + 2;
}
