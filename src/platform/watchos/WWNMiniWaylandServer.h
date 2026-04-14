// WWNMiniWaylandServer.h
// Minimal in-process Wayland compositor server for watchOS.
//
// Uses libwayland-server.a (compiled via Nix for watchOS) to host a real
// Wayland protocol server inside the app process.  Wayland clients such as
// weston-simple-shm connect through the Unix-domain socket; when they commit
// an SHM buffer the frame callback fires and the ObjC bridge can render it.
//
// Falls back gracefully (frame callback never fires) when the Wayland server
// headers are absent from a local Xcode build (before Nix deps are built).

#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WWNMiniWaylandServer WWNMiniWaylandServer;

/// Frame-ready callback.  Invoked from the compositor dispatch thread each time
/// a client commits a new SHM buffer.
/// @param pixels   Pointer to the raw pixel data (ARGB8888).
///                 Only valid for the duration of the callback — copy if needed.
/// @param width    Buffer width in pixels.
/// @param height   Buffer height in pixels.
/// @param stride   Row stride in bytes.
/// @param userdata Opaque pointer supplied at creation time.
typedef void (*WWNFrameCallback)(const uint8_t *pixels,
                                 uint32_t width,
                                 uint32_t height,
                                 uint32_t stride,
                                 void *userdata);

/// Create and start a Wayland server that listens on @a socket_name.
/// Sets the WAYLAND_DISPLAY environment variable so clients find the socket.
/// Returns NULL on failure (e.g. libwayland-server not linked).
WWNMiniWaylandServer *wwn_wls_create(const char *socket_name,
                                      uint32_t output_width,
                                      uint32_t output_height,
                                      WWNFrameCallback frame_cb,
                                      void *userdata);

/// Dispatch one round of the Wayland event loop.
/// @param timeout_ms  Poll timeout: 0 = non-blocking, -1 = block indefinitely,
///                    >0 = block up to that many milliseconds.
/// Returns 1 while healthy, 0 if the server has shut down.
int wwn_wls_dispatch(WWNMiniWaylandServer *srv, int timeout_ms);

/// Destroy the server and close the socket.
void wwn_wls_destroy(WWNMiniWaylandServer *srv);

#ifdef __cplusplus
}
#endif
