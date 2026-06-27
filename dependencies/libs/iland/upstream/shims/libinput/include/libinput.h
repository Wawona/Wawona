#ifndef LIBINPUT_H
#define LIBINPUT_H
#include <stdint.h>
#include <stddef.h>
#include <libudev.h>
#include <stdarg.h>
enum libinput_event_type {
    LIBINPUT_EVENT_NONE=0, LIBINPUT_EVENT_DEVICE_ADDED, LIBINPUT_EVENT_DEVICE_REMOVED,
    LIBINPUT_EVENT_KEYBOARD_KEY, LIBINPUT_EVENT_POINTER_MOTION,
    LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE, LIBINPUT_EVENT_POINTER_BUTTON,
    LIBINPUT_EVENT_POINTER_AXIS, LIBINPUT_EVENT_TOUCH_DOWN, LIBINPUT_EVENT_TOUCH_UP,
    LIBINPUT_EVENT_TOUCH_MOTION, LIBINPUT_EVENT_TOUCH_CANCEL,
    LIBINPUT_EVENT_TOUCH_FRAME,
    LIBINPUT_EVENT_TABLET_TOOL_AXIS, LIBINPUT_EVENT_TABLET_TOOL_PROXIMITY,
    LIBINPUT_EVENT_TABLET_TOOL_TIP, LIBINPUT_EVENT_TABLET_TOOL_BUTTON,
    LIBINPUT_EVENT_TABLET_PAD_BUTTON, LIBINPUT_EVENT_TABLET_PAD_RING,
    LIBINPUT_EVENT_TABLET_PAD_STRIP, LIBINPUT_EVENT_GESTURE_SWIPE_BEGIN,
    LIBINPUT_EVENT_GESTURE_SWIPE_UPDATE, LIBINPUT_EVENT_GESTURE_SWIPE_END,
    LIBINPUT_EVENT_GESTURE_PINCH_BEGIN, LIBINPUT_EVENT_GESTURE_PINCH_UPDATE,
    LIBINPUT_EVENT_GESTURE_PINCH_END, LIBINPUT_EVENT_SWITCH_TOGGLE,
};
enum libinput_capability { LIBINPUT_DEVICE_CAP_KEYBOARD=0, LIBINPUT_DEVICE_CAP_POINTER=1,
    LIBINPUT_DEVICE_CAP_TOUCH=2, LIBINPUT_DEVICE_CAP_TABLET_TOOL=3,
    LIBINPUT_DEVICE_CAP_TABLET_PAD=4, LIBINPUT_DEVICE_CAP_GESTURE=5, LIBINPUT_DEVICE_CAP_SWITCH=6 };
enum libinput_led { LIBINPUT_LED_NUM_LOCK=1, LIBINPUT_LED_CAPS_LOCK=2, LIBINPUT_LED_SCROLL_LOCK=4 };
enum libinput_key_state { LIBINPUT_KEY_STATE_RELEASED=0, LIBINPUT_KEY_STATE_PRESSED=1 };
enum libinput_button_state { LIBINPUT_BUTTON_STATE_RELEASED=0, LIBINPUT_BUTTON_STATE_PRESSED=1 };
enum libinput_tablet_tool_proximity_state { LIBINPUT_TABLET_TOOL_PROXIMITY_STATE_OUT=0, LIBINPUT_TABLET_TOOL_PROXIMITY_STATE_IN=1 };
enum libinput_tablet_tool_tip_state { LIBINPUT_TABLET_TOOL_TIP_UP=0, LIBINPUT_TABLET_TOOL_TIP_DOWN=1 };
enum libinput_pointer_axis { LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL=0, LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL=1 };
enum libinput_pointer_axis_source { LIBINPUT_POINTER_AXIS_SOURCE_WHEEL=1,
    LIBINPUT_POINTER_AXIS_SOURCE_FINGER=2, LIBINPUT_POINTER_AXIS_SOURCE_CONTINUOUS=3,
    LIBINPUT_POINTER_AXIS_SOURCE_WHEEL_TILT=4 };
enum libinput_config_accel_profile { LIBINPUT_CONFIG_ACCEL_PROFILE_NONE=0,
    LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT=1, LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE=2 };
enum libinput_config_scroll_method { LIBINPUT_CONFIG_SCROLL_NO_SCROLL=0,
    LIBINPUT_CONFIG_SCROLL_2FG=1, LIBINPUT_CONFIG_SCROLL_EDGE=2, LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN=3 };
enum libinput_config_status { LIBINPUT_CONFIG_STATUS_SUCCESS=0,
    LIBINPUT_CONFIG_STATUS_UNSUPPORTED=1, LIBINPUT_CONFIG_STATUS_INVALID=2 };
