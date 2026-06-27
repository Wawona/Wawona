//
//  WWNIlandPresenter.h
//  Wawona — macOS
//
//  Mode A in-window present consumer for nested iland GL clients
//  (kmscube / es2gears / weston-simple-egl built against iland + ANGLE).
//
//  An iland GL client renders into IOSurface-backed GBM buffers; its DRM/KMS
//  page-flips are redirected (iland_drm_set_present_callback, see
//  dependencies/libs/iland/upstream/shims/drm/drm/include/iland_present.h) to a
//  callback in THIS process. WWNIlandPresenter imports the presented IOSurface
//  into a Metal texture and composites it onto a CAMetalLayer — entirely
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

/// Launch the in-process kmscube client on a background thread. It will present
/// through this presenter. Requires the app to be linked against libkmscube.a
/// (flake .#iland-gl-clients). Returns NO if the entry point is unavailable.
- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
