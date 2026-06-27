#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <mach/mach.h>
#include <bootstrap.h>
#include <libudev.h>
#include <libinput.h>
#include <input_ipc.h>

/* ── Internal struct definitions ────────────────────────────────────── */

struct libinput_event_keyboard {
    uint32_t key;
    int32_t  key_state;
    uint32_t seat_key_count;
    uint64_t time_usec;
};

struct libinput_event_pointer {
    double    dx, dy;
    double    dx_unaccel, dy_unaccel;
    uint32_t  button;
    int32_t   button_state;
    uint32_t  seat_button_count;
    uint64_t  time_usec;
    double    axis_value[2];
    int32_t   axis_source;
};

struct libinput_event_touch {
    int32_t  seat_slot;
    uint64_t time_usec;
    double   x, y;
};

struct libinput_event_tablet_tool {
    uint64_t time;
    double   x, y, pressure, distance, tilt_x, tilt_y;
    int      tip_state, proximity_state;
    uint32_t button, button_state;
    struct libinput_tablet_tool *tool;
};

struct libinput {
    int     dummy;
    void   *user_data;
};

struct libinput_seat {
    char logical_name[64];
};

struct libinput_device {
    int               id;
    int               capabilities;
    char              name[64];
    char              sysname[64];
    unsigned int      vendor, product;
    struct libinput_seat seat;
    void             *user_data;
    int               refcount;
};

struct libinput_event {
    int                     type;
    struct libinput_device *device;
    struct libinput_event  *next;
    union {
        struct libinput_event_keyboard  keyboard;
        struct libinput_event_pointer   pointer;
        struct libinput_event_touch     touch;
        struct libinput_event_tablet_tool tablet;
    };
};

/* ── Internal context ───────────────────────────────────────────────── */

#define MAX_DEVICES 8

static struct {
    struct libinput       ctx;
    struct libinput_device devices[MAX_DEVICES];
    int                   num_devices;
    struct libinput_event *ev_head;
    struct libinput_event *ev_tail;
    pthread_mutex_t       ev_lock;
    mach_port_t           inputd_port;
    mach_port_t           recv_port;
    int                   pipe_r, pipe_w;
    pthread_t             recv_thread;
    volatile bool         running;
    bool                  connected;
    int                   pressed_keys;
    int                   pressed_buttons;
    uint32_t              button_state_mask;
    uint8_t               key_state_map[1024 / 8];
} g;

static void queue_event(struct libinput_event *ev);
static struct libinput_event *alloc_event(int type, struct libinput_device *dev);

/* ── Background thread: receive Mach IPC events ─────────────────────── */

