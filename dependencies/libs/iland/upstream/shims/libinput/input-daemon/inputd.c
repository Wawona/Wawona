#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <mach/mach.h>
#include <bootstrap.h>
#include <mach/mach_time.h>
#include <input_ipc.h>

#include <CoreFoundation/CoreFoundation.h>

/* ---- private IOKit IOHIDEventSystem API (from IOKit.framework) ---- */
typedef struct __IOHIDEventSystem *IOHIDEventSystemRef;
typedef struct __IOHIDEvent      *IOHIDEventRef;

extern IOHIDEventSystemRef IOHIDEventSystemCreate(CFAllocatorRef);
extern int                 IOHIDEventSystemOpen(IOHIDEventSystemRef, void *callback,
                                                 void *target, void *notification,
                                                 void *runLoop);

extern uint32_t IOHIDEventGetType(IOHIDEventRef);
extern uint64_t IOHIDEventGetTimeStamp(IOHIDEventRef);
extern int32_t  IOHIDEventGetIntegerValue(IOHIDEventRef, uint32_t field);
extern float    IOHIDEventGetFloatValue(IOHIDEventRef, uint32_t field);
extern CFArrayRef IOHIDEventGetChildren(IOHIDEventRef);
extern IOHIDEventRef IOHIDEventCreateCopy(CFAllocatorRef, IOHIDEventRef);
extern CFStringRef   IOHIDEventCopyDescription(IOHIDEventRef, void *);
extern int           IOHIDEventSystemClose(IOHIDEventSystemRef, void *);
extern int           IOHIDEventConformsTo(IOHIDEventRef, uint32_t type);

/* IOHIDEventType enum (from IOKit/hid/IOHIDEventTypes.h) */
enum {
    kIOHIDEventTypeNULL             = 0,
    kIOHIDEventTypeVendorDefined    = 1,
    kIOHIDEventTypeButton           = 2,
    kIOHIDEventTypeKeyboard         = 3,
    kIOHIDEventTypeTranslation      = 4,
    kIOHIDEventTypeRotation         = 5,
    kIOHIDEventTypeScroll           = 6,
    kIOHIDEventTypeScale            = 7,
    kIOHIDEventTypeZoom             = 8,
    kIOHIDEventTypeVelocity         = 9,
    kIOHIDEventTypeOrientation      = 10,
    kIOHIDEventTypeDigitizer        = 11,
    kIOHIDEventTypeAmbientLightSensor = 12,
    kIOHIDEventTypeAccelerometer    = 13,
    kIOHIDEventTypeProximity        = 14,
    kIOHIDEventTypeTemperature      = 15,
    kIOHIDEventTypeNavigationSwipe  = 16,
    kIOHIDEventTypeMouse            = 17,
    kIOHIDEventTypeProgress         = 18,
    kIOHIDEventTypeGyro             = 20,
    kIOHIDEventTypeCompass          = 21,
    kIOHIDEventTypeZoomToggle       = 22,
    kIOHIDEventTypeDockSwipe        = 23,
    kIOHIDEventTypeSymbolicHotKey   = 24,
    kIOHIDEventTypePower            = 25,
    kIOHIDEventTypeFluidTouchGesture = 26,
    kIOHIDEventTypeBoundaryScroll   = 27,
    kIOHIDEventTypeGenericGesture   = 28,
    kIOHIDEventTypeForce            = 29,
};

/* IOHIDEventField paths: (type << 16) | field_offset */
#define IOHIDEventFieldBase(type) ((uint32_t)(type) << 16)

enum {
    /* Keyboard (type 3) */
    kIOHIDEventFieldKeyboardUsagePage = IOHIDEventFieldBase(3) | 0,
    kIOHIDEventFieldKeyboardUsage     = IOHIDEventFieldBase(3) | 1,
    kIOHIDEventFieldKeyboardDown      = IOHIDEventFieldBase(3) | 2,
    kIOHIDEventFieldKeyboardRepeat    = IOHIDEventFieldBase(3) | 3,

    /* Button (type 2) */
    kIOHIDEventFieldButtonMask       = IOHIDEventFieldBase(2) | 0,
    kIOHIDEventFieldButtonNumber     = IOHIDEventFieldBase(2) | 1,
    kIOHIDEventFieldButtonClickCount = IOHIDEventFieldBase(2) | 2,
    kIOHIDEventFieldButtonPressure   = IOHIDEventFieldBase(2) | 3,
    kIOHIDEventFieldButtonState      = IOHIDEventFieldBase(2) | 4,

    /* Translation (type 4) — trackpad delta */
    kIOHIDEventFieldTranslationX = IOHIDEventFieldBase(4) | 0,
    kIOHIDEventFieldTranslationY = IOHIDEventFieldBase(4) | 1,
    kIOHIDEventFieldTranslationZ = IOHIDEventFieldBase(4) | 2,

    /* Scroll (type 6) */
    kIOHIDEventFieldScrollX       = IOHIDEventFieldBase(6) | 0,
    kIOHIDEventFieldScrollY       = IOHIDEventFieldBase(6) | 1,
    kIOHIDEventFieldScrollZ       = IOHIDEventFieldBase(6) | 2,
    kIOHIDEventFieldScrollMomentum = IOHIDEventFieldBase(6) | 3,

