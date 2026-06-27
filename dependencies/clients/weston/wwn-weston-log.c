#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

typedef int (*wwn_log_func_t)(const char *fmt, va_list ap);

extern void weston_log_set_handler(wwn_log_func_t log, wwn_log_func_t cont);

#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
static int g_wwn_client_log_fd = -1;
static pthread_once_t g_wwn_client_log_fd_once = PTHREAD_ONCE_INIT;

static void
wwn_client_log_fd_init(void)
{
	g_wwn_client_log_fd = dup(STDERR_FILENO);
	if (g_wwn_client_log_fd < 0)
		g_wwn_client_log_fd = STDERR_FILENO;
}

static int
wwn_client_log_fd(void)
{
	pthread_once(&g_wwn_client_log_fd_once, wwn_client_log_fd_init);
	return g_wwn_client_log_fd;
}
#endif

static int
wwn_client_vlog(const char *fmt, va_list ap)
{
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
	/*
	 * Surface client weston_log() to the app log by default so launch
	 * stalls (display_create, fontconfig, display_run) are diagnosable.
	 * Set WWN_WESTON_QUIET=1 to silence once the path is healthy.
	 */
	if (getenv("WWN_WESTON_QUIET") != NULL)
		return 0;
	return vdprintf(wwn_client_log_fd(), fmt, ap);
#else
	return vfprintf(stderr, fmt, ap);
#endif
}

void
wwn_weston_client_log_init(void)
{
	static int installed;

	if (installed)
		return;

#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
	(void)wwn_client_log_fd();
#endif

	weston_log_set_handler(wwn_client_vlog, wwn_client_vlog);
	installed = 1;
}
