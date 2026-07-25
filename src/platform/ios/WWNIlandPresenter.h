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

/// Launch one of the bundled in-process cube clients on a background thread; it
/// presents through this presenter. `clientId` is a Machines catalog id:
/// `kmscube` and `opengl-cube` render GLES through iland + ANGLE, `vkcube`
/// renders Vulkan through MoltenVK. All three drive the same iland virtual DRM.
/// Returns NO for an unknown id, or when the client's archive is absent.
- (BOOL)launchNestedIlandGpuClient:(NSString *)clientId
                             width:(int)width
                            height:(int)height;

/// Back-compat wrapper for `launchNestedIlandGpuClient:@"kmscube"`.
- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
