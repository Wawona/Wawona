#ifndef DRM_IOCTL_H
#define DRM_IOCTL_H

#include <stddef.h>
#include <stdint.h>

#define DRM_VIRTUAL_FD  42

/* ── Linux ioctl number encoding ───────────────────────────────────────── */

#define LINUX_IOC_NRBITS     8
#define LINUX_IOC_TYPEBITS   8
#define LINUX_IOC_SIZEBITS   14
#define LINUX_IOC_DIRBITS    2

#define LINUX_IOC_NRSHIFT    0
#define LINUX_IOC_TYPESHIFT  8
#define LINUX_IOC_SIZESHIFT  16
#define LINUX_IOC_DIRSHIFT   30

#define LINUX_IOC_NONE       0
#define LINUX_IOC_READ       1
#define LINUX_IOC_WRITE      2

#define LINUX_IOC(dir,type,nr,size) \
    (((dir)  << LINUX_IOC_DIRSHIFT)  | \
     ((type) << LINUX_IOC_TYPESHIFT) | \
     ((nr)   << LINUX_IOC_NRSHIFT)   | \
     ((size) << LINUX_IOC_SIZESHIFT))

#define LINUX_IO(type, nr)        LINUX_IOC(0, type, nr, 0)
#define LINUX_IOR(type, nr, size) LINUX_IOC(1, type, nr, size)
#define LINUX_IOW(type, nr, size) LINUX_IOC(2, type, nr, size)
#define LINUX_IOWR(type, nr, size) LINUX_IOC(3, type, nr, size)

#define DRM_IOCTL_BASE  'd'

/* decode helpers */
#define DRM_IOCTL_NR(req)   ((req) & 0xFF)
#define DRM_IOCTL_TYPE(req) (((req) >> 8) & 0xFF)

/* ── kernel struct definitions ───────────────────────────────────────────
 *  These mirror the Linux DRM kernel header (drm_mode.h etc.).
 *  All user-space pointers are stored as uint64_t (__u64 in Linux terms). */

struct drm_version {
    int     version_major;
    int     version_minor;
    int     version_patchlevel;
    size_t  name_len;
    char   *name;
    size_t  date_len;
    char   *date;
    size_t  desc_len;
    char   *desc;
};

struct drm_get_cap {
    uint64_t capability;
    uint64_t value;
};

struct drm_set_client_cap {
    uint64_t capability;
    uint64_t value;
};

struct drm_prime_handle {
    int      fd;
    uint32_t handle;
    uint32_t flags;
};

struct drm_mode_card_res {
    uint64_t fb_id_ptr;
    uint64_t crtc_id_ptr;
    uint64_t connector_id_ptr;
    uint64_t encoder_id_ptr;
    uint32_t count_fbs;
    uint32_t count_crtcs;
    uint32_t count_connectors;
    uint32_t count_encoders;
    uint32_t min_width;
    uint32_t max_width;
    uint32_t min_height;
    uint32_t max_height;
};

struct drm_mode_crtc {
    uint64_t set_connectors_ptr;
    uint32_t count_connectors;
    uint32_t crtc_id;
    uint32_t fb_id;
    uint32_t x;
    uint32_t y;
    uint32_t gamma_size;
    uint32_t mode_valid;
    struct drm_mode_modeinfo {
        uint32_t clock;
        uint16_t hdisplay, hsync_start, hsync_end, htotal, hskew;
        uint16_t vdisplay, vsync_start, vsync_end, vtotal, vscan;
        uint32_t vrefresh;
        uint32_t flags;
        uint32_t type;
        char     name[32];
    } mode;
};

#define DRM_MODE_CURSOR_BO    0x01
#define DRM_MODE_CURSOR_MOVE  0x02

struct drm_mode_cursor {
    uint32_t flags;
    uint32_t crtc_id;
    int32_t  x;
    int32_t  y;
    uint32_t width;
    uint32_t height;
    uint32_t handle;
};

struct drm_mode_get_encoder {
    uint32_t encoder_id;
    uint32_t encoder_type;
    uint32_t crtc_id;
    uint32_t possible_crtcs;
    uint32_t possible_clones;
};

