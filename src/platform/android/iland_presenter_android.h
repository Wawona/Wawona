#ifndef ILAND_PRESENTER_ANDROID_H
#define ILAND_PRESENTER_ANDROID_H

#include <stdint.h>
#include <android/hardware_buffer.h>

#ifdef __cplusplus
extern "C" {
#endif

void wwn_iland_presenter_android_init(void);
void wwn_iland_presenter_android_shutdown(void);
void wwn_iland_presenter_android_set_surface_size(uint32_t width, uint32_t height);

int wwn_iland_presenter_android_launch_kmscube(void);
int wwn_iland_presenter_android_is_active(void);
int wwn_iland_presenter_android_take_hardware_buffer(
    AHardwareBuffer **out_buffer, uint32_t *out_w, uint32_t *out_h,
    uint32_t *out_stride, uint32_t *out_fb_id);
void wwn_iland_presenter_android_frame_presented(uint32_t fb_id);

#ifdef __cplusplus
}
#endif

#endif
