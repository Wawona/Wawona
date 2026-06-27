#include <drm_linux.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void fill_pattern(uint32_t *buf, int w, int h, int pitch,
                         int frame, int nframes)
{
    float t = (float)frame / nframes;
    for (int y = 0; y < h; y++) {
        uint32_t *row = (uint32_t *)((uint8_t *)buf + y * pitch);
        for (int x = 0; x < w; x++) {
            float nx = (float)x / w;
            float ny = (float)y / h;
            uint8_t r = (uint8_t)((nx * 255) * (0.5f + 0.5f * t));
            uint8_t g = (uint8_t)((ny * 255) * (1.0f - 0.5f * t));
            uint8_t b = (uint8_t)(((1.0f - nx) * 128 + ny * 128) * (0.8f + 0.2f * t));
            row[x] = (uint32_t)r << 16 | (uint32_t)g << 8 | (uint32_t)b;
        }
    }
}

int main(void)
{
    printf("[drm_fullscreen] drmOpen …\n");
    int fd = drmOpen("virtual", NULL);
    if (fd < 0) { perror("drmOpen"); return 1; }
    printf("[drm_fullscreen] fd = %d\n", fd);

    uint64_t cap;
    if (drmGetCap(fd, DRM_CAP_DUMB_BUFFER, &cap) == 0)
        printf("[drm_fullscreen] DUMB_BUFFER = %llu\n", (unsigned long long)cap);
    if (drmGetCap(fd, DRM_CAP_PRIME, &cap) == 0)
        printf("[drm_fullscreen] PRIME = %llu\n", (unsigned long long)cap);

    printf("[drm_fullscreen] drmModeGetResources …\n");
    drmModeResPtr res = drmModeGetResources(fd);
    if (!res) { fprintf(stderr, "drmModeGetResources failed\n"); drmClose(fd); return 1; }
    printf("[drm_fullscreen]   %d CRTCs, %d connectors, %d encoders\n",
           res->count_crtcs, res->count_connectors, res->count_encoders);
    if (res->count_crtcs < 1 || res->count_connectors < 1) {
        fprintf(stderr, "not enough resources\n");
        drmModeFreeResources(res); drmClose(fd); return 1;
    }

    uint32_t crtc_id = res->crtcs[0];
    uint32_t conn_id = res->connectors[0];

    printf("[drm_fullscreen] drmModeGetConnector(%u) …\n", conn_id);
    drmModeConnectorPtr conn = drmModeGetConnector(fd, conn_id);
    if (!conn) { perror("drmModeGetConnector"); drmModeFreeResources(res); drmClose(fd); return 1; }
    printf("[drm_fullscreen]   type=%d, connected=%d, %d modes\n",
           conn->connector_type, conn->connection, conn->count_modes);
    if (conn->count_modes < 1) {
        fprintf(stderr, "no modes\n");
        drmModeFreeConnector(conn); drmModeFreeResources(res); drmClose(fd); return 1;
    }
    for (int i = 0; i < conn->count_modes && i < 3; i++)
        printf("[drm_fullscreen]   mode[%d]: %s %dx%d@%d\n", i,
               conn->modes[i].name,
               conn->modes[i].hdisplay, conn->modes[i].vdisplay,
               conn->modes[i].vrefresh);

    drmModeModeInfo mode = conn->modes[0];
    int dw = mode.hdisplay, dh = mode.vdisplay;

    if (res->count_encoders > 0) {
        drmModeEncoderPtr enc = drmModeGetEncoder(fd, res->encoders[0]);
        if (enc) {
            printf("[drm_fullscreen] encoder %u: crtc=%u possible=0x%x\n",
                   enc->encoder_id, enc->crtc_id, enc->possible_crtcs);
            drmModeFreeEncoder(enc);
        }
    }

    {
        drmModeCrtcPtr crtc = drmModeGetCrtc(fd, crtc_id);
        if (crtc) {
            printf("[drm_fullscreen] CRTC %u: fb=%u gamma=%u\n",
                   crtc->crtc_id, crtc->buffer_id, crtc->gamma_size);
            drmModeFreeCrtc(crtc);
        }
    }

    printf("[drm_fullscreen] drmModeCreateDumbBuffer(%dx%d) …\n", dw, dh);
    uint32_t handle, pitch;
    uint64_t size;
    if (drmModeCreateDumbBuffer(fd, dw, dh, 32, 0, &handle, &pitch, &size) < 0) {
        perror("drmModeCreateDumbBuffer");
        drmModeFreeConnector(conn); drmModeFreeResources(res); drmClose(fd); return 1;
    }
    printf("[drm_fullscreen]   handle=%u pitch=%u size=%llu\n",
           handle, pitch, (unsigned long long)size);

    printf("[drm_fullscreen] drmModeMapDumbBuffer …\n");
    uint64_t offset;
    if (drmModeMapDumbBuffer(fd, handle, &offset) < 0) {
        perror("drmModeMapDumbBuffer");
        drmModeDestroyDumbBuffer(fd, handle);
        drmModeFreeConnector(conn); drmModeFreeResources(res); drmClose(fd); return 1;
    }
    printf("[drm_fullscreen]   vaddr=0x%llx\n", (unsigned long long)offset);
    uint32_t *pixels = (uint32_t *)(uintptr_t)offset;

    printf("[drm_fullscreen] drmModeAddFB(%dx%d) …\n", dw, dh);
    uint32_t fb_id;
    if (drmModeAddFB(fd, dw, dh, 24, 32, pitch, handle, &fb_id) < 0) {
        perror("drmModeAddFB");
        drmModeDestroyDumbBuffer(fd, handle);
        drmModeFreeConnector(conn); drmModeFreeResources(res); drmClose(fd); return 1;
    }
    printf("[drm_fullscreen]   fb_id=%u\n", fb_id);

    {
        uint32_t conns[] = {conn_id};
        printf("[drm_fullscreen] drmModeSetCrtc(%u, %u, %s) …\n",
               crtc_id, fb_id, mode.name);
        int ret = drmModeSetCrtc(fd, crtc_id, fb_id, 0, 0, conns, 1, &mode);
        printf("[drm_fullscreen]   ret=%d\n", ret);
    }

    printf("[drm_fullscreen] page flip loop × 4 …\n");
    for (int f = 0; f < 4; f++) {
        fill_pattern(pixels, dw, dh, pitch, f, 4);
        int ret = drmModePageFlip(fd, crtc_id, fb_id,
                                  DRM_MODE_PAGE_FLIP_EVENT,
                                  (void *)(uintptr_t)(f + 1));
        if (ret < 0) {
            perror("drmModePageFlip");
            printf("[drm_fullscreen]   flip %d failed\n", f);
            break;
        }
        printf("[drm_fullscreen]   flip %d ok (tag=%lu)\n",
               f, (unsigned long)(f + 1));
        usleep(500000);
    }

    printf("[drm_fullscreen] drmModeRmFB …\n");
    drmModeRmFB(fd, fb_id);

    printf("[drm_fullscreen] drmModeDestroyDumbBuffer …\n");
    drmModeDestroyDumbBuffer(fd, handle);

    drmModeFreeConnector(conn);
    drmModeFreeResources(res);

    printf("[drm_fullscreen] drmClose …\n");
    drmClose(fd);

    printf("[drm_fullscreen] DONE\n");
    return 0;
}
