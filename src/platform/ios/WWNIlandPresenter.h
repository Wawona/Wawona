//
//  WWNIlandPresenter.h
//  Wawona. IOS
//
//  Mode A in-window present consumer for nested iland KMS/GBM GL clients
//  (kmscube / gbm-es2-demo). weston-simple-egl is a Wayland-EGL client of the
//  Wawona compositor (wl_egl_window + ANGLE GLES + linux-dmabuf). It does not
//  use this presenter.
//
//  A KMS/GBM client renders into IOSurface-backed GBM buffers; its DRM/KMS
//  page-flips are redirected (iland_drm_set_present_callback) to a callback in
//  THIS process. WWNIlandPresenter imports the presented IOSurface into a Metal
//  texture and composites it onto WWNCompositorView_ios's CAMetalLayer.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <IOSurface/IOSurfaceRef.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNIlandPresenter : NSObject

- (instancetype)initWithLayer:(CAMetalLayer *)layer
                       device:(nullable id<MTLDevice>)device;

- (void)invalidate;

/// Re-read layer bounds×scale into drawableSize + iland preferred DRM mode.
- (void)syncPreferredModeFromLayer;

/// Present a compositor-imported IOSurface through the same Metal texture cache
/// and pipeline as iland KMS. This does not complete a DRM page flip.
- (BOOL)presentCompositorIOSurface:(IOSurfaceRef)surface
                     bottomUpRows:(BOOL)bottomUpRows
                      contentRect:(CGRect)normalizedContentRect;

/// Launch one of the bundled in-process cube clients on a background thread; it
/// presents through this presenter. `clientId` is a Machines catalog id:
/// `kmscube` renders GLES through iland + ANGLE into the virtual DRM. Returns
/// NO for an unknown id, or when the archive is absent. `opengl-cube` and
/// `vkcube` are Wayland clients (IOSurface dmabuf winsys), not KMS hosts.
- (BOOL)launchNestedIlandGpuClient:(NSString *)clientId
                             width:(int)width
                            height:(int)height;

/// Client id currently running on the presenter's DRM thread, or nil.
- (nullable NSString *)runningClientId;

/// Back-compat wrapper for `launchNestedIlandGpuClient:@"kmscube"`.
- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
