//
// WWNIomfbPresenter.m - iOS Mode B IOMobileFramebuffer present sink
//
// Linked only into WWN_MODE_B / Mode B schemes (TrollStore .tipa, Sileo .deb).
// Store IPA must never compile this file. Same IOSurface objects as Mode A
// Metal; this sink owns the panel instead of CAMetalLayer.
//
// Scaffolding: logs + no-op until entitlements + SPI are wired on device /
// vphone jb.

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>

#if defined(WWN_MODE_B) && WWN_MODE_B

BOOL WWNIomfbPresentIOSurface(uint32_t iosurfaceId, uint32_t width,
                              uint32_t height, uint32_t format) {
  (void)width;
  (void)height;
  (void)format;
  IOSurfaceRef surf = IOSurfaceLookup(iosurfaceId);
  if (!surf) {
    NSLog(@"[WawonaDmabuf] op=present os=ios sink=iomfb backing_id=%u "
          @"copy=cpu client=modeb lookup_failed",
          iosurfaceId);
    return NO;
  }
  CFRelease(surf);
  NSLog(@"[WawonaDmabuf] op=present os=ios sink=iomfb backing_id=%u "
        @"format=%u copy=zero client=modeb scaffolding",
        iosurfaceId, format);
  // TODO: IOMobileFramebufferGetMainDisplay → set layer surface → swap.
  return NO;
}

#else

BOOL WWNIomfbPresentIOSurface(uint32_t iosurfaceId, uint32_t width,
                              uint32_t height, uint32_t format) {
  (void)iosurfaceId;
  (void)width;
  (void)height;
  (void)format;
  return NO;
}

#endif