static void *recv_thread(void *arg)
{
    (void)arg;
    while (g.running) {
        union {
            input_ipc_event_t event;
            uint8_t padding[sizeof(input_ipc_event_t) + 64];
        } buf = {0};
        input_ipc_event_t *msg = &buf.event;
        msg->header.msgh_size       = sizeof(buf);
        msg->header.msgh_local_port = g.recv_port;

        kern_return_t kr = mach_msg(&msg->header, MACH_RCV_MSG, 0, sizeof(buf),
                                     g.recv_port, MACH_MSG_TIMEOUT_NONE,
                                     MACH_PORT_NULL);
        if (kr != KERN_SUCCESS) {
            if (g.running)
                fprintf(stderr, "[libinput] mach_msg recv: %s\n",
                        mach_error_string(kr));
            continue;
        }
        fprintf(stderr, "[libinput] recv event_type=%d id=%d\n",
                msg->event_type, msg->device_id);
        if (msg->header.msgh_id != INPUT_IPC_EVENT_ID) {
            fprintf(stderr, "[libinput] unexpected msgh_id %d\n",
                    msg->header.msgh_id);
            continue;
        }

        struct libinput_device *dev = NULL;
        for (int i = 0; i < g.num_devices; i++) {
            if (g.devices[i].id == msg->device_id) {
                dev = &g.devices[i];
                break;
            }
        }

        struct libinput_event *ev = NULL;

        switch (msg->event_type) {
        case INPUT_IPC_EVENT_DEVICE_ADDED: {
            fprintf(stderr, "[libinput] DEVICE_ADDED id=%d caps=%d name=\"%s\"\n",
                    msg->device_id, msg->device_caps, msg->device_name);
            if (g.num_devices >= MAX_DEVICES) break;
            dev = &g.devices[g.num_devices++];
            memset(dev, 0, sizeof(*dev));
            dev->id = msg->device_id;
            dev->capabilities = msg->device_caps;
            strncpy(dev->name, msg->device_name, sizeof(dev->name) - 1);
            snprintf(dev->sysname, sizeof(dev->sysname), "event%d", msg->device_id);
            snprintf(dev->seat.logical_name, sizeof(dev->seat.logical_name),
                     "seat0");
            ev = alloc_event(LIBINPUT_EVENT_DEVICE_ADDED, dev);
            break;
        }
        case INPUT_IPC_EVENT_DEVICE_REMOVED:
            ev = alloc_event(LIBINPUT_EVENT_DEVICE_REMOVED, dev);
            break;
        case INPUT_IPC_EVENT_KEYBOARD_KEY: {
            uint16_t key = msg->key & 0x3FF;
            int byte = key / 8, bit = key % 8;
            int already_pressed = (g.key_state_map[byte] >> bit) & 1;
            int state_changed = 0;
            if (msg->key_state == LIBINPUT_KEY_STATE_PRESSED) {
                if (!already_pressed) {
                    g.pressed_keys++;
                    g.key_state_map[byte] |= (1 << bit);
                    state_changed = 1;
                }
            } else {
                if (already_pressed) {
                    g.pressed_keys--;
                    g.key_state_map[byte] &= ~(1 << bit);
                    state_changed = 1;
                }
            }
            if (!state_changed) break;
            ev = alloc_event(LIBINPUT_EVENT_KEYBOARD_KEY, dev);
            if (ev) {
                ev->keyboard.key = msg->key;
                ev->keyboard.key_state = msg->key_state;
                ev->keyboard.seat_key_count = g.pressed_keys;
                ev->keyboard.time_usec = msg->time_usec;
            }
            break;
        }
        case INPUT_IPC_EVENT_POINTER_MOTION:
            ev = alloc_event(LIBINPUT_EVENT_POINTER_MOTION, dev);
            if (ev) {
                ev->pointer.dx = msg->pointer_dx;
                ev->pointer.dy = msg->pointer_dy;
                ev->pointer.dx_unaccel = msg->pointer_dx;
                ev->pointer.dy_unaccel = msg->pointer_dy;
                ev->pointer.time_usec = msg->time_usec;
            }
            break;
        case INPUT_IPC_EVENT_POINTER_BUTTON: {
            uint32_t btn_bit = 1u << (msg->pointer_button & 31);
            int already_pressed = (g.button_state_mask & btn_bit) != 0;
            int state_changed = 0;
            if (msg->pointer_button_state == LIBINPUT_BUTTON_STATE_PRESSED) {
                if (!already_pressed) {
                    g.pressed_buttons++;
                    g.button_state_mask |= btn_bit;
                    state_changed = 1;
                }
            } else {
                if (already_pressed) {
                    g.pressed_buttons--;
                    g.button_state_mask &= ~btn_bit;
                    state_changed = 1;
                }
            }
            if (!state_changed) break;
            ev = alloc_event(LIBINPUT_EVENT_POINTER_BUTTON, dev);
            if (ev) {
                ev->pointer.button = msg->pointer_button;
                ev->pointer.button_state = msg->pointer_button_state;
                ev->pointer.seat_button_count = g.pressed_buttons;
                ev->pointer.time_usec = msg->time_usec;
            }
            fprintf(stderr, "[libinput] button %u %s count=%d mask=0x%x\n",
                    msg->pointer_button,
                    msg->pointer_button_state ? "down" : "up",
                    g.pressed_buttons, g.button_state_mask);
            break;
        }
        case INPUT_IPC_EVENT_POINTER_AXIS:
            ev = alloc_event(LIBINPUT_EVENT_POINTER_AXIS, dev);
            if (ev) {
                int axis = msg->pointer_axis;
                if (axis >= 0 && axis < 2)
                    ev->pointer.axis_value[axis] = msg->pointer_axis_value;
                ev->pointer.axis_source = LIBINPUT_POINTER_AXIS_SOURCE_FINGER;
                ev->pointer.time_usec = msg->time_usec;
            }
            break;
        case INPUT_IPC_EVENT_TOUCH_DOWN:
        case INPUT_IPC_EVENT_TOUCH_UP:
        case INPUT_IPC_EVENT_TOUCH_MOTION:
        case INPUT_IPC_EVENT_TOUCH_FRAME:
            ev = alloc_event(msg->event_type == INPUT_IPC_EVENT_TOUCH_DOWN
                             ? LIBINPUT_EVENT_TOUCH_DOWN
                             : msg->event_type == INPUT_IPC_EVENT_TOUCH_UP
                             ? LIBINPUT_EVENT_TOUCH_UP
                             : msg->event_type == INPUT_IPC_EVENT_TOUCH_MOTION
                             ? LIBINPUT_EVENT_TOUCH_MOTION
                             : LIBINPUT_EVENT_TOUCH_FRAME, dev);
            if (ev) {
                ev->touch.seat_slot = msg->touch_slot;
                ev->touch.x = msg->touch_x;
                ev->touch.y = msg->touch_y;
                ev->touch.time_usec = msg->time_usec;
            }
            break;
        }
        if (ev)
            queue_event(ev);
    }
    return NULL;
}

