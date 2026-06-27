#ifndef GBM_H
#define GBM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GBM_FORMAT_XRGB8888         0x34325258
#define GBM_FORMAT_ARGB8888         0x34325241
#define GBM_FORMAT_XBGR8888         0x34324258
#define GBM_FORMAT_ABGR8888         0x34324241
#define GBM_FORMAT_RGB565           0x36314752

#define GBM_BO_USE_SCANOUT          (1 << 0)
#define GBM_BO_USE_RENDERING        (1 << 1)
#define GBM_BO_USE_WRITE            (1 << 2)
#define GBM_BO_USE_LINEAR           (1 << 4)
#define GBM_BO_USE_CURSOR_64X64     (1 << 1)

#define GBM_BO_IMPORT_WL_BUFFER         0x5501
#define GBM_BO_IMPORT_EGL_IMAGE         0x5502
#define GBM_BO_IMPORT_FD                0x5503
#define GBM_BO_IMPORT_FD_MODIFIER       0x5504

struct gbm_import_fd_modifier_data {
    uint32_t width;
    uint32_t height;
    uint32_t format;
    uint32_t num_fds;
    int fds[4];
    int strides[4];
    int offsets[4];
    uint64_t modifier;
};

struct gbm_device;
struct gbm_surface;
struct gbm_bo;

union gbm_bo_handle {
    void    *ptr;
    int32_t  s32;
    uint32_t u32;
    int64_t  s64;
    uint64_t u64;
};

struct gbm_device *gbm_create_device(int fd);
void               gbm_device_destroy(struct gbm_device *gbm);

struct gbm_surface *gbm_surface_create(struct gbm_device *gbm,
                                       uint32_t width, uint32_t height,
                                       uint32_t format, uint32_t flags);
struct gbm_surface *gbm_surface_create_with_modifiers(struct gbm_device *gbm,
                                                      uint32_t width, uint32_t height,
                                                      uint32_t format,
                                                      const uint64_t *modifiers,
                                                      const unsigned int count);
void                gbm_surface_destroy(struct gbm_surface *surface);
struct gbm_bo      *gbm_surface_lock_front_buffer(struct gbm_surface *surface);
void                gbm_surface_release_buffer(struct gbm_surface *surface,
                                               struct gbm_bo *bo);

uint32_t            gbm_bo_get_width(struct gbm_bo *bo);
uint32_t            gbm_bo_get_height(struct gbm_bo *bo);
uint32_t            gbm_bo_get_stride(struct gbm_bo *bo);
uint32_t            gbm_bo_get_format(struct gbm_bo *bo);
struct gbm_device  *gbm_bo_get_device(struct gbm_bo *bo);
union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo);

void gbm_bo_set_user_data(struct gbm_bo *bo, void *data,
                          void (*destroy)(struct gbm_bo *, void *));
void *gbm_bo_get_user_data(struct gbm_bo *bo);

void              gbm_bo_destroy(struct gbm_bo *bo);
struct gbm_bo    *gbm_bo_create(struct gbm_device *gbm,
                                uint32_t width, uint32_t height,
                                uint32_t format, uint32_t flags);
struct gbm_bo    *gbm_bo_create_with_modifiers(struct gbm_device *gbm,
                                               uint32_t width, uint32_t height,
                                               uint32_t format,
                                               const uint64_t *modifiers,
                                               const unsigned int count);
struct gbm_bo    *gbm_bo_create_with_modifiers2(struct gbm_device *gbm,
                                                uint32_t width, uint32_t height,
                                                uint32_t format,
                                                const uint64_t *modifiers,
                                                uint32_t count,
                                                uint32_t flags);
int               gbm_bo_get_plane_count(struct gbm_bo *bo);
int               gbm_bo_get_fd(struct gbm_bo *bo);
int               gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane);
uint32_t          gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane);
uint32_t          gbm_bo_get_offset(struct gbm_bo *bo, int plane);
uint64_t          gbm_bo_get_modifier(struct gbm_bo *bo);
int               gbm_device_get_fd(struct gbm_device *gbm);
int               gbm_bo_write(struct gbm_bo *bo, const void *buf, size_t count);

struct gbm_bo    *gbm_bo_import(struct gbm_device *gbm, uint32_t type,
                                void *buffer, uint32_t usage);
union gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int plane);

#ifdef __cplusplus
}
#endif

#endif /* GBM_H */
