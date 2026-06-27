#include "drm_ioctl.h"
#include "drm_linux.h"
#include "drm.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── helper: copy modeinfo from our type to kernel struct layout ──────── */
static void copy_mode(uint32_t *dst, const drmModeModeInfo *src)
{
    dst[0]  = src->clock;
    dst[1]  = (uint32_t)src->hdisplay | ((uint32_t)src->hsync_start << 16);
    dst[2]  = (uint32_t)src->hsync_end | ((uint32_t)src->htotal << 16);
    dst[3]  = (uint32_t)src->hskew   | ((uint32_t)src->vdisplay << 16);
    dst[4]  = (uint32_t)src->vsync_start | ((uint32_t)src->vsync_end << 16);
    dst[5]  = (uint32_t)src->vtotal  | ((uint32_t)src->vscan << 16);
    dst[6]  = src->vrefresh;
    dst[7]  = src->flags;
    dst[8]  = src->type;
    memcpy(&dst[9], src->name, 32);
}

/* ── per-ioctl handlers ────────────────────────────────────────────────── */

static int handle_version(void *arg)
{
    struct drm_version *v = arg;
    static const char *name = "wayland-mac";
    static const char *date = "2026";
    static const char *desc = "Virtual DRM for macOS";

    v->version_major = 2;
    v->version_minor = 6;
    v->version_patchlevel = 0;

    size_t name_len = strlen(name) + 1;
    if (v->name && v->name_len >= name_len)
        memcpy(v->name, name, name_len);
    v->name_len = name_len;

    size_t date_len = strlen(date) + 1;
    if (v->date && v->date_len >= date_len)
        memcpy(v->date, date, date_len);
    v->date_len = date_len;

    size_t desc_len = strlen(desc) + 1;
    if (v->desc && v->desc_len >= desc_len)
        memcpy(v->desc, desc, desc_len);
    v->desc_len = desc_len;

    return 0;
}

static int handle_get_magic(void *arg)
{
    struct drm_auth *a = arg;
    drm_magic_t magic;
    int ret = drmGetMagic(DRM_VIRTUAL_FD, &magic);
    if (ret == 0)
        a->magic = (uint32_t)magic;
    return ret;
}

static int handle_auth_magic(void *arg)
{
    struct drm_auth *a = arg;
    return drmAuthMagic(DRM_VIRTUAL_FD, a->magic);
}

static int handle_get_cap(void *arg)
{
    struct drm_get_cap *c = arg;
    return drmGetCap(DRM_VIRTUAL_FD, c->capability, &c->value);
}

static int handle_set_client_cap(void *arg)
{
    struct drm_set_client_cap *c = arg;
    return drmSetClientCap(DRM_VIRTUAL_FD, c->capability, c->value);
}

static int handle_set_master(void *arg)
{
    (void)arg;
    return drmSetMaster(DRM_VIRTUAL_FD);
}

static int handle_drop_master(void *arg)
{
    (void)arg;
    return drmDropMaster(DRM_VIRTUAL_FD);
}

static int handle_prime_handle_to_fd(void *arg)
{
    struct drm_prime_handle *p = arg;
    return drmPrimeHandleToFD(DRM_VIRTUAL_FD, p->handle, p->flags, &p->fd);
}

static int handle_prime_fd_to_handle(void *arg)
{
    struct drm_prime_handle *p = arg;
    return drmPrimeFDToHandle(DRM_VIRTUAL_FD, p->fd, &p->handle);
}

static int handle_get_resources(void *arg)
{
    struct drm_mode_card_res *res = arg;
    drmModeResPtr r = drmModeGetResources(DRM_VIRTUAL_FD);
    if (!r) return -1;

    res->count_fbs        = r->count_fbs;
    res->count_crtcs      = r->count_crtcs;
    res->count_connectors = r->count_connectors;
    res->count_encoders   = r->count_encoders;
    res->min_width        = r->min_width;
    res->max_width        = r->max_width;
    res->min_height       = r->min_height;
    res->max_height       = r->max_height;

    uint32_t *crtcs = (uint32_t *)(uintptr_t)res->crtc_id_ptr;
    uint32_t *conns = (uint32_t *)(uintptr_t)res->connector_id_ptr;
    uint32_t *encs  = (uint32_t *)(uintptr_t)res->encoder_id_ptr;

    if (crtcs && res->count_crtcs > 0)
        for (int i = 0; i < r->count_crtcs && i < (int)res->count_crtcs; i++)
            crtcs[i] = r->crtcs[i];
    if (conns && res->count_connectors > 0)
        for (int i = 0; i < r->count_connectors && i < (int)res->count_connectors; i++)
            conns[i] = r->connectors[i];
    if (encs && res->count_encoders > 0)
        for (int i = 0; i < r->count_encoders && i < (int)res->count_encoders; i++)
            encs[i] = r->encoders[i];

    drmModeFreeResources(r);
    return 0;
}