/* ── Event queue ────────────────────────────────────────────────────── */

static struct libinput_event *alloc_event(int type, struct libinput_device *dev)
{
    struct libinput_event *ev = calloc(1, sizeof(*ev));
    if (!ev) return NULL;
    ev->type = type;
    ev->device = dev;
    return ev;
}

static void queue_event(struct libinput_event *ev)
{
    pthread_mutex_lock(&g.ev_lock);
    if (!g.ev_head) {
        g.ev_head = g.ev_tail = ev;
    } else {
        g.ev_tail->next = ev;
        g.ev_tail = ev;
    }
    pthread_mutex_unlock(&g.ev_lock);

    if (g.pipe_w >= 0) {
        char c = 1;
        write(g.pipe_w, &c, 1);
    }
}

/* ── Connect to inputd via Mach IPC ──────────────────────────────────── */

static int connect_inputd(void)
{
    kern_return_t kr = bootstrap_look_up(bootstrap_port, INPUT_IPC_SERVICE_NAME,
                                         &g.inputd_port);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[libinput] inputd not available (%s), using stub\n",
                mach_error_string(kr));
        return -1;
    }

    kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE,
                            &g.recv_port);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[libinput] mach_port_allocate: %s\n",
                mach_error_string(kr));
        return -1;
    }

    input_ipc_subscribe_t sub = {0};
    sub.header.msgh_bits = MACH_MSGH_BITS_COMPLEX
                         | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    sub.header.msgh_remote_port = g.inputd_port;
    sub.header.msgh_local_port  = MACH_PORT_NULL;
    sub.header.msgh_id          = INPUT_IPC_SUBSCRIBE_ID;
    sub.header.msgh_size        = sizeof(sub);
    sub.body.msgh_descriptor_count = 1;
    sub.client_port.name        = g.recv_port;
    sub.client_port.disposition = MACH_MSG_TYPE_MAKE_SEND;
    sub.client_port.type        = MACH_MSG_PORT_DESCRIPTOR;

    kr = mach_msg(&sub.header, MACH_SEND_MSG, sizeof(sub), 0, MACH_PORT_NULL,
                  MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[libinput] mach_msg subscribe: %s\n",
                mach_error_string(kr));
        return -1;
    }

    fprintf(stderr, "[libinput] subscribed to inputd\n");
    return 0;
}

