#include "libudev.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static struct udev g_dev;
static struct udev_device g_devnode_dev;
static struct udev_enumerate g_enum;
static struct udev_list_entry g_entry;
static int g_init;

static void ensure(void) {
    if (g_init) return;
    g_entry.name = "card0";
    g_entry.next = NULL;
    g_dev.refcount = 1;
    g_dev.monitor_pipe_r = -1;
    g_dev.monitor_pipe_w = -1;
    g_devnode_dev.devnode = "/dev/dri/card0";
    g_devnode_dev.syspath = "/sys/devices/virtual/drm/card0";
    g_devnode_dev.sysnum = "0";
    g_devnode_dev.property_val = NULL;
    g_init = 1;
}

static int ensure_monitor_pipe(struct udev *u) {
    if (u->monitor_pipe_r < 0) {
        int p[2];
        if (pipe(p) == 0) {
            fcntl(p[0], F_SETFL, fcntl(p[0], F_GETFL) | O_NONBLOCK);
            u->monitor_pipe_r = p[0];
            u->monitor_pipe_w = p[1];
        }
    }
    return u->monitor_pipe_r;
}

struct udev *udev_new(void) {
    ensure();
    g_dev.refcount++;
    return &g_dev;
}

struct udev *udev_unref(struct udev *u) {
    if (u && --u->refcount <= 0)
        g_init = 0;
    return NULL;
}

struct udev_device *udev_device_new_from_syspath(struct udev *u, const char *p) {
    (void)u;
    ensure();
    if (p) g_devnode_dev.syspath = p;
    g_devnode_dev.devnode = "/dev/dri/card0";
    return &g_devnode_dev;
}

struct udev_device *udev_device_new_from_subsystem_sysname(struct udev *u, const char *subsys, const char *sysname) {
    (void)u;(void)subsys;(void)sysname;
    ensure();
    g_devnode_dev.devnode = "/dev/dri/card0";
    return &g_devnode_dev;
}

struct udev_device *udev_device_ref(struct udev_device *d) { return d; }
struct udev_device *udev_device_unref(struct udev_device *d) { (void)d; return NULL; }

struct udev_device *udev_device_get_parent_with_subsystem_devtype(
    struct udev_device *d, const char *a, const char *b) {
    (void)d;(void)a;(void)b;
    return NULL;
}

const char *udev_device_get_syspath(struct udev_device *d) {
    return d ? d->syspath : NULL;
}

const char *udev_device_get_sysattr_value(struct udev_device *d, const char *a) {
    (void)d;(void)a;
    return NULL;
}

const char *udev_device_get_property_value(struct udev_device *d, const char *k) {
    (void)k;
    return d ? d->property_val : NULL;
}

const char *udev_device_get_devnode(struct udev_device *d) {
    return d ? d->devnode : NULL;
}

const char *udev_device_get_sysnum(struct udev_device *d) {
    return d ? d->sysnum : NULL;
}

dev_t udev_device_get_devnum(struct udev_device *d) {
    (void)d;
    return 0;
}

struct udev_enumerate *udev_enumerate_new(struct udev *u) {
    (void)u;
    ensure();
    return &g_enum;
}

int udev_enumerate_add_match_subsystem(struct udev_enumerate *e, const char *s) {
    (void)e;(void)s;
    return 0;
}

int udev_enumerate_add_match_sysname(struct udev_enumerate *e, const char *s) {
    (void)e;(void)s;
    return 0;
}

int udev_enumerate_scan_devices(struct udev_enumerate *e) {
    (void)e;
    return 0;
}

struct udev_enumerate *udev_enumerate_unref(struct udev_enumerate *e) {
    (void)e;
    return NULL;
}

struct udev_list_entry *udev_enumerate_get_list_entry(struct udev_enumerate *e) {
    (void)e;
    ensure();
    return &g_entry;
}

struct udev_list_entry *udev_list_entry_get_next(struct udev_list_entry *e) {
    (void)e;
    return NULL;
}

const char *udev_list_entry_get_name(struct udev_list_entry *e) {
    return e ? e->name : NULL;
}

struct udev_monitor *udev_monitor_new_from_netlink(struct udev *u, const char *n) {
    (void)n;
    ensure();
    /* Return a pointer into the udev struct itself */
    return (struct udev_monitor *)&u->monitor_pipe_r;
}

int udev_monitor_filter_add_match_subsystem_devtype(struct udev_monitor *m, const char *a, const char *b) {
    (void)m;(void)a;(void)b;
    return 0;
}

int udev_monitor_enable_receiving(struct udev_monitor *m) {
    (void)m;
    return 0;
}

int udev_monitor_get_fd(struct udev_monitor *m) {
    return ensure_monitor_pipe(&g_dev);
}

struct udev_device *udev_monitor_receive_device(struct udev_monitor *m) {
    (void)m;
    return NULL;
}

struct udev_monitor *udev_monitor_unref(struct udev_monitor *m) {
    (void)m;
    return NULL;
}
