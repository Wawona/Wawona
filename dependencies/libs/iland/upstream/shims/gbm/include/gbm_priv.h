#ifndef GBM_PRIV_H
#define GBM_PRIV_H

#include "gbm.h"
#include <IOSurface/IOSurface.h>

#define GBM_NUM_BUFFERS 4

struct gbm_device {
    int fd;
    int refcount;
};

struct gbm_bo {
    struct gbm_device *device;
    IOSurfaceRef       surface;
    uint32_t           width;
    uint32_t           height;
    uint32_t           stride;
    uint32_t           format;
    void              *user_data;
    void             (*destroy_user_data)(struct gbm_bo *, void *);
};

struct gbm_surface {
    struct gbm_device *device;
    uint32_t           width;
    uint32_t           height;
    uint32_t           format;
    uint32_t           flags;
    struct gbm_bo     *bos[GBM_NUM_BUFFERS];
    int                write_idx;
    int                read_idx;
    int                count;
};

IOSurfaceRef gbm_bo_get_iosurface(struct gbm_bo *bo);
struct gbm_bo *gbm_surface_get_write_bo(struct gbm_surface *surface);
void gbm_surface_advance_write(struct gbm_surface *surface);

#endif