/* ── libinput API implementation ─────────────────────────────────────── */

struct libinput *libinput_udev_create_context(
    const struct libinput_interface *iface, void *user_data, struct udev *udev)
{
    (void)iface;
    (void)udev;

    if (g.pipe_r <= 0) {
        if (g.pipe_r == 0) g.pipe_r = -1;
        int p[2];
        if (pipe(p) == 0) {
            g.pipe_r = p[0];
            g.pipe_w = p[1];
            fcntl(g.pipe_r, F_SETFL, fcntl(g.pipe_r, F_GETFL) | O_NONBLOCK);
        }
    }

    int connected = 0;
    if (!g.connected) {
        g.connected = true;
        g.running = true;
        if (connect_inputd() == 0) {
            connected = 1;
            pthread_mutex_init(&g.ev_lock, NULL);
            pthread_create(&g.recv_thread, NULL, recv_thread, NULL);
            pthread_detach(g.recv_thread);
        }
    }

    (void)connected;
    memset(&g.ctx, 0, sizeof(g.ctx));
    g.ctx.user_data = user_data;
    return &g.ctx;
}

struct libinput *libinput_unref(struct libinput *l)
{
    (void)l;
    g.running = false;
    if (g.pipe_r >= 0) { close(g.pipe_r); g.pipe_r = -1; }
    if (g.pipe_w >= 0) { close(g.pipe_w); g.pipe_w = -1; }
    return NULL;
}

int libinput_udev_assign_seat(struct libinput *l, const char *seat)
{
    (void)l;
    (void)seat;
    return 0;
}

int libinput_get_fd(struct libinput *l)
{
    (void)l;
    return g.pipe_r >= 0 ? g.pipe_r : -1;
}

int libinput_dispatch(struct libinput *l)
{
    (void)l;
    if (g.pipe_r >= 0) {
        char buf[64];
        while (read(g.pipe_r, buf, sizeof(buf)) > 0) {}
    }
    return 0;
}

struct libinput_event *libinput_get_event(struct libinput *l)
{
    (void)l;
    pthread_mutex_lock(&g.ev_lock);
    struct libinput_event *ev = g.ev_head;
    if (ev) {
        g.ev_head = ev->next;
        if (!g.ev_head) g.ev_tail = NULL;
        fprintf(stderr, "[libinput] get_event type=%d\n", ev->type);
    }
    pthread_mutex_unlock(&g.ev_lock);
    return ev;
}

void libinput_event_destroy(struct libinput_event *ev)
{
    free(ev);
}

struct libinput *libinput_event_get_context(struct libinput_event *ev)
{
    (void)ev;
    return &g.ctx;
}

enum libinput_event_type libinput_event_get_type(struct libinput_event *ev)
{
    return (enum libinput_event_type)ev->type;
}

struct libinput_device *libinput_event_get_device(struct libinput_event *ev)
{
    return ev->device;
}

int libinput_suspend(struct libinput *l)
{
    (void)l;
    return 0;
}

int libinput_resume(struct libinput *l)
{
    (void)l;
    return 0;
}

/* ── Device functions ──────────────────────────────────────────────────── */

struct libinput_device *libinput_device_ref(struct libinput_device *d)
{
    if (d) d->refcount++;
    return d;
}

struct libinput_device *libinput_device_unref(struct libinput_device *d)
{
    if (d && --d->refcount <= 0) {}
    return NULL;
}

void libinput_device_set_user_data(struct libinput_device *d, void *p)
{
    if (d) d->user_data = p;
}

void *libinput_device_get_user_data(struct libinput_device *d)
{
    return d ? d->user_data : NULL;
}

int libinput_device_has_capability(struct libinput_device *d,
                                   enum libinput_capability c)
{
    if (!d) return 0;
    int mask = 0;
    switch (c) {
    case LIBINPUT_DEVICE_CAP_KEYBOARD: mask = INPUT_IPC_CAP_KEYBOARD; break;
    case LIBINPUT_DEVICE_CAP_POINTER:  mask = INPUT_IPC_CAP_POINTER;  break;
    case LIBINPUT_DEVICE_CAP_TOUCH:    mask = INPUT_IPC_CAP_TOUCH;    break;
    default: return 0;
    }
    return (d->capabilities & mask) != 0;
}