enum libinput_tablet_tool_type { LIBINPUT_TABLET_TOOL_TYPE_PEN=1, LIBINPUT_TABLET_TOOL_TYPE_ERASER=2 };
enum libinput_log_priority { LIBINPUT_LOG_PRIORITY_ERROR=3, LIBINPUT_LOG_PRIORITY_INFO=4, LIBINPUT_LOG_PRIORITY_DEBUG=7 };
struct libinput;
struct libinput_event;
struct libinput_device;
struct libinput_seat;
struct libinput_tablet_tool;
struct libinput_event_keyboard;
struct libinput_event_pointer;
struct libinput_event_touch;
struct libinput_event_tablet_tool;
struct libinput_interface { int (*open_restricted)(const char *, int, void *); void (*close_restricted)(int, void *); };
typedef void (*libinput_log_handler)(struct libinput *, enum libinput_log_priority, const char *, va_list);

struct libinput *libinput_udev_create_context(const struct libinput_interface *, void *, struct udev *);
struct libinput *libinput_unref(struct libinput *);
int libinput_udev_assign_seat(struct libinput *, const char *);
int libinput_get_fd(struct libinput *);
int libinput_dispatch(struct libinput *);
struct libinput_event *libinput_get_event(struct libinput *);
void libinput_event_destroy(struct libinput_event *);
struct libinput *libinput_event_get_context(struct libinput_event *);
enum libinput_event_type libinput_event_get_type(struct libinput_event *);
struct libinput_device *libinput_event_get_device(struct libinput_event *);
int libinput_suspend(struct libinput *);
int libinput_resume(struct libinput *);
struct libinput_device *libinput_device_ref(struct libinput_device *);
struct libinput_device *libinput_device_unref(struct libinput_device *);
void libinput_device_set_user_data(struct libinput_device *, void *);
void *libinput_device_get_user_data(struct libinput_device *);
int libinput_device_has_capability(struct libinput_device *, enum libinput_capability);
const char *libinput_device_get_name(struct libinput_device *);
const char *libinput_device_get_sysname(struct libinput_device *);
const char *libinput_device_get_output_name(struct libinput_device *);
unsigned int libinput_device_get_id_product(struct libinput_device *);
unsigned int libinput_device_get_id_vendor(struct libinput_device *);
struct libinput_seat *libinput_device_get_seat(struct libinput_device *);
struct udev_device *libinput_device_get_udev_device(struct libinput_device *);
int libinput_device_config_tap_set_enabled(struct libinput_device *, int);
int libinput_device_config_tap_get_finger_count(struct libinput_device *);
int libinput_device_config_tap_set_drag_enabled(struct libinput_device *, int);
int libinput_device_config_tap_set_drag_lock_enabled(struct libinput_device *, int);
int libinput_device_config_calibration_has_matrix(struct libinput_device *);
int libinput_device_config_calibration_set_matrix(struct libinput_device *, const float[9]);
int libinput_device_config_calibration_get_matrix(struct libinput_device *, float[9]);
int libinput_device_config_calibration_get_default_matrix(struct libinput_device *, float[9]);
int libinput_device_config_left_handed_is_available(struct libinput_device *);
int libinput_device_config_left_handed_set(struct libinput_device *, int);
int libinput_device_config_middle_emulation_is_available(struct libinput_device *);
int libinput_device_config_middle_emulation_set_enabled(struct libinput_device *, int);
int libinput_device_config_dwt_is_available(struct libinput_device *);
int libinput_device_config_dwt_set_enabled(struct libinput_device *, int);
int libinput_device_config_rotation_is_available(struct libinput_device *);
int libinput_device_config_rotation_set_angle(struct libinput_device *, unsigned int);
int libinput_device_config_accel_is_available(struct libinput_device *);
enum libinput_config_status libinput_device_config_accel_set_speed(struct libinput_device *, double);
enum libinput_config_accel_profile libinput_device_config_accel_get_profiles(struct libinput_device *);
enum libinput_config_status libinput_device_config_accel_set_profile(struct libinput_device *, enum libinput_config_accel_profile);
enum libinput_config_scroll_method libinput_device_config_scroll_get_methods(struct libinput_device *);
enum libinput_config_status libinput_device_config_scroll_set_method(struct libinput_device *, enum libinput_config_scroll_method);
int libinput_device_config_scroll_set_button(struct libinput_device *, uint32_t);
int libinput_device_config_scroll_has_natural_scroll(struct libinput_device *);
int libinput_device_config_scroll_set_natural_scroll_enabled(struct libinput_device *, int);
int libinput_device_led_update(struct libinput_device *, enum libinput_led);
const char *libinput_seat_get_logical_name(struct libinput_seat *);
struct libinput_event_keyboard *libinput_event_get_keyboard_event(struct libinput_event *);
uint32_t libinput_event_keyboard_get_key(struct libinput_event_keyboard *);
int libinput_event_keyboard_get_key_state(struct libinput_event_keyboard *);
uint32_t libinput_event_keyboard_get_seat_key_count(struct libinput_event_keyboard *);
uint64_t libinput_event_keyboard_get_time_usec(struct libinput_event_keyboard *);
struct libinput_event_pointer *libinput_event_get_pointer_event(struct libinput_event *);
double libinput_event_pointer_get_dx(struct libinput_event_pointer *);
double libinput_event_pointer_get_dy(struct libinput_event_pointer *);
double libinput_event_pointer_get_dx_unaccelerated(struct libinput_event_pointer *);
double libinput_event_pointer_get_dy_unaccelerated(struct libinput_event_pointer *);
double libinput_event_pointer_get_absolute_x_transformed(struct libinput_event_pointer *, uint32_t);
double libinput_event_pointer_get_absolute_y_transformed(struct libinput_event_pointer *, uint32_t);
uint32_t libinput_event_pointer_get_button(struct libinput_event_pointer *);
int libinput_event_pointer_get_button_state(struct libinput_event_pointer *);
uint32_t libinput_event_pointer_get_seat_button_count(struct libinput_event_pointer *);
uint64_t libinput_event_pointer_get_time_usec(struct libinput_event_pointer *);
int libinput_event_pointer_has_axis(struct libinput_event_pointer *, enum libinput_pointer_axis);
double libinput_event_pointer_get_axis_value(struct libinput_event_pointer *, enum libinput_pointer_axis);
double libinput_event_pointer_get_axis_value_discrete(struct libinput_event_pointer *, enum libinput_pointer_axis);
enum libinput_pointer_axis_source libinput_event_pointer_get_axis_source(struct libinput_event_pointer *);
struct libinput_event_touch *libinput_event_get_touch_event(struct libinput_event *);
int32_t libinput_event_touch_get_seat_slot(struct libinput_event_touch *);
uint64_t libinput_event_touch_get_time_usec(struct libinput_event_touch *);
double libinput_event_touch_get_x_transformed(struct libinput_event_touch *, uint32_t);
double libinput_event_touch_get_y_transformed(struct libinput_event_touch *, uint32_t);
struct libinput_event_tablet_tool *libinput_event_get_tablet_tool_event(struct libinput_event *);
double libinput_event_tablet_tool_get_x_transformed(struct libinput_event_tablet_tool *, uint32_t);
double libinput_event_tablet_tool_get_y_transformed(struct libinput_event_tablet_tool *, uint32_t);
double libinput_event_tablet_tool_get_pressure(struct libinput_event_tablet_tool *);
double libinput_event_tablet_tool_get_distance(struct libinput_event_tablet_tool *);
double libinput_event_tablet_tool_get_tilt_x(struct libinput_event_tablet_tool *);
double libinput_event_tablet_tool_get_tilt_y(struct libinput_event_tablet_tool *);
int libinput_event_tablet_tool_get_tip_state(struct libinput_event_tablet_tool *);
int libinput_event_tablet_tool_get_proximity_state(struct libinput_event_tablet_tool *);
uint32_t libinput_event_tablet_tool_get_button(struct libinput_event_tablet_tool *);
uint32_t libinput_event_tablet_tool_get_button_state(struct libinput_event_tablet_tool *);
uint64_t libinput_event_tablet_tool_get_time(struct libinput_event_tablet_tool *);
int libinput_event_tablet_tool_x_has_changed(struct libinput_event_tablet_tool *);
int libinput_event_tablet_tool_y_has_changed(struct libinput_event_tablet_tool *);
int libinput_event_tablet_tool_pressure_has_changed(struct libinput_event_tablet_tool *);
int libinput_event_tablet_tool_distance_has_changed(struct libinput_event_tablet_tool *);
int libinput_event_tablet_tool_tilt_x_has_changed(struct libinput_event_tablet_tool *);
int libinput_event_tablet_tool_tilt_y_has_changed(struct libinput_event_tablet_tool *);
struct libinput_tablet_tool *libinput_event_tablet_tool_get_tool(struct libinput_event_tablet_tool *);
enum libinput_tablet_tool_type libinput_tablet_tool_get_type(struct libinput_tablet_tool *);
uint64_t libinput_tablet_tool_get_tool_id(struct libinput_tablet_tool *);
uint64_t libinput_tablet_tool_get_serial(struct libinput_tablet_tool *);
int libinput_tablet_tool_is_unique(struct libinput_tablet_tool *);
int libinput_tablet_tool_has_pressure(struct libinput_tablet_tool *);
int libinput_tablet_tool_has_distance(struct libinput_tablet_tool *);
int libinput_tablet_tool_has_tilt(struct libinput_tablet_tool *);
void libinput_tablet_tool_set_user_data(struct libinput_tablet_tool *, void *);
void *libinput_tablet_tool_get_user_data(struct libinput_tablet_tool *);
void *libinput_get_user_data(struct libinput *);
void libinput_log_set_handler(struct libinput *, libinput_log_handler);
void libinput_log_set_priority(struct libinput *, enum libinput_log_priority);
#endif /* LIBINPUT_H */