    /* Mouse (type 17) — field offsets per IDA: 0x110000=X, 0x110001=Y */
    kIOHIDEventFieldMouseX        = IOHIDEventFieldBase(17) | 0,
    kIOHIDEventFieldMouseY        = IOHIDEventFieldBase(17) | 1,
    kIOHIDEventFieldMouseButton   = IOHIDEventFieldBase(17) | 3,

    /* Digitizer (type 11) — absolute touch */
    kIOHIDEventFieldDigitizerX             = IOHIDEventFieldBase(11) | 0,
    kIOHIDEventFieldDigitizerY             = IOHIDEventFieldBase(11) | 1,
    kIOHIDEventFieldDigitizerType          = IOHIDEventFieldBase(11) | 2,
    kIOHIDEventFieldDigitizerIndex         = IOHIDEventFieldBase(11) | 3,
    kIOHIDEventFieldDigitizerIdentity      = IOHIDEventFieldBase(11) | 4,
    kIOHIDEventFieldDigitizerEventMask     = IOHIDEventFieldBase(11) | 5,
    kIOHIDEventFieldDigitizerRange         = IOHIDEventFieldBase(11) | 14,
    kIOHIDEventFieldDigitizerTouch         = IOHIDEventFieldBase(11) | 15,
    kIOHIDEventFieldDigitizerCollection    = IOHIDEventFieldBase(11) | 16,
    kIOHIDEventFieldDigitizerChildCount    = IOHIDEventFieldBase(11) | 17,

    /* Accelerometer (type 13) */
    kIOHIDEventFieldAccelerometerX = IOHIDEventFieldBase(13) | 0,
    kIOHIDEventFieldAccelerometerY = IOHIDEventFieldBase(13) | 1,
    kIOHIDEventFieldAccelerometerZ = IOHIDEventFieldBase(13) | 2,
};

static const char *iohid_event_type_name(uint32_t type)
{
    switch (type) {
    case kIOHIDEventTypeNULL:              return "NULL";
    case kIOHIDEventTypeVendorDefined:     return "VendorDefined";
    case kIOHIDEventTypeButton:            return "Button";
    case kIOHIDEventTypeKeyboard:          return "Keyboard";
    case kIOHIDEventTypeTranslation:       return "Translation";
    case kIOHIDEventTypeRotation:          return "Rotation";
    case kIOHIDEventTypeScroll:            return "Scroll";
    case kIOHIDEventTypeScale:             return "Scale";
    case kIOHIDEventTypeZoom:              return "Zoom";
    case kIOHIDEventTypeVelocity:          return "Velocity";
    case kIOHIDEventTypeOrientation:       return "Orientation";
    case kIOHIDEventTypeDigitizer:         return "Digitizer";
    case kIOHIDEventTypeAmbientLightSensor: return "AmbientLightSensor";
    case kIOHIDEventTypeAccelerometer:     return "Accelerometer";
    case kIOHIDEventTypeProximity:         return "Proximity";
    case kIOHIDEventTypeTemperature:       return "Temperature";
    case kIOHIDEventTypeNavigationSwipe:   return "NavigationSwipe";
    case kIOHIDEventTypeMouse:             return "Mouse";
    case kIOHIDEventTypeProgress:          return "Progress";
    case kIOHIDEventTypeGyro:              return "Gyro";
    case kIOHIDEventTypeCompass:           return "Compass";
    case kIOHIDEventTypeZoomToggle:        return "ZoomToggle";
    case kIOHIDEventTypeDockSwipe:         return "DockSwipe";
    case kIOHIDEventTypeSymbolicHotKey:    return "SymbolicHotKey";
    case kIOHIDEventTypePower:             return "Power";
    case kIOHIDEventTypeFluidTouchGesture: return "FluidTouchGesture";
    case kIOHIDEventTypeBoundaryScroll:    return "BoundaryScroll";
    case kIOHIDEventTypeGenericGesture:    return "GenericGesture";
    case kIOHIDEventTypeForce:             return "Force";
    }
    return "Unknown";
}

/* MultitouchSupport private framework types */
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;
enum {
    MTTouchStateNotTracking = 0, MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2, MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4, MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6, MTTouchStateOutOfRange = 7,
};
typedef int MTTouchState;
typedef struct {
    int frame; double timestamp; int identifier; MTTouchState state;
    int fingerId; int handId; MTVector normalizedPosition;
    float total; float pressure; float angle;
    float majorAxis; float minorAxis; MTVector absolutePosition;
    int field14; int field15; float density;
} MTTouch;
typedef void *MTDeviceRef;
typedef void (*MTFrameCallback)(MTDeviceRef, MTTouch[], int, double, int);

bool MTDeviceIsAvailable(void);
MTDeviceRef MTDeviceCreateDefault(void);
int MTDeviceStart(MTDeviceRef, int);
int MTDeviceStop(MTDeviceRef);
void MTDeviceRelease(MTDeviceRef);
void MTRegisterContactFrameCallback(MTDeviceRef, MTFrameCallback);