const char *libinput_device_get_name(struct libinput_device *d)
{
    return d ? d->name : "stub";
}

const char *libinput_device_get_sysname(struct libinput_device *d)
{
    return d ? d->sysname : "stub";
}

const char *libinput_device_get_output_name(struct libinput_device *d)
{
    (void)d;
    return NULL;
}

unsigned int libinput_device_get_id_product(struct libinput_device *d)
{
    return d ? d->product : 0;
}

unsigned int libinput_device_get_id_vendor(struct libinput_device *d)
{
    return d ? d->vendor : 0;
}

struct libinput_seat *libinput_device_get_seat(struct libinput_device *d)
{
    return d ? &d->seat : NULL;
}

struct udev_device *libinput_device_get_udev_device(struct libinput_device *d)
{
    (void)d;
    return NULL;
}

/* ── Device config functions (all stubs) ──────────────────────────────── */

int libinput_device_config_tap_set_enabled(struct libinput_device *d, int e)
{ (void)d;(void)e; return 0; }

int libinput_device_config_tap_get_finger_count(struct libinput_device *d)
{ (void)d; return 0; }

int libinput_device_config_tap_set_drag_enabled(struct libinput_device *d, int e)
{ (void)d;(void)e; return 0; }

int libinput_device_config_tap_set_drag_lock_enabled(struct libinput_device *d, int e)
{ (void)d;(void)e; return 0; }

int libinput_device_config_calibration_has_matrix(struct libinput_device *d)
{ (void)d; return 0; }

int libinput_device_config_calibration_set_matrix(struct libinput_device *d,
                                                  const float m[9])
{ (void)d;(void)m; return 0; }

int libinput_device_config_calibration_get_matrix(struct libinput_device *d,
                                                  float m[9])
{ (void)d;(void)m; return 0; }

int libinput_device_config_calibration_get_default_matrix(
    struct libinput_device *d, float m[9])
{ (void)d;(void)m; return 0; }

int libinput_device_config_left_handed_is_available(struct libinput_device *d)
{ (void)d; return 0; }

int libinput_device_config_left_handed_set(struct libinput_device *d, int e)
{ (void)d;(void)e; return 0; }

int libinput_device_config_middle_emulation_is_available(
    struct libinput_device *d)
{ (void)d; return 0; }

int libinput_device_config_middle_emulation_set_enabled(
    struct libinput_device *d, int e)
{ (void)d;(void)e; return 0; }

int libinput_device_config_dwt_is_available(struct libinput_device *d)
{ (void)d; return 0; }

int libinput_device_config_dwt_set_enabled(struct libinput_device *d, int e)
{ (void)d;(void)e; return 0; }

int libinput_device_config_rotation_is_available(struct libinput_device *d)
{ (void)d; return 0; }

int libinput_device_config_rotation_set_angle(struct libinput_device *d,
                                              unsigned int a)
{ (void)d;(void)a; return 0; }

int libinput_device_config_accel_is_available(struct libinput_device *d)
{ (void)d; return 0; }

enum libinput_config_status libinput_device_config_accel_set_speed(
    struct libinput_device *d, double s)
{ (void)d;(void)(int)s; return LIBINPUT_CONFIG_STATUS_UNSUPPORTED; }

enum libinput_config_accel_profile libinput_device_config_accel_get_profiles(
    struct libinput_device *d)
{ (void)d; return LIBINPUT_CONFIG_ACCEL_PROFILE_NONE; }

enum libinput_config_status libinput_device_config_accel_set_profile(
    struct libinput_device *d, enum libinput_config_accel_profile p)
{ (void)d;(void)(int)p; return LIBINPUT_CONFIG_STATUS_UNSUPPORTED; }

