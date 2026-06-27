/*
 * Host-compositor in-process Weston clients (weston-terminal, etc.) and
 * roundtrip helpers for libweston-13.a.  Does not depend on weston.h so it
 * can compile in the toytoolkit-only ios.nix derivation.
 */
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <TargetConditionals.h>

#include "wwn-mobile-clients.h"

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
#include <pthread/qos.h>
#include <sched.h>
#include <time.h>
#include <wayland-client.h>

extern void weston_log(const char *fmt, ...);

static _Atomic int wwn_pending_roundtrips;
static _Atomic int wwn_active_clients;

void
wwn_mobile_roundtrip_begin(void)
{
	atomic_fetch_add(&wwn_pending_roundtrips, 1);
}

void
wwn_mobile_roundtrip_end(void)
{
	atomic_fetch_sub(&wwn_pending_roundtrips, 1);
}

int
wwn_mobile_pending_roundtrips(void)
{
	return atomic_load(&wwn_pending_roundtrips);
}

int
wwn_mobile_active_clients(void)
{
	return atomic_load(&wwn_active_clients);
}

int
wwn_mobile_pump_client_display(struct wl_display *display, int max_iterations)
{
	struct timespec dispatch_timeout = {
		.tv_sec = 0,
		.tv_nsec = 1000000L,
	};
	int i;

	for (i = 0; i < max_iterations; i++) {
		if (wl_display_flush(display) < 0 && errno != EAGAIN)
			return -1;
		if (wl_display_dispatch_pending(display) < 0)
			return -1;
		if (wl_display_dispatch_timeout(display, &dispatch_timeout) < 0)
			return -1;
		wwn_ios_pump_host_compositor();
		sched_yield();
	}
	return 0;
}

int
wwn_mobile_pump_client_display_for_ms(struct wl_display *display, int max_ms)
{
	struct timespec dispatch_timeout = {
		.tv_sec = 0,
		.tv_nsec = 1000000L,
	};
	struct timespec start;
	struct timespec now;
	int idle_spins = 0;

	if (max_ms <= 0)
		return 0;
	if (clock_gettime(CLOCK_MONOTONIC, &start) != 0)
		return wwn_mobile_pump_client_display(display, max_ms);

	while (1) {
		if (wl_display_flush(display) < 0 && errno != EAGAIN)
			return -1;
		if (wl_display_dispatch_pending(display) < 0)
			return -1;
		if (wl_display_dispatch_timeout(display, &dispatch_timeout) < 0)
			return -1;

		wwn_ios_pump_host_compositor();

		if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
			break;

		long elapsed_ms = (now.tv_sec - start.tv_sec) * 1000L +
			(now.tv_nsec - start.tv_nsec) / 1000000L;
		if (elapsed_ms >= max_ms)
			break;

		if (wl_display_prepare_read(display) == 0) {
			wl_display_cancel_read(display);
			idle_spins++;
			if (idle_spins >= 8)
				break;
		} else {
			idle_spins = 0;
		}

		sched_yield();
	}
	return 0;
}

struct wwn_roundtrip_done_data {
	bool done;
};

static void
wwn_roundtrip_done(void *data, struct wl_callback *callback, uint32_t time)
{
	struct wwn_roundtrip_done_data *rd = data;

	(void)time;
	rd->done = true;
	wl_callback_destroy(callback);
}

static const struct wl_callback_listener wwn_roundtrip_listener = {
	.done = wwn_roundtrip_done,
};

int
wwn_mobile_display_roundtrip(struct wl_display *display)
{
	struct wwn_roundtrip_done_data rd = { .done = false };
	struct wl_callback *callback;
	int spins = 0;
	struct timespec dispatch_timeout = {
		.tv_sec = 0,
		.tv_nsec = 1000000L,
	};

	wwn_mobile_roundtrip_begin();

	callback = wl_display_sync(display);
	wl_callback_add_listener(callback, &wwn_roundtrip_listener, &rd);

	while (!rd.done) {
		if (wl_display_flush(display) < 0 && errno != EAGAIN) {
			wwn_mobile_roundtrip_end();
			return -1;
		}
		if (wl_display_dispatch_pending(display) < 0) {
			wwn_mobile_roundtrip_end();
			return -1;
		}
		if (wl_display_dispatch_timeout(display, &dispatch_timeout) < 0) {
			wwn_mobile_roundtrip_end();
			return -1;
		}
		wwn_ios_pump_host_compositor();
		if (++spins > 10000) {
			weston_log("wwn mobile client: display roundtrip timed out\n");
			wwn_mobile_roundtrip_end();
			return -1;
		}
		sched_yield();
	}

	wwn_mobile_roundtrip_end();
	return 0;
}

int
wwn_mobile_display_dispatch(struct wl_display *display)
{
	struct timespec dispatch_timeout = {
		.tv_sec = 0,
		.tv_nsec = 1000000L,
	};

	if (wl_display_flush(display) < 0 && errno != EAGAIN)
		return -1;
	wwn_ios_pump_host_compositor();
	if (wl_display_dispatch_pending(display) < 0)
		return -1;
	return wl_display_dispatch_timeout(display, &dispatch_timeout);
}