struct drm_mode_get_connector {
    uint64_t encoders_ptr;
    uint64_t modes_ptr;
    uint64_t props_ptr;
    uint64_t prop_values_ptr;
    uint32_t count_modes;
    uint32_t count_props;
    uint32_t count_encoders;
    uint32_t encoder_id;
    uint32_t connector_id;
    uint32_t connector_type;
    uint32_t connector_type_id;
    uint32_t connection;
    uint32_t mm_width;
    uint32_t mm_height;
    uint32_t subpixel;
    uint32_t pad;
};

struct drm_mode_fb_cmd {
    uint32_t fb_id;
    uint32_t width;
    uint32_t height;
    uint32_t pitch;
    uint32_t bpp;
    uint32_t depth;
    uint32_t handle;
};

struct drm_mode_crtc_page_flip {
    uint32_t crtc_id;
    uint32_t fb_id;
    uint32_t flags;
    uint32_t reserved;
    uint64_t user_data;
};

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

struct drm_mode_get_plane_res {
    uint64_t plane_id_ptr;
    uint32_t count_planes;
};

struct drm_mode_get_plane {
    uint32_t plane_id;
    uint32_t crtc_id;
    uint32_t fb_id;
    uint32_t possible_crtcs;
    uint32_t gamma_size;
    uint32_t count_format_types;
    uint64_t format_type_ptr;
};

struct drm_mode_fb_cmd2 {
    uint32_t fb_id;
    uint32_t width;
    uint32_t height;
    uint32_t pixel_format;
    uint32_t flags;
    uint32_t handles[4];
    uint32_t pitches[4];
    uint32_t offsets[4];
    uint64_t modifier[4];
};

struct drm_mode_obj_get_properties {
    uint64_t props_ptr;
    uint64_t prop_values_ptr;
    uint32_t count_props;
    uint32_t obj_id;
    uint32_t obj_type;
};

struct drm_mode_get_property {
    uint64_t values_ptr;
    uint64_t enum_blob_ptr;
    uint32_t prop_id;
    uint32_t flags;
    char     name[32];
    uint32_t count_values;
    uint32_t count_enum_blobs;
    uint32_t pad;
};

struct drm_mode_atomic {
    uint32_t flags;
    uint32_t count_objs;
    uint64_t objs_ptr;
    uint64_t count_props_ptr;
    uint64_t props_ptr;
    uint64_t prop_values_ptr;
    uint64_t reserved;
    uint64_t user_data;
};

struct drm_mode_create_blob {
    uint64_t data;
    uint32_t length;
    uint32_t blob_id;
};

struct drm_mode_destroy_blob {
    uint32_t blob_id;
};

struct drm_mode_get_property_blob {
    uint64_t data;
    uint32_t length;
    uint32_t blob_id;
};

struct drm_syncobj_create {
    uint32_t handle;
    uint32_t flags;
};

struct drm_syncobj_destroy {
    uint32_t handle;
    uint32_t pad;
};

struct drm_syncobj_handle {
    uint32_t handle;
    int      fd;
    uint32_t flags;
    uint32_t pad;
};

struct drm_syncobj_array {
    uint64_t handles_ptr;
    uint32_t count_handles;
    uint32_t pad;
    int      sync_file_fd;
    uint32_t pad2;
};

/* Kernel struct for GET_MAGIC / AUTH_MAGIC */
struct drm_auth {
    uint32_t magic;
};

/* ── ioctl number constants ────────────────────────────────────────────── */

#define DRM_IOCTL_VERSION \
    LINUX_IOWR(DRM_IOCTL_BASE, 0x00, sizeof(struct drm_version))

#define DRM_IOCTL_GET_MAGIC \
    LINUX_IOR(DRM_IOCTL_BASE, 0x06, sizeof(struct drm_auth))

#define DRM_IOCTL_AUTH_MAGIC \
    LINUX_IOW(DRM_IOCTL_BASE, 0x07, sizeof(struct drm_auth))

#define DRM_IOCTL_GET_CAP \
    LINUX_IOWR(DRM_IOCTL_BASE, 0x0C, sizeof(struct drm_get_cap))

#define DRM_IOCTL_SET_CLIENT_CAP \
    LINUX_IOW(DRM_IOCTL_BASE, 0x0D, sizeof(struct drm_set_client_cap))