#define LIBINPUT_KEY_STATE_RELEASED 0
#define LIBINPUT_KEY_STATE_PRESSED 1
#define LIBINPUT_BUTTON_STATE_RELEASED 0
#define LIBINPUT_BUTTON_STATE_PRESSED 1

#define MAX_CLIENTS 4
#define MAX_HID_USAGE 0x100

static volatile bool g_running = true;
static mach_port_t   g_server_port = MACH_PORT_NULL;
static mach_port_t   g_clients[MAX_CLIENTS];
static int           g_num_clients;
static pthread_mutex_t g_client_lock = PTHREAD_MUTEX_INITIALIZER;

static void handle_signal(int sig)
{
    (void)sig;
    g_running = false;
}

static IOHIDEventSystemRef g_hid_system;

/* multitouch state */
static MTDeviceRef g_mt_device;
static int g_mt_finger_id = -1;
static float g_mt_prev_x, g_mt_prev_y;
static bool g_mt_touching;

static pthread_t g_mach_thread;
static pthread_t g_hid_thread;

enum {
    KEY_RESERVED   = 0,   KEY_ESC       = 1,   KEY_1         = 2,
    KEY_2         = 3,   KEY_3         = 4,   KEY_4         = 5,
    KEY_5         = 6,   KEY_6         = 7,   KEY_7         = 8,
    KEY_8         = 9,   KEY_9         = 10,  KEY_0         = 11,
    KEY_MINUS     = 12,  KEY_EQUAL     = 13,  KEY_BACKSPACE = 14,
    KEY_TAB       = 15,  KEY_Q         = 16,  KEY_W         = 17,
    KEY_E         = 18,  KEY_R         = 19,  KEY_T         = 20,
    KEY_Y         = 21,  KEY_U         = 22,  KEY_I         = 23,
    KEY_O         = 24,  KEY_P         = 25,  KEY_LEFTBRACE = 26,
    KEY_RIGHTBRACE= 27,  KEY_ENTER     = 28,  KEY_LEFTCTRL  = 29,
    KEY_A         = 30,  KEY_S         = 31,  KEY_D         = 32,
    KEY_F         = 33,  KEY_G         = 34,  KEY_H         = 35,
    KEY_J         = 36,  KEY_K         = 37,  KEY_L         = 38,
    KEY_SEMICOLON = 39,  KEY_APOSTROPHE= 40,  KEY_GRAVE     = 41,
    KEY_LEFTSHIFT = 42,  KEY_BACKSLASH = 43,  KEY_Z         = 44,
    KEY_X         = 45,  KEY_C         = 46,  KEY_V         = 47,
    KEY_B         = 48,  KEY_N         = 49,  KEY_M         = 50,
    KEY_COMMA     = 51,  KEY_DOT       = 52,  KEY_SLASH     = 53,
    KEY_RIGHTSHIFT= 54,  KEY_KPASTERISK= 55,  KEY_LEFTALT   = 56,
    KEY_SPACE     = 57,  KEY_CAPSLOCK  = 58,
    KEY_F1        = 59,  KEY_F2        = 60,  KEY_F3        = 61,
    KEY_F4        = 62,  KEY_F5        = 63,  KEY_F6        = 64,
    KEY_F7        = 65,  KEY_F8        = 66,  KEY_F9        = 67,
    KEY_F10       = 68,  KEY_NUMLOCK   = 69,  KEY_SCROLLLOCK= 70,
    KEY_KP7       = 71,  KEY_KP8       = 72,  KEY_KP9       = 73,
    KEY_KPMINUS   = 74,  KEY_KP4       = 75,  KEY_KP5       = 76,
    KEY_KP6       = 77,  KEY_KPPLUS    = 78,  KEY_KP1       = 79,
    KEY_KP2       = 80,  KEY_KP3       = 81,  KEY_KP0       = 82,
    KEY_KPDOT     = 83,  KEY_102ND     = 86,
    KEY_F11       = 87,  KEY_F12       = 88,
    KEY_KPENTER   = 96,  KEY_RIGHTCTRL = 97,  KEY_KPSLASH   = 98,
    KEY_SYSRQ     = 99,  KEY_RIGHTALT  = 100, KEY_LINEFEED  = 101,
    KEY_HOME      = 102, KEY_UP        = 103, KEY_PAGEUP    = 104,
    KEY_LEFT      = 105, KEY_RIGHT     = 106, KEY_END       = 107,
    KEY_DOWN      = 108, KEY_PAGEDOWN  = 109, KEY_INSERT    = 110,
    KEY_DELETE    = 111, KEY_MUTE      = 113,
    KEY_VOLUMEUP  = 115, KEY_VOLUMEDOWN= 114,
    KEY_POWER     = 116, KEY_KPEQUAL   = 117,
    KEY_PAUSE     = 119, KEY_KPCOMMA   = 121,
    KEY_LEFTMETA  = 125, KEY_RIGHTMETA = 126, KEY_COMPOSE   = 127,
    KEY_STOP      = 128, KEY_AGAIN     = 129, KEY_PROPS     = 130,
    KEY_UNDO      = 131, KEY_FRONT     = 132, KEY_COPY      = 133,
    KEY_OPEN      = 134, KEY_PASTE     = 135, KEY_FIND      = 136,
    KEY_CUT       = 137, KEY_HELP      = 138, KEY_MENU      = 139,
    KEY_CALC      = 140, KEY_SELECT    = 141, KEY_SLEEP     = 142,
    KEY_BOOKMARKS = 156, KEY_BACK      = 158, KEY_FORWARD   = 159,
    KEY_REFRESH   = 173,
    KEY_SEARCH    = 217,
    KEY_BRIGHTNESSDOWN = 224, KEY_BRIGHTNESSUP = 225,
    KEY_F13       = 183, KEY_F14       = 184, KEY_F15       = 185,
    KEY_F16       = 186, KEY_F17       = 187, KEY_F18       = 188,
    KEY_F19       = 189, KEY_F20       = 190, KEY_F21       = 191,
    KEY_F22       = 192, KEY_F23       = 193, KEY_F24       = 194,
    BTN_MISC      = 0x100, BTN_0      = 0x100,
    BTN_1         = 0x101, BTN_2      = 0x102,
    BTN_LEFT      = 0x110, BTN_RIGHT  = 0x111,
    BTN_MIDDLE    = 0x112, BTN_SIDE   = 0x113,
    BTN_EXTRA     = 0x114, BTN_FORWARD= 0x115,
    BTN_BACK      = 0x116, BTN_TASK   = 0x117,
    BTN_TOUCH     = 0x14a,
};

