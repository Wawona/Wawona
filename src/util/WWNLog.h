/*
 * WWNLog.h — Unified logging for Wawona
 *
 * Format: YYYY-MM-DD HH:MM:SS [MODULE] message
 *
 * Usage (ObjC):  WWNLog("BRIDGE", @"Output: %ux%u", w, h);
 * Usage (C):     WWNLog("SEAT",   "Created fd=%d", fd);
 * Usage (fd):    WWNLogFd(fd, "WAYPIPE", "Exit code: %d", rc);
 */

#ifndef WWNLOG_H
#define WWNLOG_H

#include <stdio.h>
#include <time.h>

#ifdef __OBJC__
#import <Foundation/Foundation.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-zero-variadic-macro-arguments"

/* ObjC variant — supports %@ via NSString formatting. */
#define WWNLog(module, fmt, ...)                                               \
  do {                                                                         \
    time_t _wt = time(NULL);                                                   \
    struct tm _wtm;                                                            \
    localtime_r(&_wt, &_wtm);                                                  \
    NSString *_wmsg = [NSString stringWithFormat:fmt, ##__VA_ARGS__];          \
    fprintf(stderr, "%04d-%02d-%02d %02d:%02d:%02d [%s] %s\n",                 \
            _wtm.tm_year + 1900, _wtm.tm_mon + 1, _wtm.tm_mday, _wtm.tm_hour,  \
            _wtm.tm_min, _wtm.tm_sec, module, [_wmsg UTF8String]);             \
  } while (0)

#else

/* Pure-C variant — standard printf format specifiers only. */
#define WWNLog(module, fmt, ...)                                               \
  do {                                                                         \
    time_t _wt = time(NULL);                                                   \
    struct tm _wtm;                                                            \
    localtime_r(&_wt, &_wtm);                                                  \
    fprintf(stderr, "%04d-%02d-%02d %02d:%02d:%02d [%s] " fmt "\n",            \
            _wtm.tm_year + 1900, _wtm.tm_mon + 1, _wtm.tm_mday, _wtm.tm_hour,  \
            _wtm.tm_min, _wtm.tm_sec, module, ##__VA_ARGS__);                  \
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

#pragma clang diagnostic pop

#endif /* WWNLOG_H */
