#include <libinput.h>
#include <libudev.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile int g_running = 1;

static void handle_signal(int sig)
{
    (void)sig;
    g_running = 0;
}

static const char *event_name(int type)
{
    switch (type) {
    case LIBINPUT_EVENT_NONE:               return "NONE";
    case LIBINPUT_EVENT_DEVICE_ADDED:       return "DEVICE_ADDED";
    case LIBINPUT_EVENT_DEVICE_REMOVED:     return "DEVICE_REMOVED";
    case LIBINPUT_EVENT_KEYBOARD_KEY:       return "KEYBOARD_KEY";
    case LIBINPUT_EVENT_POINTER_MOTION:     return "POINTER_MOTION";
    case LIBINPUT_EVENT_POINTER_BUTTON:     return "POINTER_BUTTON";
    case LIBINPUT_EVENT_POINTER_AXIS:       return "POINTER_AXIS";
    default:                                return "UNKNOWN";
    }
}

int main(void)
{
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    struct udev *udev = udev_new();
    if (!udev) {
        fprintf(stderr, "udev_new failed\n");
        return 1;
    }

    struct libinput_interface iface = { NULL, NULL };
    struct libinput *li = libinput_udev_create_context(&iface, NULL, udev);
    if (!li) {
        fprintf(stderr, "libinput_udev_create_context failed\n");
        return 1;
    }

    if (libinput_udev_assign_seat(li, "seat0") != 0) {
        fprintf(stderr, "libinput_udev_assign_seat failed\n");
        return 1;
    }

    int fd = libinput_get_fd(li);
    printf("fd=%d\n", fd);

    while (g_running) {
        struct pollfd pfd = { .fd = fd, .events = POLLIN };
        int ret = poll(&pfd, 1, 100);
        if (ret < 0) break;
        if (ret == 0) continue;

        libinput_dispatch(li);

        struct libinput_event *ev;
        while ((ev = libinput_get_event(li)) != NULL) {
            int type = (int)libinput_event_get_type(ev);
            struct libinput_device *dev = libinput_event_get_device(ev);

            printf("[%s]", event_name(type));

            switch (type) {
            case LIBINPUT_EVENT_DEVICE_ADDED: {
                const char *name = libinput_device_get_name(dev);
                int has_kbd = libinput_device_has_capability(dev,
                                LIBINPUT_DEVICE_CAP_KEYBOARD);
                int has_ptr = libinput_device_has_capability(dev,
                                LIBINPUT_DEVICE_CAP_POINTER);
                int has_touch = libinput_device_has_capability(dev,
                                 LIBINPUT_DEVICE_CAP_TOUCH);
                printf("  name=\"%s\" caps=", name ? name : "?");
                if (has_kbd)  printf(" KEYBOARD");
                if (has_ptr)  printf(" POINTER");
                if (has_touch) printf(" TOUCH");
                break;
            }
            case LIBINPUT_EVENT_DEVICE_REMOVED: {
                const char *name = libinput_device_get_name(dev);
                printf("  name=\"%s\"", name ? name : "?");
                break;
            }
            case LIBINPUT_EVENT_KEYBOARD_KEY: {
                uint32_t key = libinput_event_keyboard_get_key(
                    libinput_event_get_keyboard_event(ev));
                int state = libinput_event_keyboard_get_key_state(
                    libinput_event_get_keyboard_event(ev));
                printf("  key=%u state=%s", key,
                       state == LIBINPUT_KEY_STATE_PRESSED ? "PRESSED"
                                                           : "RELEASED");
                break;
            }
            case LIBINPUT_EVENT_POINTER_MOTION: {
                double dx = libinput_event_pointer_get_dx(
                    libinput_event_get_pointer_event(ev));
                double dy = libinput_event_pointer_get_dy(
                    libinput_event_get_pointer_event(ev));
                printf("  dx=%.1f dy=%.1f", dx, dy);
                break;
            }
            case LIBINPUT_EVENT_POINTER_BUTTON: {
                uint32_t btn = libinput_event_pointer_get_button(
                    libinput_event_get_pointer_event(ev));
                int state = libinput_event_pointer_get_button_state(
                    libinput_event_get_pointer_event(ev));
                printf("  button=%u state=%s", btn,
                       state == LIBINPUT_BUTTON_STATE_PRESSED ? "PRESSED"
                                                              : "RELEASED");
                break;
            }
            case LIBINPUT_EVENT_POINTER_AXIS: {
                double val = libinput_event_pointer_get_axis_value(
                    libinput_event_get_pointer_event(ev),
                    LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL);
                printf("  scroll=%.1f", val);
                break;
            }
            }

            printf("\n");
            libinput_event_destroy(ev);
        }
    }

    libinput_unref(li);
    udev_unref(udev);
    return 0;
}