static const uint16_t hid_to_evdev[MAX_HID_USAGE] = {
    [0x00] = KEY_RESERVED,    [0x01] = KEY_RESERVED,
    [0x02] = KEY_RESERVED,    [0x03] = KEY_RESERVED,
    [0x04] = KEY_A,           [0x05] = KEY_B,
    [0x06] = KEY_C,           [0x07] = KEY_D,
    [0x08] = KEY_E,           [0x09] = KEY_F,
    [0x0A] = KEY_G,           [0x0B] = KEY_H,
    [0x0C] = KEY_I,           [0x0D] = KEY_J,
    [0x0E] = KEY_K,           [0x0F] = KEY_L,
    [0x10] = KEY_M,           [0x11] = KEY_N,
    [0x12] = KEY_O,           [0x13] = KEY_P,
    [0x14] = KEY_Q,           [0x15] = KEY_R,
    [0x16] = KEY_S,           [0x17] = KEY_T,
    [0x18] = KEY_U,           [0x19] = KEY_V,
    [0x1A] = KEY_W,           [0x1B] = KEY_X,
    [0x1C] = KEY_Y,           [0x1D] = KEY_Z,
    [0x1E] = KEY_1,           [0x1F] = KEY_2,
    [0x20] = KEY_3,           [0x21] = KEY_4,
    [0x22] = KEY_5,           [0x23] = KEY_6,
    [0x24] = KEY_7,           [0x25] = KEY_8,
    [0x26] = KEY_9,           [0x27] = KEY_0,
    [0x28] = KEY_ENTER,       [0x29] = KEY_ESC,
    [0x2A] = KEY_BACKSPACE,   [0x2B] = KEY_TAB,
    [0x2C] = KEY_SPACE,       [0x2D] = KEY_MINUS,
    [0x2E] = KEY_EQUAL,       [0x2F] = KEY_LEFTBRACE,
    [0x30] = KEY_RIGHTBRACE,  [0x31] = KEY_BACKSLASH,
    [0x32] = KEY_BACKSLASH,   [0x33] = KEY_SEMICOLON,
    [0x34] = KEY_APOSTROPHE,  [0x35] = KEY_GRAVE,
    [0x36] = KEY_COMMA,       [0x37] = KEY_DOT,
    [0x38] = KEY_SLASH,       [0x39] = KEY_CAPSLOCK,
    [0x3A] = KEY_F1,          [0x3B] = KEY_F2,
    [0x3C] = KEY_F3,          [0x3D] = KEY_F4,
    [0x3E] = KEY_F5,          [0x3F] = KEY_F6,
    [0x40] = KEY_F7,          [0x41] = KEY_F8,
    [0x42] = KEY_F9,          [0x43] = KEY_F10,
    [0x44] = KEY_F11,         [0x45] = KEY_F12,
    [0x46] = KEY_SYSRQ,       [0x47] = KEY_SCROLLLOCK,
    [0x48] = KEY_PAUSE,       [0x49] = KEY_INSERT,
    [0x4A] = KEY_HOME,        [0x4B] = KEY_PAGEUP,
    [0x4C] = KEY_DELETE,      [0x4D] = KEY_END,
    [0x4E] = KEY_PAGEDOWN,    [0x4F] = KEY_RIGHT,
    [0x50] = KEY_LEFT,        [0x51] = KEY_DOWN,
    [0x52] = KEY_UP,          [0x53] = KEY_NUMLOCK,
    [0x54] = KEY_KPSLASH,     [0x55] = KEY_KPASTERISK,
    [0x56] = KEY_KPMINUS,     [0x57] = KEY_KPPLUS,
    [0x58] = KEY_KPENTER,     [0x59] = KEY_KP1,
    [0x5A] = KEY_KP2,         [0x5B] = KEY_KP3,
    [0x5C] = KEY_KP4,         [0x5D] = KEY_KP5,
    [0x5E] = KEY_KP6,         [0x5F] = KEY_KP7,
    [0x60] = KEY_KP8,         [0x61] = KEY_KP9,
    [0x62] = KEY_KP0,         [0x63] = KEY_KPDOT,
    [0x64] = KEY_102ND,       [0x65] = KEY_COMPOSE,
    [0x66] = KEY_POWER,       [0x67] = KEY_KPEQUAL,
    [0x68] = KEY_F13,         [0x69] = KEY_F14,
    [0x6A] = KEY_F15,         [0x6B] = KEY_F16,
    [0x6C] = KEY_F17,         [0x6D] = KEY_F18,
    [0x6E] = KEY_F19,         [0x6F] = KEY_F20,
    [0x70] = KEY_F21,         [0x71] = KEY_F22,
    [0x72] = KEY_F23,         [0x73] = KEY_F24,
    [0x74] = KEY_OPEN,        [0x75] = KEY_HELP,
    [0x76] = KEY_MENU,        [0x77] = KEY_SELECT,
    [0xE0] = KEY_LEFTCTRL,    [0xE1] = KEY_LEFTSHIFT,
    [0xE2] = KEY_LEFTALT,     [0xE3] = KEY_LEFTMETA,
    [0xE4] = KEY_RIGHTCTRL,   [0xE5] = KEY_RIGHTSHIFT,
    [0xE6] = KEY_RIGHTALT,    [0xE7] = KEY_RIGHTMETA,
};

