#include <wayland-mac.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

int main(void) {
    int fd, ret;
    uint64_t cap;

    printf("[test_drm] open virtual device\n");
    fd = drmOpen("virtual", NULL);
    if (fd < 0) {
        printf("[test_drm] drmOpen failed\n");
        return 1;
    }

    printf("[test_drm] drmGetCap(PRIME)\n");
    ret = drmGetCap(fd, DRM_CAP_PRIME, &cap);
    if (ret == 0) printf("[test_drm]   PRIME = %llu\n", (unsigned long long)cap);

    printf("[test_drm] drmModeGetResources\n");
    drmModeResPtr res = drmModeGetResources(fd);
    if (!res) {
        printf("[test_drm]   FAILED\n");
        return 1;
    }
    printf("[test_drm]   %d CRTCs, %d connectors, %d encoders\n",
           res->count_crtcs, res->count_connectors, res->count_encoders);

    printf("[test_drm] drmModeGetConnector(1)\n");
    drmModeConnectorPtr conn = drmModeGetConnector(fd, res->connectors[0]);
    if (!conn) {
        printf("[test_drm]   FAILED\n");
        return 1;
    }
    printf("[test_drm]   type=%d, connection=%d, %d modes\n",
           conn->connector_type, conn->connection, conn->count_modes);

    for (int i = 0; i < conn->count_modes && i < 2; i++)
        printf("[test_drm]   mode[%d]: %s %dx%d@%d\n", i,
               conn->modes[i].name,
               conn->modes[i].hdisplay, conn->modes[i].vdisplay,
               conn->modes[i].vrefresh);

    printf("[test_drm] drmModeGetEncoder(1)\n");
    drmModeEncoderPtr enc = drmModeGetEncoder(fd, res->encoders[0]);
    if (enc) printf("[test_drm]   encoder_id=%d crtc_id=%d\n",
                    enc->encoder_id, enc->crtc_id);

    printf("[test_drm] drmModeCreateDumbBuffer(320, 240, 32)\n");
    uint32_t handle, pitch;
    uint64_t size;
    ret = drmModeCreateDumbBuffer(fd, 320, 240, 32, 0,
                                  &handle, &pitch, &size);
    if (ret != 0) {
        printf("[test_drm]   FAILED\n");
        return 1;
    }
    printf("[test_drm]   handle=%u pitch=%u size=%llu\n",
           handle, pitch, (unsigned long long)size);

    printf("[test_drm] drmModeMapDumbBuffer\n");
    uint64_t offset;
    ret = drmModeMapDumbBuffer(fd, handle, &offset);
    printf("[test_drm]   offset=0x%llx\n", (unsigned long long)offset);

    printf("[test_drm] writing test pattern\n");
    uint32_t *pixels = (uint32_t *)(uintptr_t)offset;
    for (int y = 0; y < 240; y++) {
        for (int x = 0; x < 320; x++) {
            uint8_t r = (uint8_t)(x * 255 / 319);
            uint8_t g = (uint8_t)(y * 255 / 239);
            uint8_t b = (uint8_t)((x + y) * 128 / 559);
            pixels[y * (pitch/4) + x] = (uint32_t)r << 16
                                       | (uint32_t)g << 8
                                       | (uint32_t)b;
        }
    }

    printf("[test_drm] drmModeAddFB(320, 240, 32)\n");
    uint32_t fb_id;
    ret = drmModeAddFB(fd, 320, 240, 24, 32, pitch, handle, &fb_id);
    if (ret != 0) {
        printf("[test_drm]   FAILED\n");
        return 1;
    }
    printf("[test_drm]   fb_id=%u\n", fb_id);

    printf("[test_drm] drmModeSetCrtc(1, fb_id, mode=1920x1080)\n");
    uint32_t conns[] = {1};
    drmModeModeInfo mode = conn->modes[0];
    ret = drmModeSetCrtc(fd, 1, fb_id, 0, 0, conns, 1, &mode);
    printf("[test_drm]   ret=%d\n", ret);

    printf("[test_drm] drmModeGetCrtc(1)\n");
    drmModeCrtcPtr crtc = drmModeGetCrtc(fd, 1);
    if (crtc) printf("[test_drm]   fb=%u %dx%d mode_valid=%d\n",
                     crtc->buffer_id, crtc->width, crtc->height,
                     crtc->mode_valid);

    printf("[test_drm] drmModePageFlip(1, fb_id)\n");
    ret = drmModePageFlip(fd, 1, fb_id, DRM_MODE_PAGE_FLIP_EVENT, NULL);
    printf("[test_drm]   ret=%d\n", ret);

    printf("[test_drm] drmModeRmFB\n");
    drmModeRmFB(fd, fb_id);

    printf("[test_drm] drmModeDestroyDumbBuffer\n");
    drmModeDestroyDumbBuffer(fd, handle);

    printf("[test_drm] free resources\n");
    drmModeFreeCrtc(crtc);
    drmModeFreeEncoder(enc);
    drmModeFreeConnector(conn);
    drmModeFreeResources(res);

    printf("[test_drm] drmClose\n");
    drmClose(fd);

    printf("[test_drm] PASSED\n");
    return 0;
}