#define DRM_IOCTL_SET_MASTER    LINUX_IO(DRM_IOCTL_BASE, 0x1E)
#define DRM_IOCTL_DROP_MASTER   LINUX_IO(DRM_IOCTL_BASE, 0x1F)

#define DRM_IOCTL_PRIME_HANDLE_TO_FD \
    LINUX_IOWR(DRM_IOCTL_BASE, 0x2D, sizeof(struct drm_prime_handle))

#define DRM_IOCTL_PRIME_FD_TO_HANDLE \
    LINUX_IOWR(DRM_IOCTL_BASE, 0x2E, sizeof(struct drm_prime_handle))

#define DRM_IOCTL_MODE_GETRESOURCES \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xA0, sizeof(struct drm_mode_card_res))

#define DRM_IOCTL_MODE_GETCRTC \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xA1, sizeof(struct drm_mode_crtc))

#define DRM_IOCTL_MODE_SETCRTC \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xA2, sizeof(struct drm_mode_crtc))

#define DRM_IOCTL_MODE_CURSOR \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xA3, sizeof(struct drm_mode_cursor))

#define DRM_IOCTL_MODE_GETENCODER \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xA6, sizeof(struct drm_mode_get_encoder))

#define DRM_IOCTL_MODE_GETCONNECTOR \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xA7, sizeof(struct drm_mode_get_connector))

#define DRM_IOCTL_MODE_ADDFB \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xAE, sizeof(struct drm_mode_fb_cmd))

#define DRM_IOCTL_MODE_RMFB \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xAF, sizeof(int))

#define DRM_IOCTL_MODE_PAGE_FLIP \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xB0, sizeof(struct drm_mode_crtc_page_flip))

#define DRM_IOCTL_MODE_CREATE_DUMB \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xB2, sizeof(struct drm_mode_create_dumb))

#define DRM_IOCTL_MODE_MAP_DUMB \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xB3, sizeof(struct drm_mode_map_dumb))

#define DRM_IOCTL_MODE_DESTROY_DUMB \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xB4, sizeof(struct drm_mode_destroy_dumb))

#define DRM_IOCTL_MODE_GETPLANERESOURCES \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xB5, sizeof(struct drm_mode_get_plane_res))

#define DRM_IOCTL_MODE_GETPLANE \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xB6, sizeof(struct drm_mode_get_plane))

#define DRM_IOCTL_MODE_ADDFB2 \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xB8, sizeof(struct drm_mode_fb_cmd2))

#define DRM_IOCTL_MODE_OBJ_GETPROPERTIES \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xB9, sizeof(struct drm_mode_obj_get_properties))

#define DRM_IOCTL_MODE_GETPROPERTY \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xBB, sizeof(struct drm_mode_get_property))

#define DRM_IOCTL_MODE_ATOMIC \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xBC, sizeof(struct drm_mode_atomic))

#define DRM_IOCTL_MODE_CREATEPROPBLOB \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xBD, sizeof(struct drm_mode_create_blob))

#define DRM_IOCTL_MODE_DESTROYPROPBLOB \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xBE, sizeof(struct drm_mode_destroy_blob))

#define DRM_IOCTL_MODE_GETPROPBLOB \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xBF, sizeof(struct drm_mode_get_property_blob))

#define DRM_IOCTL_SYNCOBJ_CREATE \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xC0, sizeof(struct drm_syncobj_create))

#define DRM_IOCTL_SYNCOBJ_DESTROY \
    LINUX_IOW(DRM_IOCTL_BASE, 0xC1, sizeof(struct drm_syncobj_destroy))

#define DRM_IOCTL_SYNCOBJ_HANDLE_TO_FD \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xC2, sizeof(struct drm_syncobj_handle))

#define DRM_IOCTL_SYNCOBJ_FD_TO_HANDLE \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xC3, sizeof(struct drm_syncobj_handle))

#define DRM_IOCTL_SYNCOBJ_IMPORT_SYNC_FILE \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xC4, sizeof(struct drm_syncobj_array))

#define DRM_IOCTL_SYNCOBJ_EXPORT_SYNC_FILE \
    LINUX_IOWR(DRM_IOCTL_BASE, 0xC5, sizeof(struct drm_syncobj_array))

/* ── dispatch entry point ─────────────────────────────────────────────── */
int drm_ioctl_dispatch(unsigned long request, void *arg);

#endif /* DRM_IOCTL_H */