static int hid_usage_to_evdev(uint32_t usage_page, uint32_t usage)
{
    if (usage_page == 0x07 && usage < MAX_HID_USAGE)
        return hid_to_evdev[usage];
    if (usage_page == 0x09 && usage >= 1 && usage <= 32)
        return BTN_LEFT + (int)(usage - 1);
    return 0;
}

static uint64_t now_usec(void)
{
    static mach_timebase_info_data_t tb = {0};
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t now = mach_absolute_time();
    return (now * tb.numer) / (tb.denom * 1000);
}

static int send_event(input_ipc_event_t *msg)
{
    pthread_mutex_lock(&g_client_lock);
    int count = g_num_clients;
    for (int i = 0; i < count; i++) {
        msg->header.msgh_remote_port = g_clients[i];
        kern_return_t kr = mach_msg(&msg->header, MACH_SEND_MSG,
                                     sizeof(*msg), 0, MACH_PORT_NULL,
                                     MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "[inputd] send to client %d: %s\n", i,
                    mach_error_string(kr));
        }
    }
    pthread_mutex_unlock(&g_client_lock);
    return 0;
}

static void send_device_added(int id, int caps, const char *name)
{
    input_ipc_event_t msg = {0};
    msg.header.msgh_bits      = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id         = INPUT_IPC_EVENT_ID;
    msg.header.msgh_size       = sizeof(msg);
    msg.body.msgh_descriptor_count = 0;
    msg.event_type   = INPUT_IPC_EVENT_DEVICE_ADDED;
    msg.device_id    = id;
    msg.device_caps  = caps;
    msg.time_usec    = now_usec();
    strncpy(msg.device_name, name, sizeof(msg.device_name) - 1);
    send_event(&msg);
}

static void send_device_removed(int id)
{
    input_ipc_event_t msg = {0};
    msg.header.msgh_bits      = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id         = INPUT_IPC_EVENT_ID;
    msg.header.msgh_size       = sizeof(msg);
    msg.body.msgh_descriptor_count = 0;
    msg.event_type   = INPUT_IPC_EVENT_DEVICE_REMOVED;
    msg.device_id    = id;
    send_event(&msg);
}

static void send_key_event(uint64_t time, int key, int pressed)
{
    input_ipc_event_t msg = {0};
    msg.header.msgh_bits      = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id         = INPUT_IPC_EVENT_ID;
    msg.header.msgh_size       = sizeof(msg);
    msg.body.msgh_descriptor_count = 0;
    msg.event_type   = INPUT_IPC_EVENT_KEYBOARD_KEY;
    msg.device_id    = 0;
    msg.time_usec    = time;
    msg.key          = key;
    msg.key_state    = pressed ? LIBINPUT_KEY_STATE_PRESSED
                               : LIBINPUT_KEY_STATE_RELEASED;
    send_event(&msg);
}

static void send_motion_event(uint64_t time, double dx, double dy)
{
    input_ipc_event_t msg = {0};
    msg.header.msgh_bits      = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id         = INPUT_IPC_EVENT_ID;
    msg.header.msgh_size       = sizeof(msg);
    msg.body.msgh_descriptor_count = 0;
    msg.event_type   = INPUT_IPC_EVENT_POINTER_MOTION;
    msg.device_id    = 1;
    msg.time_usec    = time;
    msg.pointer_dx   = dx;
    msg.pointer_dy   = dy;
    send_event(&msg);
}

