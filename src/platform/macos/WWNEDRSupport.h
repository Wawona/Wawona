//
//  WWNEDRSupport.h
//  Wawona. Shared HDR/EDR layer configuration (header-only).
//
//  When the user enables "HDR / Color Operations" (ColorOperations pref),
//  CAMetalLayer presentation paths switch to extended-dynamic-range output:
//  float16 drawables in extended linear sRGB with EDR compositing requested.
//  On SDR-only displays the OS tone-maps back down, so this is safe to apply
//  whenever the preference is on.
//

#ifndef WWN_EDR_SUPPORT_H
#define WWN_EDR_SUPPORT_H

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <TargetConditionals.h>

/// Configure `layer` for EDR output when `hdrEnabled` is set and the OS
/// supports it. Returns YES when EDR was applied (callers must then match
/// their render-pipeline color attachment to `layer.pixelFormat`).
static inline BOOL WWNEDRConfigureMetalLayer(CAMetalLayer *layer,
                                             BOOL hdrEnabled) {
  if (!layer || !hdrEnabled) {
    return NO;
  }
#if TARGET_OS_WATCH || TARGET_OS_TV
  // CAMetalLayer.wantsExtendedDynamicRangeContent is unavailable on tvOS/watchOS.
  (void)layer;
  return NO;
#else
#if !TARGET_OS_OSX
  if (@available(iOS 16.0, visionOS 1.0, *)) {
    // wantsExtendedDynamicRangeContent exists on this OS.
  } else {
    return NO;
  }
#endif
  layer.wantsExtendedDynamicRangeContent = YES;
  layer.pixelFormat = MTLPixelFormatRGBA16Float;
  CGColorSpaceRef cs =
      CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
  if (cs) {
    layer.colorspace = cs;
    CGColorSpaceRelease(cs);
  }
  return YES;
#endif
}

#endif /* WWN_EDR_SUPPORT_H */
