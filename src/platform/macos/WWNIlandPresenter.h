//
//  WWNIlandPresenter.h
//  Wawona. MacOS
//
//  Mode A in-window present consumer for nested iland GL clients
//  (kmscube / es2gears / weston-simple-egl built against iland + ANGLE).
//
//  An iland GL client renders into IOSurface-backed GBM buffers; its DRM/KMS
//  page-flips are redirected (iland_drm_set_present_callback, see
//  dependencies/libs/iland/upstream/shims/drm/drm/include/iland_present.h) to a
//  callback in THIS process. WWNIlandPresenter imports the presented IOSurface
//  into a Metal texture and composites it onto a CAMetalLayer. Entirely
//  in-window, no framebufferd daemon, no Mach IPC, App-Store-safe.
//
//  Because the present callback is an in-process C function pointer, the GL
//  client must run inside Wawona's address space (a dedicated thread), not as a
//  separate process. See -launchNestedKmscubeWithWidth:height: .
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNIlandPresenter : NSObject

/// Create a presenter targeting `layer`. Registers the iland present callback so
/// subsequent client page-flips are composited into `layer`. Pass a device, or
/// nil to use the layer's device / the system default.
- (instancetype)initWithLayer:(CAMetalLayer *)layer
                       device:(nullable id<MTLDevice>)device;

/// Unregister the iland present callback. Safe to call multiple times.
- (void)invalidate;

/// Re-read the host layer geometry and republish it as the iland preferred mode.
/// Main thread only. It touches CALayer state the client's render thread must
/// not. Note this only reaches clients that (re-)enumerate DRM modes; a stock
/// KMS client such as kmscube fixes its framebuffer size at startup, and the
/// presenter letterboxes it for the rest of the session.
- (void)hostGeometryDidChange;

/// Launch a bundled in-process iland KMS client on a background thread; it
/// presents through this presenter. Supported ids: `kmscube`, `gbm-es2-demo`
/// (each has its own entry point. Never alias one to the other).
/// `opengl-cube` and `vkcube` are Wayland clients and go through the
/// compositor. Returns NO for an unknown id, absent archive, or when a
/// *different* client thread already owns this presenter.
- (BOOL)launchNestedIlandGpuClient:(NSString *)clientId
                             width:(int)width
                            height:(int)height;

/// Client id currently running on the presenter's DRM thread, or nil.
- (nullable NSString *)runningClientId;

/// Back-compat wrapper for `launchNestedIlandGpuClient:@"kmscube"`.
- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
