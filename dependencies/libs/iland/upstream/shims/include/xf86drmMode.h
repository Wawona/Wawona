#ifndef XF86DRM_MODE_H
#define XF86DRM_MODE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct drmModeModeInfo {
    uint32_t clock;
    uint16_t hdisplay, hsync_start, hsync_end, htotal, hskew;
    uint16_t vdisplay, vsync_start, vsync_end, vtotal, vscan;
    uint32_t vrefresh;
    uint32_t flags;
    uint32_t type;
    char     name[32];
} drmModeModeInfo;

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

typedef struct drmModeModeInfo drmModeModeInfo;

typedef struct drmModeFB {
    uint32_t fb_id;
    uint32_t width, height;
    uint32_t pitch;
    uint32_t bpp;
    uint32_t depth;
    uint32_t handle;
} drmModeFB, *drmModeFBPtr;

typedef struct drmModeCrtc {
    uint32_t        crtc_id;
    uint32_t        buffer_id;
    uint32_t        x, y;
    uint32_t        width, height;
    int             mode_valid;
    drmModeModeInfo mode;
    int             gamma_size;
} drmModeCrtc, *drmModeCrtcPtr;

typedef struct drmModeEncoder {
    uint32_t encoder_id;
    uint32_t encoder_type;
    uint32_t crtc_id;
    uint32_t possible_crtcs;
    uint32_t possible_clones;
} drmModeEncoder, *drmModeEncoderPtr;

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
#define DRM_MODE_CONNECTOR_DPI          17
#define DRM_MODE_CONNECTOR_WRITEBACK    18

#define DRM_MODE_TYPE_USERDEF       0x00000020
#define DRM_MODE_TYPE_PREFERRED     0x00000040
#define DRM_MODE_TYPE_DRIVER         0x00000080

#define DRM_MODE_FLAG_PHSYNC        0x00000001
#define DRM_MODE_FLAG_NHSYNC        0x00000002
#define DRM_MODE_FLAG_PVSYNC        0x00000004
#define DRM_MODE_FLAG_NVSYNC        0x00000008
#define DRM_MODE_FLAG_INTERLACE     0x00000010
#define DRM_MODE_FLAG_DBLSCAN       0x00000020

#define DRM_MODE_FLAG_PIC_AR_MASK   0x00000F00
#define DRM_MODE_FLAG_PIC_AR_NONE   0x00000100
#define DRM_MODE_FLAG_PIC_AR_4_3    0x00000200
#define DRM_MODE_FLAG_PIC_AR_16_9   0x00000400
#define DRM_MODE_FLAG_PIC_AR_64_27  0x00000800
#define DRM_MODE_FLAG_PIC_AR_256_135 0x00001000

#define DRM_MODE_SUBPIXEL_UNKNOWN        1
#define DRM_MODE_SUBPIXEL_NONE           2
#define DRM_MODE_SUBPIXEL_HORIZONTAL_RGB 3
#define DRM_MODE_SUBPIXEL_HORIZONTAL_BGR 4
#define DRM_MODE_SUBPIXEL_VERTICAL_RGB   5
#define DRM_MODE_SUBPIXEL_VERTICAL_BGR   6

typedef struct drmModeConnector {
    uint32_t         connector_id;
    uint32_t         encoder_id;
    uint32_t         connector_type;
    uint32_t         connector_type_id;
    uint32_t         connection;
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

typedef drmModePropertyRes  drmModeProperty;
typedef drmModePropertyResPtr drmModePropertyPtr;

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

struct hdr_metadata_infoframe {
	uint16_t eotf;
	uint8_t  metadata_type;
	struct { uint16_t x, y; } display_primaries[3];
	struct { uint16_t x, y; } white_point;
	uint16_t max_display_mastering_luminance;
	uint16_t min_display_mastering_luminance;
	uint16_t max_cll;
	uint16_t max_fall;
};

struct hdr_output_metadata {
	uint32_t metadata_type;
	struct hdr_metadata_infoframe hdmi_metadata_type1;
};

typedef drmModePropertyBlobRes *drmModePropertyBlobPtr;

#define DRM_MODE_PAGE_FLIP_EVENT 0x01
#define DRM_MODE_PAGE_FLIP_ASYNC 0x02

#define DRM_EVENT_CONTEXT_VERSION 3

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

#define DRM_MODE_PROP_RANGE         (1 << 0)
#define DRM_MODE_PROP_ENUM          (1 << 1)
#define DRM_MODE_PROP_BLOB          (1 << 2)
#define DRM_MODE_PROP_BITMASK       (1 << 3)
#define DRM_MODE_PROP_IMMUTABLE     (1 << 4)
#define DRM_MODE_PROP_ATOMIC        (1 << 5)
#define DRM_MODE_PROP_PENDING       (1 << 6)
#define DRM_MODE_PROP_SIGNED_RANGE  (1 << 13)

#define DRM_MODE_OBJECT_CRTC        0xCCCCCCCC
#define DRM_MODE_OBJECT_CONNECTOR   0xC0C0C0C0
#define DRM_MODE_OBJECT_ENCODER     0xE0E0E0E0
#define DRM_MODE_OBJECT_MODE        0xDEDEDEDE
#define DRM_MODE_OBJECT_PROPERTY    0xB0B0B0B0
#define DRM_MODE_OBJECT_FB          0xFBFBFBFB
#define DRM_MODE_OBJECT_BLOB        0xBBBBBBBB
#define DRM_MODE_OBJECT_PLANE       0xEEEEEEEE
#define DRM_MODE_OBJECT_ANY         0

#define DRM_PLANE_TYPE_OVERLAY   0
#define DRM_PLANE_TYPE_PRIMARY   1
#define DRM_PLANE_TYPE_CURSOR    2

#define DRM_MODE_ATOMIC_TEST_ONLY      0x0100
#define DRM_MODE_ATOMIC_NONBLOCK       0x0200
#define DRM_MODE_ATOMIC_ALLOW_MODESET  0x0400

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
                               const uint64_t modifier[4],
                               uint32_t *buf_id, uint32_t flags);