static void send_button_event(uint64_t time, int btn, int pressed)
{
    input_ipc_event_t msg = {0};
    msg.header.msgh_bits      = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id         = INPUT_IPC_EVENT_ID;
    msg.header.msgh_size       = sizeof(msg);
    msg.body.msgh_descriptor_count = 0;
    msg.event_type   = INPUT_IPC_EVENT_POINTER_BUTTON;
    msg.device_id    = 1;
    msg.time_usec    = time;
    msg.pointer_button = btn;
    msg.pointer_button_state = pressed ? LIBINPUT_BUTTON_STATE_PRESSED
                                        : LIBINPUT_BUTTON_STATE_RELEASED;
    send_event(&msg);
}

static void send_scroll_event(uint64_t time, int axis, double value)
{
    input_ipc_event_t msg = {0};
    msg.header.msgh_bits      = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id         = INPUT_IPC_EVENT_ID;
    msg.header.msgh_size       = sizeof(msg);
    msg.body.msgh_descriptor_count = 0;
    msg.event_type   = INPUT_IPC_EVENT_POINTER_AXIS;
    msg.device_id    = 1;
    msg.time_usec    = time;
    msg.pointer_axis = axis;
    msg.pointer_axis_value = value;
    send_event(&msg);
}

static pthread_mutex_t g_accel_lock = PTHREAD_MUTEX_INITIALIZER;
static double g_accel_dx, g_accel_dy;

static void flush_motion(void)
{
    pthread_mutex_lock(&g_accel_lock);
    double dx = g_accel_dx;
    double dy = g_accel_dy;
    g_accel_dx = g_accel_dy = 0.0;
    pthread_mutex_unlock(&g_accel_lock);

    if (dx != 0.0 || dy != 0.0)
        send_motion_event(now_usec(), dx, dy);
}

static void accum_motion(double dx, double dy)
{
    pthread_mutex_lock(&g_accel_lock);
    g_accel_dx += dx;
    g_accel_dy += dy;
    pthread_mutex_unlock(&g_accel_lock);
}

static float mt_sensitivity = 1800.0f;

static void mt_contact_frame(MTDeviceRef device, MTTouch touches[],
                              int numTouches, double timestamp, int frame)
{
    (void)device;(void)timestamp;(void)frame;
    for (int i = 0; i < numTouches; i++) {
        MTTouch *t = &touches[i];
        if (t->state == MTTouchStateMakeTouch ||
            t->state == MTTouchStateTouching) {
            float nx = t->normalizedPosition.position.x;
            float ny = t->normalizedPosition.position.y;
            if (g_mt_touching) {
                float dx = (nx - g_mt_prev_x) * mt_sensitivity;
                float dy = (g_mt_prev_y - ny) * mt_sensitivity;
                if (dx != 0.0f || dy != 0.0f)
                    accum_motion((double)dx, (double)dy);
            }
            g_mt_prev_x = nx;
            g_mt_prev_y = ny;
            g_mt_touching = true;
            return;
        }
    }
    g_mt_touching = false;
}

static void motion_timer_cb(CFRunLoopTimerRef timer, void *info)
{
    (void)timer;(void)info;
    if (!g_running) {
        CFRunLoopStop(CFRunLoopGetCurrent());
        return;
    }
    flush_motion();
}

/* IOHIDEvent callback — matches CGXHIDEventCallback signature from WSInitialize.
 * IOHIDEventSystemOpen(system, iohid_event_callback, NULL, NULL, NULL) */
