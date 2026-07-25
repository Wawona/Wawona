/*
 * anowaw.h — C ABI for the anowaW bridge (github.com/Wawona/wwn-anowaW).
 *
 * anowaW renders a native macOS (Cocoa/AppKit) or Android app as a Wayland
 * client inside Wawona's nested-Weston desktop. This header is consumed by the
 * Wawona app's ObjC runner (WWNAnowaWRunner) and Android JNI bridge.
 *
 * Threading: every call for a given AnowawBridge* MUST occur on the same thread
 * that created it. The bridge is not internally synchronized.
 *
 * Return codes: 0 = success; small negative values = error. Constructors
 * return NULL on failure.
 */
#ifndef ANOWAW_H
#define ANOWAW_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void AnowawBridge;

/* Pixel format discriminants (mirror Rust `PixelFormat`). */
typedef enum {
    ANOWAW_FORMAT_BGRA8888 = 0,
    ANOWAW_FORMAT_BGRX8888 = 1,
    ANOWAW_FORMAT_RGBA8888 = 2,
    ANOWAW_FORMAT_RGBX8888 = 3,
} AnowawPixelFormat;

/* Input event kinds (mirror Rust `InputKind`). */
typedef enum {
    ANOWAW_INPUT_POINTER_MOTION = 0,
    ANOWAW_INPUT_POINTER_BUTTON = 1,
    ANOWAW_INPUT_POINTER_AXIS   = 2,
    ANOWAW_INPUT_KEY            = 3,
    ANOWAW_INPUT_TOUCH          = 4,
    ANOWAW_INPUT_MODIFIERS      = 5,
    ANOWAW_INPUT_POINTER_FOCUS  = 6,
} AnowawInputKind;

/* Flat input event, memcpy-safe across the ABI (mirrors Rust `InputEvent`). */
typedef struct {
    uint64_t handle;   /* target bridged app */
    uint32_t kind;     /* AnowawInputKind */
    uint32_t code;     /* evdev KEY_/BTN_* code, touch id, or modifier mask */
    int32_t  value;    /* press/release/phase/enter-leave value */
    double   x;        /* surface-local X or horizontal axis delta */
    double   y;        /* surface-local Y or vertical axis delta */
    uint32_t time_ms;  /* compositor timestamp */
    uint32_t _reserved;
} AnowawInputEvent;

/* ABI version implemented by the linked bridge. */
uint32_t anowaw_abi_version(void);

/* Connect to the nested Weston compositor on `socket_name`
 * (e.g. "wayland-1"; "" = ambient WAYLAND_DISPLAY). NULL on failure. */
AnowawBridge *anowaw_start(const char *socket_name);

/* Register a host app + create its Wayland toplevel. Returns nonzero handle,
 * or 0 on failure. */
uint64_t anowaw_bridge_app(AnowawBridge *bridge, const char *app_id,
                           const char *title, uint32_t width, uint32_t height);

/* Upload one captured frame (`len` bytes, laid out as stride*height). */
int anowaw_push_frame(AnowawBridge *bridge, uint64_t handle, const uint8_t *data,
                      size_t len, uint32_t width, uint32_t height,
                      uint32_t stride, uint32_t format /* AnowawPixelFormat */);

/* Drain up to `cap` decoded input events. Returns count written or <0 error. */
int anowaw_poll_input(AnowawBridge *bridge, AnowawInputEvent *out, size_t cap);

/* 1 if the compositor asked to close this app's toplevel, else 0. */
int anowaw_close_requested(AnowawBridge *bridge, uint64_t handle);

/* Destroy a bridged app's Wayland objects. */
void anowaw_close_app(AnowawBridge *bridge, uint64_t handle);

/* Pump the Wayland event queue once (non-blocking). */
int anowaw_dispatch(AnowawBridge *bridge);

/* Disconnect and free the bridge; pointer invalid afterwards. */
void anowaw_stop(AnowawBridge *bridge);

#ifdef __cplusplus
}
#endif

#endif /* ANOWAW_H */
