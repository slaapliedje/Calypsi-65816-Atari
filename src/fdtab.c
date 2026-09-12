/* fdtab.c -- the file descriptor table and the CIO round trip the stubs
 * share. */
#include <errno.h>
#include "lib.h"

uint8_t __atari_fd_open;
uint8_t __atari_fd_text;
uint8_t __atari_iobuf[IOBUF_SIZE];
struct atari_pos __atari_pos[CIO_IOCBS];

int __atari_cioerr(int status)
{
    switch (status) {
    case 0x80: return -EINTR;       /* BREAK */
    case 0x81: return -EBUSY;       /* IOCB in use */
    case 0x82: return -ENODEV;      /* no such device */
    case 0x84: return -EINVAL;      /* invalid command */
    case 0x85: return -EBADF;       /* not open */
    case 0x86: return -EBADF;       /* invalid IOCB */
    case 0x87: return -EACCES;      /* write to a read-only channel */
    case 0x88: return 0;            /* end of file */
    case 0x89: return 0;            /* record truncated: the data is there */
    case 0x92: return -EINVAL;      /* function not implemented */
    case 0xA0: return -ENODEV;      /* drive number */
    case 0xA1: return -EMFILE;      /* the DOS's file table is full */
    case 0xA2: return -ENOSPC;      /* disk full */
    case 0xA5: return -EINVAL;      /* file name */
    case 0xA6: return -EINVAL;      /* POINT length */
    case 0xA7: return -EACCES;      /* locked */
    case 0xA8: return -EINVAL;      /* command not for this device */
    case 0xA9: return -ENOSPC;      /* directory full */
    case 0xAA: return -ENOENT;      /* not found */
    case 0xAB: return -EINVAL;      /* POINT invalid */
    default:   return -EIO;
    }
}

long __atari_note(int iocb)
{
    volatile IOCB *io = &CIO_IOCB[iocb];
    int status;

    io->iccom = CIO_NOTE;
    status = __atari_cio(iocb);
    if (status >= 0x80)
        return __atari_cioerr(status);
    return (long)io->icax3 | ((long)io->icax4 << 8) | ((long)io->icax5 << 16);
}

int __atari_cioxfer(int iocb, int cmd, const void *buf, unsigned len)
{
    volatile IOCB *io = &CIO_IOCB[iocb];
    struct atari_pos *ps = &__atari_pos[iocb];
    int status, moved;

    /* Until the DOS has shown that it counts bytes, remember where each
     * transfer starts: it is the only kind of place a seek can go back
     * to.  A device that cannot NOTE cannot seek either. */
    if (iocb != 0 && (ps->kind == POS_UNKNOWN || ps->kind == POS_COOKIE)) {
        long c = __atari_note(iocb);
        if (c < 0) {
            ps->kind = POS_NONE;
        } else {
            ps->note_last = c;
            ps->pos_last = ps->pos;
        }
    }

    io->iccom = cmd;
    io->icbal = (uint16_t)buf;
    io->icbll = len;
    status = __atari_cio(iocb);
    if (status == CIO_E_EOF)        /* what was there before the end */
        moved = io->icbll < len ? io->icbll : 0;
    else if (status >= 0x80)
        return __atari_cioerr(status);
    else
        moved = io->icbll;

    if (iocb != 0 && moved > 0) {
        if (ps->kind == POS_UNKNOWN) {
            long c = __atari_note(iocb);
            ps->kind = c == ps->note_last + moved ? POS_BYTES : POS_COOKIE;
        }
        ps->pos += moved;
    }
    return moved;
}

int __atari_fd_iocb(int fd)
{
    if (fd >= 0 && fd <= 2)
        return 0;
    if (fd >= FD_MIN && fd <= FD_MAX && (__atari_fd_open & (1 << FD_IOCB(fd))))
        return FD_IOCB(fd);
    return -1;
}