static void iohid_event_callback(void *target, void *sender,
                                  void *notification, IOHIDEventRef event)
{
    (void)target; (void)sender; (void)notification;

    if (!event) return;

    uint32_t type = IOHIDEventGetType(event);
    uint64_t ts   = IOHIDEventGetTimeStamp(event);

    /* Use IOHIDEventConformsTo like EventTranslator does — events may be
     * VendorDefined (type 1) but still conform to keyboard (3) or button (2). */
    int conforms_kb  = IOHIDEventConformsTo(event, kIOHIDEventTypeKeyboard);
    int conforms_btn = IOHIDEventConformsTo(event, kIOHIDEventTypeButton);

    fprintf(stderr, "[inputd] IOHIDEvent type=%u (%s) conforms_kb=%d conforms_btn=%d ts=%llu\n",
            type, iohid_event_type_name(type), conforms_kb, conforms_btn, ts);

    /* Keyboard — check conforms first (covers VendorDefined wrapping keyboard) */
    if (conforms_kb) {
        int32_t usagePage = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardUsagePage);
        int32_t usage     = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardUsage);
        int32_t down      = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardDown);
        int pressed = (down != 0) ? 1 : 0;
        int evdev = hid_usage_to_evdev((uint32_t)usagePage, (uint32_t)usage);
        if (evdev > 0) {
            fprintf(stderr, "[inputd]   Keyboard: page=0x%x usage=0x%x evdev=%d down=%d pressed=%d\n",
                    usagePage, usage, evdev, (int)down, pressed);
            send_key_event(ts, evdev, pressed);
        }
        return;
    }

    /* Button — check conforms first */
    if (conforms_btn) {
        int32_t mask   = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldButtonMask);
        int32_t number = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldButtonNumber);
        int32_t clicks = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldButtonClickCount);
        int32_t state  = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldButtonState);
        fprintf(stderr, "[inputd]   Button: mask=0x%x number=%d clicks=%d state=%d\n",
                mask, number, clicks, state);

        int btn = BTN_LEFT + (number - 1);
        int pressed = (mask != 0) ? 1 : 0;
        send_button_event(ts, btn, pressed);
        return;
    }

    /* Process children — Digitizer events contain Button children for click */
    CFArrayRef children = IOHIDEventGetChildren(event);
    if (children) {
        CFIndex count = CFArrayGetCount(children);
        for (CFIndex i = 0; i < count; i++) {
            IOHIDEventRef child = (IOHIDEventRef)CFArrayGetValueAtIndex(children, i);
            uint32_t ctype = IOHIDEventGetType(child);

            if (IOHIDEventConformsTo(child, kIOHIDEventTypeButton)) {
                int32_t number = IOHIDEventGetIntegerValue(child, kIOHIDEventFieldButtonNumber);
                int32_t mask   = IOHIDEventGetIntegerValue(child, kIOHIDEventFieldButtonMask);
                int32_t clicks = IOHIDEventGetIntegerValue(child, kIOHIDEventFieldButtonClickCount);
                int32_t state  = IOHIDEventGetIntegerValue(child, kIOHIDEventFieldButtonState);
                fprintf(stderr, "[inputd]   Child Button: number=%d mask=0x%x clicks=%d state=%d\n", number, mask, clicks, state);
                int btn = BTN_LEFT + (number - 1);
                int pressed = (mask != 0) ? 1 : 0;
                send_button_event(ts, btn, pressed);
            } else if (ctype == kIOHIDEventTypeTranslation) {
                float dx = IOHIDEventGetFloatValue(child, kIOHIDEventFieldTranslationX);
                float dy = IOHIDEventGetFloatValue(child, kIOHIDEventFieldTranslationY);
                fprintf(stderr, "[inputd]   Child Translation: dx=%.2f dy=%.2f\n", dx, dy);
                if (dx != 0.0f || dy != 0.0f)
                    accum_motion((double)dx, (double)dy);
            } else if (ctype == kIOHIDEventTypeScroll) {
                float sy = IOHIDEventGetFloatValue(child, kIOHIDEventFieldScrollY);
                float sx = IOHIDEventGetFloatValue(child, kIOHIDEventFieldScrollX);
                fprintf(stderr, "[inputd]   Child Scroll: sx=%.2f sy=%.2f\n", sx, sy);
                if (sy != 0.0f) send_scroll_event(ts, 0, (double)sy);
                if (sx != 0.0f) send_scroll_event(ts, 1, (double)sx);
            }
        }
    }

    /* Also handle top-level types that aren't keyboard/button */
    switch (type) {
    case kIOHIDEventTypeTranslation: {
        float dx = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTranslationX);
        float dy = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTranslationY);
        fprintf(stderr, "[inputd]   Translation: dx=%.2f dy=%.2f\n", dx, dy);
        if (dx != 0.0f || dy != 0.0f)
            accum_motion((double)dx, (double)dy);
        break;
    }
    case kIOHIDEventTypeScroll: {
        float sx = IOHIDEventGetFloatValue(event, kIOHIDEventFieldScrollX);
        float sy = IOHIDEventGetFloatValue(event, kIOHIDEventFieldScrollY);
        fprintf(stderr, "[inputd]   Scroll: sx=%.2f sy=%.2f\n", sx, sy);
        if (sy != 0.0f) send_scroll_event(ts, 0, (double)sy);
        if (sx != 0.0f) send_scroll_event(ts, 1, (double)sx);
        break;
    }
    case kIOHIDEventTypeMouse: {
        float mx = IOHIDEventGetFloatValue(event, kIOHIDEventFieldMouseX);
        float my = IOHIDEventGetFloatValue(event, kIOHIDEventFieldMouseY);
        fprintf(stderr, "[inputd]   Mouse: x=%.2f y=%.2f\n", mx, my);
        if (mx != 0.0f || my != 0.0f)
            accum_motion((double)mx, (double)my);
        break;
    }
    case kIOHIDEventTypeDigitizer: {
        float tx = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerX);
        float ty = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerY);
        int32_t touch = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerTouch);
        fprintf(stderr, "[inputd]   Digitizer: x=%.4f y=%.4f touch=%d\n",
                tx, ty, touch);
        break;
    }
    default:
        break;
    }
}