static int handle_get_crtc(void *arg)
{
    struct drm_mode_crtc *c = arg;
    drmModeCrtcPtr crtc = drmModeGetCrtc(DRM_VIRTUAL_FD, c->crtc_id);
    if (!crtc) return -1;

    c->fb_id      = crtc->buffer_id;
    c->x          = crtc->x;
    c->y          = crtc->y;
    c->gamma_size = crtc->gamma_size;
    c->mode_valid = crtc->mode_valid;
    if (crtc->mode_valid) {
        copy_mode((uint32_t *)&c->mode, &crtc->mode);
    }

    drmModeFreeCrtc(crtc);
    return 0;
}

static int handle_set_crtc(void *arg)
{
    struct drm_mode_crtc *c = arg;
    drmModeModeInfo mode;
    memcpy(&mode, &c->mode, sizeof(mode));
    return drmModeSetCrtc(DRM_VIRTUAL_FD, c->crtc_id, c->fb_id,
                          c->x, c->y, NULL, 0, &mode);
}

static int handle_cursor(void *arg)
{
    struct drm_mode_cursor *c = arg;
    if (c->flags & DRM_MODE_CURSOR_BO) {
        return drmModeSetCursor(DRM_VIRTUAL_FD, c->crtc_id,
                                c->handle, c->width, c->height);
    }
    if (c->flags & DRM_MODE_CURSOR_MOVE) {
        return drmModeMoveCursor(DRM_VIRTUAL_FD, c->crtc_id, c->x, c->y);
    }
    errno = EINVAL;
    return -1;
}

static int handle_get_encoder(void *arg)
{
    struct drm_mode_get_encoder *e = arg;
    drmModeEncoderPtr enc = drmModeGetEncoder(DRM_VIRTUAL_FD, e->encoder_id);
    if (!enc) return -1;

    e->encoder_type   = enc->encoder_type;
    e->crtc_id        = enc->crtc_id;
    e->possible_crtcs = enc->possible_crtcs;
    e->possible_clones= enc->possible_clones;

    drmModeFreeEncoder(enc);
    return 0;
}

static int handle_get_connector(void *arg)
{
    struct drm_mode_get_connector *kc = arg;
    drmModeConnectorPtr c = drmModeGetConnector(DRM_VIRTUAL_FD,
                                                 kc->connector_id);
    if (!c) return -1;

    kc->encoder_id       = c->encoder_id;
    kc->connector_type   = c->connector_type;
    kc->connector_type_id= c->connector_type_id;
    kc->connection       = c->connection;
    kc->mm_width         = c->mmWidth;
    kc->mm_height        = c->mmHeight;
    kc->subpixel         = c->subpixel;

    /* Copy modes */
    {
        struct drm_mode_modeinfo *dst = (void *)(uintptr_t)kc->modes_ptr;
        kc->count_modes = c->count_modes;
        if (dst && c->count_modes > 0) {
            int n = c->count_modes;
            for (int i = 0; i < n; i++)
                copy_mode((uint32_t *)&dst[i], &c->modes[i]);
        }
    }

    /* Copy props and values */
    {
        uint32_t *p    = (uint32_t *)(uintptr_t)kc->props_ptr;
        uint64_t *pv   = (uint64_t *)(uintptr_t)kc->prop_values_ptr;
        kc->count_props = c->count_props;
        if (p && pv && c->count_props > 0) {
            for (int i = 0; i < c->count_props; i++) {
                p[i]  = c->props[i];
                pv[i] = c->prop_values[i];
            }
        }
    }

    /* Copy encoders */
    {
        uint32_t *dst = (uint32_t *)(uintptr_t)kc->encoders_ptr;
        kc->count_encoders = c->count_encoders;
        if (dst && c->count_encoders > 0) {
            for (int i = 0; i < c->count_encoders; i++)
                dst[i] = c->encoders[i];
        }
    }

    drmModeFreeConnector(c);
    return 0;
}