enum libinput_config_scroll_method libinput_device_config_scroll_get_methods(
    struct libinput_device *d)
{ (void)d; return LIBINPUT_CONFIG_SCROLL_NO_SCROLL; }

enum libinput_config_status libinput_device_config_scroll_set_method(
    struct libinput_device *d, enum libinput_config_scroll_method m)
{ (void)d;(void)(int)m; return LIBINPUT_CONFIG_STATUS_UNSUPPORTED; }

int libinput_device_config_scroll_set_button(struct libinput_device *d,
                                             uint32_t b)
{ (void)d;(void)b; return 0; }

int libinput_device_config_scroll_has_natural_scroll(
    struct libinput_device *d)
{ (void)d; return 0; }

int libinput_device_config_scroll_set_natural_scroll_enabled(
    struct libinput_device *d, int e)
{ (void)d;(void)e; return 0; }

int libinput_device_led_update(struct libinput_device *d, enum libinput_led l)
{ (void)d;(void)(int)l; return 0; }

/* ── Seat functions ────────────────────────────────────────────────────── */

const char *libinput_seat_get_logical_name(struct libinput_seat *s)
{
    return s ? s->logical_name : "default";
}

/* ── Event accessor functions ─────────────────────────────────────────── */

struct libinput_event_keyboard *libinput_event_get_keyboard_event(
    struct libinput_event *ev)
{
    return &ev->keyboard;
}

uint32_t libinput_event_keyboard_get_key(struct libinput_event_keyboard *e)
{
    return e->key;
}

int libinput_event_keyboard_get_key_state(struct libinput_event_keyboard *e)
{
    return e->key_state;
}

uint32_t libinput_event_keyboard_get_seat_key_count(
    struct libinput_event_keyboard *e)
{
    return e->seat_key_count;
}

uint64_t libinput_event_keyboard_get_time_usec(
    struct libinput_event_keyboard *e)
{
    return e->time_usec;
}

struct libinput_event_pointer *libinput_event_get_pointer_event(
    struct libinput_event *ev)
{
    return &ev->pointer;
}

double libinput_event_pointer_get_dx(struct libinput_event_pointer *e)
{
    return e->dx;
}

double libinput_event_pointer_get_dy(struct libinput_event_pointer *e)
{
    return e->dy;
}

double libinput_event_pointer_get_dx_unaccelerated(
    struct libinput_event_pointer *e)
{
    return e->dx_unaccel;
}

double libinput_event_pointer_get_dy_unaccelerated(
    struct libinput_event_pointer *e)
{
    return e->dy_unaccel;
}

double libinput_event_pointer_get_absolute_x_transformed(
    struct libinput_event_pointer *e, uint32_t w)
{
    (void)w;
    return e->dx;
}

double libinput_event_pointer_get_absolute_y_transformed(
    struct libinput_event_pointer *e, uint32_t h)
{
    (void)h;
    return e->dy;
}

uint32_t libinput_event_pointer_get_button(struct libinput_event_pointer *e)
{
    return e->button;
}

int libinput_event_pointer_get_button_state(struct libinput_event_pointer *e)
{
    return e->button_state;
}

uint32_t libinput_event_pointer_get_seat_button_count(
    struct libinput_event_pointer *e)
{
    return e->seat_button_count;
}

uint64_t libinput_event_pointer_get_time_usec(
    struct libinput_event_pointer *e)
{
    return e->time_usec;
}

int libinput_event_pointer_has_axis(struct libinput_event_pointer *e,
                                    enum libinput_pointer_axis a)
{
    return e->axis_value[a] != 0.0 ? 1 : 0;
}

double libinput_event_pointer_get_axis_value(
    struct libinput_event_pointer *e, enum libinput_pointer_axis a)
{
    return e->axis_value[a];
}

double libinput_event_pointer_get_axis_value_discrete(
    struct libinput_event_pointer *e, enum libinput_pointer_axis a)
{
    return e->axis_value[a];
}

enum libinput_pointer_axis_source libinput_event_pointer_get_axis_source(
    struct libinput_event_pointer *e)
{
    return e->axis_source;
}

