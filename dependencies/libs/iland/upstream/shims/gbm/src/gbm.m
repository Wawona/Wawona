#import <gbm_priv.h>
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <stdlib.h>
#import <string.h>
#import <errno.h>
#import "DisplaySurface.h"

/* Register GBM buffer handles so drmModeAddFB can resolve them. */
extern void drm_register_gbm_buffer(uint32_t handle, void *surface);
extern void drm_unregister_gbm_buffer(uint32_t handle);

static IOSurfaceRef create_iosurface(uint32_t width, uint32_t height,
                                      uint32_t format)
{
    (void)format;
    DisplaySurfaceInfo dsi = DisplaySurface_create(width, height, kWSPixelFormatBGRA);
    return dsi.surface;
}

struct gbm_device *gbm_create_device(int fd)
{
    struct gbm_device *dev = calloc(1, sizeof(*dev));
    if (!dev) return NULL;
    dev->fd = fd;
    dev->refcount = 1;
    return dev;
}

void gbm_device_destroy(struct gbm_device *gbm)
{
    if (!gbm) return;
    if (--gbm->refcount > 0) return;
    free(gbm);
}

struct gbm_surface *gbm_surface_create(struct gbm_device *gbm,
                                        uint32_t width, uint32_t height,
                                        uint32_t format, uint32_t flags)
{
    struct gbm_surface *surf = calloc(1, sizeof(*surf));
    if (!surf) return NULL;

    surf->device = gbm;
    surf->width  = width;
    surf->height = height;
    surf->format = format;
    surf->flags  = flags;

    for (int i = 0; i < GBM_NUM_BUFFERS; i++) {
        struct gbm_bo *bo = calloc(1, sizeof(*bo));
        if (!bo) goto fail;
        bo->device = gbm;
        bo->width  = width;
        bo->height = height;
        bo->surface = create_iosurface(width, height, format);
        if (!bo->surface) { free(bo); goto fail; }
        bo->stride = (uint32_t)IOSurfaceGetBytesPerRow(bo->surface);
        bo->format = format;
        drm_register_gbm_buffer((uint32_t)IOSurfaceGetID(bo->surface),
                                (void*)bo->surface);
        surf->bos[i] = bo;
    }
    return surf;

fail:
    for (int i = 0; i < GBM_NUM_BUFFERS; i++) {
        if (surf->bos[i]) {
            if (surf->bos[i]->surface) {
                drm_unregister_gbm_buffer(
                    (uint32_t)IOSurfaceGetID(surf->bos[i]->surface));
                CFRelease(surf->bos[i]->surface);
            }
            free(surf->bos[i]);
        }
    }
    free(surf);
    return NULL;
}

void gbm_surface_destroy(struct gbm_surface *surface)
{
    if (!surface) return;
    for (int i = 0; i < GBM_NUM_BUFFERS; i++) {
        if (surface->bos[i]) {
            if (surface->bos[i]->surface) {
                drm_unregister_gbm_buffer(
                    (uint32_t)IOSurfaceGetID(surface->bos[i]->surface));
                CFRelease(surface->bos[i]->surface);
            }
            free(surface->bos[i]);
        }
    }
    free(surface);
}

struct gbm_bo *gbm_surface_lock_front_buffer(struct gbm_surface *surface)
{
    if (!surface || surface->count == 0) return NULL;
    struct gbm_bo *bo = surface->bos[surface->read_idx];
    surface->read_idx = (surface->read_idx + 1) % GBM_NUM_BUFFERS;
    surface->count--;
    return bo;
}

void gbm_surface_release_buffer(struct gbm_surface *surface,
                                 struct gbm_bo *bo)
{
    (void)surface;
    (void)bo;
}

IOSurfaceRef gbm_bo_get_iosurface(struct gbm_bo *bo)
{
    return bo ? bo->surface : NULL;
}

struct gbm_bo *gbm_surface_get_write_bo(struct gbm_surface *surface)
{
    if (!surface) return NULL;
    return surface->bos[surface->write_idx];
}

void gbm_surface_advance_write(struct gbm_surface *surface)
{
    if (!surface) return;
    surface->write_idx = (surface->write_idx + 1) % GBM_NUM_BUFFERS;
    surface->count++;
}

uint32_t gbm_bo_get_width(struct gbm_bo *bo)
{
    return bo ? bo->width : 0;
}

uint32_t gbm_bo_get_height(struct gbm_bo *bo)
{
    return bo ? bo->height : 0;
}

uint32_t gbm_bo_get_stride(struct gbm_bo *bo)
{
    return bo ? bo->stride : 0;
}