static pthread_key_t wwn_wayland_fd_key;
static pthread_once_t wwn_wayland_fd_once = PTHREAD_ONCE_INIT;

static void
wwn_wayland_fd_key_destroy(void *data)
{
	int fd = (int)(intptr_t)data;

	if (fd >= 0)
		close(fd);
}

static void
wwn_wayland_fd_key_init(void)
{
	pthread_key_create(&wwn_wayland_fd_key, wwn_wayland_fd_key_destroy);
}

void
wwn_mobile_clear_wayland_socket_fd(void)
{
	pthread_once(&wwn_wayland_fd_once, wwn_wayland_fd_key_init);
	pthread_setspecific(wwn_wayland_fd_key, NULL);
}

void
wwn_mobile_set_wayland_socket_fd(int fd)
{
	pthread_once(&wwn_wayland_fd_once, wwn_wayland_fd_key_init);
	if (fd <= STDERR_FILENO) {
		pthread_setspecific(wwn_wayland_fd_key, NULL);
		return;
	}
	pthread_setspecific(wwn_wayland_fd_key, (void *)(intptr_t)fd);
}

int
wwn_mobile_consume_wayland_socket_fd(void)
{
	int fd;
	void *data;

	pthread_once(&wwn_wayland_fd_once, wwn_wayland_fd_key_init);
	data = pthread_getspecific(wwn_wayland_fd_key);
	if (!data)
		return -1;
	fd = (int)(intptr_t)data;
	pthread_setspecific(wwn_wayland_fd_key, NULL);
	if (fd <= STDERR_FILENO)
		return -1;
	return fd;
}
#endif /* Apple mobile */

static char *
wwn_strdup(const char *s)
{
	size_t n;
	char *d;

	if (!s)
		return NULL;
	n = strlen(s) + 1;
	d = malloc(n);
	if (d)
		memcpy(d, s, n);
	return d;
}

static char **
wwn_strv_dup(char *const *src)
{
	size_t n = 0;
	char **dst;

	if (!src)
		return NULL;
	while (src[n])
		n++;
	dst = calloc(n + 1, sizeof(*dst));
	if (!dst)
		return NULL;
	for (size_t i = 0; i < n; i++) {
		dst[i] = wwn_strdup(src[i]);
		if (!dst[i]) {
			for (size_t j = 0; j < i; j++)
				free(dst[j]);
			free(dst);
			return NULL;
		}
	}
	return dst;
}

static void
wwn_strv_free(char **v)
{
	if (!v)
		return;
	for (size_t i = 0; v[i]; i++)
		free(v[i]);
	free(v);
}

static int
wwn_count_argv(char *const *argv)
{
	int n = 0;

	if (!argv)
		return 0;
	while (argv[n])
		n++;
	return n;
}

static const char *
wwn_basename(const char *path)
{
	const char *slash = strrchr(path, '/');

	return slash ? slash + 1 : path;
}

static void
wwn_apply_wayland_socket_env(struct wwn_client_launch_ctx *ctx)
{
	char entry[32];

	if (ctx->wayland_socket_fd < 0) {
		weston_log("wwn mobile client: '%s' missing WAYLAND_SOCKET fd\n",
			   ctx->argp && ctx->argp[0] ? ctx->argp[0] : "(null)");
		return;
	}

	snprintf(entry, sizeof entry, "%d", ctx->wayland_socket_fd);
	if (setenv("WAYLAND_SOCKET", entry, 1) != 0) {
		weston_log("wwn mobile client: setenv WAYLAND_SOCKET=%s failed: %s\n",
			   entry, strerror(errno));
		return;
	}

	unsetenv("WAYLAND_DISPLAY");
}

static void
wwn_log_mobile_env(const char *client)
{
	static const char *vars[] = {
		"WESTON_CONFIG_FILE",
		"FONTCONFIG_FILE",
		"FONTCONFIG_PATH",
		"WAWONA_MONO_FONT",
		"XKB_CONFIG_ROOT",
		"HOME",
		"XDG_RUNTIME_DIR",
		"WAYLAND_DISPLAY",
		"WAYLAND_SOCKET",
		"WAWONA_ROOTFS",
		"WAWONA_BUNDLE_ROOTFS",
		"WAWONA_ZSH_IN_PROCESS",
		"WAWONA_SHELL",
		"PATH",
		"ZDOTDIR",
		NULL,
	};

	for (int i = 0; vars[i]; i++) {
		const char *v = getenv(vars[i]);

		weston_log("wwn mobile client: %s env %s=%s\n", client, vars[i],
			   v && v[0] ? v : "(unset)");
	}
}

