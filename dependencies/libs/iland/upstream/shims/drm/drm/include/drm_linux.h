/*
 * drm_linux.h — Linux-compatible DRM API shim for macOS.
 *
 * Provides the subset of xf86drm.h / drm_mode.h used by Wayland compositors
 * (wlroots, mutter, etc.).  All functions are implemented as stubs that route
 * through the Mach IPC channel to framebufferd; unsupported ioctls return -1
 * with errno = ENOSYS.
 */

#ifndef DRM_LINUX_H
#define DRM_LINUX_H

#include <stdint.h>
#include <stddef.h>

/* Pipe write end for DRM event signaling.  drmModePageFlip writes a byte
 * here after sending the IPC, making virtual fd 42 readable by select/poll.
 * Initialised by wayland-mac.c before any DRM open.  -1 = not ready.    */
extern int g_drm_event_pipe_write;

#ifdef __cplusplus
extern "C" {
#endif

/* ── basic types ──────────────────────────────────────────────────────── */

typedef unsigned int  drm_handle_t;
typedef unsigned int  drm_context_t;
typedef unsigned int  drm_drawable_t;
typedef unsigned long drm_magic_t;

/* ── connector / encoder / CRTC id types (opaque uint32) ─────────────── */

typedef uint32_t drmModeConnectorID;
typedef uint32_t drmModeEncoderID;
typedef uint32_t drmModeCrtcID;

/* ── mode info ────────────────────────────────────────────────────────── */

typedef struct drmModeModeInfo {
    uint32_t clock;
    uint16_t hdisplay, hsync_start, hsync_end, htotal, hskew;
    uint16_t vdisplay, vsync_start, vsync_end, vtotal, vscan;
    uint32_t vrefresh;
    uint32_t flags;
    uint32_t type;
    char     name[32];
} drmModeModeInfo;

/* ── framebuffer ──────────────────────────────────────────────────────── */

typedef struct drmModeFB {
    uint32_t fb_id;
    uint32_t width, height;
    uint32_t pitch;
    uint32_t bpp;
    uint32_t depth;
    uint32_t handle;
} drmModeFB, *drmModeFBPtr;

/* ── CRTC ─────────────────────────────────────────────────────────────── */

typedef struct drmModeCrtc {
    uint32_t        crtc_id;
    uint32_t        buffer_id;
    uint32_t        x, y;
    uint32_t        width, height;
    int             mode_valid;
    drmModeModeInfo mode;
    int             gamma_size;
} drmModeCrtc, *drmModeCrtcPtr;

/* ── encoder ──────────────────────────────────────────────────────────── */

typedef struct drmModeEncoder {
    uint32_t encoder_id;
    uint32_t encoder_type;
    uint32_t crtc_id;
    uint32_t possible_crtcs;
    uint32_t possible_clones;
} drmModeEncoder, *drmModeEncoderPtr;

/* ── connector ────────────────────────────────────────────────────────── */

#define DRM_MODE_CONNECTED         1
#define DRM_MODE_DISCONNECTED      2
#define DRM_MODE_UNKNOWNCONNECTION 3

#define DRM_MODE_CONNECTOR_Unknown      0
#define DRM_MODE_CONNECTOR_VGA          1
#define DRM_MODE_CONNECTOR_DVII         2
#define DRM_MODE_CONNECTOR_DVID         3
#define DRM_MODE_CONNECTOR_DVIA         4
#define DRM_MODE_CONNECTOR_Composite    5
#define DRM_MODE_CONNECTOR_SVIDEO       6
#define DRM_MODE_CONNECTOR_LVDS         7
#define DRM_MODE_CONNECTOR_Component    8
#define DRM_MODE_CONNECTOR_9PinDIN      9
#define DRM_MODE_CONNECTOR_DisplayPort  10
#define DRM_MODE_CONNECTOR_HDMIA        11
#define DRM_MODE_CONNECTOR_HDMIB        12
#define DRM_MODE_CONNECTOR_TV           13
#define DRM_MODE_CONNECTOR_eDP          14
#define DRM_MODE_CONNECTOR_VIRTUAL      15
#define DRM_MODE_CONNECTOR_DSI          16

typedef struct drmModeConnector {
    uint32_t         connector_id;
    uint32_t         encoder_id;
    uint32_t         connector_type;
    uint32_t         connector_type_id;
    uint32_t         connection;       /* DRM_MODE_CONNECTED etc. */
    uint32_t         mmWidth, mmHeight;
    uint32_t         subpixel;
    int              count_modes;
    drmModeModeInfo *modes;
    int              count_props;
    uint32_t        *props;
    uint64_t        *prop_values;
    int              count_encoders;
    uint32_t        *encoders;
} drmModeConnector, *drmModeConnectorPtr;

/* ── resource set ─────────────────────────────────────────────────────── */

typedef struct drmModeRes {
    int       count_fbs;
    uint32_t *fbs;
    int       count_crtcs;
    uint32_t *crtcs;
    int       count_connectors;
    uint32_t *connectors;
    int       count_encoders;
    uint32_t *encoders;
    uint32_t  min_width,  max_width;
    uint32_t  min_height, max_height;
} drmModeRes, *drmModeResPtr;

/* ── page-flip event ──────────────────────────────────────────────────── */

#define DRM_EVENT_CONTEXT_VERSION 4

typedef struct drmEventContext {
    int version;
    void (*vblank_handler)(int fd,
                           unsigned int sequence,
                           unsigned int tv_sec,
                           unsigned int tv_usec,
                           void *user_data);
    void (*page_flip_handler)(int fd,
                              unsigned int sequence,
                              unsigned int tv_sec,
                              unsigned int tv_usec,
                              void *user_data);
    void (*page_flip_handler2)(int fd,
                               unsigned int sequence,
                               unsigned int tv_sec,
                               unsigned int tv_usec,
                               unsigned int crtc_id,
                               void *user_data);
} drmEventContext, *drmEventContextPtr;

/* ── page-flip flags ──────────────────────────────────────────────────── */

#define DRM_MODE_PAGE_FLIP_EVENT 0x01
#define DRM_MODE_PAGE_FLIP_ASYNC 0x02

/* ── mode type flags ────────────────────────────────────────────────────── */

#define DRM_MODE_TYPE_PREFERRED  0x00000040
#define DRM_MODE_TYPE_DRIVER     0x00000080

/* ── prime ────────────────────────────────────────────────────────────── */

#define DRM_CLOEXEC  0x80000000
#define DRM_RDWR     0x40000000

/* ── open / close ─────────────────────────────────────────────────────── */

int  drmOpen(const char *name, const char *busid);
int  drmOpenWithType(const char *name, const char *busid, int type);
int  drmClose(int fd);

/* ── capability ───────────────────────────────────────────────────────── */

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

int drmGetCap(int fd, uint64_t capability, uint64_t *value);

/* ── mode resources ───────────────────────────────────────────────────── */

drmModeResPtr       drmModeGetResources(int fd);
void                drmModeFreeResources(drmModeResPtr ptr);

drmModeConnectorPtr drmModeGetConnector(int fd, uint32_t connector_id);
void                drmModeFreeConnector(drmModeConnectorPtr ptr);

drmModeEncoderPtr   drmModeGetEncoder(int fd, uint32_t encoder_id);
void                drmModeFreeEncoder(drmModeEncoderPtr ptr);

drmModeCrtcPtr      drmModeGetCrtc(int fd, uint32_t crtc_id);
void                drmModeFreeCrtc(drmModeCrtcPtr ptr);

int drmModeSetCrtc(int fd, uint32_t crtc_id, uint32_t fb_id,
                   uint32_t x, uint32_t y,
                   uint32_t *connectors, int count,
                   drmModeModeInfo *mode);

/* ── framebuffer ──────────────────────────────────────────────────────── */

int drmModeAddFB(int fd, uint32_t width, uint32_t height,
                 uint8_t depth, uint8_t bpp,
                 uint32_t pitch, uint32_t bo_handle,
                 uint32_t *buf_id);

int drmModeAddFB2(int fd, uint32_t width, uint32_t height,
                  uint32_t pixel_format,
                  const uint32_t bo_handles[4],
                  const uint32_t pitches[4],
                  const uint32_t offsets[4],
                  uint32_t *buf_id, uint32_t flags);

int drmModeAddFB2WithModifiers(int fd, uint32_t width, uint32_t height,
                               uint32_t pixel_format,
                               const uint32_t bo_handles[4],
                               const uint32_t pitches[4],
                               const uint32_t offsets[4],
                               uint32_t *buf_id, uint32_t flags);

int drmModeRmFB(int fd, uint32_t buf_id);

/* GBM buffer registration — called by gbm.m so drmModeAddFB can resolve
 * GBM-created buffer handles to IOSurfaces.                          */
void drm_register_gbm_buffer(uint32_t handle, void *surface);
void drm_unregister_gbm_buffer(uint32_t handle);

/* ── page flip ────────────────────────────────────────────────────────── */

int drmModePageFlip(int fd, uint32_t crtc_id, uint32_t fb_id,
                    uint32_t flags, void *user_data);

int drmHandleEvent(int fd, drmEventContextPtr evctx);

/* ── dumb buffers ─────────────────────────────────────────────────────── */

int drmModeCreateDumbBuffer(int fd, uint32_t width, uint32_t height,
                            uint32_t bpp, uint32_t flags,
                            uint32_t *handle, uint32_t *pitch,
                            uint64_t *size);

int drmModeDestroyDumbBuffer(int fd, uint32_t handle);

int drmModeMapDumbBuffer(int fd, uint32_t handle, uint64_t *offset);

/* ── prime ────────────────────────────────────────────────────────────── */

int drmPrimeHandleToFD(int fd, uint32_t handle, uint32_t flags, int *prime_fd);
int drmPrimeFDToHandle(int fd, int prime_fd, uint32_t *handle);

/* ── generic ioctl passthrough ────────────────────────────────────────── */

int drmIoctl(int fd, unsigned long request, void *arg);

/* ── client capability ────────────────────────────────────────────────── */

#define DRM_CLIENT_CAP_STEREO_3D         1
#define DRM_CLIENT_CAP_UNIVERSAL_PLANES  2
#define DRM_CLIENT_CAP_ATOMIC            3
#define DRM_CLIENT_CAP_ASPECT_RATIO      4
#define DRM_CLIENT_CAP_WRITEBACK_CONNECTORS 5

int drmSetClientCap(int fd, uint64_t capability, uint64_t value);

/* ── format codes (FourCC) ───────────────────────────────────────────── */

#define DRM_FORMAT_XRGB8888         0x34325258
#define DRM_FORMAT_ARGB8888         0x34325241
#define DRM_FORMAT_XBGR8888         0x34324258
#define DRM_FORMAT_ABGR8888         0x34324241
#define DRM_FORMAT_RGB565           0x36314752
#define DRM_FORMAT_XRGB2101010      0x30335258
#define DRM_FORMAT_ARGB2101010      0x30335241
#define DRM_FORMAT_XBGR2101010      0x30334258
#define DRM_FORMAT_ABGR2101010      0x30334241
#define DRM_FORMAT_MOD_LINEAR       0
#define DRM_FORMAT_MOD_INVALID      ((uint64_t)1 << 56)

/* ── properties ───────────────────────────────────────────────────────── */

#define DRM_MODE_PROP_RANGE         (1 << 0)
#define DRM_MODE_PROP_ENUM          (1 << 1)
#define DRM_MODE_PROP_BLOB          (1 << 2)
#define DRM_MODE_PROP_BITMASK       (1 << 3)
#define DRM_MODE_PROP_IMMUTABLE     (1 << 4)
#define DRM_MODE_PROP_ATOMIC        (1 << 5)
#define DRM_MODE_PROP_PENDING       (1 << 6)

#define DRM_MODE_OBJECT_CRTC        0xCCCCCCCC
#define DRM_MODE_OBJECT_CONNECTOR   0xC0C0C0C0
#define DRM_MODE_OBJECT_ENCODER     0xE0E0E0E0
#define DRM_MODE_OBJECT_MODE        0xDEDEDEDE
#define DRM_MODE_OBJECT_PROPERTY    0xB0B0B0B0
#define DRM_MODE_OBJECT_FB          0xFBFBFBFB
#define DRM_MODE_OBJECT_BLOB        0xBBBBBBBB
#define DRM_MODE_OBJECT_PLANE       0xEEEEEEEE
#define DRM_MODE_OBJECT_ANY         0

typedef struct drmModePropertyRes {
    uint32_t  prop_id;
    uint32_t  flags;
    char      name[32];
    uint32_t  count_values;
    uint64_t *values;
    uint32_t  count_enums;
    struct {
        uint64_t value;
        char     name[32];
    } *enums;
    uint32_t  count_blobs;
    uint32_t *blob_ids;
} drmModePropertyRes, *drmModePropertyResPtr;

typedef struct drmModeObjectProperties {
    uint32_t  count_props;
    uint32_t *props;
    uint64_t *prop_values;
} drmModeObjectProperties, *drmModeObjectPropertiesPtr;

typedef struct drmModePropertyBlobRes {
    uint32_t id;
    uint32_t length;
    void    *data;
} drmModePropertyBlobRes, *drmModePropertyBlobResPtr;

drmModePropertyResPtr       drmModeGetProperty(int fd, uint32_t property_id);
void                        drmModeFreeProperty(drmModePropertyResPtr ptr);
drmModeObjectPropertiesPtr  drmModeObjectGetProperties(int fd, uint32_t object_id, uint32_t object_type);
void                        drmModeFreeObjectProperties(drmModeObjectPropertiesPtr ptr);
drmModePropertyBlobResPtr   drmModeGetPropertyBlob(int fd, uint32_t blob_id);
void                        drmModeFreePropertyBlob(drmModePropertyBlobResPtr ptr);
int                         drmModeCreatePropertyBlob(int fd, const void *data, size_t length, uint32_t *blob_id);
int                         drmModeDestroyPropertyBlob(int fd, uint32_t blob_id);

/* ── planes ───────────────────────────────────────────────────────────── */

#define DRM_PLANE_TYPE_OVERLAY   0
#define DRM_PLANE_TYPE_PRIMARY   1
#define DRM_PLANE_TYPE_CURSOR    2

typedef struct drmModePlane {
    uint32_t  possible_crtcs;
    uint32_t  gamma_size;
    uint32_t  count_formats;
    uint32_t *formats;
    uint32_t  plane_id;
    uint32_t  crtc_id;
    uint32_t  fb_id;
    uint64_t *format_modifiers;
} drmModePlane, *drmModePlanePtr;

typedef struct drmModePlaneRes {
    uint32_t  count_planes;
    uint32_t *planes;
} drmModePlaneRes, *drmModePlaneResPtr;

drmModePlaneResPtr     drmModeGetPlaneResources(int fd);
drmModePlanePtr        drmModeGetPlane(int fd, uint32_t plane_id);
void                   drmModeFreePlaneResources(drmModePlaneResPtr ptr);
void                   drmModeFreePlane(drmModePlanePtr ptr);

/* ── atomic mode setting ──────────────────────────────────────────────── */

#define DRM_MODE_ATOMIC_TEST_ONLY      0x0100
#define DRM_MODE_ATOMIC_NONBLOCK       0x0200
#define DRM_MODE_ATOMIC_ALLOW_MODESET  0x0400

typedef struct _drmModeAtomicReq drmModeAtomicReq;

drmModeAtomicReq *drmModeAtomicAlloc(void);
void              drmModeAtomicFree(drmModeAtomicReq *req);
int               drmModeAtomicAddProperty(drmModeAtomicReq *req, uint32_t object_id, uint32_t property_id, uint64_t value);
int               drmModeAtomicCommit(int fd, drmModeAtomicReq *req, uint32_t flags, void *user_data);

/* ── cursor ───────────────────────────────────────────────────────────── */

int drmModeSetCursor(int fd, uint32_t crtc_id, uint32_t bo_handle, uint32_t width, uint32_t height);
int drmModeMoveCursor(int fd, uint32_t crtc_id, int x, int y);

/* ── VBlank ───────────────────────────────────────────────────────────── */

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

/* ── format modifier blob iterator ───────────────────────────────────── */

typedef struct _drmModeFormatModifierIterator {
    uint32_t fmt_idx;
    uint32_t mod_idx;
} drmModeFormatModifierIterator;

/* ── sync objects ─────────────────────────────────────────────────────── */

int drmSyncobjCreate(int fd, uint32_t flags, uint32_t *handle);
int drmSyncobjDestroy(int fd, uint32_t handle);
int drmSyncobjImportSyncFile(int fd, uint32_t handle, int sync_file_fd);
int drmSyncobjExportSyncFile(int fd, uint32_t handle, int *sync_file_fd);
int drmSyncobjFDToHandle(int fd, int sync_file_fd, uint32_t *handle);
int drmSyncobjHandleToFD(int fd, uint32_t handle, int *sync_file_fd);

/* ── auth / master ────────────────────────────────────────────────────── */

int drmGetMagic(int fd, drm_magic_t *magic);
int drmAuthMagic(int fd, drm_magic_t magic);
int drmSetMaster(int fd);
int drmDropMaster(int fd);

#ifdef __cplusplus
}
#endif

#endif /* DRM_LINUX_H */
