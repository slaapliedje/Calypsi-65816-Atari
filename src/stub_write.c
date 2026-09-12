#include <errno.h>
#include <calypsi/stubs.h>
#include "lib.h"

/* Through the bounce buffer, a chunk at a time, translating '\n' to the
 * OS's EOL in text mode. */
size_t _Stub_write(int fd, const void *buf, size_t count)
{
    int iocb = __atari_fd_iocb(fd);
    const uint8_t *p = buf;
    size_t done = 0;
    int text;

    if (iocb < 0 || fd == 0)
        return (size_t)-EBADF;
    text = iocb == 0 || (__atari_fd_text & (1 << iocb));

    while (done < count) {
        unsigned n = 0;
        int r;
        while (n < IOBUF_SIZE && done + n < count) {
            uint8_t c = p[done + n];
            if (text && c == '\n')
                c = CIO_EOL;
            __atari_iobuf[n++] = c;
        }
        r = __atari_cioxfer(iocb, CIO_PUTCHR, __atari_iobuf, n);
        if (r < 0)
            return (size_t)r;
        done += n;
    }
    return count;
}
