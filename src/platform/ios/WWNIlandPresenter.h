//
//  WWNIlandPresenter.h
//  Wawona — iOS
//
//  Mode A in-window present consumer for nested iland GL clients
//  (kmscube / weston-simple-egl built against iland + ANGLE).
//
//  An iland GL client renders into IOSurface-backed GBM buffers; its DRM/KMS
//  page-flips are redirected (iland_drm_set_present_callback) to a callback in
//  THIS process. WWNIlandPresenter imports the presented IOSurface into a Metal
//  texture and composites it onto WWNCompositorView_ios's CAMetalLayer.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNIlandPresenter : NSObject

- (instancetype)initWithLayer:(CAMetalLayer *)layer
                       device:(nullable id<MTLDevice>)device;

- (void)invalidate;

/// Re-read layer bounds×scale into drawableSize + iland preferred DRM mode.
- (void)syncPreferredModeFromLayer;

- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
