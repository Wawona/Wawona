/*
 * WWNLog.h. Unified logging for Wawona
 *
 * Format: YYYY-MM-DD HH:MM:SS [MODULE] message
 *
 * Writes to a preserved stderr fd so in-process zsh (dup2 onto fds 0-2) does
 * not route compositor logs into weston-terminal.
 *
 * Usage (ObjC):  WWNLog("BRIDGE", @"Output: %ux%u", w, h);
 * Usage (C):     WWNLog("SEAT",   "Created fd=%d", fd);
 * Usage (fd):    WWNLogFd(fd, "WAYPIPE", "Exit code: %d", rc);
 */

#ifndef WWNLOG_H
#define WWNLOG_H

#include <pthread.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

/*
 * Optional startup log sink.
 *
 * When WWNStartupLogger is active (during client launch), this function
 * pointer is set to a thin C shim that forwards each log entry into the
 * native scrollable startup log view.  It is reset to NULL after the view
 * dismisses itself (first frame presented or user tap).
 *
 * Call sites must not rely on the sink being called in any particular order
 * relative to the dprintf write. It is an advisory, best-effort channel.
 *
 * The sink is called with the module tag and a pre-formatted UTF-8 string.
 * It must be safe to call from any thread.
 */
extern void (*wwn_startup_log_sink)(const char *module, const char *msg);

static int g_wwn_preserved_stderr_fd = -1;
static pthread_once_t g_wwn_preserved_stderr_once = PTHREAD_ONCE_INIT;

static void wwn_preserved_stderr_init(void)
{
  g_wwn_preserved_stderr_fd = dup(STDERR_FILENO);
  if (g_wwn_preserved_stderr_fd < 0) {
    g_wwn_preserved_stderr_fd = STDERR_FILENO;
  }
}

static inline int WWNPreservedStderrFd(void)
{
  pthread_once(&g_wwn_preserved_stderr_once, wwn_preserved_stderr_init);
  return g_wwn_preserved_stderr_fd;
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-zero-variadic-macro-arguments"

/* ObjC variant. Supports %@ via NSString formatting. */
#define WWNLog(module, fmt, ...)                                               \
  do {                                                                         \
    time_t _wt = time(NULL);                                                   \
    struct tm _wtm;                                                            \
    localtime_r(&_wt, &_wtm);                                                  \
    NSString *_wmsg = [NSString stringWithFormat:fmt, ##__VA_ARGS__];          \
    dprintf(WWNPreservedStderrFd(),                                            \
            "%04d-%02d-%02d %02d:%02d:%02d [%s] %s\n",                         \
            _wtm.tm_year + 1900, _wtm.tm_mon + 1, _wtm.tm_mday, _wtm.tm_hour,  \
            _wtm.tm_min, _wtm.tm_sec, module, [_wmsg UTF8String]);             \
    if (wwn_startup_log_sink) {                                                \
      wwn_startup_log_sink(module, [_wmsg UTF8String]);                        \
    }                                                                          \
  } while (0)

#pragma clang diagnostic pop

#else

/* Pure-C variant. Standard printf format specifiers only. */
#define WWNLog(module, fmt, ...)                                               \
  do {                                                                         \
    time_t _wt = time(NULL);                                                   \
    struct tm _wtm;                                                            \
    localtime_r(&_wt, &_wtm);                                                  \
    dprintf(WWNPreservedStderrFd(),                                            \
            "%04d-%02d-%02d %02d:%02d:%02d [%s] " fmt "\n",                    \
            _wtm.tm_year + 1900, _wtm.tm_mon + 1, _wtm.tm_mday, _wtm.tm_hour,  \
            _wtm.tm_min, _wtm.tm_sec, module, ##__VA_ARGS__);                  \
    if (wwn_startup_log_sink) {                                                \
      char _wbuf[1024];                                                        \
      snprintf(_wbuf, sizeof(_wbuf), fmt, ##__VA_ARGS__);                      \
      wwn_startup_log_sink(module, _wbuf);                                     \
    }                                                                          \
  } while (0)

#endif /* __OBJC__ */

/* File-descriptor variant (e.g. waypipe stderr redirect). */
#define WWNLogFd(fd, module, fmt, ...)                                         \
  do {                                                                         \
    time_t _wt = time(NULL);                                                   \
    struct tm _wtm;                                                            \
    localtime_r(&_wt, &_wtm);                                                  \
    dprintf(fd, "%04d-%02d-%02d %02d:%02d:%02d [%s] " fmt "\n",                \
            _wtm.tm_year + 1900, _wtm.tm_mon + 1, _wtm.tm_mday, _wtm.tm_hour,  \
            _wtm.tm_min, _wtm.tm_sec, module, ##__VA_ARGS__);                  \
  } while (0)

#endif /* WWNLOG_H */
