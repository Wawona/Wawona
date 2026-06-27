#include "glibc-compat.h"
#include <sys/cdefs.h>
#include <fcntl.h>
#include <unistd.h>

/* funopen is a BSD/macOS extension; may be hidden by _POSIX_C_SOURCE */
FILE *funopen(const void *cookie,
              int (*readfn)(void *, char *, int),
              int (*writefn)(void *, const char *, int),
              fpos_t (*seekfn)(void *, fpos_t, int),
              int (*closefn)(void *));

/* Callback invoked by macOS stdio when flushing the FILE* stream.
 * cookie points to our wrapper struct:
 *   wrapper[0] = original user cookie
 *   wrapper[1..] = cookie_io_functions_t (function pointers)
 *
 * IMPORTANT: f->write must receive the ORIGINAL user cookie, not the wrapper. */
static int _fopencookie_write(void *cookie, const char *buf, int size) {
    void **wrapper = (void **)cookie;
    cookie_io_functions_t *f = (cookie_io_functions_t *)(wrapper + 1);
    return (int)f->write(wrapper[0], buf, (size_t)size);
}

static int _fopencookie_close(void *cookie) {
    void **wrapper = (void **)cookie;
    cookie_io_functions_t *f = (cookie_io_functions_t *)(wrapper + 1);
    int ret = f->close(wrapper[0]);
    free(wrapper);
    return ret;
}

FILE *fopencookie(void *cookie, const char *mode,
                  cookie_io_functions_t io_funcs) {
    (void)mode;
    void **wrapper = malloc(sizeof(void *) + sizeof(io_funcs));
    if (!wrapper) return NULL;
    wrapper[0] = cookie;
    memcpy(wrapper + 1, &io_funcs, sizeof(io_funcs));
    return funopen(wrapper, NULL, _fopencookie_write, NULL, _fopencookie_close);
}

/* ── udev input stubs (weston-internal, not in any shim) ─────────── */

struct udev_input;
struct udev_seat;
struct weston_compositor;
struct udev;

int udev_input_init(struct udev_input *input,
                    struct weston_compositor *c,
                    struct udev *udev,
                    const char *seat_id,
                    void *configure_device)
{
    (void)input;(void)c;(void)udev;(void)seat_id;(void)configure_device;
    return 0;
}

void udev_input_destroy(struct udev_input *input)
{
    (void)input;
}

int udev_input_enable(struct udev_input *input)
{
    (void)input;
    return 0;
}

void udev_input_disable(struct udev_input *input)
{
    (void)input;
}

struct udev_seat *udev_seat_get_named(struct udev_input *u,
                                       const char *seat_name)
{
    (void)u;(void)seat_name;
    return NULL;
}

/* ── libseat stubs (override the broken stub in deps/libseat.dylib) ── */

struct libseat;
struct libseat_seat_listener;

/* Internal struct for our fake libseat — two ints: pipe_r, pipe_w */
#define SEAT_PIPE_R_OFF 0
#define SEAT_PIPE_W_OFF 4

static void *seat_state(void)
{
    static struct {
        int pipe_r;
        int pipe_w;
    } s = { -1, -1 };
    if (s.pipe_r < 0) {
        int p[2];
        if (pipe(p) == 0) {
            fcntl(p[0], F_SETFL, fcntl(p[0], F_GETFL) | O_NONBLOCK);
            s.pipe_r = p[0]; s.pipe_w = p[1];
        }
    }
    return &s;
}

struct libseat *libseat_open_seat(const struct libseat_seat_listener *l,
                                   void *data)
{
    (void)l;(void)data;
    return (struct libseat *)seat_state();
}

void libseat_close_seat(struct libseat *s) { (void)s; }

int libseat_get_fd(struct libseat *s)
{
    int *pipes = (int *)s;
    return pipes ? pipes[0] : -1; /* pipe_r */
}

int libseat_dispatch(struct libseat *s, int timeout)
{
    (void)timeout;
    int *pipes = (int *)s;
    if (pipes && pipes[0] >= 0) {
        char buf[64];
        while (read(pipes[0], buf, sizeof(buf)) > 0);
    }
    return 0;
}

int libseat_get_vt(struct libseat *s) { (void)s; return -1; }

int libseat_open_device(struct libseat *s, const char *path, int *fd)
{
    (void)s;
    if (!path || !fd) return -1;
    int opened = open(path, O_RDWR);
    if (opened < 0) return -1;
    *fd = opened;
    return opened; /* device_id = fd */
}

int libseat_close_device(struct libseat *s, int device_id)
{
    (void)s;
    close(device_id);
    return 0;
}

int libseat_disable_seat(struct libseat *s) { (void)s; return 0; }

int libseat_switch_session(struct libseat *s, int session)
{
    (void)s;(void)session;
    return 0;
}

typedef void (*libseat_log_handler)(int level, const char *fmt, void *ap);
void libseat_set_log_handler(libseat_log_handler handler) { (void)handler; }

enum libseat_log_level { LIBSEAT_LOG_LEVEL_NONE, LIBSEAT_LOG_LEVEL_INFO, LIBSEAT_LOG_LEVEL_DEBUG };
void libseat_set_log_level(enum libseat_log_level level) { (void)level; }