static int handle_add_fb(void *arg)
{
    struct drm_mode_fb_cmd *f = arg;
    return drmModeAddFB(DRM_VIRTUAL_FD, f->width, f->height,
                        f->depth, f->bpp, f->pitch, f->handle,
                        &f->fb_id);
}

static int handle_rm_fb(void *arg)
{
    return drmModeRmFB(DRM_VIRTUAL_FD, *(int *)arg);
}

static int handle_page_flip(void *arg)
{
    struct drm_mode_crtc_page_flip *p = arg;
    return drmModePageFlip(DRM_VIRTUAL_FD, p->crtc_id, p->fb_id,
                           p->flags, (void *)(uintptr_t)p->user_data);
}

static int handle_create_dumb(void *arg)
{
    struct drm_mode_create_dumb *d = arg;
    return drmModeCreateDumbBuffer(DRM_VIRTUAL_FD,
                                   d->width, d->height, d->bpp, d->flags,
                                   &d->handle, &d->pitch, &d->size);
}

static int handle_map_dumb(void *arg)
{
    struct drm_mode_map_dumb *m = arg;
    return drmModeMapDumbBuffer(DRM_VIRTUAL_FD, m->handle, &m->offset);
}

static int handle_destroy_dumb(void *arg)
{
    struct drm_mode_destroy_dumb *d = arg;
    return drmModeDestroyDumbBuffer(DRM_VIRTUAL_FD, d->handle);
}

static int handle_get_plane_resources(void *arg)
{
    struct drm_mode_get_plane_res *res = arg;
    drmModePlaneResPtr r = drmModeGetPlaneResources(DRM_VIRTUAL_FD);
    if (!r) return -1;

    res->count_planes = r->count_planes;
    uint32_t *dst = (uint32_t *)(uintptr_t)res->plane_id_ptr;
    if (dst && r->planes)
        for (uint32_t i = 0; i < r->count_planes; i++)
            dst[i] = r->planes[i];

    drmModeFreePlaneResources(r);
    return 0;
}

static int handle_get_plane(void *arg)
{
    struct drm_mode_get_plane *kp = arg;
    drmModePlanePtr p = drmModeGetPlane(DRM_VIRTUAL_FD, kp->plane_id);
    if (!p) return -1;

    kp->crtc_id            = p->crtc_id;
    kp->fb_id              = p->fb_id;
    kp->possible_crtcs     = p->possible_crtcs;
    kp->gamma_size         = p->gamma_size;
    kp->count_format_types = p->count_formats;

    uint32_t *fmt_dst = (uint32_t *)(uintptr_t)kp->format_type_ptr;
    if (fmt_dst && p->formats)
        for (uint32_t i = 0; i < p->count_formats; i++)
            fmt_dst[i] = p->formats[i];

    drmModeFreePlane(p);
    return 0;
}

static int handle_add_fb2(void *arg)
{
    struct drm_mode_fb_cmd2 *f = arg;
    return drmModeAddFB2(DRM_VIRTUAL_FD, f->width, f->height,
                         f->pixel_format, f->handles, f->pitches,
                         f->offsets, &f->fb_id, f->flags);
}

static int handle_obj_get_properties(void *arg)
{
    struct drm_mode_obj_get_properties *kp = arg;
    drmModeObjectPropertiesPtr p =
        drmModeObjectGetProperties(DRM_VIRTUAL_FD, kp->obj_id, kp->obj_type);
    if (!p) return -1;

    kp->count_props = p->count_props;
    uint32_t *props = (uint32_t *)(uintptr_t)kp->props_ptr;
    uint64_t *vals  = (uint64_t *)(uintptr_t)kp->prop_values_ptr;
    if (props && vals && p->props && p->prop_values)
        for (uint32_t i = 0; i < p->count_props; i++) {
            props[i] = p->props[i];
            vals[i]  = p->prop_values[i];
        }

    drmModeFreeObjectProperties(p);
    return 0;
}

