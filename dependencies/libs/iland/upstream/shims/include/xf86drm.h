#ifndef XF86DRM_H
#define XF86DRM_H

#include <stdint.h>
#include <stddef.h>
#include <errno.h>
#include <drm.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned int  drm_handle_t;
typedef unsigned int  drm_context_t;
typedef unsigned int  drm_drawable_t;
typedef unsigned long drm_magic_t;

#define DRM_MAX_MINOR   16
#define DRM_NR_MINORS   128

#define DRM_CLOEXEC  0x80000000
#define DRM_RDWR     0x40000000

int drmOpen(const char *name, const char *busid);
int drmOpenWithType(const char *name, const char *busid, int type);
int drmClose(int fd);

int drmGetCap(int fd, uint64_t capability, uint64_t *value);
int drmSetMaster(int fd);
int drmDropMaster(int fd);
int drmGetMagic(int fd, drm_magic_t *magic);
int drmAuthMagic(int fd, drm_magic_t magic);

int drmIoctl(int fd, unsigned long request, void *arg);

int drmPrimeHandleToFD(int fd, uint32_t handle, uint32_t flags, int *prime_fd);
int drmCloseBufferHandle(int fd, int handle);
int drmPrimeFDToHandle(int fd, int prime_fd, uint32_t *handle);

int drmSetClientCap(int fd, uint64_t capability, uint64_t value);

#define DRM_CAP_DUMB_BUFFER          0x1
#define DRM_CAP_VBLANK_HIGH_CRTC     0x2
#define DRM_CAP_DUMB_PREFERRED_DEPTH 0x3
#define DRM_CAP_DUMB_PREFER_SHADOW   0x4
#define DRM_CAP_PRIME                0x5
#define DRM_CAP_TIMESTAMP_MONOTONIC  0x6
#define DRM_CAP_ASYNC_PAGE_FLIP      0x7
#define DRM_CAP_CURSOR_WIDTH         0x8
#define DRM_CAP_CURSOR_HEIGHT        0x9
#define DRM_CAP_ADDFB2_MODIFIERS     0x10
#define DRM_CAP_PAGE_FLIP_TARGET     0x11
#define DRM_CAP_CRTC_IN_VBLANK_EVENT 0x12
#define DRM_CAP_SYNCOBJ             0x13

const char *drmGetFormatModifierName(uint64_t modifier);
const char *drmGetFormatModifierVendor(uint64_t modifier);

#define DRM_CLIENT_CAP_STEREO_3D         1
#define DRM_CLIENT_CAP_UNIVERSAL_PLANES  2
#define DRM_CLIENT_CAP_ATOMIC            3
#define DRM_CLIENT_CAP_ASPECT_RATIO      4
#define DRM_CLIENT_CAP_WRITEBACK_CONNECTORS 5

#define DRM_VBLANK_HIGH_CRTC_SHIFT 1
#define DRM_VBLANK_HIGH_CRTC_MASK  0x0000003E
#define DRM_VBLANK_SECONDARY       0x00000001
#define DRM_VBLANK_RELATIVE        0x00000001

typedef struct drmVBlankReq {
    uint32_t type;
    uint32_t sequence;
    uint64_t signal;
} drmVBlankReq;

typedef struct drmVBlankReply {
    uint32_t type;
    uint32_t sequence;
    uint32_t tval_sec;
    uint32_t tval_usec;
} drmVBlankReply;

typedef struct drmVBlank {
    drmVBlankReq request;
    drmVBlankReply reply;
} drmVBlank;

int drmWaitVBlank(int fd, drmVBlank *vbl);

/* DRM mode dumb buffer definitions (from kernel drm_mode.h) */
struct drm_mode_create_dumb {
    uint32_t height;
    uint32_t width;
    uint32_t bpp;
    uint32_t flags;
    uint32_t handle;
    uint32_t pitch;
    uint64_t size;
};

struct drm_mode_map_dumb {
    uint32_t handle;
    uint32_t pad;
    uint64_t offset;
};

struct drm_mode_destroy_dumb {
    uint32_t handle;
};

#define DRM_MODE_FB_MODIFIERS (1 << 0)

/* These ioctl numbers must match what drmHandle.c computes via
   _IOWR('d', 0xB2, struct drm_mode_create_dumb) etc. */
#define DRM_IOCTL_MODE_CREATE_DUMB  0xC02064B2
#define DRM_IOCTL_MODE_MAP_DUMB     0xC01064B3
#define DRM_IOCTL_MODE_DESTROY_DUMB 0xC00464B4

#ifdef __cplusplus
}
#endif

#endif /* XF86DRM_H */