static void *hid_thread(void *arg)
{
    (void)arg;

    g_hid_system = IOHIDEventSystemCreate(kCFAllocatorDefault);
    if (!g_hid_system) {
        fprintf(stderr, "[inputd] IOHIDEventSystemCreate failed\n");
        return NULL;
    }

    int ret = IOHIDEventSystemOpen(g_hid_system, iohid_event_callback,
                                    NULL, NULL, NULL);
    if (!ret) {
        fprintf(stderr, "[inputd] IOHIDEventSystemOpen failed\n");
        CFRelease(g_hid_system);
        g_hid_system = NULL;
        return NULL;
    }

    fprintf(stderr, "[inputd] IOHIDEventSystem capture started\n");

    if (MTDeviceIsAvailable()) {
        g_mt_device = MTDeviceCreateDefault();
        if (g_mt_device) {
            MTRegisterContactFrameCallback(g_mt_device, mt_contact_frame);
            MTDeviceStart(g_mt_device, 0);
            fprintf(stderr, "[inputd] multitouch started\n");
        } else {
            fprintf(stderr, "[inputd] MTDeviceCreateDefault failed\n");
        }
    } else {
        fprintf(stderr, "[inputd] multitouch not available\n");
    }

    CFRunLoopTimerRef mtimer = CFRunLoopTimerCreate(
        kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(),
        1.0 / 250.0, 0, 0, motion_timer_cb, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), mtimer, kCFRunLoopCommonModes);

    CFRunLoopRun();

    CFRelease(mtimer);
    if (g_mt_device) {
        MTDeviceStop(g_mt_device);
        MTDeviceRelease(g_mt_device);
        g_mt_device = NULL;
    }
    IOHIDEventSystemClose(g_hid_system, NULL);
    CFRelease(g_hid_system);
    g_hid_system = NULL;
    return NULL;
}

static void mach_server_thread(void)
{
    while (g_running) {
        union {
            input_ipc_subscribe_t subscribe;
            uint8_t padding[sizeof(input_ipc_subscribe_t) + 64];
        } buf = {0};
        input_ipc_subscribe_t *msg = &buf.subscribe;
        msg->header.msgh_size       = sizeof(buf);
        msg->header.msgh_local_port = g_server_port;

        kern_return_t kr = mach_msg(&msg->header,
                                     MACH_RCV_MSG | MACH_RCV_TIMEOUT,
                                     0, sizeof(buf),
                                     g_server_port, 500,
                                     MACH_PORT_NULL);
        if (kr == MACH_RCV_TIMED_OUT) {
            continue;
        }
        if (kr != KERN_SUCCESS) {
            if (g_running)
                fprintf(stderr, "[inputd] mach_msg recv: %s\n",
                        mach_error_string(kr));
            continue;
        }

        if (msg->header.msgh_id != INPUT_IPC_SUBSCRIBE_ID)
            continue;

        if (msg->body.msgh_descriptor_count >= 1 &&
            msg->client_port.type == MACH_MSG_PORT_DESCRIPTOR &&
            msg->client_port.name != MACH_PORT_NULL)
        {
            mach_port_t client_port = msg->client_port.name;

            fprintf(stderr, "[inputd] client subscribed, port=%d\n",
                    client_port);

            pthread_mutex_lock(&g_client_lock);
            if (g_num_clients < MAX_CLIENTS)
                g_clients[g_num_clients++] = client_port;
            pthread_mutex_unlock(&g_client_lock);

            send_device_added(0, INPUT_IPC_CAP_KEYBOARD, "macOS Keyboard");
            send_device_added(1, INPUT_IPC_CAP_POINTER,  "macOS Pointer");

            {
                input_ipc_event_t m = {0};
                m.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
                m.header.msgh_remote_port = client_port;
                m.header.msgh_id          = INPUT_IPC_EVENT_ID;
                m.header.msgh_size        = sizeof(m);
                m.event_type              = INPUT_IPC_EVENT_POINTER_MOTION;
                m.device_id               = 1;
                m.pointer_dx              = 0.0;
                m.pointer_dy              = 0.0;
                m.time_usec               = now_usec();
                kern_return_t kr = mach_msg(&m.header, MACH_SEND_MSG,
                                             sizeof(m), 0, MACH_PORT_NULL,
                                             MACH_MSG_TIMEOUT_NONE,
                                             MACH_PORT_NULL);
                if (kr != KERN_SUCCESS)
                    fprintf(stderr, "[inputd] send motion: %s\n",
                            mach_error_string(kr));
            }
        } else {
            fprintf(stderr, "[inputd] subscribe missing port descriptor\n");
        }
    }
}

int main(void)
{
    signal(SIGINT,  handle_signal);
    signal(SIGTERM, handle_signal);

    kern_return_t kr = mach_port_allocate(mach_task_self(),
                                           MACH_PORT_RIGHT_RECEIVE,
                                           &g_server_port);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[inputd] mach_port_allocate: %s\n",
                mach_error_string(kr));
        return 1;
    }

    kr = mach_port_insert_right(mach_task_self(), g_server_port,
                                 g_server_port, MACH_MSG_TYPE_MAKE_SEND);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[inputd] mach_port_insert_right: %s\n",
                mach_error_string(kr));
        return 1;
    }

    kr = bootstrap_register(bootstrap_port, INPUT_IPC_SERVICE_NAME,
                             g_server_port);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[inputd] bootstrap_register %s: %s\n",
                INPUT_IPC_SERVICE_NAME, mach_error_string(kr));
        return 1;
    }

    fprintf(stderr, "[inputd] listening on %s\n", INPUT_IPC_SERVICE_NAME);

    pthread_create(&g_hid_thread, NULL, hid_thread, NULL);
    pthread_detach(g_hid_thread);

    mach_server_thread();

    send_device_removed(0);
    send_device_removed(1);

    fprintf(stderr, "[inputd] shutting down\n");
    return 0;
}