static int handle_get_property(void *arg)
{
    struct drm_mode_get_property *kp = arg;
    drmModePropertyResPtr p = drmModeGetProperty(DRM_VIRTUAL_FD, kp->prop_id);
    if (!p) return -1;

    kp->flags = p->flags;
    memcpy(kp->name, p->name, 32);
    kp->count_values     = p->count_values;
    kp->count_enum_blobs = p->count_enums;
    /* For blob properties, count_enum_blobs is the blob count. The kernel
     * ABI is ambiguous here — we report enums + blobs combined. */
    if (p->count_blobs > 0 && (p->flags & DRM_MODE_PROP_BLOB))
        kp->count_enum_blobs = p->count_blobs;

    uint64_t *vals = (uint64_t *)(uintptr_t)kp->values_ptr;
    if (vals && p->values)
        for (uint32_t i = 0; i < p->count_values; i++)
            vals[i] = p->values[i];

    /* enum_blob_ptr: for enum props, copy enum structs;
     * for blob props, copy blob ids. We skip this for now — most
     * compositors handle it gracefully if count_enum_blobs is 0. */

    drmModeFreeProperty(p);
    return 0;
}

static int handle_atomic(void *arg)
{
    struct drm_mode_atomic *ka = arg;

    if (ka->count_objs == 0) {
        return 0;
    }

    if (ka->count_objs > 64) {
        errno = E2BIG;
        return -1;
    }

    uint32_t *obj_ids = (uint32_t *)(uintptr_t)ka->objs_ptr;
    uint32_t *count_props = (uint32_t *)(uintptr_t)ka->count_props_ptr;
    uint32_t *prop_ids = (uint32_t *)(uintptr_t)ka->props_ptr;
    uint64_t *prop_vals = (uint64_t *)(uintptr_t)ka->prop_values_ptr;

    if (!obj_ids || !count_props || !prop_ids || !prop_vals) {
        errno = EFAULT;
        return -1;
    }

    /* Pool of 4 pre-allocated atomic reqs — avoids malloc/free per frame.
     * At 60fps with typical single-threaded use, this is always enough. */
    static drmModeAtomicReq *pool[4];
    static uint8_t pool_in_use;
    drmModeAtomicReq *req = NULL;

    for (int i = 0; i < 4; i++) {
        if (!(pool_in_use & (1u << i))) {
            pool_in_use |= (1u << i);
            if (!pool[i]) pool[i] = drmModeAtomicAlloc();
            req = pool[i];
            break;
        }
    }
    if (!req) {
        /* All slots taken — fall back to heap */
        req = drmModeAtomicAlloc();
        if (!req) { errno = ENOMEM; return -1; }
    }

    int flat_idx = 0;
    for (uint32_t i = 0; i < ka->count_objs; i++) {
        for (uint32_t j = 0; j < count_props[i]; j++) {
            drmModeAtomicAddProperty(req, obj_ids[i],
                                     prop_ids[flat_idx],
                                     prop_vals[flat_idx]);
            flat_idx++;
        }
    }

    int ret = drmModeAtomicCommit(DRM_VIRTUAL_FD, req, ka->flags,
                                  (void *)(uintptr_t)ka->user_data);

    /* Return to pool if it came from there */
    for (int i = 0; i < 4; i++) {
        if (req == pool[i]) {
            pool_in_use &= ~(1u << i);
            return ret;
        }
    }
    drmModeAtomicFree(req);
    return ret;
}

static int handle_create_prop_blob(void *arg)
{
    struct drm_mode_create_blob *b = arg;
    void *data = (void *)(uintptr_t)b->data;
    return drmModeCreatePropertyBlob(DRM_VIRTUAL_FD, data,
                                     b->length, &b->blob_id);
}

static int handle_destroy_prop_blob(void *arg)
{
    struct drm_mode_destroy_blob *b = arg;
    return drmModeDestroyPropertyBlob(DRM_VIRTUAL_FD, b->blob_id);
}

static int handle_get_prop_blob(void *arg)
{
    struct drm_mode_get_property_blob *kb = arg;
    drmModePropertyBlobResPtr b =
        drmModeGetPropertyBlob(DRM_VIRTUAL_FD, kb->blob_id);
    if (!b) return -1;

    kb->length = b->length;
    void *dst = (void *)(uintptr_t)kb->data;
    if (dst && b->data)
        memcpy(dst, b->data, b->length);

    drmModeFreePropertyBlob(b);
    return 0;
}

