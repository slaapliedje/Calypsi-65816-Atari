#include <errno.h>
#include <calypsi/stubs.h>
#include "lib.h"

/* XIO on a free IOCB: the DOS takes the name from the buffer and needs
 * nothing open. */
static int xio(int cmd, const char *name)
{
    int iocb, status;
    unsigned n;
    volatile IOCB *io;

    for (iocb = 7; iocb >= 1; iocb--)
        if (CIO_IOCB[iocb].ichid == 0xFF && !(__atari_fd_open & (1 << iocb)))
            break;
    if (iocb < 1)
        return -EMFILE;
    for (n = 0; name[n] != 0; n++) {
        if (n >= IOBUF_SIZE - 1)
            return -EINVAL;
        __atari_iobuf[n] = (uint8_t)name[n];
    }
    __atari_iobuf[n] = CIO_EOL;
    io = &CIO_IOCB[iocb];
    io->iccom = cmd;
    io->icbal = (uint16_t)__atari_iobuf;
    io->icbll = n + 1;
    io->icax1 = 0;
    io->icax2 = 0;
    status = __atari_cio(iocb);
    if (status >= 0x80)
        return __atari_cioerr(status);
    return 0;
}

int _Stub_remove(const char *path)
{
    return xio(CIO_DELETE, path);
}

/* The DOS wants "D:OLD,NEW" in one buffer, and NEW without its device. */
int _Stub_rename(const char *oldpath, const char *newpath)
{
    char both[IOBUF_SIZE];
    unsigned i = 0, j;

    while (oldpath[i] != 0) {
        if (i >= IOBUF_SIZE - 2)
            return -EINVAL;
        both[i] = oldpath[i];
        i++;
    }
    both[i++] = ',';
    if (newpath[0] != 0 && newpath[1] == ':')
        newpath += 2;
    else if (newpath[0] != 0 && newpath[1] != 0 && newpath[2] == ':')
        newpath += 3;
    for (j = 0; newpath[j] != 0; j++) {
        if (i >= IOBUF_SIZE - 1)
            return -EINVAL;
        both[i++] = newpath[j];
    }
    both[i] = 0;
    return xio(CIO_RENAME, both);
}
