#include <errno.h>
#include <calypsi/stubs.h>
#include "lib.h"

/* E: hands back a whole typed line, EOL included, however it is asked;
 * a file hands back what was asked for.  Text mode turns EOL into '\n'. */
size_t _Stub_read(int fd, void *buf, size_t count)
{
    int iocb = __atari_fd_iocb(fd);
    uint8_t *p = buf;
    unsigned n, i;
    int r, text;

    if (iocb < 0 || fd == 1 || fd == 2)
        return (size_t)-EBADF;
    text = iocb == 0 || (__atari_fd_text & (1 << iocb));

    n = count < IOBUF_SIZE ? (unsigned)count : IOBUF_SIZE;
    r = __atari_cioxfer(iocb, CIO_GETCHR, __atari_iobuf, n);
    if (r <= 0)
        return (size_t)r;
    for (i = 0; i < (unsigned)r; i++) {
        uint8_t c = __atari_iobuf[i];
        if (text && c == CIO_EOL)
            c = '\n';
        p[i] = c;
    }
    return r;
}
