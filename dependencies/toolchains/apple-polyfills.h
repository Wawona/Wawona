#ifndef WAWONA_APPLE_POLYFILLS_H
#define WAWONA_APPLE_POLYFILLS_H

#include <fcntl.h>
#include <unistd.h>

#ifndef pipe2
static inline int pipe2(int fds[2], int flags) {
    if (pipe(fds) != 0)
        return -1;
    if (flags & O_CLOEXEC) {
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    }
    if (flags & O_NONBLOCK) {
        fcntl(fds[0], F_SETFL, O_NONBLOCK);
        fcntl(fds[1], F_SETFL, O_NONBLOCK);
    }
    return 0;
}
#endif

#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <errno.h>

#if TARGET_OS_TV || TARGET_OS_WATCH
/* fork/exec are prohibited on tvOS/watchOS; stub so glib (gbacktrace)
 * compiles and fails gracefully at runtime instead of at compile time. */
static inline pid_t wwn_apple_fork(void) {
    errno = ENOSYS;
    return (pid_t)-1;
}

#undef fork
#define fork() wwn_apple_fork()

#define execve(file, argv, envp) (-1)
#define execv(file, argv) (-1)
#define execvp(file, argv) (-1)
#endif
#endif

#endif
