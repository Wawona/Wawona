#include "wrap.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <unistd.h>

#include "compat_ppoll.h"

extern typeof(read) *wrap_real_read;
extern typeof(write) *wrap_real_write;
extern typeof(close) *wrap_real_close;
extern typeof(poll) *wrap_real_poll;
#if !defined(__APPLE__)
extern typeof(ppoll) *wrap_real_ppoll;
#endif
extern typeof(fcntl) *wrap_real_fcntl;

ssize_t
real_read(int fd, void *buf, size_t nbytes)
{
  return wrap_real_read(fd, buf, nbytes);
}

ssize_t
real_write(int fd, void const *buf, size_t nbytes)
{
  return wrap_real_write(fd, buf, nbytes);
}

int
real_close(int fd)
{
  return wrap_real_close(fd);
}

int
real_poll(struct pollfd fds[], nfds_t nfds, int timeout)
{
  return wrap_real_poll(fds, nfds, timeout);
}

int
real_ppoll(struct pollfd fds[], nfds_t nfds,
    struct timespec const *restrict timeout,
    sigset_t const *restrict newsigmask)
{
#ifdef __APPLE__
  return compat_ppoll(fds, nfds, timeout, newsigmask);
#else
  return wrap_real_ppoll(fds, nfds, timeout, newsigmask);
#endif
}

int
real_fcntl(int fd, int cmd, ...)
{
  va_list ap;
  va_start(ap, cmd);
  void *arg = va_arg(ap, void *);
  int rv = wrap_real_fcntl(fd, cmd, arg);
  va_end(ap);
  return rv;
}
