#ifndef WWN_MOBILE_CLIENTS_H
#define WWN_MOBILE_CLIENTS_H

/* Renamed entry points for in-process Weston shell clients (see ios.nix -Dmain=). */
int weston_desktop_shell_main(int argc, char *argv[]);
int weston_keyboard_main(int argc, char *argv[]);
int weston_terminal_main(int argc, char *argv[]);

#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
/*
 * In-process Weston clients cannot rely on WAYLAND_SOCKET env on iOS.
 * mobile-weston-host-clients.c stashes the dup'd socket fd per-thread;
 * display_create() in window.c consumes it via wl_display_connect_to_fd().
 */
struct wl_display;

typedef int (*wwn_client_main_fn)(int, char **);

struct wwn_client_launch_ctx {
	char **argp;
	char **envp;
	int wayland_socket_fd;
	wwn_client_main_fn main_fn;
};

void wwn_mobile_set_wayland_socket_fd(int fd);
int wwn_mobile_consume_wayland_socket_fd(void);
void wwn_mobile_clear_wayland_socket_fd(void);
void wwn_mobile_roundtrip_begin(void);
void wwn_mobile_roundtrip_end(void);
int wwn_mobile_pending_roundtrips(void);
int wwn_mobile_active_clients(void);
int wwn_mobile_display_roundtrip(struct wl_display *display);
int wwn_mobile_pump_client_display(struct wl_display *display, int max_iterations);
int wwn_mobile_pump_client_display_for_ms(struct wl_display *display, int max_ms);
int wwn_mobile_display_dispatch(struct wl_display *display);
void wwn_weston_client_log_init(void);
void wwn_ios_refresh_bundle_env(void);
void wwn_propagate_mobile_env(void);
/* Nested compositor wl_display for panel-launched clients (desktop-shell). */
void wwn_mobile_register_compositor_display(struct wl_display *display);
/* desktop-shell panel launcher (fork/exec unavailable on Apple mobile). */
void wwn_launch_panel_client(char *const *argp, char *const *envp);
/* Host compositor clients (weston-terminal, etc.) without nested socket fd. */
void wwn_launch_host_client(char *const *argp, char *const *envp);
/* Pump Wawona's host compositor while in-process clients block in roundtrip. */
void wwn_ios_pump_host_compositor(void);
/* Shared client thread entry (libweston-13.a; used by nested compositor too). */
wwn_client_main_fn wwn_lookup_client_main(const char *path);
struct wwn_client_launch_ctx *
wwn_client_launch_ctx_new(char *const *argp, char *const *envp,
			  int wayland_socket_fd, wwn_client_main_fn main_fn);
void wwn_client_launch_ctx_destroy(struct wwn_client_launch_ctx *ctx);
void *wwn_client_thread_entry(void *data);
#endif
#endif

#endif