struct libinput_event_touch *libinput_event_get_touch_event(
    struct libinput_event *ev)
{
    return &ev->touch;
}

int32_t libinput_event_touch_get_seat_slot(struct libinput_event_touch *e)
{
    return e->seat_slot;
}

uint64_t libinput_event_touch_get_time_usec(struct libinput_event_touch *e)
{
    return e->time_usec;
}

double libinput_event_touch_get_x_transformed(
    struct libinput_event_touch *e, uint32_t w)
{
    (void)w;
    return e->x;
}

double libinput_event_touch_get_y_transformed(
    struct libinput_event_touch *e, uint32_t h)
{
    (void)h;
    return e->y;
}

/* ── Tablet tool functions (all stubs) ─────────────────────────────────── */

struct libinput_event_tablet_tool *libinput_event_get_tablet_tool_event(
    struct libinput_event *ev)
{
    (void)ev;
    return NULL;
}

double libinput_event_tablet_tool_get_x_transformed(
    struct libinput_event_tablet_tool *e, uint32_t w)
{ (void)e;(void)w; return 0; }

double libinput_event_tablet_tool_get_y_transformed(
    struct libinput_event_tablet_tool *e, uint32_t h)
{ (void)e;(void)h; return 0; }

double libinput_event_tablet_tool_get_pressure(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

double libinput_event_tablet_tool_get_distance(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

double libinput_event_tablet_tool_get_tilt_x(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

double libinput_event_tablet_tool_get_tilt_y(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

int libinput_event_tablet_tool_get_tip_state(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

int libinput_event_tablet_tool_get_proximity_state(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

uint32_t libinput_event_tablet_tool_get_button(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

uint32_t libinput_event_tablet_tool_get_button_state(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

uint64_t libinput_event_tablet_tool_get_time(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

int libinput_event_tablet_tool_x_has_changed(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

int libinput_event_tablet_tool_y_has_changed(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

int libinput_event_tablet_tool_pressure_has_changed(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

int libinput_event_tablet_tool_distance_has_changed(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

int libinput_event_tablet_tool_tilt_x_has_changed(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

int libinput_event_tablet_tool_tilt_y_has_changed(
    struct libinput_event_tablet_tool *e)
{ (void)e; return 0; }

struct libinput_tablet_tool *libinput_event_tablet_tool_get_tool(
    struct libinput_event_tablet_tool *e)
{ (void)e; return NULL; }

enum libinput_tablet_tool_type libinput_tablet_tool_get_type(
    struct libinput_tablet_tool *t)
{ (void)t; return 0; }

uint64_t libinput_tablet_tool_get_tool_id(struct libinput_tablet_tool *t)
{ (void)t; return 0; }

uint64_t libinput_tablet_tool_get_serial(struct libinput_tablet_tool *t)
{ (void)t; return 0; }

int libinput_tablet_tool_is_unique(struct libinput_tablet_tool *t)
{ (void)t; return 0; }

int libinput_tablet_tool_has_pressure(struct libinput_tablet_tool *t)
{ (void)t; return 0; }

int libinput_tablet_tool_has_distance(struct libinput_tablet_tool *t)
{ (void)t; return 0; }

int libinput_tablet_tool_has_tilt(struct libinput_tablet_tool *t)
{ (void)t; return 0; }

void libinput_tablet_tool_set_user_data(struct libinput_tablet_tool *t,
                                        void *d)
{ (void)t;(void)d; }

void *libinput_tablet_tool_get_user_data(struct libinput_tablet_tool *t)
{ (void)t; return NULL; }

/* ── Misc functions ────────────────────────────────────────────────────── */

void *libinput_get_user_data(struct libinput *l)
{
    return l ? l->user_data : NULL;
}

void libinput_log_set_handler(struct libinput *l, libinput_log_handler h)
{
    (void)l;(void)(void*)h;
}

void libinput_log_set_priority(struct libinput *l, enum libinput_log_priority p)
{
    (void)l;(void)(int)p;
}
