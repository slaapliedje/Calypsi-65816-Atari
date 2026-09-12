/* lib.h -- what the stubs share.  Not installed; the public face is
 * include/atari/atari.h. */
#ifndef ATARI_LIB_H
#define ATARI_LIB_H

#include <stdint.h>
#include <atari/atari.h>

/* fd 0-2 are the console (IOCB 0, the E: the OS opened); fd 3..9 are
 * IOCB 1..7. */
#define FD_MIN     3
#define FD_MAX     9
#define FD_IOCB(fd) ((fd) - 2)

/* One bit per IOCB. */
extern uint8_t __atari_fd_open;     /* opened by _Stub_open */
extern uint8_t __atari_fd_text;     /* '\n' <-> EOL translation */

/* Where a file is.  NOTE and POINT carry a 24-bit position, but what it
 * means is the DOS's business: SpartaDOS counts bytes, DOS 2 (and MyDOS,
 * and Altirra's H:) hands out a sector/byte pair that is only good for
 * going back to.  So the stubs count bytes themselves, and turn a byte
 * position into a POINT when the DOS counts bytes too, or into a POINT
 * to a position they have a cookie for followed by reading forward. */
#define POS_UNKNOWN 0   /* nothing moved yet */
#define POS_BYTES   1   /* NOTE returns a byte offset */
#define POS_COOKIE  2   /* NOTE returns something else */
#define POS_NONE    3   /* NOTE fails: not a file */

struct atari_pos {
    long    pos;        /* the byte position, counted here */
    long    note0;      /* NOTE right after OPEN: the start */
    long    note_last;  /* NOTE before the last transfer or after the
                           last POINT, and the byte position then */
    long    pos_last;
    uint8_t kind;       /* POS_* */
};
extern struct atari_pos __atari_pos[CIO_IOCBS];

/* A bank-$00 bounce buffer: CIO addresses 16 bits, and the file name
 * has to end in an EOL. */
#define IOBUF_SIZE 256
extern uint8_t __atari_iobuf[IOBUF_SIZE];

/* A CIO status ($80 and up) as a negated errno. */
int __atari_cioerr(int status);

/* Fill in IOCB `iocb` and call CIO.  Returns the bytes moved, or a
 * negated errno; end of file is 0.  Keeps __atari_pos up to date. */
int __atari_cioxfer(int iocb, int cmd, const void *buf, unsigned len);

/* NOTE on IOCB `iocb`: the 24-bit position, or a negated errno. */
long __atari_note(int iocb);

/* Move IOCB `iocb` to byte `offset` from `whence` (SEEK_*), returning
 * the new position or a negated errno. */
long __atari_seek(int iocb, long offset, int whence);

/* The IOCB an fd names, or -1. */
int __atari_fd_iocb(int fd);

#endif /* ATARI_LIB_H */
