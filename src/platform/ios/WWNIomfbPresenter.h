//
// WWNIomfbPresenter.h - Mode B IOMobileFramebuffer present (TrollStore/Sileo)
//
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Present an IOSurface id on the Mode B own-display panel.
/// Returns true only on a real page-flip (`copy=zero`). Mode A builds always
/// return false. Never call from App Store UI paths.
BOOL WWNIomfbPresentIOSurface(uint32_t iosurfaceId, uint32_t width,
                              uint32_t height, uint32_t format);

#ifdef __cplusplus
}
#endif