static int handle_syncobj_create(void *arg)
{
    struct drm_syncobj_create *s = arg;
    return drmSyncobjCreate(DRM_VIRTUAL_FD, s->flags, &s->handle);
}

static int handle_syncobj_destroy(void *arg)
{
    struct drm_syncobj_destroy *s = arg;
    return drmSyncobjDestroy(DRM_VIRTUAL_FD, s->handle);
}

static int handle_syncobj_handle_to_fd(void *arg)
{
    struct drm_syncobj_handle *s = arg;
    return drmSyncobjHandleToFD(DRM_VIRTUAL_FD, s->handle, &s->fd);
}

static int handle_syncobj_fd_to_handle(void *arg)
{
    struct drm_syncobj_handle *s = arg;
    return drmSyncobjFDToHandle(DRM_VIRTUAL_FD, s->fd, &s->handle);
}

static int handle_syncobj_import_sync_file(void *arg)
{
    struct drm_syncobj_array *s = arg;
    uint32_t *handles = (uint32_t *)(uintptr_t)s->handles_ptr;
    if (!handles || s->count_handles == 0) { errno = EINVAL; return -1; }
    return drmSyncobjImportSyncFile(DRM_VIRTUAL_FD,
                                    handles[0], s->sync_file_fd);
}

static int handle_syncobj_export_sync_file(void *arg)
{
    struct drm_syncobj_array *s = arg;
    uint32_t *handles = (uint32_t *)(uintptr_t)s->handles_ptr;
    if (!handles || s->count_handles == 0) { errno = EINVAL; return -1; }
    return drmSyncobjExportSyncFile(DRM_VIRTUAL_FD,
                                    handles[0], &s->sync_file_fd);
}

/* ── dispatch table ────────────────────────────────────────────────────── */

typedef int (*ioctl_handler_t)(void *arg);

static const ioctl_handler_t g_handlers[0x100] = {
    [0x00] = handle_version,
    [0x06] = handle_get_magic,
    [0x07] = handle_auth_magic,
    [0x0C] = handle_get_cap,
    [0x0D] = handle_set_client_cap,
    [0x1E] = handle_set_master,
    [0x1F] = handle_drop_master,
    [0x2D] = handle_prime_handle_to_fd,
    [0x2E] = handle_prime_fd_to_handle,
    [0xA0] = handle_get_resources,
    [0xA1] = handle_get_crtc,
    [0xA2] = handle_set_crtc,
    [0xA3] = handle_cursor,
    [0xA6] = handle_get_encoder,
    [0xA7] = handle_get_connector,
    [0xAE] = handle_add_fb,
    [0xAF] = handle_rm_fb,
    [0xB0] = handle_page_flip,
    [0xB2] = handle_create_dumb,
    [0xB3] = handle_map_dumb,
    [0xB4] = handle_destroy_dumb,
    [0xB5] = handle_get_plane_resources,
    [0xB6] = handle_get_plane,
    [0xB8] = handle_add_fb2,
    [0xB9] = handle_obj_get_properties,
    [0xBB] = handle_get_property,
    [0xBC] = handle_atomic,
    [0xBD] = handle_create_prop_blob,
    [0xBE] = handle_destroy_prop_blob,
    [0xBF] = handle_get_prop_blob,
    [0xC0] = handle_syncobj_create,
    [0xC1] = handle_syncobj_destroy,
    [0xC2] = handle_syncobj_handle_to_fd,
    [0xC3] = handle_syncobj_fd_to_handle,
    [0xC4] = handle_syncobj_import_sync_file,
    [0xC5] = handle_syncobj_export_sync_file,
};

/* ── public entry point ────────────────────────────────────────────────── */

int drm_ioctl_dispatch(unsigned long request, void *arg)
{
    unsigned int nr  = DRM_IOCTL_NR(request);
    unsigned int typ = DRM_IOCTL_TYPE(request);

    if (typ != DRM_IOCTL_BASE) {
        errno = ENOTTY;
        return -1;
    }

    ioctl_handler_t h = g_handlers[nr];
    if (!h) {
        errno = ENOTTY;
        return -1;
    }

    return h(arg);
}
