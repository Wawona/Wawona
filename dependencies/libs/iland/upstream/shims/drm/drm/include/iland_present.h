#ifndef ILAND_PRESENT_H
#define ILAND_PRESENT_H

/*
 * iland Mode A — in-window present hook.
 *
 * By default iland's DRM/KMS shim presents a client's framebuffer by sending the
 * backing IOSurface to the `framebufferd` Mach service (Mode B — bare-metal
 * WindowServer replacement; macOS-only, requires SIP off + root + entitlements).
 *
 * Mode A registers an in-process callback instead: on every page-flip / atomic
 * FB_ID commit the shim invokes the callback directly with the client's
 * IOSurface, and the host compositor (Wawona) imports it into a CAMetalLayer-
 * backed Metal texture for in-window composition.
 *
 * Mode A is App-Store-safe: no Mach IPC to an external daemon, no private SPI,
 * no code injection, no SIP/root. It is the default path on every Apple platform
 * (incl. macOS) once a callback is registered.
 */

#include <stdint.h>
#include <IOSurface/IOSurface.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Present callback. Invoked synchronously from the client's render thread at
 * page-flip / atomic-commit time.
 *
 * `surface` is the IOSurface backing framebuffer `fb_id` on `crtc_id`. iland
 * retains its own reference for the framebuffer's lifetime, so the callback must
 * CFRetain `surface` if it needs to keep it past the call (e.g. for async Metal
 * presentation); otherwise it must not be retained.
 */
typedef void (*iland_present_callback_t)(uint32_t crtc_id,
                                         uint32_t fb_id,
                                         IOSurfaceRef surface,
                                         uint32_t flags,
                                         void *user);

/*
 * Cursor callback. `op` is 0 for a cursor image set (`surface` non-NULL) and 1
 * for a cursor move (`surface` NULL; `x`/`y` are CRTC-relative coordinates).
 */
typedef void (*iland_cursor_callback_t)(int32_t op,
                                        int32_t x,
                                        int32_t y,
                                        IOSurfaceRef surface,
                                        void *user);

/*
 * Register (or, with cb == NULL, clear) the in-window present callback. While a
 * callback is registered the shim uses Mode A and never touches the framebufferd
 * Mach service. Intended to be called once during compositor startup.
 */
void iland_drm_set_present_callback(iland_present_callback_t cb, void *user);

/* Register (or clear) the optional in-window cursor callback. */
void iland_drm_set_cursor_callback(iland_cursor_callback_t cb, void *user);

/* Returns non-zero when an in-window present callback is registered (Mode A). */
int iland_drm_present_is_in_window(void);

#ifdef __cplusplus
}
#endif

#endif /* ILAND_PRESENT_H */
