#ifndef DRM_H
#define DRM_H

#include <mach/mach.h>
#include <stddef.h>

/* Send a JSON string to framebufferd over Mach IPC.
 * Returns 0 on success, -1 on error. */
int drm_send_json(const char *json);

/* Send a JSON string to framebufferd along with an IOSurface mach port.
 * If surface_port is MACH_PORT_NULL, behaves like drm_send_json.
 * The surface_port must be a send right obtained from IOSurfaceCreateMachPort.
 * Ownership: after the call the caller may deallocate surface_port; the
 * IOSurfaceRef itself remains valid in the caller's process. */
int drm_send_json_with_surface(const char *json, mach_port_t surface_port);

#endif