uint32_t gbm_bo_get_format(struct gbm_bo *bo)
{
    return bo ? bo->format : 0;
}

struct gbm_device *gbm_bo_get_device(struct gbm_bo *bo)
{
    return bo ? bo->device : NULL;
}

union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo)
{
    union gbm_bo_handle h = {0};
    if (bo && bo->surface)
        h.u32 = (uint32_t)IOSurfaceGetID(bo->surface);
    return h;
}

void gbm_bo_set_user_data(struct gbm_bo *bo, void *data,
                           void (*destroy)(struct gbm_bo *, void *))
{
    if (!bo) return;
    bo->user_data = data;
    bo->destroy_user_data = destroy;
}

void *gbm_bo_get_user_data(struct gbm_bo *bo)
{
    return bo ? bo->user_data : NULL;
}

/* ── missing GBM API stubs ────────────────────────────────────────── */

struct gbm_bo *gbm_bo_create(struct gbm_device *gbm,
                              uint32_t width, uint32_t height,
                              uint32_t format, uint32_t flags)
{
    struct gbm_bo *bo = calloc(1, sizeof(*bo));
    if (!bo) return NULL;
    bo->device = gbm;
    bo->width  = width;
    bo->height = height;
    bo->surface = create_iosurface(width, height, format);
    if (!bo->surface) { free(bo); return NULL; }
    bo->stride = (uint32_t)IOSurfaceGetBytesPerRow(bo->surface);
    bo->format = format;
    drm_register_gbm_buffer((uint32_t)IOSurfaceGetID(bo->surface),
                            (void*)bo->surface);
    return bo;
}

struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm,
                                             uint32_t width, uint32_t height,
                                             uint32_t format,
                                             const uint64_t *modifiers,
                                             const unsigned int count)
{
    (void)modifiers;(void)count;
    return gbm_bo_create(gbm, width, height, format, 0);
}

struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *gbm,
                                              uint32_t width, uint32_t height,
                                              uint32_t format,
                                              const uint64_t *modifiers,
                                              uint32_t count,
                                              uint32_t flags)
{
    (void)modifiers;(void)count;(void)flags;
    return gbm_bo_create(gbm, width, height, format, 0);
}

void gbm_bo_destroy(struct gbm_bo *bo)
{
    if (!bo) return;
    if (bo->surface) {
        drm_unregister_gbm_buffer((uint32_t)IOSurfaceGetID(bo->surface));
        CFRelease(bo->surface);
    }
    free(bo);
}

int gbm_bo_get_fd(struct gbm_bo *bo)
{
    (void)bo;
    errno = ENOSYS;
    return -1;
}

int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane)
{
    (void)bo;(void)plane;
    errno = ENOSYS;
    return -1;
}

int gbm_bo_get_plane_count(struct gbm_bo *bo)
{
    (void)bo;
    return 1;
}

uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane)
{
    (void)plane;
    return bo ? bo->stride : 0;
}

uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane)
{
    (void)bo;(void)plane;
    return 0;
}

uint64_t gbm_bo_get_modifier(struct gbm_bo *bo)
{
    (void)bo;
    return 0; /* DRM_FORMAT_MOD_LINEAR */
}

int gbm_device_get_fd(struct gbm_device *gbm)
{
    return gbm ? gbm->fd : -1;
}

int gbm_bo_write(struct gbm_bo *bo, const void *buf, size_t count)
{
    if (!bo || !bo->surface) { errno = EINVAL; return -1; }
    IOSurfaceLock(bo->surface, 0, NULL);
    void *base = IOSurfaceGetBaseAddress(bo->surface);
    size_t avail = (size_t)bo->stride * bo->height;
    if (count > avail) count = avail;
    memcpy(base, buf, count);
    IOSurfaceUnlock(bo->surface, 0, NULL);
    return 0;
}

struct gbm_bo *gbm_bo_import(struct gbm_device *gbm, uint32_t type,
                              void *buffer, uint32_t usage)
{
    (void)gbm;(void)type;(void)buffer;(void)usage;
    errno = ENOSYS;
    return NULL;
}

struct gbm_surface *gbm_surface_create_with_modifiers(
    struct gbm_device *gbm,
    uint32_t width, uint32_t height,
    uint32_t format, const uint64_t *modifiers,
    const unsigned int count)
{
    (void)modifiers;(void)count;
    return gbm_surface_create(gbm, width, height, format, 0);
}

union gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int plane)
{
    (void)plane;
    return gbm_bo_get_handle(bo);
}
