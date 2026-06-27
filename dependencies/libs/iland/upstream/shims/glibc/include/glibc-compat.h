#ifndef GLIBC_COMPAT_H
#define GLIBC_COMPAT_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* fopencookie (glibc) -> funopen (BSD/macOS) wrapper.
 * glibc-specific extensions that macOS lacks, provided via BSD equivalents. */

typedef struct {
    ssize_t (*read)(void *cookie, char *buf, size_t size);
    ssize_t (*write)(void *cookie, const char *buf, size_t size);
    int     (*seek)(void *cookie, fpos_t *offset, int whence);
    int     (*close)(void *cookie);
} cookie_io_functions_t;

FILE *fopencookie(void *cookie, const char *mode,
                  cookie_io_functions_t io_funcs);

#ifdef __cplusplus
}
#endif

#endif /* GLIBC_COMPAT_H */
