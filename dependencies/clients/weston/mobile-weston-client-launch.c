/*
 * Nested Weston compositor in-process client launch (panel / wet_client_launch).
 * Shared roundtrip + host-client symbols live in mobile-weston-host-clients.c
 * (libweston-13.a).
 */
#include "config.h"

#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <TargetConditionals.h>

#include "weston.h"
#include "shared/process-util.h"
#include "include/wwn-mobile-clients.h"

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
#include <pthread/qos.h>
#include <sys/socket.h>
#include <wayland-server.h>

static struct wl_display *wwn_mobile_server_display;
static pthread_mutex_t wwn_mobile_server_display_lock =
	PTHREAD_MUTEX_INITIALIZER;

static int wwn_dup_wayland_socket(int fd);

void
wwn_mobile_register_compositor_display(struct wl_display *display)
{
	pthread_mutex_lock(&wwn_mobile_server_display_lock);
	wwn_mobile_server_display = display;
	pthread_mutex_unlock(&wwn_mobile_server_display_lock);
}

static int
wwn_panel_client_alloc_wayland_socket(const char *client_name)
{
	int sv[2];
	struct wl_client *client;
	int client_fd;

	if (os_socketpair_cloexec(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
		weston_log("wwn panel client: socketpair failed for '%s': %s\n",
			   client_name, strerror(errno));
		return -1;
	}

	pthread_mutex_lock(&wwn_mobile_server_display_lock);
	if (!wwn_mobile_server_display) {
		pthread_mutex_unlock(&wwn_mobile_server_display_lock);
		weston_log("wwn panel client: nested compositor display not registered "
			   "for '%s'\n", client_name);
		close(sv[0]);
		close(sv[1]);
		return -1;
	}
	client = wl_client_create(wwn_mobile_server_display, sv[0]);
	pthread_mutex_unlock(&wwn_mobile_server_display_lock);
	if (!client) {
		weston_log("wwn panel client: wl_client_create failed for '%s': %s\n",
			   client_name, strerror(errno));
		close(sv[0]);
		close(sv[1]);
		return -1;
	}

	client_fd = wwn_dup_wayland_socket(sv[1]);
	close(sv[1]);
	if (client_fd < 0) {
		weston_log("wwn panel client: failed to dup client socket for '%s'\n",
			   client_name);
		return -1;
	}

	weston_log("wwn panel client: allocated WAYLAND_SOCKET fd=%d for '%s'\n",
		   client_fd, client_name);
	return client_fd;
}

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

static void
wwn_strv_free(char **v)
{
	if (!v)
		return;
	for (size_t i = 0; v[i]; i++)
		free(v[i]);
	free(v);
}

static char **
wwn_env_set_wayland_socket(char **envp, int fd)
{
	char entry[32];
	char **out;
	size_t n = 0;
	bool replaced = false;

	snprintf(entry, sizeof entry, "WAYLAND_SOCKET=%d", fd);
	if (!envp) {
		out = calloc(2, sizeof(*out));
		if (!out)
			return NULL;
		out[0] = wwn_strdup(entry);
		if (!out[0]) {
			free(out);
			return NULL;
		}
		return out;
	}
	while (envp[n])
		n++;
	out = calloc(n + 1, sizeof(*out));
	if (!out)
		return NULL;
	for (size_t i = 0; i < n; i++) {
		if (strncmp(envp[i], "WAYLAND_SOCKET=", 15) == 0) {
			out[i] = wwn_strdup(entry);
			replaced = true;
		} else {
			out[i] = wwn_strdup(envp[i]);
		}
		if (!out[i]) {
			for (size_t j = 0; j < i; j++)
				free(out[j]);
			free(out);
			return NULL;
		}
	}
	if (!replaced) {
		char **grown = realloc(out, (n + 2) * sizeof(*out));

		if (!grown) {
			wwn_strv_free(out);
			return NULL;
		}
		out = grown;
		out[n] = wwn_strdup(entry);
		if (!out[n]) {
			wwn_strv_free(out);
			return NULL;
		}
		out[n + 1] = NULL;
	} else {
		out[n] = NULL;
	}
	return out;
}

static int
wwn_dup_wayland_socket(int fd)
{
	int dupfd;

	if (fd < 0)
		return -1;
	dupfd = dup(fd);
	if (dupfd < 0)
		return -1;
	if (os_fd_clear_cloexec(dupfd) < 0) {
		close(dupfd);
		return -1;
	}
	return dupfd;
}

static int
wwn_deferred_client_timer(void *data)
{
	struct wwn_client_launch_ctx *ctx = data;
	pthread_t thread;

	if (pthread_create(&thread, NULL, wwn_client_thread_entry, ctx) != 0) {
		weston_log("wwn mobile client: pthread_create failed for '%s': %s\n",
			   ctx->argp && ctx->argp[0] ? ctx->argp[0] : "(null)",
			   strerror(errno));
		if (ctx->wayland_socket_fd >= 0)
			close(ctx->wayland_socket_fd);
		wwn_client_launch_ctx_destroy(ctx);
		return 0;
	}
	pthread_detach(thread);
	return 0;
}

static void
wwn_schedule_deferred_client_start(struct weston_compositor *compositor,
				   struct wwn_client_launch_ctx *ctx)
{
	struct wl_event_loop *loop =
		wl_display_get_event_loop(compositor->wl_display);
	struct wl_event_source *source;
	static _Atomic int launch_serial;
	int delay = 1 + atomic_fetch_add(&launch_serial, 1) * 25;

	source = wl_event_loop_add_timer(loop, wwn_deferred_client_timer, ctx);
	if (!source ||
	    wl_event_source_timer_update(source, delay) < 0) {
		weston_log("wwn mobile client: timer defer failed for '%s', starting immediately\n",
			   ctx->argp && ctx->argp[0] ? ctx->argp[0] : "(null)");
		wwn_deferred_client_timer(ctx);
	}
}

struct wet_process *
wwn_wet_client_launch_inprocess(struct weston_compositor *compositor,
				char *const *argp,
				char *const *envp,
				int *no_cloexec_fds,
				size_t num_no_cloexec_fds,
				wet_process_cleanup_func_t cleanup,
				void *cleanup_data)
{
	struct wet_process *proc;
	struct wwn_client_launch_ctx *ctx;
	wwn_client_main_fn main_fn;
	static pid_t fake_pid = 900000;

	if (!argp || !argp[0]) {
		weston_log("wwn mobile client: missing argv for launch\n");
		return NULL;
	}

	main_fn = wwn_lookup_client_main(argp[0]);
	if (!main_fn) {
		weston_log("wwn mobile client: no in-process entry for '%s'\n",
			   argp[0]);
		return NULL;
	}

	ctx = wwn_client_launch_ctx_new(argp, envp, -1, main_fn);
	if (!ctx) {
		weston_log("wwn mobile client: failed to duplicate argv for '%s'\n",
			   argp[0]);
		return NULL;
	}

	if (num_no_cloexec_fds > 0) {
		char **new_env;

		ctx->wayland_socket_fd =
			wwn_dup_wayland_socket(no_cloexec_fds[0]);
		if (ctx->wayland_socket_fd < 0) {
			weston_log("wwn mobile client: failed to dup WAYLAND_SOCKET fd %d for '%s': %s\n",
				   no_cloexec_fds[0], argp[0], strerror(errno));
			wwn_client_launch_ctx_destroy(ctx);
			return NULL;
		}
		new_env = wwn_env_set_wayland_socket(ctx->envp,
						     ctx->wayland_socket_fd);
		if (!new_env) {
			weston_log("wwn mobile client: failed to set WAYLAND_SOCKET for '%s'\n",
				   argp[0]);
			close(ctx->wayland_socket_fd);
			wwn_client_launch_ctx_destroy(ctx);
			return NULL;
		}
		wwn_strv_free(ctx->envp);
		ctx->envp = new_env;
	}

	wwn_schedule_deferred_client_start(compositor, ctx);

	proc = calloc(1, sizeof(*proc));
	if (!proc)
		return NULL;
	proc->pid = fake_pid++;
	proc->path = strdup(argp[0]);
	proc->cleanup = cleanup;
	proc->cleanup_data = cleanup_data;

	weston_log("wwn mobile client: started '%s' in-process (pid=%d)\n",
		   argp[0], proc->pid);
	return proc;
}

void
wwn_launch_panel_client(char *const *argp, char *const *envp)
{
	struct wwn_client_launch_ctx *ctx;
	wwn_client_main_fn main_fn;
	pthread_t thread;

	if (!argp || !argp[0]) {
		weston_log("wwn panel client: missing argv\n");
		return;
	}

	main_fn = wwn_lookup_client_main(argp[0]);
	if (!main_fn) {
		weston_log("wwn panel client: no in-process entry for '%s'\n",
			   argp[0]);
		return;
	}

	ctx = wwn_client_launch_ctx_new(argp, envp, -1, main_fn);
	if (!ctx) {
		weston_log("wwn panel client: failed to duplicate argv for '%s'\n",
			   argp[0]);
		return;
	}

	ctx->wayland_socket_fd = wwn_panel_client_alloc_wayland_socket(argp[0]);
	if (ctx->wayland_socket_fd < 0) {
		wwn_client_launch_ctx_destroy(ctx);
		return;
	}

	if (pthread_create(&thread, NULL, wwn_client_thread_entry, ctx) != 0) {
		weston_log("wwn panel client: pthread_create failed for '%s': %s\n",
			   argp[0], strerror(errno));
		wwn_client_launch_ctx_destroy(ctx);
		return;
	}
	pthread_detach(thread);
}

#else /* !(TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH) */

struct wet_process *
wwn_wet_client_launch_inprocess(struct weston_compositor *compositor,
				char *const *argp,
				char *const *envp,
				int *no_cloexec_fds,
				size_t num_no_cloexec_fds,
				wet_process_cleanup_func_t cleanup,
				void *cleanup_data)
{
	(void)compositor;
	(void)argp;
	(void)envp;
	(void)no_cloexec_fds;
	(void)num_no_cloexec_fds;
	(void)cleanup;
	(void)cleanup_data;
	return NULL;
}

#endif