int drmModeRmFB(int fd, uint32_t buf_id);

int drmModePageFlip(int fd, uint32_t crtc_id, uint32_t fb_id,
                    uint32_t flags, void *user_data);

int drmModeSetPlane(int fd, uint32_t plane_id, uint32_t crtc_id,
                    uint32_t fb_id, uint32_t flags,
                    int32_t crtc_x, int32_t crtc_y,
                    uint32_t crtc_w, uint32_t crtc_h,
                    uint32_t src_x, uint32_t src_y,
                    uint32_t src_w, uint32_t src_h);

int drmHandleEvent(int fd, drmEventContextPtr evctx);

int drmModeCreateDumbBuffer(int fd, uint32_t width, uint32_t height,
                            uint32_t bpp, uint32_t flags,
                            uint32_t *handle, uint32_t *pitch,
                            uint64_t *size);

int drmModeDestroyDumbBuffer(int fd, uint32_t handle);

int drmModeMapDumbBuffer(int fd, uint32_t handle, uint64_t *offset);

int drmModeSetCursor(int fd, uint32_t crtc_id,
                     uint32_t bo_handle, uint32_t width, uint32_t height);
int drmModeMoveCursor(int fd, uint32_t crtc_id, int x, int y);

drmModePlaneResPtr     drmModeGetPlaneResources(int fd);
drmModePlanePtr        drmModeGetPlane(int fd, uint32_t plane_id);
void                   drmModeFreePlaneResources(drmModePlaneResPtr ptr);
void                   drmModeFreePlane(drmModePlanePtr ptr);

drmModePropertyResPtr       drmModeGetProperty(int fd, uint32_t property_id);
void                        drmModeFreeProperty(drmModePropertyResPtr ptr);
drmModeObjectPropertiesPtr  drmModeObjectGetProperties(int fd, uint32_t object_id, uint32_t object_type);
void                        drmModeFreeObjectProperties(drmModeObjectPropertiesPtr ptr);
drmModePropertyBlobResPtr   drmModeGetPropertyBlob(int fd, uint32_t blob_id);
void                        drmModeFreePropertyBlob(drmModePropertyBlobResPtr ptr);
int                         drmModeCreatePropertyBlob(int fd, const void *data, size_t length, uint32_t *blob_id);
int                         drmModeDestroyPropertyBlob(int fd, uint32_t blob_id);

typedef struct _drmModeAtomicReq drmModeAtomicReq;

drmModeAtomicReq *drmModeAtomicAlloc(void);
void              drmModeAtomicFree(drmModeAtomicReq *req);
int               drmModeAtomicAddProperty(drmModeAtomicReq *req,
                                           uint32_t object_id,
                                           uint32_t property_id,
                                           uint64_t value);
int               drmModeAtomicCommit(int fd, drmModeAtomicReq *req,
                                      uint32_t flags, void *user_data);

typedef struct _drmModeFormatModifierIterator {
	uint32_t fmt_idx, mod_idx;
	uint32_t fmt;
	uint64_t mod;
} drmModeFormatModifierIterator;

bool drmModeFormatModifierBlobIterNext(const drmModePropertyBlobRes *blob,
                                       drmModeFormatModifierIterator *iter);

int drmModeCrtcSetGamma(int fd, uint32_t crtc_id, uint32_t size,
                        uint16_t *red, uint16_t *green, uint16_t *blue);
int drmModeConnectorSetProperty(int fd, uint32_t connector_id,
                                uint32_t property_id, uint64_t value);

int drmSyncobjCreate(int fd, uint32_t flags, uint32_t *handle);
int drmSyncobjDestroy(int fd, uint32_t handle);
int drmSyncobjImportSyncFile(int fd, uint32_t handle, int sync_file_fd);
int drmSyncobjExportSyncFile(int fd, uint32_t handle, int *sync_file_fd);
int drmSyncobjFDToHandle(int fd, int sync_file_fd, uint32_t *handle);
int drmSyncobjHandleToFD(int fd, uint32_t handle, int *sync_file_fd);

#ifdef __cplusplus
}
#endif

#endif /* XF86DRM_MODE_H */
