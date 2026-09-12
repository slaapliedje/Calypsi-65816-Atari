/* fdopen.c -- a replacement for the C library's __fs_fdopen, the piece
 * of fopen() that makes the FILE.
 *
 * Why it is here: cc65816 5.18, small data model, miscompiles
 *
 *     stream->fs_bufend = &stream->fs_bufstart[BUFSIZ];
 *
 * when `stream` is held on the stack -- the load reads fs_bufend instead
 * of fs_bufstart (see docs/cc65816-bug.md for the reproducer), so every
 * stream fopen() makes has fs_bufend = garbage + 64.  fwrite() then
 * copies a whole request into the 64-byte buffer and anything past 64
 * bytes lands on the heap.  The library is shipped compiled, so the
 * only fix short of a new compiler is to supply the function ourselves:
 * an archive named before clib-*.a on the link line wins.
 *
 * While here, fs_next starts out NULL.  The library leaves it as malloc
 * returned it, and fclose() unlinks by walking the list, so with two
 * streams open the walk reads whatever was there.
 *
 * This file goes away once a fixed compiler is the minimum version.
 * The layout of struct __file_struct is the library's (src/lib/file.h
 * in the Calypsi distribution, with _CONFIG_NUNGET_CHARS 0); it is
 * checked against sizeof at link time by the library itself in no way,
 * so keep it in step if Calypsi changes it. */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>

struct __file_struct {
    struct __file_struct *fs_next;
    int                   fs_fd;
    unsigned char        *fs_bufstart;
    unsigned char        *fs_bufend;
    unsigned char        *fs_bufpos;
    unsigned char        *fs_bufread;
    uint16_t              fs_oflags;
    uint8_t               fs_flags;
};

int __fs_fdopen(int fd, int oflags, FILE **filep)
{
    struct __streamlist *slist = &__global_streams;
    FILE *stream;
    unsigned char *buf;

    if (fd < 0) {
        if (filep)
            *filep = NULL;
        return -EBADF;
    }
    if (fd >= 3) {
        stream = malloc(sizeof *stream);
        buf = stream ? malloc(BUFSIZ) : NULL;
        if (buf == NULL) {
            free(stream);
            if (filep)
                *filep = NULL;
            return -ENOMEM;
        }
        stream->fs_next = NULL;
        stream->fs_flags = 0;
        stream->fs_bufstart = buf;
        stream->fs_bufend = buf + BUFSIZ;
        stream->fs_bufpos = buf;
        stream->fs_bufread = buf;
        if (slist->sl_tail)
            slist->sl_tail->fs_next = stream;
        else
            slist->sl_head = stream;
        slist->sl_tail = stream;
    } else {
        stream = slist->sl_std[fd];
    }
    stream->fs_fd = fd;
    stream->fs_oflags = (uint16_t)oflags;
    if (filep)
        *filep = stream;
    return 0;
}
