#ifndef LIBUDEV_H
#define LIBUDEV_H

#include <sys/types.h>

struct udev {
    int refcount;
    int monitor_pipe_r;
    int monitor_pipe_w;
};

struct udev_device {
    const char *devnode;
    const char *syspath;
    const char *sysnum;
    const char *property_val;
};

struct udev_enumerate {
    int dummy;
};

struct udev_list_entry {
    const char *name;
    struct udev_list_entry *next;
};

struct udev_monitor {
    int pipe_r;
    int pipe_w;
};

#ifdef __cplusplus
extern "C" {
#endif

struct udev *udev_new(void);
struct udev *udev_unref(struct udev *);
struct udev_device *udev_device_new_from_syspath(struct udev *, const char *);
struct udev_device *udev_device_new_from_subsystem_sysname(struct udev *, const char *, const char *);
struct udev_device *udev_device_ref(struct udev_device *);
struct udev_device *udev_device_unref(struct udev_device *);
struct udev_device *udev_device_get_parent_with_subsystem_devtype(struct udev_device *, const char *, const char *);
const char *udev_device_get_syspath(struct udev_device *);
const char *udev_device_get_sysattr_value(struct udev_device *, const char *);
const char *udev_device_get_property_value(struct udev_device *, const char *);
const char *udev_device_get_devnode(struct udev_device *);
const char *udev_device_get_sysnum(struct udev_device *);
dev_t udev_device_get_devnum(struct udev_device *);
struct udev_enumerate *udev_enumerate_new(struct udev *);
int udev_enumerate_add_match_subsystem(struct udev_enumerate *, const char *);
int udev_enumerate_add_match_sysname(struct udev_enumerate *, const char *);
int udev_enumerate_scan_devices(struct udev_enumerate *);
struct udev_enumerate *udev_enumerate_unref(struct udev_enumerate *);
struct udev_list_entry *udev_enumerate_get_list_entry(struct udev_enumerate *);
struct udev_list_entry *udev_list_entry_get_next(struct udev_list_entry *);
const char *udev_list_entry_get_name(struct udev_list_entry *);
#define udev_list_entry_foreach(e, list) for (e = list; e; e = udev_list_entry_get_next(e))
struct udev_monitor *udev_monitor_new_from_netlink(struct udev *, const char *);
int udev_monitor_filter_add_match_subsystem_devtype(struct udev_monitor *, const char *, const char *);
int udev_monitor_enable_receiving(struct udev_monitor *);
int udev_monitor_get_fd(struct udev_monitor *);
struct udev_device *udev_monitor_receive_device(struct udev_monitor *);
struct udev_monitor *udev_monitor_unref(struct udev_monitor *);

#ifdef __cplusplus
}
#endif

#endif /* LIBUDEV_H */