void
wwn_propagate_mobile_env(void)
{
	static const char *vars[] = {
		"WESTON_CONFIG_FILE",
		"WESTON_DATA_DIR",
		"XCURSOR_PATH",
		"XCURSOR_THEME",
		"FONTCONFIG_FILE",
		"FONTCONFIG_PATH",
		"WAWONA_MONO_FONT",
		"XKB_CONFIG_ROOT",
		"HOME",
		"XDG_RUNTIME_DIR",
		"WAWONA_ROOTFS",
		"WAWONA_BUNDLE_ROOTFS",
		"WAWONA_ZSH_IN_PROCESS",
		"WAWONA_SHELL",
		"PATH",
		"ZDOTDIR",
		NULL,
	};

	for (int i = 0; vars[i]; i++) {
		const char *v = getenv(vars[i]);

		if (v && v[0])
			setenv(vars[i], v, 1);
	}
}

static wwn_client_main_fn
wwn_lookup_client_main_impl(const char *path)
{
	const char *base = wwn_basename(path);

	if (strcmp(base, "weston-desktop-shell") == 0)
		return weston_desktop_shell_main;
	if (strcmp(base, "weston-keyboard") == 0)
		return weston_keyboard_main;
	if (strcmp(base, "weston-terminal") == 0)
		return weston_terminal_main;
	return NULL;
}

wwn_client_main_fn
wwn_lookup_client_main(const char *path)
{
	return wwn_lookup_client_main_impl(path);
}

struct wwn_client_launch_ctx *
wwn_client_launch_ctx_new(char *const *argp, char *const *envp,
			  int wayland_socket_fd, wwn_client_main_fn main_fn)
{
	struct wwn_client_launch_ctx *ctx;

	ctx = calloc(1, sizeof(*ctx));
	if (!ctx)
		return NULL;
	ctx->wayland_socket_fd = wayland_socket_fd;
	ctx->main_fn = main_fn;
	ctx->argp = wwn_strv_dup(argp);
	ctx->envp = wwn_strv_dup(envp);
	if (!ctx->argp) {
		wwn_client_launch_ctx_destroy(ctx);
		return NULL;
	}
	return ctx;
}

void
wwn_client_launch_ctx_destroy(struct wwn_client_launch_ctx *ctx)
{
	if (!ctx)
		return;
	wwn_strv_free(ctx->argp);
	wwn_strv_free(ctx->envp);
	free(ctx);
}

static int
wwn_client_run(struct wwn_client_launch_ctx *ctx, bool own_ctx)
{
	char **envp = ctx->envp;
	int argc;
	int rc = -1;

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
	pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
	atomic_fetch_add(&wwn_active_clients, 1);
#endif

	wwn_weston_client_log_init();
	wwn_ios_refresh_bundle_env();
	wwn_propagate_mobile_env();

	if (envp) {
		for (char **e = envp; *e; e++) {
			char *eq = strchr(*e, '=');

			if (!eq)
				continue;
			*eq = '\0';
			setenv(*e, eq + 1, 1);
			*eq = '=';
		}
	}

	wwn_apply_wayland_socket_env(ctx);
	wwn_log_mobile_env(ctx->argp && ctx->argp[0] ? ctx->argp[0] : "(null)");

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
	if (ctx->wayland_socket_fd >= 0) {
		wwn_mobile_set_wayland_socket_fd(ctx->wayland_socket_fd);
		ctx->wayland_socket_fd = -1;
	}
#endif

	argc = wwn_count_argv(ctx->argp);
	if (ctx->main_fn)
		rc = ctx->main_fn(argc, ctx->argp);

	weston_log("wwn mobile client: '%s' exited with status %d\n",
		   ctx->argp && ctx->argp[0] ? ctx->argp[0] : "(null)", rc);

	if (own_ctx) {
		wwn_strv_free(ctx->argp);
		wwn_strv_free(ctx->envp);
		free(ctx);
	}

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
	atomic_fetch_sub(&wwn_active_clients, 1);
#endif
	return rc;
}

void *
wwn_client_thread_entry(void *data)
{
	wwn_client_run(data, true);
	return NULL;
}

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
void
wwn_launch_host_client(char *const *argp, char *const *envp)
{
	struct wwn_client_launch_ctx *ctx;
	wwn_client_main_fn main_fn;
	pthread_t thread;

	if (!argp || !argp[0]) {
		weston_log("wwn host client: missing argv\n");
		return;
	}

	main_fn = wwn_lookup_client_main_impl(argp[0]);
	if (!main_fn) {
		weston_log("wwn host client: no in-process entry for '%s' (basename '%s')\n",
			   argp[0], wwn_basename(argp[0]));
		return;
	}

	ctx = wwn_client_launch_ctx_new(argp, envp, -1, main_fn);
	if (!ctx) {
		weston_log("wwn host client: failed to duplicate argv for '%s'\n",
			   argp[0]);
		return;
	}

	if (pthread_create(&thread, NULL, wwn_client_thread_entry, ctx) != 0) {
		weston_log("wwn host client: pthread_create failed for '%s': %s\n",
			   argp[0], strerror(errno));
		wwn_client_launch_ctx_destroy(ctx);
		return;
	}
	pthread_join(thread, NULL);
}
#endif
