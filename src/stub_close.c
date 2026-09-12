#include <errno.h>
#include <calypsi/stubs.h>
#include "lib.h"

int _Stub_close(int fd)
{
    int iocb = __atari_fd_iocb(fd);
    int status;

    if (iocb <= 0)
        return -EBADF;
    CIO_IOCB[iocb].iccom = CIO_CLOSE;
    status = __atari_cio(iocb);
    __atari_fd_open &= ~(1 << iocb);
    if (status >= 0x80)
        return __atari_cioerr(status);
    return 0;
}
