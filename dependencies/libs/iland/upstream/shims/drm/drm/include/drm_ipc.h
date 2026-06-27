#ifndef DRM_IPC_H
#define DRM_IPC_H

#include <mach/mach.h>
#include <stdint.h>

#define DRM_IPC_SERVICE_NAME  "com.wayland-mac.framebufferd"
#define DRM_IPC_MSG_ID        0x44524D31   /* 'DRM1' */
#define DRM_IPC_JSON_MAX      4096

/* Message format for IPC with framebufferd.
 *
 * When body.msgh_descriptor_count == 1, surface_port carries a send right
 * to an IOSurface mach port (created via IOSurfaceCreateMachPort).
 * The receiver can call IOSurfaceLookupFromMachPort() to obtain the surface.
 *
 * When msgh_descriptor_count == 0, no surface is carried (simple JSON msg).
 */
typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t   body;
    mach_msg_port_descriptor_t surface_port;
    uint32_t          json_len;
    char              json[DRM_IPC_JSON_MAX];
} drm_ipc_msg_t;

#endif /* DRM_IPC_H */
