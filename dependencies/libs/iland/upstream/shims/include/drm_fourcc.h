#ifndef DRM_FOURCC_H
#define DRM_FOURCC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DRM_FORMAT_XRGB8888         0x34325258
#define DRM_FORMAT_ARGB8888         0x34325241
#define DRM_FORMAT_XBGR8888         0x34324258
#define DRM_FORMAT_ABGR8888         0x34324241
#define DRM_FORMAT_RGB565           0x36314752
#define DRM_FORMAT_XRGB2101010      0x30335258
#define DRM_FORMAT_ARGB2101010      0x30335241
#define DRM_FORMAT_XBGR2101010      0x30334258
#define DRM_FORMAT_ABGR2101010      0x30334241

#define DRM_FORMAT_INVALID          0
#define DRM_FORMAT_ABGR1555             0x35314241
#define DRM_FORMAT_ABGR16161616         0x38344241
#define DRM_FORMAT_ABGR16161616F        0x48344241
#define DRM_FORMAT_ABGR4444             0x32314241
#define DRM_FORMAT_ARGB1555             0x35315241
#define DRM_FORMAT_ARGB16161616         0x38345241
#define DRM_FORMAT_ARGB16161616F        0x48345241
#define DRM_FORMAT_ARGB4444             0x32315241
#define DRM_FORMAT_BGR565               0x36314742
#define DRM_FORMAT_BGR888               0x34324742
#define DRM_FORMAT_BGRA1010102          0x30334142
#define DRM_FORMAT_BGRA4444             0x32314142
#define DRM_FORMAT_BGRA5551             0x35314142
#define DRM_FORMAT_BGRA8888             0x34324142
#define DRM_FORMAT_BGRX1010102          0x30335842
#define DRM_FORMAT_BGRX4444             0x32315842
#define DRM_FORMAT_BGRX5551             0x35315842
#define DRM_FORMAT_AYUV                 0x56555941
#define DRM_FORMAT_BIG_ENDIAN           (1U << 31)
#define DRM_FORMAT_BGRX8888             0x34325842
#define DRM_FORMAT_GR1616               0x32335247
#define DRM_FORMAT_GR88                 0x38385247
#define DRM_FORMAT_NV12                 0x3231564E
#define DRM_FORMAT_NV15                 0x3531564E
#define DRM_FORMAT_NV16                 0x3631564E
#define DRM_FORMAT_NV20                 0x3032564E
#define DRM_FORMAT_NV21                 0x3132564E
#define DRM_FORMAT_NV24                 0x3432564E
#define DRM_FORMAT_NV30                 0x3033564E
#define DRM_FORMAT_NV42                 0x3234564E
#define DRM_FORMAT_NV61                 0x3136564E
#define DRM_FORMAT_P010                 0x30313050
#define DRM_FORMAT_P012                 0x32313050
#define DRM_FORMAT_P016                 0x36313050
#define DRM_FORMAT_P030                 0x30333050
#define DRM_FORMAT_R16                  0x20363152
#define DRM_FORMAT_R8                   0x20203852
#define DRM_FORMAT_RG1616               0x32334752
#define DRM_FORMAT_RG88                 0x38384752
#define DRM_FORMAT_RGB888               0x34324752
#define DRM_FORMAT_RGBA1010102          0x30334152
#define DRM_FORMAT_RGBA4444             0x32314152
#define DRM_FORMAT_RGBA5551             0x35314152
#define DRM_FORMAT_RGBA8888             0x34324152
#define DRM_FORMAT_RGBX1010102          0x30335852
#define DRM_FORMAT_RGBX4444             0x32315852
#define DRM_FORMAT_RGBX5551             0x35315852
#define DRM_FORMAT_RGBX8888             0x34325852
#define DRM_FORMAT_S010                 0x30313053
#define DRM_FORMAT_S012                 0x32313053
#define DRM_FORMAT_S016                 0x36313053
#define DRM_FORMAT_S210                 0x30313253
#define DRM_FORMAT_S212                 0x32313253
#define DRM_FORMAT_S216                 0x36313253
#define DRM_FORMAT_S410                 0x30313453
#define DRM_FORMAT_S412                 0x32313453
#define DRM_FORMAT_S416                 0x36313453
#define DRM_FORMAT_UYVY                 0x59565955
#define DRM_FORMAT_VYUY                 0x59555956
#define DRM_FORMAT_XBGR1555             0x35314258
#define DRM_FORMAT_XBGR16161616         0x38344258
#define DRM_FORMAT_XBGR16161616F        0x48344258
#define DRM_FORMAT_XBGR4444             0x32314258
#define DRM_FORMAT_XRGB1555             0x35315258
#define DRM_FORMAT_XRGB16161616         0x38345258
#define DRM_FORMAT_XRGB16161616F        0x48345258
#define DRM_FORMAT_XRGB4444             0x32315258
#define DRM_FORMAT_XYUV8888             0x56555958
#define DRM_FORMAT_YUV410               0x39305559
#define DRM_FORMAT_YUV411               0x31315559
#define DRM_FORMAT_YUV420               0x32315559
#define DRM_FORMAT_YUV420_10BIT         0x30314D59
#define DRM_FORMAT_YUV420_8BIT          0x20204D59
#define DRM_FORMAT_YUV422               0x36315559
#define DRM_FORMAT_YUV444               0x34325559
#define DRM_FORMAT_YUYV                 0x56595559
#define DRM_FORMAT_YVU410               0x39305659
#define DRM_FORMAT_YVU411               0x31315659
#define DRM_FORMAT_YVU420               0x32315659
#define DRM_FORMAT_YVU422               0x36315659
#define DRM_FORMAT_YVU444               0x34325659
#define DRM_FORMAT_YVYU                 0x55595659
#define DRM_FORMAT_MOD_LINEAR       0
#define DRM_FORMAT_MOD_INVALID      ((uint64_t)1 << 56)

#ifdef __cplusplus
}
#endif

#endif /* DRM_FOURCC_H */
