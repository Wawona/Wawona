#ifndef INPUT_IPC_H
#define INPUT_IPC_H

#include <mach/mach.h>
#include <stdint.h>

#define INPUT_IPC_SERVICE_NAME   "com.wayland-mac.inputd"
#define INPUT_IPC_SUBSCRIBE_ID   0x494E5053  /* 'INPS' */
#define INPUT_IPC_EVENT_ID       0x494E5045  /* 'INPE' */

typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t   body;
    mach_msg_port_descriptor_t client_port;
} input_ipc_subscribe_t;

#define INPUT_IPC_EVENT_NONE           0
#define INPUT_IPC_EVENT_DEVICE_ADDED   1
#define INPUT_IPC_EVENT_DEVICE_REMOVED 2
#define INPUT_IPC_EVENT_KEYBOARD_KEY   3
#define INPUT_IPC_EVENT_POINTER_MOTION 4
#define INPUT_IPC_EVENT_POINTER_BUTTON 5
#define INPUT_IPC_EVENT_POINTER_AXIS   6
#define INPUT_IPC_EVENT_TOUCH_DOWN     7
#define INPUT_IPC_EVENT_TOUCH_UP       8
#define INPUT_IPC_EVENT_TOUCH_MOTION   9
#define INPUT_IPC_EVENT_TOUCH_FRAME    10

#define INPUT_IPC_CAP_KEYBOARD (1 << 0)
#define INPUT_IPC_CAP_POINTER  (1 << 1)
#define INPUT_IPC_CAP_TOUCH    (1 << 2)

typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t   body;
    uint64_t          time_usec;
    int32_t           event_type;
    int32_t           device_id;
    int32_t           device_caps;
    char              device_name[64];
    int32_t           key;
    int32_t           key_state;
    double            pointer_dx;
    double            pointer_dy;
    int32_t           pointer_button;
    int32_t           pointer_button_state;
    int32_t           pointer_axis;
    double            pointer_axis_value;
    int32_t           touch_slot;
    double            touch_x;
    double            touch_y;
    int32_t           touch_state;
} input_ipc_event_t;

#endif
