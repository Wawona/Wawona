//  WWNCompositorBridge.m
//  Direct C API - calling plain C exports from Rust

#import "WWNCompositorBridge.h"
#if !TARGET_OS_IPHONE
#import "WWNPopupWindow.h"
#endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import "WWNCompositorView_ios.h"
#import "WWNPopupHost.h"
#import "ui/Settings/WWNWaypipeRunner.h"
#endif
#import "../../util/WWNLog.h"
#import "WWNPlatformCallbacks.h"
#import "ui/Settings/WWNPreferencesManager.h"
#import "ui/Machines/WWNMachineProfileStore.h"
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import "WWNWindow.h"
#endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <IOSurface/IOSurfaceRef.h>
#import <QuartzCore/QuartzCore.h> // For CALayer
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <ApplicationServices/ApplicationServices.h> // CGSetDisplayTransferByTable, etc.
#endif
#include <stdatomic.h>
#include <math.h>
#include <string.h> // For strdup

static BOOL WWNForceSSDEnabled(void) {
#if TARGET_OS_TV
  // Fill-primary: Wayland CSD cannot stand alone on the TV. macOS keeps the
  // Settings toggle. iPhone still follows the pref (hostLocked fill is enough).
  return YES;
#else
  return [[WWNPreferencesManager sharedManager] forceServerSideDecorations];
#endif
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
static NSTimeInterval s_lastPointerMotionLog = 0;
static NSTimeInterval s_lastTouchMotionLog = 0;
static const NSTimeInterval kInputLogIntervalSec = 0.1;

extern int wwn_mobile_pending_roundtrips(void);
extern int wwn_mobile_active_clients(void);

static BOOL WWNShouldLogThrottledMotion(NSTimeInterval *lastLog) {
  NSTimeInterval now = CFAbsoluteTimeGetCurrent();
  if (now - *lastLog >= kInputLogIntervalSec) {
    *lastLog = now;
    return YES;
  }
  return NO;
}

/// One host window/scene per Wayland client on iPadOS + visionOS (matrix).
static BOOL WWNEnablePerWindowHosting(void) {
#if TARGET_OS_VISION
  return YES;
#elif TARGET_OS_IOS
  if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
    return NO;
  }
  return YES;
#else
  return NO;
#endif
}
#endif

// Plain C FFI functions exported from Rust with #[no_mangle]
extern void *WWNCoreNew(void);
extern bool WWNCoreStart(void *core, const char *socket_name);
extern bool WWNCoreStop(void *core);
extern bool WWNCoreIsRunning(const void *core);
extern char *WWNCoreGetSocketPath(const void *core);
extern char *WWNCoreGetSocketName(const void *core);
extern void WWNStringFree(char *s);
extern bool WWNCoreProcessEvents(void *core);
extern void WWNCoreSetOutputSize(void *core, uint32_t w, uint32_t h, float s);
extern void WWNCoreSetOutputGeometryForWindow(void *core, uint64_t window_id,
                                              uint32_t w, uint32_t h, float s);
extern void WWNCoreNotifyFramePresented(void *core, uint32_t surface_id,
                                        uint64_t buffer_id, uint32_t timestamp);
extern uint32_t WWNCoreGetTimestampMs(void *core);
extern void WWNCoreFree(void *core);
extern void WWNCoreInjectWindowResize(void *core, uint64_t window_id,
                                      uint32_t width, uint32_t height);
extern void WWNCoreBeginInteractiveResize(void *core, uint64_t window_id);
extern void WWNCoreEndInteractiveResize(void *core, uint64_t window_id,
                                        uint32_t width, uint32_t height);
extern void WWNCoreApplyHostWindowFullscreen(void *core, uint64_t window_id,
                                             bool fullscreen, uint32_t width,
                                             uint32_t height);
extern void WWNCoreApplyHostWindowMaximized(void *core, uint64_t window_id,
                                            bool maximized, uint32_t width,
                                            uint32_t height);
extern bool WWNCoreRequestWindowClose(void *core, uint64_t window_id);
extern bool WWNCoreForceDestroyHostWindow(void *core, uint64_t window_id);
extern bool WWNCoreNotifyPopupDismissed(void *core, uint64_t window_id);
extern void WWNCoreSetWindowActivated(void *core, uint64_t window_id,
                                      bool active);
extern void WWNCoreSetWindowActivatedSilent(void *core, uint64_t window_id,
                                            bool active);
extern void WWNCoreFlushClients(void *core);
extern uint32_t WWNCoreDisconnectAllClients(void *core);
extern void WWNCoreSetForceSSD(void *core, bool enabled);
extern void WWNCoreSetForceSSDForClientLaunch(void *core, bool enabled);
extern void WWNCoreSetFillsHostForClientLaunch(void *core, bool fills_host);
extern void WWNCoreSetWindowHostSceneIndependent(void *core, uint64_t window_id,
                                                 bool independent);

/// Bundled weston demos with a fixed preferred square (flower/smoke 200x200,
/// simple-shm/simple-egl 250x250). Must never receive host fill configures or
/// stretch presentation. OWL keeps Client authority, same as weston-flower.
///
/// Catalog ids (`weston-simple-egl`), xdg app_ids
/// (`org.freedesktop.weston.simple-egl`), and display titles (`Weston Simple
/// EGL`) must all match. Hyphen vs space is why simple-egl followed host
/// resize while flower/smoke did not (`"flower"` is a substring of
/// `"Weston Flower"`; `"simple-egl"` is not a substring of `"Weston Simple EGL"`).
static NSString *WWNNormWestonDemoKey(NSString *value) {
  if (value.length == 0) {
    return @"";
  }
  NSString *lower = value.lowercaseString;
  NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@" _"];
  NSArray<NSString *> *parts = [lower componentsSeparatedByCharactersInSet:sep];
  NSMutableArray<NSString *> *kept = [NSMutableArray array];
  for (NSString *p in parts) {
    if (p.length > 0) {
      [kept addObject:p];
    }
  }
  return [kept componentsJoinedByString:@"-"];
}

BOOL WWNWestonDemoPrefersFixedSquare(NSString *clientId, NSString *title) {
  NSString *idNorm = WWNNormWestonDemoKey(clientId);
  if (idNorm.length > 0) {
    static NSSet<NSString *> *fixedClients;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      fixedClients = [NSSet setWithArray:@[
        @"weston-smoke",
        @"smoke",
        @"weston-flower",
        @"flower",
        @"weston-simple-shm",
        @"simple-shm",
        @"weston-simple-egl",
        @"simple-egl",
        @"org.freedesktop.weston.simple-egl",
        @"org.freedesktop.weston.simple-shm",
        @"weston-clickdot",
        @"clickdot",
        @"weston-eventdemo",
        @"eventdemo",
      ]];
    });
    if ([fixedClients containsObject:idNorm] ||
        [idNorm hasSuffix:@"simple-egl"] || [idNorm hasSuffix:@"simple-shm"] ||
        [idNorm hasSuffix:@"weston-flower"] || [idNorm hasSuffix:@"weston-smoke"] ||
        [idNorm hasSuffix:@"weston-clickdot"] ||
        [idNorm hasSuffix:@"weston-eventdemo"]) {
      return YES;
    }
  }
  NSString *tNorm = WWNNormWestonDemoKey(title);
  if (tNorm.length == 0) {
    return NO;
  }
  return [tNorm containsString:@"simple-shm"] ||
         [tNorm containsString:@"simple-egl"] ||
         [tNorm containsString:@"flower"] || [tNorm containsString:@"smoke"] ||
         [tNorm containsString:@"clickdot"] ||
         [tNorm containsString:@"eventdemo"];
}

/// Terminals and nested compositors fill the host. Demos stay client-preferred
/// (`configure(0,0)`). Nested weston/niri size their output from the first
/// non-zero xdg configure; a 0x0 seed leaves a blank parent window.
static BOOL WWNBundledClientFillsHost(NSString *clientId) {
  if (clientId.length == 0) {
    return NO;
  }
  return [clientId isEqualToString:@"weston-terminal"] ||
         [clientId isEqualToString:@"wayland-terminal"] ||
         [clientId isEqualToString:@"foot"] ||
         [clientId isEqualToString:@"niri"] ||
         [clientId isEqualToString:@"weston"];
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static BOOL WWNTitleIndicatesNestedCompositor(NSString *title) {
  NSString *t = title.lowercaseString;
  if (t.length == 0) {
    return NO;
  }
  if ([t isEqualToString:@"weston compositor"] ||
      [t hasPrefix:@"weston compositor -"]) {
    return YES;
  }
  if ([t isEqualToString:@"niri"] || [t hasPrefix:@"niri -"]) {
    return YES;
  }
  return NO;
}

static NSString *WWNResolveActiveMachineBundledClientId(void) {
  NSString *mid = [WWNMachineProfileStore activeMachineId];
  WWNMachineProfile *profile =
      mid.length > 0 ? [WWNMachineProfileStore profileById:mid] : nil;
  if (!profile ||
      [profile.type isEqualToString:kWWNMachineTypeContainer] ||
      [profile.type isEqualToString:kWWNMachineTypeVirtualMachine] ||
      [profile.type isEqualToString:kWWNMachineTypeSSHWaypipe] ||
      [profile.type isEqualToString:kWWNMachineTypeSSHTerminal]) {
    return nil;
  }
  id runtimeBundled = profile.runtimeOverrides[@"bundledAppID"];
  if ([runtimeBundled isKindOfClass:[NSString class]] &&
      [(NSString *)runtimeBundled length] > 0) {
    return (NSString *)runtimeBundled;
  }
  id settingsNative = profile.settingsOverrides[@"NativeClientId"];
  if ([settingsNative isKindOfClass:[NSString class]] &&
      [(NSString *)settingsNative length] > 0) {
    return (NSString *)settingsNative;
  }
  return nil;
}
#endif

#if TARGET_OS_IPHONE
NSString *const WWNClientWindowSceneActivityType =
    @"com.aspauldingcode.Wawona.clientWindow";
NSString *const WWNClientWindowSceneWindowIdKey = @"wwn.windowId";

/// Synthetic host window id for iland DRM/KMS clients (kmscube) that have no
/// Wayland toplevel. Used only to request a dedicated UIWindowScene on
/// iPadOS / visionOS so the Metal plate is not buried under Machines UI.
static const uint64_t kWWNIlandHostSceneWindowId = 0x574E4E494C414E44ULL; // "WNNILAND"

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
static BOOL WWNIosBundledClientPrefersFixedSize(NSString *clientId) {
  return WWNWestonDemoPrefersFixedSquare(clientId, nil);
}
static BOOL WWNIosBundledClientFillsHost(NSString *clientId) {
  return WWNBundledClientFillsHost(clientId);
}
#endif

static NSString *WWNIosResolveBundledClientIdForWindow(WWNCompositorBridge *bridge,
                                                       uint64_t windowId) {
  NSString *clientId =
      [WWNWaypipeRunner sharedRunner].activeIOSBundledClientId;
  if (clientId.length == 0) {
    NSString *mid = [WWNMachineProfileStore activeMachineId];
    WWNMachineProfile *profile =
        mid.length > 0 ? [WWNMachineProfileStore profileById:mid] : nil;
    id runtimeBundled = profile.runtimeOverrides[@"bundledAppID"];
    id settingsNative = profile.settingsOverrides[@"NativeClientId"];
    if ([runtimeBundled isKindOfClass:[NSString class]] &&
        [(NSString *)runtimeBundled length] > 0) {
      clientId = (NSString *)runtimeBundled;
    } else if ([settingsNative isKindOfClass:[NSString class]]) {
      clientId = (NSString *)settingsNative;
    }
  }
  (void)bridge;
  (void)windowId;
  return clientId;
}
#endif
extern void WWNCoreSetSafeAreaInsets(void *core, int32_t top, int32_t right,
                                     int32_t bottom, int32_t left);
extern void WWNCoreInjectPointerAxis(void *core, uint64_t window_id,
                                     uint32_t axis, double value,
                                     uint32_t timestamp_ms);
extern void WWNCoreTextInputCommit(void *core, const char *text);
extern void WWNCoreTextInputPreedit(void *core, const char *text,
                                    int32_t cursor_begin, int32_t cursor_end);
extern void WWNCoreTextInputDeleteSurrounding(void *core, uint32_t before,
                                              uint32_t after);
extern int WWNCoreTextInputIsEnabled(void *core);
extern int WWNCoreTextEntryWanted(void *core);
extern void WWNCoreTextInputGetContentType(void *core, uint32_t *out_hint,
                                           uint32_t *out_purpose);
extern void WWNCoreTextInputGetCursorRect(void *core, int32_t *out_x,
                                          int32_t *out_y, int32_t *out_width,
                                          int32_t *out_height);
extern CBufferData *WWNCorePopPendingBuffer(void *core);
extern void WWNBufferDataFree(CBufferData *data);
extern IOSurfaceRef IOSurfaceLookup(uint32_t csid);
extern void WWNCoreSetClipboardText(void *core, const char *text);
extern char *WWNCorePollClipboardText(void *core);
extern void WWNStringFree(char *s);

// Screencopy (zwlr_screencopy)
typedef struct {
  uint64_t capture_id;
  void *ptr;
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  size_t size;
} CScreencopyRequest;
extern CScreencopyRequest WWNCoreGetPendingScreencopy(void *core);
extern void WWNCoreScreencopyDone(void *core, uint64_t capture_id);
extern void WWNCoreScreencopyFailed(void *core, uint64_t capture_id);

// Image copy capture (ext-image-copy-capture-v1, same structure as screencopy)
extern CScreencopyRequest WWNCoreGetPendingImageCopyCapture(void *core);
extern void WWNCoreImageCopyCaptureDone(void *core, uint64_t capture_id);
extern void WWNCoreImageCopyCaptureFailed(void *core, uint64_t capture_id);

// Gamma control (zwlr_gamma_control_manager_v1)
typedef struct {
  uint32_t output_id;
  uint32_t size;
  const uint16_t *red;
  const uint16_t *green;
  const uint16_t *blue;
} CGammaApply;
extern CGammaApply *WWNCorePopPendingGammaApply(void *core);
extern void WWNGammaApplyFree(CGammaApply *apply);
extern uint32_t WWNCorePopPendingGammaRestore(void *core);

// Scene Graph types
typedef struct CRenderNode {
  uint64_t node_id;
  uint64_t window_id;
  uint32_t surface_id;
  uint64_t buffer_id;
  float x;
  float y;
  float width;
  float height;
  float scale;
  float opacity;
  float corner_radius;
  bool is_opaque;
  uint32_t buffer_width;
  uint32_t buffer_height;
  uint32_t buffer_stride;
  uint32_t buffer_format;
  uint32_t iosurface_id;
  float anchor_output_x;
  float anchor_output_y;
  float content_rect_x;
  float content_rect_y;
  float content_rect_w;
  float content_rect_h;
} CRenderNode;

typedef struct CRenderScene {
  CRenderNode *nodes;
  size_t count;
  size_t capacity;
  // Cursor state (Wayland client cursor surface)
  bool has_cursor;
  float cursor_x;
  float cursor_y;
  float cursor_hotspot_x;
  float cursor_hotspot_y;
  uint32_t cursor_surface_id;
  uint64_t cursor_buffer_id;
  uint32_t cursor_width;
  uint32_t cursor_height;
  uint32_t cursor_stride;
  uint32_t cursor_format;
  uint32_t cursor_iosurface_id;
} CRenderScene;

typedef struct {
  uint32_t surface_id;
  uint64_t buffer_id;
} WWNPresentedBuffer;

extern CRenderScene *WWNCoreGetRenderScene(void *core);
extern void WWNRenderSceneFree(CRenderScene *scene);

// MARK: - Cursor Shape Mapping

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static NSCursor *NSCursorFromWaylandShape(uint32_t shape) {
  switch (shape) {
  case 1:  return [NSCursor arrowCursor];
  case 2:  return [NSCursor arrowCursor];           // context-menu
  case 3:  return [NSCursor arrowCursor];           // help
  case 4:  return [NSCursor pointingHandCursor];    // pointer
  case 5:  return [NSCursor arrowCursor];           // progress
  case 6:  return [NSCursor arrowCursor];           // wait
  case 7:  return [NSCursor crosshairCursor];       // cell
  case 8:  return [NSCursor crosshairCursor];       // crosshair
  case 9:  return [NSCursor IBeamCursor];           // text
  case 10: return [NSCursor IBeamCursor];           // vertical-text
  case 11: return [NSCursor arrowCursor];           // alias
  case 12: return [NSCursor dragCopyCursor];        // copy
  case 13: return [NSCursor arrowCursor];           // move
  case 14: return [NSCursor operationNotAllowedCursor]; // no-drop
  case 15: return [NSCursor operationNotAllowedCursor]; // not-allowed
  case 16: return [NSCursor openHandCursor];        // grab
  case 17: return [NSCursor closedHandCursor];      // grabbing
  case 18: return [NSCursor resizeRightCursor];     // e-resize
  case 19: return [NSCursor resizeUpCursor];        // n-resize
  case 20: return [NSCursor arrowCursor];           // ne-resize
  case 21: return [NSCursor arrowCursor];           // nw-resize
  case 22: return [NSCursor resizeDownCursor];      // s-resize
  case 23: return [NSCursor arrowCursor];           // se-resize
  case 24: return [NSCursor arrowCursor];           // sw-resize
  case 25: return [NSCursor resizeLeftCursor];      // w-resize
  case 26: return [NSCursor resizeLeftRightCursor]; // ew-resize
  case 27: return [NSCursor resizeUpDownCursor];    // ns-resize
  case 28: return [NSCursor arrowCursor];           // nesw-resize
  case 29: return [NSCursor arrowCursor];           // nwse-resize
  case 30: return [NSCursor resizeLeftRightCursor]; // col-resize
  case 31: return [NSCursor resizeUpDownCursor];    // row-resize
  case 32: return [NSCursor arrowCursor];           // all-scroll
  case 33: return [NSCursor arrowCursor];           // zoom-in
  case 34: return [NSCursor arrowCursor];           // zoom-out
  default: return [NSCursor arrowCursor];
  }
}
#endif

static inline NSString *WWNBufferCacheKey(uint32_t surface_id,
                                          uint64_t buffer_id) {
  // wl_buffer ids are client-scoped in Wayland, so buffer_id alone collides
  // across clients. Include surface_id to keep cache entries disambiguated.
  return [NSString stringWithFormat:@"%u:%llu", surface_id, buffer_id];
}

// Wayland buffers are top-down and so is CoreAnimation, but OpenGL renders
// bottom-up, so a GPU client's IOSurface arrives upside down. Its wl_buffer
// says so via the dmabuf Y_INVERT flag, which cannot reach here. We resolve
// the surface by id and never see the buffer's flags. So iland's Wayland-EGL
// winsys also marks the IOSurface itself. A mirrored 3D scene looks like broken
// depth testing rather than a flip, which makes this worth being explicit about.
static BOOL WWNBufferIsBottomUp(IOSurfaceRef surf) {
  if (!surf) {
    return NO;
  }
  CFTypeRef value = IOSurfaceCopyValue(surf, CFSTR("WWNBottomUp"));
  BOOL bottomUp = value == kCFBooleanTrue;
  if (value) {
    CFRelease(value);
  }
  return bottomUp;
}

/// Bake an IOSurface into a CGImage. UIKit cannot composite IOSurface as
/// CALayer.contents. AppKit can, but a Y-scale transform under
/// geometryFlipped looks like inverted X+Y, and CPU-mapping the IOSurface
/// does not change the GPU plane CALayer samples. A flipped CGImage is the
/// same present path as wl_shm and is upright on both families.
static CGImageRef WWNCreateCGImageFromIOSurface(IOSurfaceRef surf,
                                                BOOL flipVertical) {
  if (!surf) {
    return NULL;
  }
  size_t w = IOSurfaceGetWidth(surf);
  size_t h = IOSurfaceGetHeight(surf);
  size_t bpr = IOSurfaceGetBytesPerRow(surf);
  if (w == 0 || h == 0 || bpr < 4) {
    return NULL;
  }

  // Success is 0 (IOReturn). Do not use kIOReturnSuccess. IOKit is missing on
  // the iOS family SDKs.
  if (IOSurfaceLock(surf, kIOSurfaceLockReadOnly, NULL) != 0) {
    return NULL;
  }
  const uint8_t *base = (const uint8_t *)IOSurfaceGetBaseAddress(surf);
  if (!base) {
    IOSurfaceUnlock(surf, kIOSurfaceLockReadOnly, NULL);
    return NULL;
  }

  size_t nbytes = bpr * h;
  CFMutableDataRef data =
      CFDataCreateMutable(kCFAllocatorDefault, (CFIndex)nbytes);
  if (!data) {
    IOSurfaceUnlock(surf, kIOSurfaceLockReadOnly, NULL);
    return NULL;
  }
  CFDataSetLength(data, (CFIndex)nbytes);
  uint8_t *dst = CFDataGetMutableBytePtr(data);
  if (flipVertical) {
    for (size_t y = 0; y < h; y++) {
      memcpy(dst + y * bpr, base + (h - 1 - y) * bpr, bpr);
    }
  } else {
    memcpy(dst, base, nbytes);
  }
  IOSurfaceUnlock(surf, kIOSurfaceLockReadOnly, NULL);

  // Force opaque alpha. ANGLE/Metal IOSurfaces sometimes land with A=0 while
  // RGB is populated; UIKit then composites a fully transparent CGImage over
  // the black host window → "blank OpenGL window".
  for (size_t y = 0; y < h; y++) {
    uint8_t *row = dst + y * bpr;
    for (size_t x = 0; x < w; x++) {
      row[x * 4 + 3] = 0xFF;
    }
  }

  static int s_iosurfPxLog = 0;
  if (s_iosurfPxLog < 4) {
    s_iosurfPxLog++;
    WWNLog("CACHE",
           @"IOSurface→CGImage %zux%zu flip=%d px0=B%d,G%d,R%d,A%d "
           @"(forced opaque)",
           w, h, (int)flipVertical, (int)dst[0], (int)dst[1], (int)dst[2],
           (int)dst[3]);
  }

  CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
  CFRelease(data);
  if (!provider) {
    return NULL;
  }
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  // ANGLE / Metal IOSurfaces are BGRA8. Same little-endian layout as wl_shm
  // ARGB8888 (B,G,R,A in memory).
  CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little |
                            (CGBitmapInfo)kCGImageAlphaPremultipliedFirst;
  CGImageRef image =
      CGImageCreate(w, h, 8, 32, bpr, colorSpace, bitmapInfo, provider, NULL,
                    false, kCGRenderingIntentDefault);
  CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(provider);
  return image;
}

/// Drop stale SHM/IOSurface cache entries for a surface, keeping only `keepKey`.
/// Required on macOS too: without this, every frame accumulates in `_bufferCache`
/// until the session stops (looks like a session memleak).
static void WWNPruneBufferCacheForSurface(NSMutableDictionary *cache,
                                          uint32_t surfaceId,
                                          NSString *keepKey) {
  NSString *prefix =
      [NSString stringWithFormat:@"%u:", surfaceId];
  for (id key in [cache.allKeys copy]) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *cacheKey = (NSString *)key;
    if ([cacheKey hasPrefix:prefix] && ![cacheKey isEqualToString:keepKey]) {
      [cache removeObjectForKey:cacheKey];
    }
  }
}

// Coalesce AppKit live-resize bursts before emitting Wayland configure events.
// Slightly slower cadence reduces nested-compositor configure thrash on macOS.
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
static const NSTimeInterval kWWNResizeDebounceSeconds = 0.010;
#else
static const NSTimeInterval kWWNResizeDebounceSeconds = 0.040;
#endif

NSNotificationName const WWNNativeClientWillLaunchNotification =
    @"WWNNativeClientWillLaunchNotification";
NSNotificationName const WWNClientMinimizeRequestedNotification =
    @"WWNClientMinimizeRequestedNotification";
NSNotificationName const WWNClientFocusRequestedNotification =
    @"WWNClientFocusRequestedNotification";
NSNotificationName const WWNHostWindowsDidChangeNotification =
    @"WWNHostWindowsDidChangeNotification";

static uint32_t WWNBridgeFrameTimestampMs(void *core) {
  if (core) {
    return WWNCoreGetTimestampMs(core);
  }
  return (uint32_t)(CACurrentMediaTime() * 1000.0);
}

// Marks blocks running on _compositorThread (reentrancy + pump routing).
static void *const kWWNCompositorQueueKey = (void *)&kWWNCompositorQueueKey;

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// Close host NSWindows without racing AppKit transform animations. Immediate
// close after toggleFullScreen (or during an in-flight CA commit) can crash in
// _NSWindowTransformAnimation dealloc when Stop tears down a live client.
static void WWNFinishHostWindowTeardown(NSWindow *window) {
  if (!window) {
    return;
  }
  if ([window respondsToSelector:@selector(setAnimationBehavior:)]) {
    window.animationBehavior = NSWindowAnimationBehaviorNone;
  }
  [window orderOut:nil];
  dispatch_async(dispatch_get_main_queue(), ^{
    [window close];
  });
}

static void WWNCloseHostWindowSafely(NSWindow *window) {
  if (!window) {
    return;
  }
  if ((window.styleMask & NSWindowStyleMaskFullScreen) == 0) {
    WWNFinishHostWindowTeardown(window);
    return;
  }
  __weak NSWindow *weakWindow = window;
  __block id token = nil;
  void (^finishOnce)(void) = ^{
    if (!token) {
      return;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:token];
    token = nil;
    WWNFinishHostWindowTeardown(weakWindow);
  };
  token = [[NSNotificationCenter defaultCenter]
      addObserverForName:NSWindowDidExitFullScreenNotification
                    object:window
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(__unused NSNotification *note) {
                  finishOnce();
                }];
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        if (token) {
          WWNLog("BRIDGE",
                 @"Fullscreen exit timed out during teardown. Forcing close");
          finishOnce();
        }
      });
  [window toggleFullScreen:nil];
}
#endif

@interface WWNCompositorThread : NSThread
@property (nonatomic, strong) NSRunLoop *runLoop;
@end

@implementation WWNCompositorThread
- (void)main {
    @autoreleasepool {
        self.runLoop = [NSRunLoop currentRunLoop];
        [self.runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        while (!self.isCancelled) {
            [self.runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    }
}
@end

@implementation WWNCompositorBridge {
  void *_rustCore;
  NSTimer *_eventTimer;
  CADisplayLink *_displayLink;
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // Pause 60Hz ticks while the user drags/resizes any AppKit window
  // (Machines SwiftUI host included). Tracking-mode alone is not enough:
  // some move paths stay in default mode and still feel laggy at 60Hz FFI.
  BOOL _hostWindowInteractionPaused;
  id _hostWindowMouseUpMonitor;
#endif

  // Serial queue for all Rust FFI calls. Keeps heavy compositor work
  // (Wayland dispatch, buffer processing, scene graph building) off the
  // main thread so UIKit/AppKit stays responsive.
  WWNCompositorThread *_compositorThread;

  // Guards against frame pile-up: when YES, a compositor tick is in
  // flight and the next CADisplayLink/NSTimer callback is skipped.
  // Atomic because it is written on _compositorThread and read on the
  // main thread; without barriers, ARM64 weak ordering can cause the
  // main thread to read a stale YES and skip ticks indefinitely.
  atomic_bool _compositorBusy;

  // Clipboard <-> NSPasteboard/UIPasteboard bridge. `_lastPasteboardChangeCount`
  // tracks the pasteboard's `changeCount` as of our last read *or* write, so
  // that a write we perform ourselves (native text a client just copied)
  // never gets read back and bounced into the compositor as if the user had
  // copied it natively, and vice versa. See -_syncClipboardWithPasteboard.
  NSInteger _lastPasteboardChangeCount;
  BOOL _pasteboardChangeCountInitialized;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // Last polled text_entry_wanted (committed TI or terminal synthesis).
  BOOL _lastTextEntryWanted;
  BOOL _lastTextEntryWantedInitialized;
  uint32_t _lastTextInputPurpose;
#endif

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSMutableDictionary<NSNumber *, id> *_windows;
  NSMutableDictionary<NSNumber *, id> *_popups;
  NSMutableDictionary<NSNumber *, UIWindow *> *_iosHostWindows;
  NSMutableSet<NSNumber *> *_hostLockedWindowIds;
  BOOL _iosPerWindowHostingEnabled;
  // iPadOS / visionOS multi-window (#120): client toplevel views awaiting their
  // dedicated UIWindowScene. handleWindowCreated stages the view here and
  // requests a new scene carrying the window id; the scene delegate claims the
  // view in -scene:willConnectToSession: once the OS actually connects the
  // scene, so the client gets its own host window/scene (not stacked onto the
  // primary scene).
  NSMutableDictionary<NSNumber *, UIView *> *_pendingSceneClientViews;
  /// Window ids with a pending xdg_toplevel.close grace period (iOS family).
  NSMutableSet<NSNumber *> *_iosHostCloseDeferred;
  /// Last host-reported xdg maximized/fullscreen bits (fill-primary iOS family).
  NSMutableDictionary<NSNumber *, NSNumber *> *_iosHostMaximizedByWindowId;
  NSMutableDictionary<NSNumber *, NSNumber *> *_iosHostFullscreenByWindowId;
  // Host compositor view for iland Metal demos (kmscube) / nested DRM when
  // no Wayland toplevel exists yet. containerView is a plain UIView.
  WWNCompositorView_ios *_ilandHostView;
#else
  NSMutableDictionary<NSNumber *, id>
      *_windows; /* WWNWindow toplevel or WWNView popup */
  NSMutableDictionary<NSNumber *, id> *_popups;
#endif
  // Scene Graph caches
  NSMutableDictionary<id<NSCopying>, id> *_bufferCache;
  // Cache keys whose IOSurface is bottom-up (see WWNBufferIsBottomUp). Decided
  // once at import so the per-frame path stays a set lookup.
  NSMutableSet<NSString *> *_bottomUpBuffers;
  NSMutableDictionary<NSNumber *, CALayer *> *_surfaceLayers;
  NSMutableDictionary<NSNumber *, NSNumber *> *_latestBufferBySurface;
  NSMutableDictionary<NSNumber *, NSNumber *> *_lastPresentedBufferBySurface;
  NSMutableDictionary<NSNumber *, NSNumber *> *_staleSceneSelectionsBySurface;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSMutableDictionary<NSNumber *, NSNumber *> *_presentGenerationBySurface;
  uint64_t _waylandPresentGeneration;
#endif
  // Which machine owns each toplevel window id. Available on ALL platforms:
  // macOS uses it for per-machine window raise; iOS/iPadOS/visionOS use it for
  // per-machine focus / minimize / hide when multiple machines run
  // concurrently (#84 / concurrent machines).
  NSMutableDictionary<NSNumber *, NSString *> *_windowOwnerMachineIdByWindowId;

  // Per-window resize coalescing.  Each window gets its own "latest"
  // dimensions so concurrent resizes of different windows never collide.
  // Key = window_id (NSNumber wrapping uint64_t).
  NSMutableDictionary<NSNumber *, NSValue *> *_latestResizeDims;
  NSMutableDictionary<NSNumber *, NSValue *> *_sentResizeDims;
  NSMutableSet<NSNumber *> *_resizeInFlightWindows;

  // Windows whose AppKit frame has been authoritatively sized at least once
  // (either via an initial injected resize, or the client's first committed
  // buffer). Until a window is in this set, its first ClientCommit size is
  // always trusted. The host defers the initial xdg_toplevel configure to
  // (0, 0), so the client's first commit is its real preferred size for
  // every Wayland client, not just a known allowlist.
  NSMutableSet<NSNumber *> *_windowsWithInitialSizeSynced;

  // Windows already auto-shown after their first presented buffer. The render
  // loop must never re-order-front (or steal key status from) a window on
  // subsequent frames. Focus changes come only from explicit activation.
  NSMutableSet<NSNumber *> *_windowsAutoShownAfterFirstBuffer;

  // Cursor policy: runtime detection from wp_cursor_shape or wl_pointer.set_cursor
  BOOL _clientWantsCursorRendered;
  uint64_t _lastCursorBufferId;
  uint32_t _lastCursorSurfaceId;

  // Output-size coalescing (same pattern)
  BOOL _outputResizeInFlight;
  uint32_t _latestOutputW;
  uint32_t _latestOutputH;
  float _latestOutputScale;
  uint32_t _sentOutputW;
  uint32_t _sentOutputH;
  float _sentOutputScale;
  // Once a live host surface has seeded wl_output, never invent phone portrait.
  BOOL _hasObservedRealOutputSize;

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // Saved gamma for restore (nested compositor may not use; main display only)
  CGGammaValue *_savedGammaRed;
  CGGammaValue *_savedGammaGreen;
  CGGammaValue *_savedGammaBlue;
  uint32_t _savedGammaSize;
  // Host window for iland Metal demos (kmscube) when no Wayland toplevel exists.
  NSWindow *_ilandHostWindow;
#endif
}

+ (instancetype)sharedBridge {
  static WWNCompositorBridge *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[WWNCompositorBridge alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    WWNConfigureBundledRuntimeEnvIfNeeded();
    WWNLog("BRIDGE", @"Creating WWNCore via direct C API");
    _rustCore = WWNCoreNew();

    if (!_rustCore) {
      WWNLog("BRIDGE", @"Error: Failed to create WWNCore");
      return nil;
    }

    // High-priority serial queue for all Rust compositor FFI work.
    // USER_INTERACTIVE QoS ensures low-latency event processing while
    // keeping the main thread free for UI.
    _compositorThread = [[WWNCompositorThread alloc] init];
    [_compositorThread setName:@"com.wawona.compositor"];
    [_compositorThread setQualityOfService:NSQualityOfServiceUserInteractive];
    [_compositorThread start];

    WWNLog("BRIDGE", @"WWNCore created successfully via C API!");
    _windows = [NSMutableDictionary dictionary];
    _popups = [NSMutableDictionary dictionary];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    _iosHostWindows = [NSMutableDictionary dictionary];
    _pendingSceneClientViews = [NSMutableDictionary dictionary];
    _iosHostCloseDeferred = [NSMutableSet set];
    _iosHostMaximizedByWindowId = [NSMutableDictionary dictionary];
    _iosHostFullscreenByWindowId = [NSMutableDictionary dictionary];
    _hostLockedWindowIds = [NSMutableSet set];
    _iosPerWindowHostingEnabled = WWNEnablePerWindowHosting();
    WWNLog("BRIDGE", @"iOS/vision per-window hosting %@", _iosPerWindowHostingEnabled ? @"enabled" : @"disabled");
#endif
    _bufferCache = [NSMutableDictionary dictionary];
    _bottomUpBuffers = [NSMutableSet set];
    _surfaceLayers = [NSMutableDictionary dictionary];
    _latestBufferBySurface = [NSMutableDictionary dictionary];
    _lastPresentedBufferBySurface = [NSMutableDictionary dictionary];
    _staleSceneSelectionsBySurface = [NSMutableDictionary dictionary];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    _presentGenerationBySurface = [NSMutableDictionary dictionary];
    _waylandPresentGeneration = 0;
#endif
    _windowOwnerMachineIdByWindowId = [NSMutableDictionary dictionary];
    _latestResizeDims = [NSMutableDictionary dictionary];
    _sentResizeDims = [NSMutableDictionary dictionary];
    _resizeInFlightWindows = [NSMutableSet set];
    _windowsWithInitialSizeSynced = [NSMutableSet set];
    _windowsAutoShownAfterFirstBuffer = [NSMutableSet set];
    [self setForceSSD:WWNForceSSDEnabled()];
    // SwiftUI MachineSettings / WawonaPreferences write Force SSD to defaults
    // and post this notification. ObjC WWNPreferences only observes defaults
    // after its window is opened. Without this, Force SSD toggles never reach
    // Rust and weston stays borderless (no macOS SSD chrome / resize controls).
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_forceSSDPreferenceChanged:)
               name:kWWNForceSSDChangedNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_forceSSDUserDefaultsChanged:)
               name:NSUserDefaultsDidChangeNotification
             object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  if (_rustCore) {
    WWNCoreFree(_rustCore);
  }
}

- (void)_forceSSDPreferenceChanged:(NSNotification *)notification {
  (void)notification;
  [self setForceSSD:WWNForceSSDEnabled()];
}

- (void)_forceSSDUserDefaultsChanged:(NSNotification *)notification {
  (void)notification;
  // Cover Swift paths that write ForceServerSideDecorations / wawona.pref.forceSSD
  // without posting kWWNForceSSDChangedNotification.
  static BOOL sLastForceSSD = NO;
  static BOOL sHasForceSSDSample = NO;
  BOOL enabled = WWNForceSSDEnabled();
  if (!sHasForceSSDSample || sLastForceSSD != enabled) {
    sHasForceSSDSample = YES;
    sLastForceSSD = enabled;
    [self setForceSSD:enabled];
  }
}

// MARK: - Lifecycle

// MARK: - Lifecycle

- (void)_setupRuntimeEnvironmentWithSocketName:(NSString *)socketName {
  // 1. Set XDG_RUNTIME_DIR to a well-known, stable directory
  // On macOS, use /tmp/wawona-<uid> so clients in other terminals can find it.
  // On iOS, use a short shared runtime dir (see WWNPreferencesManager).
  NSString *runtimeDir;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  runtimeDir = [WWNPreferencesManager preferredSharedRuntimeDir];
#else
  // macOS: use /tmp/wawona-<uid> matching the client wrapper scripts in
  // flake.nix
  uid_t uid = getuid();
  runtimeDir = [NSString stringWithFormat:@"/tmp/wawona-%u", uid];
#endif

  // Ensure it exists with restricted permissions
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *dirError = nil;
  [fm createDirectoryAtPath:runtimeDir
      withIntermediateDirectories:YES
                       attributes:@{NSFilePosixPermissions : @0700}
                            error:&dirError];
  if (dirError) {
    WWNLog("BRIDGE", @"Warning: Could not create runtime dir %@: %@",
           runtimeDir, dirError);
  }

  // Important: overwrite=1 to ensure Rust sees the new path
  setenv("XDG_RUNTIME_DIR", [runtimeDir UTF8String], 1);
  WWNLog("BRIDGE", @"Configured XDG_RUNTIME_DIR: %@", runtimeDir);

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
  // iOS has no /etc/xdg or ~/.config. weston-desktop-shell parses weston.ini
  // via open_config_file() which only searches XDG_CONFIG_HOME, HOME/.config,
  // and XDG_CONFIG_DIRS. Never cwd. Without HOME the client gets NULL config
  // and crashes in weston_config_section_get_bool(NULL, ...).
  if (!getenv("HOME")) {
    setenv("HOME", [runtimeDir UTF8String], 1);
    WWNLog("BRIDGE", @"Configured HOME: %s", runtimeDir.UTF8String);
  }
#endif

  // 2. Cleanup stale socket files
  // If the app crashed, the socket file might still exist, causing
  // "Address in use"
  NSString *sockName = socketName ?: @"wayland-0";
  NSString *lockName = [sockName stringByAppendingString:@".lock"];

  NSArray *filesToRemove = @[ sockName, lockName ];

  for (NSString *filename in filesToRemove) {
    NSString *filePath = [runtimeDir stringByAppendingPathComponent:filename];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
      NSError *error = nil;
      [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
      if (error) {
        WWNLog("BRIDGE", @"Warning: Failed to remove stale file %@: %@",
               filePath, error);
      } else {
        WWNLog("BRIDGE", @"Cleaned up stale file: %@", filePath);
      }
    }
  }
}

- (BOOL)startWithSocketName:(NSString *)socketName {
  WWNConfigureBundledRuntimeEnvIfNeeded();
  [self _setupRuntimeEnvironmentWithSocketName:socketName];

  if (!_rustCore) {
    WWNLog("BRIDGE", @"No Rust core");
    return NO;
  }

  const char *name = socketName ? [socketName UTF8String] : NULL;
  WWNLog("BRIDGE", @"Starting compositor...");

  __block bool success = false;
  if (_compositorThread) {
    // Ensure any pre-start configuration enqueued via _dispatchToRust
    // (e.g. setOutputWidth/setForceSSD from main.m) is applied before start.
    [self _dispatchSyncToCompositor:^{
      success = WWNCoreStart(self->_rustCore, name);
    }];
  } else {
    success = WWNCoreStart(_rustCore, name);
  }

  if (success) {
    // Re-apply after start: init may have raced, and Swift prefs can change
    // between WWNCoreNew and WWNCoreStart. decoration_policy must match the
    // Force SSD toggle before the first client connects.
    [self setForceSSD:WWNForceSSDEnabled()];

    // Export WAYLAND_DISPLAY so child processes and logs can reference it
    NSString *displayName = socketName ?: @"wayland-0";
    setenv("WAYLAND_DISPLAY", [displayName UTF8String], 1);

    char *socketPath = WWNCoreGetSocketPath(_rustCore);
    if (socketPath) {
      WWNLog("BRIDGE", @"Compositor started. Socket: %s", socketPath);
      WWNLog("BRIDGE", @"Connect clients with:");
      WWNLog("BRIDGE", @"  export XDG_RUNTIME_DIR=%s",
             getenv("XDG_RUNTIME_DIR"));
      WWNLog("BRIDGE", @"  export WAYLAND_DISPLAY=%s",
             [displayName UTF8String]);
      free(socketPath);
    } else {
      WWNLog("BRIDGE", @"Compositor started successfully!");
    }

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Use CADisplayLink on the main thread for smooth animation pacing.
    _displayLink =
        [CADisplayLink displayLinkWithTarget:self
                                    selector:@selector(onDisplayLink:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                       forMode:NSRunLoopCommonModes];

    // Observer lifecycle to pause/resume
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationWillResignActive)
               name:UIApplicationWillResignActiveNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationDidBecomeActive)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];
#else
    // macOS: NSTimer at ~60fps for frame pacing.
    // Must run in CommonModes (includes NSEventTrackingRunLoopMode) so Wayland
    // client windows keep presenting while the user moves or live-resizes them.
    // Pausing ticks until mouse-up freezes the surface mid-drag. Forbidden by
    // wawona-host-wm-verification (live resize must stream presents mid-drag).
    // Machines / non-Wayland chrome still opts out via
    // _hostWindowInteractionPaused (see _installHostWindowInteractionPause).
    _eventTimer = [NSTimer timerWithTimeInterval:0.016
                                          target:self
                                        selector:@selector(onTimerTick:)
                                        userInfo:nil
                                         repeats:YES];
    _eventTimer.tolerance = 0.004;
    [[NSRunLoop mainRunLoop] addTimer:_eventTimer
                              forMode:NSRunLoopCommonModes];
    [self _installHostWindowInteractionPause];
    WWNLog("BRIDGE",
           @"Using NSTimer for frame pacing (60fps, common runloop modes)");
#endif

  } else {
    WWNLog("BRIDGE", @"Error: Start failed");
  }

  return success;
}

- (void)stop {
  WWNLog("BRIDGE", @"Stopping compositor bridge...");

  // 1. Stop timers first. No new ticks will be scheduled after this.
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if (_displayLink) {
    [_displayLink invalidate];
    _displayLink = nil;
  }
  [[NSNotificationCenter defaultCenter] removeObserver:self];
#else
  if (_displayLink) {
    [_displayLink invalidate];
    _displayLink = nil;
  }
  if (_eventTimer) {
    [_eventTimer invalidate];
    _eventTimer = nil;
  }
  [self _removeHostWindowInteractionPause];
#endif

  // 2. Drain the compositor queue: wait for any in-flight tick to finish,
  //    then stop the Rust compositor.  dispatch_sync is safe here because
  //    the in-flight tick only uses dispatch_async to bounce back to main
  //    (no deadlock. The async block will simply run after we return).
  if (_rustCore && _compositorThread) {
    dispatch_semaphore_t stopSem = dispatch_semaphore_create(0);
    __block bool stopped = false;
    [self _dispatchAsyncToCompositor:^{
      if (self->_rustCore) {
        WWNCoreStop(self->_rustCore);
        self->_rustCore = NULL;
        stopped = true;
        WWNLog("BRIDGE", @"Compositor stopped on compositor queue");
      }
      dispatch_semaphore_signal(stopSem);
    }];
    dispatch_semaphore_wait(
        stopSem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
    if (!stopped && _rustCore) {
      WWNLog("BRIDGE", @"Compositor stop timed out. Forcing teardown");
      WWNCoreStop(_rustCore);
      _rustCore = NULL;
    }
  } else if (_rustCore) {
    WWNCoreStop(_rustCore);
    _rustCore = NULL;
    WWNLog("BRIDGE", @"Compositor stopped");
  }

  // 3. Close all windows gracefully (main thread UI work)
  NSUInteger windowCount = [_windows count];
  if (windowCount > 0) {
    WWNLog("BRIDGE", @"Closing %lu window(s)...", (unsigned long)windowCount);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    for (NSNumber *key in [_windows allKeys]) {
      WWNWindow *window = [_windows objectForKey:key];
      if ([window isKindOfClass:[WWNWindow class]]) {
        window.suppressCompositorCallbacks = YES;
        [window cancelPendingHostCloseEscalation];
      }
      [window setDelegate:nil];
      WWNCloseHostWindowSafely(window);
    }
#endif
    [_windows removeAllObjects];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    for (NSNumber *key in [_iosHostWindows allKeys]) {
      UIWindow *window = _iosHostWindows[key];
      window.hidden = YES;
      window.rootViewController = nil;
      [_iosHostWindows removeObjectForKey:key];
    }
#endif
  }

  [_bufferCache removeAllObjects];
  [_surfaceLayers removeAllObjects];
  [_latestBufferBySurface removeAllObjects];
  [_lastPresentedBufferBySurface removeAllObjects];
  [_staleSceneSelectionsBySurface removeAllObjects];
  [_windowOwnerMachineIdByWindowId removeAllObjects];
  atomic_store(&_compositorBusy, false);
  [_latestResizeDims removeAllObjects];
  [_sentResizeDims removeAllObjects];
  [_resizeInFlightWindows removeAllObjects];
  _outputResizeInFlight = NO;
  _sentOutputW = _sentOutputH = 0;
}

- (BOOL)isRunning {
  return _rustCore ? WWNCoreIsRunning(_rustCore) : NO;
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (NSData *)captureCurrentSessionThumbnailPNGData {
  NSWindow *targetWindow = nil;
  for (NSNumber *key in [_windows allKeys]) {
    id candidate = [_windows objectForKey:key];
    if (![candidate isKindOfClass:[WWNWindow class]]) {
      continue;
    }
    NSWindow *window = (NSWindow *)candidate;
    if (window.isVisible) {
      targetWindow = window;
      break;
    }
  }
  if (!targetWindow) {
    for (NSNumber *key in [_windows allKeys]) {
      id candidate = [_windows objectForKey:key];
      if ([candidate isKindOfClass:[WWNWindow class]]) {
        targetWindow = (NSWindow *)candidate;
        break;
      }
    }
  }
  if (!targetWindow) {
    return nil;
  }

  NSView *contentView = targetWindow.contentView;
  if (!contentView) {
    return nil;
  }
  NSRect bounds = contentView.bounds;
  if (bounds.size.width < 1 || bounds.size.height < 1) {
    return nil;
  }
  NSBitmapImageRep *rep =
      [contentView bitmapImageRepForCachingDisplayInRect:bounds];
  if (!rep) {
    return nil;
  }
  [contentView cacheDisplayInRect:bounds toBitmapImageRep:rep];
  return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

- (BOOL)focusClientWindows {
  NSMutableArray<NSWindow *> *clientWindows = [NSMutableArray array];
  for (NSNumber *key in [_windows allKeys]) {
    id candidate = [_windows objectForKey:key];
    if ([candidate isKindOfClass:[WWNWindow class]]) {
      [clientWindows addObject:(NSWindow *)candidate];
    }
  }
  if (clientWindows.count == 0) {
    return NO;
  }

  [NSApp activateIgnoringOtherApps:YES];
  for (NSWindow *window in clientWindows) {
    if (window.isMiniaturized) {
      [window deminiaturize:nil];
    }
    [window orderFront:nil];
  }
  [[clientWindows firstObject] makeKeyAndOrderFront:nil];
  return YES;
}

- (BOOL)focusClientWindowsForMachineId:(NSString *)machineId {
  if (machineId.length == 0) {
    return [self focusClientWindows];
  }
  NSMutableArray<NSWindow *> *clientWindows = [NSMutableArray array];
  for (NSNumber *key in [_windows allKeys]) {
    id candidate = [_windows objectForKey:key];
    if (![candidate isKindOfClass:[WWNWindow class]]) {
      continue;
    }
    NSString *ownerId = _windowOwnerMachineIdByWindowId[key];
    if (ownerId.length > 0 && [ownerId isEqualToString:machineId]) {
      [clientWindows addObject:(NSWindow *)candidate];
    }
  }
  if (clientWindows.count == 0) {
    // Do not fall back to focusing every client window. That steals focus
    // from other machines when this profile has no windows yet (or its
    // windows were closed). Caller can retry after the client maps a surface.
    return NO;
  }

  [NSApp activateIgnoringOtherApps:YES];
  for (NSWindow *window in clientWindows) {
    if (window.isMiniaturized) {
      [window deminiaturize:nil];
    }
    [window orderFront:nil];
  }
  [[clientWindows firstObject] makeKeyAndOrderFront:nil];
  return YES;
}
#endif

- (NSString *)socketPath {
  if (!_rustCore)
    return @"";

  char *path = WWNCoreGetSocketPath(_rustCore);
  if (!path)
    return @"";

  NSString *result = [NSString stringWithUTF8String:path];
  WWNStringFree(path);
  return result ?: @"";
}

- (NSString *)socketName {
  if (!_rustCore)
    return @"";

  char *name = WWNCoreGetSocketName(_rustCore);
  if (!name)
    return @"";

  NSString *result = [NSString stringWithUTF8String:name];
  WWNStringFree(name);
  return result ?: @"";
}

// MARK: - Event Processing

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR

- (void)applicationWillResignActive {
  WWNLog("BRIDGE", @"App resigning active - pausing display link");
  _displayLink.paused = YES;
}

- (void)applicationDidBecomeActive {
  WWNLog("BRIDGE", @"App became active - resuming display link");
  _displayLink.paused = NO;
}

#endif

/// Shared compositor tick implementation.
/// Bridges the Wayland `wl_data_device` clipboard selection to/from the
/// native pasteboard (NSPasteboard on macOS, UIPasteboard on iOS/iPadOS/
/// tvOS/visionOS) so e.g. right-click Copy in weston-terminal reaches the
/// system clipboard and vice versa. Must run on the main thread (pasteboard
/// access is only officially supported there). Called once per compositor
/// tick from the main-queue half of -_compositorTick.
///
/// `_lastPasteboardChangeCount` is updated after *every* read or write we
/// perform, so a change we caused ourselves is never mistaken for a native
/// copy on the next tick (which would otherwise bounce straight back into
/// the compositor as a spurious "client" selection, and vice versa).
- (void)_syncClipboardWithPasteboard {
  if (!_rustCore) {
    return;
  }
  if (![[WWNPreferencesManager sharedManager] universalClipboardEnabled]) {
    return;
  }
#if TARGET_OS_TV
  // UIPasteboard is unavailable on tvOS; skip native clipboard bridge.
  return;
#endif
#if !TARGET_OS_TV
  // A client (e.g. weston-terminal) copied text. Push it to the native
  // pasteboard.
  char *clientText = WWNCorePollClipboardText(_rustCore);
  if (clientText) {
    NSString *text = [NSString stringWithUTF8String:clientText];
    WWNStringFree(clientText);
    if (text) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
      pasteboard.string = text;
#else
      NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
      [pasteboard clearContents];
      [pasteboard setString:text forType:NSPasteboardTypeString];
#endif
      _lastPasteboardChangeCount = pasteboard.changeCount;
      _pasteboardChangeCountInitialized = YES;
      return;
    }
  }

#if TARGET_OS_SIMULATOR
  // Reading UIPasteboard (even changeCount) pops
  // "Wawona would like to paste from CoreSimulatorBridge" and blocks the
  // main runloop. Nested EGL init (ANGLE Metal) then sits in eglInitialize
  // until that alert is dismissed. Skip inbound host paste in the simulator.
  _pasteboardChangeCountInitialized = YES;
  return;
#endif

#if TARGET_OS_IPHONE
  UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
#else
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
#endif
  NSInteger changeCount = pasteboard.changeCount;

  // Native copy (another app, or the user pasting into a text field outside
  // Wawona). Push it into the compositor so clients can paste it.
  if (!_pasteboardChangeCountInitialized) {
    // First tick: just observe, don't push whatever was already on the
    // pasteboard before Wawona launched into every freshly-focused client.
    _lastPasteboardChangeCount = changeCount;
    _pasteboardChangeCountInitialized = YES;
    return;
  }
  if (changeCount == _lastPasteboardChangeCount) {
    return;
  }
  _lastPasteboardChangeCount = changeCount;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *nativeText = pasteboard.string;
#else
  NSString *nativeText = [pasteboard stringForType:NSPasteboardTypeString];
#endif
  if (nativeText.length > 0) {
    WWNCoreSetClipboardText(_rustCore, nativeText.UTF8String);
  }
#endif /* !TARGET_OS_TV */
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
/// Drive host soft keyboard from `text_entry_wanted` (committed TI-v3 enable
/// OR allowlisted terminal keyboard focus). Accessory bar stays independent.
/// tvOS: manual toggle only. Do not auto-Expand from synthesis/TI.
- (void)_syncHostKeyboardWithTextInput {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_TV
  return;
#else
  BOOL wanted = WWNCoreTextEntryWanted(_rustCore) != 0;
  uint32_t hint = 0;
  uint32_t purpose = 0;
  WWNCoreTextInputGetContentType(_rustCore, &hint, &purpose);

  BOOL wantedChanged = !_lastTextEntryWantedInitialized ||
                       wanted != _lastTextEntryWanted;
  BOOL purposeChanged = _lastTextEntryWantedInitialized &&
                        purpose != _lastTextInputPurpose;
  if (!wantedChanged && !purposeChanged) {
    return;
  }
  _lastTextEntryWanted = wanted;
  _lastTextEntryWantedInitialized = YES;
  _lastTextInputPurpose = purpose;

  WWNCompositorView_ios *focusView = nil;
  for (NSNumber *key in self->_windows) {
    UIView *hostView = self->_windows[key];
    if ([hostView isKindOfClass:[WWNCompositorView_ios class]]) {
      focusView = (WWNCompositorView_ios *)hostView;
      if (hostView.window.isKeyWindow || hostView.isFirstResponder) {
        break;
      }
    }
  }
  if (!focusView) {
    return;
  }

  [focusView applyTextInputContentPurpose:purpose];
  if (wantedChanged) {
    [focusView applyHostKeyboardForTextInputEnabled:wanted];
  }
#endif
}
#endif

/// Called from CADisplayLink (iOS) or NSTimer (macOS).  The callback fires
/// on the main thread but we immediately dispatch the heavy Rust work to
/// _compositorThread, then bounce lightweight UI updates back to main.
- (void)_compositorTick {
  if (!_rustCore || atomic_load(&_compositorBusy)) {
    return;
  }
  atomic_store(&_compositorBusy, true);

  [self _dispatchAsyncToCompositor:^{
    // Guard: compositor may have been stopped between dispatch and execution
    if (!self->_rustCore) {
      atomic_store(&self->_compositorBusy, false);
      return;
    }

    // === Compositor Queue: heavy Rust FFI work ===

    // 1. Dispatch Wayland protocol events (accept connections, process
    //    client requests, build scene graph updates). This is the most
    //    expensive call and the primary reason we moved off main thread.
    if (!WWNCoreIsRunning(self->_rustCore)) {
      dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store(&self->_compositorBusy, false);
      });
      return;
    }
    bool processed = WWNCoreProcessEvents(self->_rustCore);
    if (!processed) {
      static CFAbsoluteTime s_lastTickSkipLog = 0;
      static NSUInteger s_tickSkipCount = 0;
      s_tickSkipCount++;
      CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
      if (now - s_lastTickSkipLog >= 2.0) {
        WWNLog("TICK",
               @"Compositor tick skipped (%lu times). Event loop not ready "
               @"(see [FFI] ProcessEvents logs)",
               (unsigned long)s_tickSkipCount);
        s_lastTickSkipLog = now;
        s_tickSkipCount = 0;
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store(&self->_compositorBusy, false);
      });
      return;
    }

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (wwn_mobile_pending_roundtrips() > 0 ||
        wwn_mobile_active_clients() > 0) {
      for (int pump = 0; pump < 4; pump++) {
        WWNCoreProcessEvents(self->_rustCore);
        WWNCoreFlushClients(self->_rustCore);
      }
    }
#endif

    // 2. Collect window-lifecycle events from Rust (cheap pops from a Vec)
    NSMutableArray *windowEvents = [NSMutableArray array];
    CWindowEvent *evt;
    while ((evt = WWNCorePopWindowEvent(self->_rustCore)) != NULL) {
      [windowEvents addObject:[NSValue valueWithPointer:evt]];
    }
    if (windowEvents.count > 0) {
      WWNLog("TICK", @"Collected %lu window event(s) this tick",
             (unsigned long)windowEvents.count);
    }

    // 3. Process pending buffers: create CGImages / lookup IOSurfaces and
    //    tell Rust the frame has been presented so it can release or reuse
    //    the buffer.  Image creation from SHM data is CPU-bound work that
    //    benefits from running off main thread.
    CBufferData *buffer;
    NSUInteger poppedBufferCount = 0;
    NSMutableArray<NSValue *> *presentedBuffers = [NSMutableArray array];
    while ((buffer = WWNCorePopPendingBuffer(self->_rustCore)) != NULL) {
      poppedBufferCount++;
      [self cacheBuffer:buffer];
      WWNPresentedBuffer presented = {
          .surface_id = buffer->surface_id,
          .buffer_id = buffer->buffer_id,
      };
      [presentedBuffers addObject:[NSValue valueWithBytes:&presented
                                                 objCType:@encode(WWNPresentedBuffer)]];
      WWNBufferDataFree(buffer);
    }

    // 3b. Flush protocol events generated during ProcessEvents (step 1).
    //     Frame-presented callbacks are emitted later on the main queue after
    //     scene/layer application. Flushing only when poppedBufferCount > 0
    //     would leave frame_done events stranded when a commit was processed
    //     but its buffer couldn't be popped (e.g. window not yet created,
    //     DMA-BUF type, SHM mapping failure).  For in-process waypipe on
    //     iOS this stalls the entire remote frame pipeline.
    WWNCoreFlushClients(self->_rustCore);

    // 4. Build the render scene graph (scene-graph traversal + buffer
    //    info lookups happen inside Rust; the returned CRenderScene is a
    //    self-contained snapshot safe to consume on any thread).
    CRenderScene *scene = WWNCoreGetRenderScene(self->_rustCore);
    if (!scene && (windowEvents.count > 0 || poppedBufferCount > 0)) {
      WWNLog("TICK",
             @"GetRenderScene returned NULL (events=%lu, buffers=%lu)",
             (unsigned long)windowEvents.count, (unsigned long)poppedBufferCount);
    }
    {
      static NSUInteger sPrevPoppedCount = 0;
      static size_t sPrevSceneCount = 0;
      static NSUInteger sPrevCacheSize = 0;
      size_t sc = scene ? scene->count : 0;
      NSUInteger cs = self->_bufferCache.count;
      if (poppedBufferCount != sPrevPoppedCount || sc != sPrevSceneCount ||
          cs != sPrevCacheSize) {
        WWNLog("TICK",
               @"Buffers popped: %lu, scene nodes: %zu, cache size: %lu",
               (unsigned long)poppedBufferCount, sc, (unsigned long)cs);
        sPrevPoppedCount = poppedBufferCount;
        sPrevSceneCount = sc;
        sPrevCacheSize = cs;
      }
    }

    // === Main Queue: lightweight UI updates ===
    // NOTE: _compositorBusy is reset at the END of this main-queue block,
    // NOT here on the compositor queue.  Resetting here would allow the
    // next tick's [self cacheBuffer:] to write _bufferCache concurrently
    // with updateLayerForNode: reading it. A data race on
    // NSMutableDictionary that causes visual flashing.
    dispatch_async(dispatch_get_main_queue(), ^{
      // Apply window events (create/destroy views, update titles)
      for (NSValue *val in windowEvents) {
        CWindowEvent *event = [val pointerValue];
        @try {
          [self _dispatchWindowEvent:event];
        } @catch (NSException *exception) {
          WWNLog("TICK",
                 @"Exception applying window event type=%llu win=%llu: %@ (%@)",
                 event->event_type, event->window_id, exception.name,
                 exception.reason);
        }
        WWNWindowEventFree(event);
      }

      // Bridge the Wayland clipboard selection <-> native pasteboard.
      [self _syncClipboardWithPasteboard];

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      // Show/hide host soft keyboard when clients Enable/Disable text-input-v3.
      [self _syncHostKeyboardWithTextInput];
#endif

      // Apply render scene (update CALayer geometry and contents)
      if (scene) {
        @try {
          for (size_t i = 0; i < scene->count; i++) {
            [self updateLayerForNode:&scene->nodes[i]];
          }

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
          // Forward cursor rendering info to all iOS window views
          [self _updateCursorFromScene:scene];
#else
          // Convert Wayland bitmap cursor to NSCursor on macOS
          [self _applyBitmapCursorFromScene:scene];
#endif
        } @catch (NSException *exception) {
          WWNLog("TICK", @"Exception applying render scene: %@ (%@)",
                 exception.name, exception.reason);
        }
        WWNRenderSceneFree(scene);
      }

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
          // Nudge UIKit to pick up layer.contents updates on the frame view.
          if (presentedBuffers.count > 0) {
            for (NSNumber *key in self->_windows) {
              UIView *hostView = self->_windows[key];
              if ([hostView isKindOfClass:[WWNCompositorView_ios class]]) {
                WWNCompositorView_ios *iosView = (WWNCompositorView_ios *)hostView;
                [iosView setNeedsDisplay];
              }
            }
          }
#else
      // WWNView uses NSViewLayerContentsRedrawNever; AppKit only picks up
      // child CALayer.contents updates when the view is marked dirty.
      if (presentedBuffers.count > 0) {
        [self _invalidateMacSurfaceHostViews];
      }
#endif

      // Acknowledge wl_surface.frame/buffer release only after scene/layer
      // updates have consumed this tick's buffers.
      if (presentedBuffers.count > 0 && self->_rustCore) {
        uint32_t ts = WWNBridgeFrameTimestampMs(self->_rustCore);
        for (NSValue *val in presentedBuffers) {
          WWNPresentedBuffer presented = {0};
          [val getValue:&presented];
          [self notifyFramePresentedForSurface:presented.surface_id
                                        buffer:presented.buffer_id
                                     timestamp:ts];
        }
        [self _dispatchToRust:^{
          WWNCoreFlushClients(self->_rustCore);
        }];
      }

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
      // Screencopy: capture window and write to client buffer
      if (!self->_rustCore) {
        WWNLog("TICK", @"Rust core became NULL before post-scene tasks");
      }
      CScreencopyRequest screencopy =
          WWNCoreGetPendingScreencopy(self->_rustCore);
      if (screencopy.capture_id != 0 && screencopy.ptr != NULL &&
          screencopy.width > 0 && screencopy.height > 0) {
        [self _fulfillScreencopy:&screencopy];
      }
      // Image copy capture (ext-image-copy-capture-v1): same pixel path as
      // screencopy
      CScreencopyRequest imageCopy =
          WWNCoreGetPendingImageCopyCapture(self->_rustCore);
      if (imageCopy.capture_id != 0 && imageCopy.ptr != NULL &&
          imageCopy.width > 0 && imageCopy.height > 0) {
        [self _fulfillImageCopyCapture:&imageCopy];
      } else if (imageCopy.capture_id != 0) {
        WWNCoreImageCopyCaptureFailed(self->_rustCore, imageCopy.capture_id);
      }

      // Gamma control: apply or restore
      CGammaApply *gammaApply = WWNCorePopPendingGammaApply(self->_rustCore);
      if (gammaApply) {
        [self _applyGamma:gammaApply];
        WWNGammaApplyFree(gammaApply);
      }
      uint32_t restoreOutputId = WWNCorePopPendingGammaRestore(self->_rustCore);
      if (restoreOutputId != 0) {
        [self _restoreGamma];
      }
#endif

      // Reset AFTER all main-queue UI work is done so the next compositor
      // tick cannot mutate _bufferCache while we are still reading it.
      atomic_store(&self->_compositorBusy, false);
    });
  }];
}

/// Runs on CADisplayLink (vsync-aligned frame callback). IOS and macOS 14+
- (void)onDisplayLink:(CADisplayLink *)link {
  // Window lifecycle events, buffer decode, and scene application must stay
  // in one _compositorTick pass. Draining events here races the tick and
  // leaves host views without a matching buffer present in the same frame.
  [self _compositorTick];
}

/// macOS: NSTimer fallback (pre-macOS 14)
- (void)onTimerTick:(NSTimer *)timer {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  if (_hostWindowInteractionPaused) {
    return;
  }
#endif
  [self _compositorTick];
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (void)_installHostWindowInteractionPause {
  // Only pause the compositor tick for non-Wayland host chrome (Machines UI,
  // etc.). WWNWindow move/live-resize must keep ticking so clients present
  // mid-drag; configure drains alone are not enough.
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self
         selector:@selector(_hostWindowInteractionBegan:)
             name:NSWindowWillMoveNotification
           object:nil];
  [nc addObserver:self
         selector:@selector(_hostWindowInteractionBegan:)
             name:NSWindowWillStartLiveResizeNotification
           object:nil];
  [nc addObserver:self
         selector:@selector(_hostWindowInteractionEnded:)
             name:NSWindowDidEndLiveResizeNotification
           object:nil];
  if (!_hostWindowMouseUpMonitor) {
    __weak typeof(self) weakSelf = self;
    _hostWindowMouseUpMonitor = [NSEvent
        addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp
                                     handler:^NSEvent *(NSEvent *event) {
                                       __strong typeof(weakSelf) strongSelf =
                                           weakSelf;
                                       if (strongSelf) {
                                         [strongSelf _hostWindowInteractionEnded:
                                                         nil];
                                       }
                                       return event;
                                     }];
  }
}

- (void)_removeHostWindowInteractionPause {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self name:NSWindowWillMoveNotification object:nil];
  [nc removeObserver:self
                name:NSWindowWillStartLiveResizeNotification
              object:nil];
  [nc removeObserver:self
                name:NSWindowDidEndLiveResizeNotification
              object:nil];
  if (_hostWindowMouseUpMonitor) {
    [NSEvent removeMonitor:_hostWindowMouseUpMonitor];
    _hostWindowMouseUpMonitor = nil;
  }
  _hostWindowInteractionPaused = NO;
}

- (void)_hostWindowInteractionBegan:(NSNotification *)note {
  NSWindow *window = [note.object isKindOfClass:[NSWindow class]]
                         ? (NSWindow *)note.object
                         : nil;
  if ([window isKindOfClass:[WWNWindow class]]) {
    // Wayland client surface: keep presenting / processing events mid-drag.
    return;
  }
  _hostWindowInteractionPaused = YES;
}

- (void)_hostWindowInteractionEnded:(NSNotification *)note {
  (void)note;
  _hostWindowInteractionPaused = NO;
}
#endif

// MARK: - Rendering

- (void)processPendingBuffers {
  if (!_rustCore) {
    return;
  }

  CBufferData *buffer;
  while ((buffer = WWNCorePopPendingBuffer(_rustCore)) != NULL) {
    [self cacheBuffer:buffer];

    // Notify Rust immediately (legacy behavior, can be refined with FrameClock)
    uint32_t ts = WWNBridgeFrameTimestampMs(_rustCore);
    [self notifyFramePresentedForSurface:buffer->surface_id
                                  buffer:buffer->buffer_id
                               timestamp:ts];

    WWNBufferDataFree(buffer);
  }
}

- (void)cacheBuffer:(CBufferData *)buffer {
  NSNumber *bufId = @(buffer->buffer_id);
  NSNumber *surfaceId = @(buffer->surface_id);
  NSString *cacheKey = WWNBufferCacheKey(buffer->surface_id, buffer->buffer_id);
  _latestBufferBySurface[surfaceId] = bufId;

  // 1. IOSurface
  if (buffer->iosurface_id != 0) {
    IOSurfaceRef surf = IOSurfaceLookup(buffer->iosurface_id);
    if (surf) {
      BOOL bottomUp = WWNBufferIsBottomUp(surf);
      // UIKit cannot assign IOSurface to CALayer.contents. AppKit can, but a
      // CALayer Y-scale under geometryFlipped looks like inverted X+Y, so both
      // families bake a CGImage. Niri/ANGLE Metal CPU mapping is already
      // top-down; WWNBottomUp as a blanket flip inverted niri. Nested Weston
      // gl-renderer leaves GL bottom-up rows. Flip only that compositor
      // (cpu_y_flip, from title "Weston Compositor - wayland0"; wayland-backend
      // never sends xdg app_id).
      BOOL westonFlip = buffer->cpu_y_flip != 0;
      (void)bottomUp;
      CGImageRef image = WWNCreateCGImageFromIOSurface(surf, westonFlip);
      CFRelease(surf);
      if (image) {
        _bufferCache[cacheKey] = (__bridge_transfer id)image;
        [_bottomUpBuffers removeObject:cacheKey];
        WWNPruneBufferCacheForSurface(_bufferCache, buffer->surface_id,
                                      cacheKey);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
        _waylandPresentGeneration++;
        _presentGenerationBySurface[surfaceId] = @(_waylandPresentGeneration);
#endif
        WWNLog("CACHE", @"Cached IOSurface→CGImage buf=%llu (westonFlip=%d)",
               buffer->buffer_id, (int)westonFlip);
      } else {
        WWNLog("CACHE",
               @"FAILED IOSurface→CGImage for buf=%llu iosurface=%u",
               buffer->buffer_id, buffer->iosurface_id);
      }
    } else {
      WWNLog("CACHE", @"FAILED IOSurface lookup for buf=%llu iosurface=%u",
             buffer->buffer_id, buffer->iosurface_id);
    }
    return;
  }

  // 2. SHM (Software)
  if (buffer->pixels) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // One-time pixel sampler: determines whether Weston is committing real
    // content or a solid color, and reports the byte layout (B,G,R,A order).
    static int s_pixelDumpCount = 0;
    if (s_pixelDumpCount < 6 && buffer->size >= 4 && buffer->stride > 0) {
      s_pixelDumpCount++;
      uint32_t w = buffer->width;
      uint32_t h = buffer->height;
      uint32_t stride = buffer->stride;
      const uint8_t *px = buffer->pixels;
      typedef struct {
        const char *name;
        uint32_t x, y;
      } SamplePt;
      SamplePt pts[] = {
          {"TL", 1, 1},          {"panel", w / 2, 8},
          {"center", w / 2, h / 2}, {"BL", 1, h - 2},
          {"BR", w - 2, h - 2},
      };
      BOOL allSame = YES;
      uint32_t first = 0;
      for (int i = 0; i < (int)(sizeof(pts) / sizeof(pts[0])); i++) {
        uint32_t x = pts[i].x, y = pts[i].y;
        if (x >= w || y >= h)
          continue;
        size_t off = (size_t)y * stride + (size_t)x * 4;
        if (off + 4 > buffer->size)
          continue;
        uint32_t b = px[off + 0], g = px[off + 1], r = px[off + 2],
                 a = px[off + 3];
        uint32_t packed = (a << 24) | (r << 16) | (g << 8) | b;
        if (i == 0)
          first = packed;
        else if (packed != first)
          allSame = NO;
        WWNLog("PXDUMP",
               @"buf=%llu fmt=%u %s(%u,%u) B=%02X G=%02X R=%02X A=%02X",
               buffer->buffer_id, buffer->format, pts[i].name, x, y, b, g, r,
               a);
      }
      WWNLog("PXDUMP", @"buf=%llu %ux%u stride=%u uniformSolid=%@",
             buffer->buffer_id, w, h, stride, allSame ? @"YES" : @"NO");
    }

    // Keep popup shadows/transparency intact. Only force opaque alpha when
    // the buffer format lacks alpha (XRGB8888) or ARGB appears entirely zero.
    BOOL needsAlphaFix = (buffer->format == 1);
    if (!needsAlphaFix && buffer->format == 0 && buffer->size >= 4 &&
        buffer->stride > 0 && buffer->height > 0) {
      size_t sample = (size_t)buffer->stride * (size_t)buffer->height;
      if (sample > buffer->size)
        sample = buffer->size;
      needsAlphaFix = YES;
      for (size_t off = 3; off < sample; off += 4) {
        if (buffer->pixels[off] != 0) {
          needsAlphaFix = NO;
          break;
        }
      }
    }
    if (needsAlphaFix) {
      for (size_t i = 3; i < buffer->size; i += 4) {
        buffer->pixels[i] = 0xFF;
      }
    }
#endif
    WWNPruneBufferCacheForSurface(_bufferCache, buffer->surface_id, cacheKey);
    CFDataRef pixelData =
        CFDataCreate(NULL, buffer->pixels, (CFIndex)buffer->size);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(pixelData);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    // wl_shm XRGB8888 / ARGB8888 are B,G,R,X/A in little-endian memory.
    CGBitmapInfo bitmapInfo;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    /* wl_shm XRGB8888 / ARGB8888 are B,G,R,X/A in little-endian memory. */
    if (buffer->format == 1) {
      bitmapInfo = kCGBitmapByteOrder32Little |
                   (CGBitmapInfo)kCGImageAlphaNoneSkipFirst;
    } else {
      bitmapInfo = kCGBitmapByteOrder32Little |
                   (CGBitmapInfo)kCGImageAlphaPremultipliedFirst;
    }
#else
    if (buffer->format == 1) {
      bitmapInfo = kCGBitmapByteOrder32Little |
                   (CGBitmapInfo)kCGImageAlphaNoneSkipFirst;
    } else {
      bitmapInfo = kCGBitmapByteOrder32Little |
                   (CGBitmapInfo)kCGImageAlphaPremultipliedFirst;
    }
#endif

    CGImageRef image = CGImageCreate(
        buffer->width, buffer->height, 8, 32, buffer->stride, colorSpace,
        bitmapInfo, provider, NULL, false, kCGRenderingIntentDefault);

    if (image) {
      _bufferCache[cacheKey] = (__bridge_transfer id)image;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      _waylandPresentGeneration++;
      _presentGenerationBySurface[surfaceId] = @(_waylandPresentGeneration);
#endif
    } else {
      WWNLog("CACHE", @"FAILED CGImageCreate for buf=%llu %ux%u",
             buffer->buffer_id, buffer->width, buffer->height);
    }

    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    CFRelease(pixelData);
  } else {
    WWNLog("CACHE", @"SKIP: buf=%llu has no pixels and no iosurface",
           buffer->buffer_id);
  }
}

- (void)renderScene {
  if (!_rustCore) {
    return;
  }

  CRenderScene *scene = WWNCoreGetRenderScene(_rustCore);
  if (!scene)
    return;

  // Track used layers to hide/remove unused ones (skip for now, simple update)

  if (scene->count > 0) {
    for (size_t i = 0; i < scene->count; i++) {
      [self updateLayerForNode:&scene->nodes[i]];
    }
  }

  WWNRenderSceneFree(scene);
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)_updateIOSPresentationForNode:(CRenderNode *)node {
  NSNumber *winId = @(node->window_id);
  NSNumber *surfId = @(node->surface_id);

  UIView *hostView = _windows[winId];
  if (!hostView) {
    hostView = _popups[winId];
  }
  if (![hostView isKindOfClass:[WWNCompositorView_ios class]]) {
    WWNLog("RENDER",
           @"WARNING: No iOS host view for surf=%@ win=%@ (_windows=%lu _popups=%lu)",
           surfId, winId, (unsigned long)_windows.count,
           (unsigned long)_popups.count);
    return;
  }
  WWNCompositorView_ios *iosView = (WWNCompositorView_ios *)hostView;
  if (!iosView.window && !iosView.superview) {
    return;
  }

  NSNumber *latestForSurface = _latestBufferBySurface[surfId];
  BOOL isStaleSceneBuffer =
      (node->buffer_id != 0 && latestForSurface &&
       latestForSurface.unsignedLongLongValue != node->buffer_id);
  uint64_t selectedBufferId = node->buffer_id;
  if (isStaleSceneBuffer) {
    selectedBufferId = latestForSurface.unsignedLongLongValue;
  }
  NSString *cacheKey = WWNBufferCacheKey(node->surface_id, selectedBufferId);
  id content = _bufferCache[cacheKey];
  if (!content && isStaleSceneBuffer) {
    NSString *sceneCacheKey =
        WWNBufferCacheKey(node->surface_id, node->buffer_id);
    content = _bufferCache[sceneCacheKey];
  }

  static uint64_t s_lastRenderLogBuf = 0;
  static float s_lastRenderLogW = 0;
  static float s_lastRenderLogH = 0;
  if (node->buffer_id != s_lastRenderLogBuf || node->width != s_lastRenderLogW ||
      node->height != s_lastRenderLogH) {
    s_lastRenderLogBuf = node->buffer_id;
    s_lastRenderLogW = node->width;
    s_lastRenderLogH = node->height;
    WWNLog("RENDER",
           @"Node present surf=%@ win=%@ node=%.0fx%.0f buf_id=%llu buf=%ux%u "
           @"contentRect=%.3f,%.3f %.3fx%.3f stale=%@",
           surfId, winId, node->width, node->height, node->buffer_id,
           node->buffer_width, node->buffer_height, node->content_rect_x,
           node->content_rect_y, node->content_rect_w, node->content_rect_h,
           isStaleSceneBuffer ? @"yes" : @"no");
  }

  if (node->buffer_id == 0 || !content) {
    return;
  }

  CGImageRef cgImage = NULL;
  if (CFGetTypeID((__bridge CFTypeRef)content) == CGImageGetTypeID()) {
    cgImage = (__bridge CGImageRef)content;
  }

  // During output resize, nested Weston may commit a portrait buffer while the
  // host window is already landscape (or vice versa). Skip those frames so we
  // keep showing the last good image instead of a stretched tear.
  if (_outputResizeInFlight && cgImage && node->buffer_width > 0 &&
      node->buffer_height > 0 && node->width > 0 && node->height > 0) {
    float nodeAspect = (float)node->width / (float)node->height;
    float bufAspect =
        (float)node->buffer_width / (float)node->buffer_height;
    if (fabsf(nodeAspect - bufAspect) > 0.05f) {
      static uint64_t s_lastAspectSkipLogBuf = 0;
      if (node->buffer_id != s_lastAspectSkipLogBuf) {
        s_lastAspectSkipLogBuf = node->buffer_id;
        WWNLog("RENDER",
               @"IOS skip mismatched aspect: surf=%@ win=%@ node=%.0fx%.0f "
               @"buf=%ux%u",
               surfId, winId, node->width, node->height, node->buffer_width,
               node->buffer_height);
      }
      return;
    }
  }

  float localX = node->x - node->anchor_output_x;
  float localY = node->y - node->anchor_output_y;
  CGRect frame =
      CGRectMake(localX, localY, node->width, node->height);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // Host-owned shells (weston-terminal/foot) set followHostSize without the
  // rust host_locked bit. Expand presentation to the compositor container so
  // cell-snap / CSD lag (e.g. 398×763 vs 402×778) cannot leave gutters -
  // presentWaylandFrame also stretches, but the logged/scene frame must match
  // host bounds or placement races recentering.
  BOOL hostOwnsFrame = [_hostLockedWindowIds containsObject:winId] ||
                       ([iosView isKindOfClass:[WWNCompositorView_ios class]] &&
                        (((WWNCompositorView_ios *)iosView).hostLocked ||
                         ((WWNCompositorView_ios *)iosView).followHostSize));
  if (hostOwnsFrame) {
    CGRect hostBounds = iosView.superview
                            ? iosView.superview.bounds
                            : (self.containerView ? self.containerView.bounds
                                                  : iosView.bounds);
    if (hostBounds.size.width > 0.0 && hostBounds.size.height > 0.0) {
      frame = CGRectMake(0, 0, hostBounds.size.width, hostBounds.size.height);
    }
  } else if (cgImage && node->buffer_width > 0 && node->buffer_height > 0 &&
             node->scale > 0.0f) {
    // SizeAuthority::Host can leave node dimensions at a stale host request
    // while the client buffer stays at its fixed preferred size (flower/smoke
    // 200×200). Never pass an oversized frame into presentWaylandFrame. That
    // triggers kCAGravityResize upscaling when the iPadOS scene resizes.
    float bufLogicalW = (float)node->buffer_width / node->scale;
    float bufLogicalH = (float)node->buffer_height / node->scale;
    if (node->width > bufLogicalW + 1.0f || node->height > bufLogicalH + 1.0f) {
      frame = CGRectMake(localX, localY, bufLogicalW, bufLogicalH);
    }
  }
#endif
  CGRect contentRect = CGRectMake(0, 0, 1, 1);
  if (node->content_rect_w > 0.0f && node->content_rect_h > 0.0f) {
    contentRect = CGRectMake(node->content_rect_x, node->content_rect_y,
                             node->content_rect_w, node->content_rect_h);
  }

  if (cgImage) {
    [iosView setWaylandPresentationActive:YES];
    uint64_t presentToken =
        [_presentGenerationBySurface[surfId] unsignedLongLongValue];
    static int s_presentLogCount = 0;
    static uint64_t s_lastPresentLogBuf = 0;
    if (s_presentLogCount < 8 || selectedBufferId != s_lastPresentLogBuf) {
      if (selectedBufferId != s_lastPresentLogBuf) {
        s_lastPresentLogBuf = selectedBufferId;
      }
      if (s_presentLogCount < 8) {
        s_presentLogCount++;
      }
      WWNLog("RENDER",
             @"IOS present via frameView: surf=%@ win=%@ frame=%.0f,%.0f "
             @"%.0fx%.0f imgW=%zu imgH=%zu token=%llu",
             surfId, winId, frame.origin.x, frame.origin.y, frame.size.width,
             frame.size.height, CGImageGetWidth(cgImage),
             CGImageGetHeight(cgImage), presentToken);
    }
    [iosView presentWaylandFrame:cgImage
                           frame:frame
                     contentRect:contentRect
                    presentToken:presentToken];
    return;
  }

  // IOSurface-as-CALayer.contents is AppKit-only. If an IOSurface still reaches
  // here (cache conversion failed), drop it. Painting a blank legacy layer
  // hides the real failure mode.
  WWNLog("RENDER",
         @"IOS skip non-CGImage content for surf=%@ win=%@ (type=%lu). "
         @"IOSurface must be converted in cacheBuffer",
         surfId, winId,
         (unsigned long)CFGetTypeID((__bridge CFTypeRef)content));
}
#endif

- (void)updateLayerForNode:(CRenderNode *)node {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [self _updateIOSPresentationForNode:node];
#else
  NSNumber *winId = @(node->window_id);
  NSNumber *surfId = @(node->surface_id);

  // 1. Find or Create Layer
  CALayer *layer = _surfaceLayers[surfId];
  BOOL clientSideDecorated = NO;
  id winObj = _windows[winId];
  if ([winObj isKindOfClass:[WWNWindow class]]) {
    clientSideDecorated = ((WWNWindow *)winObj).clientSideDecorated;
  }
  if (!layer) {
    layer = [CALayer layer];
    layer.contentsScale = node->scale;
    layer.contentsGravity = kCAGravityResize;
    layer.opaque = clientSideDecorated ? NO : YES;
    if (clientSideDecorated) {
      layer.backgroundColor = NULL;
    }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    layer.geometryFlipped = YES;
    layer.opaque = YES;
#endif
    _surfaceLayers[surfId] = layer;

    // Attach to window hierarchy (toplevels and popups both in _windows).
    // Layer-shell nodes use synthetic window ids (high bit set) and composite
    // onto the primary desktop/host content view when no dedicated host exists.
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    id host = _windows[winId];
    if (!host) {
      host = _popups[winId];
      if ([host conformsToProtocol:@protocol(WWNPopupHost)]) {
        host = ((id<WWNPopupHost>)host).contentView;
      }
    } else if ([host isKindOfClass:[NSWindow class]]) {
      host = [(NSWindow *)host contentView];
    }
    if (!host && (node->window_id & (1ULL << 63)) != 0) {
      for (NSNumber *key in _windows) {
        id candidate = _windows[key];
        if ([candidate isKindOfClass:[WWNWindow class]]) {
          host = [(WWNWindow *)candidate contentView];
          break;
        }
      }
    }
    if ([host isKindOfClass:[WWNView class]] &&
        [host respondsToSelector:@selector(contentLayer)]) {
      [((WWNView *)host).contentLayer addSublayer:layer];
    }
#else
    UIView *hostView = _windows[winId];
    if (!hostView)
      hostView = _popups[winId];
    if ([hostView isKindOfClass:[WWNCompositorView_ios class]]) {
      WWNCompositorView_ios *iosView = (WWNCompositorView_ios *)hostView;
      [iosView setWaylandPresentationActive:YES];
      [iosView.waylandLayer addSublayer:layer];
      WWNLog("RENDER",
             @"Created layer for surf=%@ → attached to win=%@ waylandLayer",
             surfId, winId);
    } else {
      WWNLog("RENDER",
             @"WARNING: No host view for surf=%@ win=%@ (_windows has %lu "
             @"entries, _popups has %lu)",
             surfId, winId, (unsigned long)_windows.count,
             (unsigned long)_popups.count);
    }
#endif
  }

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  if (node->buffer_id != 0 &&
      ![_windowsAutoShownAfterFirstBuffer containsObject:winId]) {
    WWNWindow *window = _windows[winId];
    if ([window isKindOfClass:[WWNWindow class]]) {
      // Reveal the window once, on its first presented buffer. Never steal
      // key status here and never re-show on later frames: doing so fought
      // user minimize (dock bounce-back) and yanked focus between clients on
      // every commit. Key status comes only from explicit activation intent
      // (window creation / WindowActivationRequested).
      [_windowsAutoShownAfterFirstBuffer addObject:winId];
      if (![window isVisible] && !window.isMiniaturized &&
          !window.wwnMiniaturizeInProgress) {
        [window orderFront:nil];
      }
    }
  }
#endif

  // Disable implicit animations so layer property changes are instantaneous.
  // During rotation, an active animation context would capture these changes
  // and animate them, causing the surface to appear frozen/stretched.
  [CATransaction begin];
  [CATransaction setDisableActions:YES];

  // 2. Update Geometry. Use anchor for window-local coords (subsurfaces)
  float localX = node->x - node->anchor_output_x;
  float localY = node->y - node->anchor_output_y;
  // Use explicit frame assignment to avoid subpixel position/bounds drift that
  // can leave thin gutters at content-view edges.
  layer.frame = CGRectMake(localX, localY, node->width, node->height);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // Buffer pixels / wl_surface buffer_scale = layer points. Do not use
  // NSWindow backingScaleFactor: that showed 1x weston buffers at half
  // size on Retina (left black, right empty, panel clipped). HiDPI is
  // the client's buffer_scale. #111 still stretches a lagging buffer
  // into the host node during live resize (Resize gravity).
  layer.contentsGravity = kCAGravityResize;
  layer.contentsScale = MAX(1.0, node->scale);
#else
  layer.contentsScale = MAX(1.0, node->scale);
#endif
  layer.opacity = node->opacity;
  layer.cornerRadius = node->corner_radius;
  layer.opaque = clientSideDecorated ? NO : YES;
  if (clientSideDecorated) {
    layer.backgroundColor = NULL;
    layer.masksToBounds = NO;
  }

  // 2b. Crop buffer to content area when CSD geometry is set.
  // The client's buffer may include shadow/frame around the content;
  // xdg_surface.set_window_geometry defines the content rect.
  // content_rect is pre-normalized (0..1) on the Rust side.
  if (node->content_rect_w > 0.0f && node->content_rect_h > 0.0f) {
    layer.contentsRect = CGRectMake(node->content_rect_x, node->content_rect_y,
                                    node->content_rect_w, node->content_rect_h);
  } else {
    // Reset to full buffer when no geometry crop is active.
    layer.contentsRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
  }

  // 3. Update Contents from Cache
  // We use node->buffer_id to look up the image
  NSNumber *latestForSurface = _latestBufferBySurface[surfId];
  BOOL isStaleSceneBuffer =
      (node->buffer_id != 0 && latestForSurface &&
       latestForSurface.unsignedLongLongValue != node->buffer_id);
  WWNLog("RENDER",
         @"Node present surf=%@ win=%@ node=%.0fx%.0f buf_id=%llu buf=%ux%u contentRect=%.3f,%.3f %.3fx%.3f stale=%@",
         surfId, winId, node->width, node->height, node->buffer_id,
         node->buffer_width, node->buffer_height, node->content_rect_x,
         node->content_rect_y, node->content_rect_w, node->content_rect_h,
         isStaleSceneBuffer ? @"yes" : @"no");
  if (isStaleSceneBuffer) {
    NSNumber *staleCountNum = _staleSceneSelectionsBySurface[surfId];
    uint64_t staleCount = staleCountNum ? staleCountNum.unsignedLongLongValue + 1 : 1;
    _staleSceneSelectionsBySurface[surfId] = @(staleCount);
    WWNLog("RENDER",
           @"STALE: surf=%@ win=%@ scene_buf=%llu latest_buf=%llu stale_count=%llu; "
           @"preferring latest cached buffer",
           surfId, winId, node->buffer_id, latestForSurface.unsignedLongLongValue,
           staleCount);
  }
  uint64_t selectedBufferId = node->buffer_id;
  if (isStaleSceneBuffer) {
    selectedBufferId = latestForSurface.unsignedLongLongValue;
  }
  NSString *cacheKey = WWNBufferCacheKey(node->surface_id, selectedBufferId);
  id content = _bufferCache[cacheKey];
  if (!content && isStaleSceneBuffer) {
    NSString *sceneCacheKey = WWNBufferCacheKey(node->surface_id, node->buffer_id);
    id sceneContent = _bufferCache[sceneCacheKey];
    if (sceneContent) {
      content = sceneContent;
      selectedBufferId = node->buffer_id;
      WWNLog("RENDER",
             @"STALE fallback: surf=%@ win=%@ latest_buf=%llu missing; using scene_buf=%llu",
             surfId, winId, latestForSurface.unsignedLongLongValue, node->buffer_id);
    }
  }
  if (node->buffer_id != 0 && !content) {
    WWNLog(
        "RENDER",
        @"MISS: surf=%@ win=%@ scene_buf=%llu selected_buf=%llu not in cache "
        @"(cache has %lu entries)",
        surfId, winId, node->buffer_id, selectedBufferId,
        (unsigned long)_bufferCache.count);
  }
  if (node->buffer_id == 0) {
    layer.contents = nil;
  } else if (content) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    UIView *hostView = _windows[winId];
    if (!hostView) {
      hostView = _popups[winId];
    }
    if ([hostView isKindOfClass:[WWNCompositorView_ios class]]) {
      [(WWNCompositorView_ios *)hostView setWaylandPresentationActive:YES];
    }
#endif
    // Clear first so Core Animation cannot skip an update when the same
    // buffer id is re-used with new SHM pixels (new CGImage, same key).
    layer.contents = nil;
    layer.contents = content;
    // Do not CATransform3DMakeScale(1,-1,1) under geometryFlipped: that looks
    // like inverted X+Y. Bottom-up GLES IOSurfaces are baked into a flipped
    // CGImage in cacheBuffer: instead.
    layer.transform = CATransform3DIdentity;
  }

  [CATransaction commit];
#endif
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
/// WWNView sets `layerContentsRedrawPolicy` to Never; without this, Wayland
/// surface sublayers can stop updating on screen after the first frame.
- (void)_invalidateMacSurfaceHostViews {
  NSArray<NSNumber *> *windowKeys = [_windows allKeys];
  for (NSNumber *key in windowKeys) {
    id w = _windows[key];
    if (!w) {
      continue;
    }
    NSView *host = nil;
    if ([w isKindOfClass:[NSWindow class]]) {
      host = [(NSWindow *)w contentView];
    }
    if ([host isKindOfClass:[WWNView class]]) {
      @try {
        [host setNeedsDisplay:YES];
      } @catch (NSException *exception) {
        WWNLog("BRIDGE",
               @"Suppressed setNeedsDisplay exception for window %@: %@",
               key, exception.reason);
      }
    }
  }
}
#endif

- (void)flushClients {
  if (!_rustCore)
    return;
  [self _dispatchToRust:^{
    WWNCoreFlushClients(self->_rustCore);
  }];
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
/// Write ARGB8888 screen capture to buffer. Returns YES on success.
- (BOOL)_writeCaptureToBuffer:(const CScreencopyRequest *)req {
  if (!req || req->capture_id == 0 || req->ptr == NULL || req->width == 0 ||
      req->height == 0)
    return NO;

  WWNWindow *window = nil;
  for (NSNumber *key in _windows) {
    id w = _windows[key];
    if ([w isKindOfClass:[WWNWindow class]]) {
      window = (WWNWindow *)w;
      break;
    }
  }
  if (!window)
    return NO;

  CGWindowID windowID = (CGWindowID)[window windowNumber];
  CGRect bounds = CGRectNull;
  CGImageRef cap = NULL;
#if __MAC_OS_X_VERSION_MAX_ALLOWED < 150000
  cap = CGWindowListCreateImage(bounds, kCGWindowListOptionIncludingWindow,
                                windowID, kCGWindowImageBoundsIgnoreFraming);
#else
  (void)windowID;
  (void)bounds;
  /* CGWindowListCreateImage obsoleted in macOS 15 - ScreenCaptureKit required
   */
#endif
  if (!cap)
    return NO;

  size_t imgWidth = CGImageGetWidth(cap);
  size_t imgHeight = CGImageGetHeight(cap);
  if (imgWidth == 0 || imgHeight == 0) {
    CGImageRelease(cap);
    return NO;
  }

  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGBitmapInfo bmpInfo = kCGBitmapByteOrder32Little |
                         (CGBitmapInfo)kCGImageAlphaPremultipliedFirst;
  CGContextRef ctx = CGBitmapContextCreate(req->ptr, req->width, req->height, 8,
                                           req->stride, cs, bmpInfo);
  if (!ctx) {
    CGColorSpaceRelease(cs);
    CGImageRelease(cap);
    return NO;
  }

  CGContextTranslateCTM(ctx, 0, req->height);
  CGContextScaleCTM(ctx, 1.0, -1.0);
  CGContextDrawImage(ctx, CGRectMake(0, 0, req->width, req->height), cap);

  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  CGImageRelease(cap);
  return YES;
}

- (void)_fulfillScreencopy:(const CScreencopyRequest *)req {
  if ([self _writeCaptureToBuffer:req])
    WWNCoreScreencopyDone(_rustCore, req->capture_id);
  else
    WWNCoreScreencopyFailed(_rustCore, req->capture_id);
}

- (void)_fulfillImageCopyCapture:(const CScreencopyRequest *)req {
  if ([self _writeCaptureToBuffer:req])
    WWNCoreImageCopyCaptureDone(_rustCore, req->capture_id);
  else
    WWNCoreImageCopyCaptureFailed(_rustCore, req->capture_id);
}

- (void)_applyGamma:(const CGammaApply *)apply {
  if (!apply || apply->size == 0 || !apply->red || !apply->green ||
      !apply->blue)
    return;

  CGDirectDisplayID displayId = CGMainDisplayID();
  uint32_t n = apply->size;

  CGGammaValue *redF = (CGGammaValue *)malloc(n * sizeof(CGGammaValue));
  CGGammaValue *greenF = (CGGammaValue *)malloc(n * sizeof(CGGammaValue));
  CGGammaValue *blueF = (CGGammaValue *)malloc(n * sizeof(CGGammaValue));
  if (!redF || !greenF || !blueF) {
    free(redF);
    free(greenF);
    free(blueF);
    return;
  }

  for (uint32_t i = 0; i < n; i++) {
    redF[i] = (CGGammaValue)apply->red[i] / 65535.0f;
    greenF[i] = (CGGammaValue)apply->green[i] / 65535.0f;
    blueF[i] = (CGGammaValue)apply->blue[i] / 65535.0f;
  }

  if (_savedGammaRed == NULL) {
    _savedGammaSize = n;
    _savedGammaRed = (CGGammaValue *)malloc(n * sizeof(CGGammaValue));
    _savedGammaGreen = (CGGammaValue *)malloc(n * sizeof(CGGammaValue));
    _savedGammaBlue = (CGGammaValue *)malloc(n * sizeof(CGGammaValue));
    if (_savedGammaRed && _savedGammaGreen && _savedGammaBlue) {
      uint32_t sampleCount = n;
      CGGetDisplayTransferByTable(displayId, n, _savedGammaRed,
                                  _savedGammaGreen, _savedGammaBlue,
                                  &sampleCount);
      _savedGammaSize = sampleCount;
    } else {
      free(_savedGammaRed);
      free(_savedGammaGreen);
      free(_savedGammaBlue);
      _savedGammaRed = _savedGammaGreen = _savedGammaBlue = NULL;
      _savedGammaSize = 0;
    }
  }

  CGSetDisplayTransferByTable(displayId, n, redF, greenF, blueF);

  free(redF);
  free(greenF);
  free(blueF);
}

- (void)_restoreGamma {
  if (_savedGammaRed && _savedGammaGreen && _savedGammaBlue &&
      _savedGammaSize > 0) {
    CGSetDisplayTransferByTable(CGMainDisplayID(), _savedGammaSize,
                                _savedGammaRed, _savedGammaGreen,
                                _savedGammaBlue);
    free(_savedGammaRed);
    free(_savedGammaGreen);
    free(_savedGammaBlue);
    _savedGammaRed = _savedGammaGreen = _savedGammaBlue = NULL;
    _savedGammaSize = 0;
  }
}
#endif

// MARK: - Input (Stubs)

// C FFI for input injection
extern void WWNCoreInjectPointerMotion(void *core, uint64_t window_id, double x,
                                       double y, uint32_t timestamp);
extern void WWNCoreInjectPointerButton(void *core, uint64_t window_id,
                                       uint32_t button, uint32_t state,
                                       uint32_t timestamp);
extern void WWNCoreInjectPointerEnter(void *core, uint64_t window_id, double x,
                                      double y, uint32_t timestamp);
extern void WWNCoreInjectPointerLeave(void *core, uint64_t window_id,
                                      uint32_t timestamp);
extern void WWNCoreInjectKey(void *core, uint32_t keycode, uint32_t state,
                             uint32_t timestamp);
extern void WWNCoreInjectKeyboardEnter(void *core, uint64_t window_id,
                                       const uint32_t *keys, size_t count,
                                       uint32_t timestamp);
extern void WWNCoreInjectKeyboardLeave(void *core, uint64_t window_id);
extern void WWNCoreInjectModifiers(void *core, uint32_t depressed,
                                   uint32_t latched, uint32_t locked,
                                   uint32_t group);

extern void WWNCoreInjectTouchDown(void *core, int32_t id, double x, double y,
                                   uint32_t timestamp);
extern void WWNCoreInjectTouchDownForWindow(void *core, uint64_t window_id,
                                            int32_t id, double x, double y,
                                            uint32_t timestamp);
extern void WWNCoreInjectTouchUp(void *core, int32_t id, uint32_t timestamp);
extern void WWNCoreInjectTouchUpForWindow(void *core, uint64_t window_id,
                                          int32_t id, uint32_t timestamp);
extern void WWNCoreInjectTouchMotion(void *core, int32_t id, double x, double y,
                                     uint32_t timestamp);
extern void WWNCoreInjectTouchMotionForWindow(void *core, uint64_t window_id,
                                              int32_t id, double x, double y,
                                              uint32_t timestamp);
extern void WWNCoreInjectTouchCancel(void *core);
extern void WWNCoreInject_touch_frame(void *core);

/// Dispatch a block to the compositor's serial queue.
/// All Rust FFI calls (input injection, configuration changes, etc.) go
/// through here so they are serialized with the compositor tick and never
/// contend for Rust-internal locks on the main thread.
- (void)_runBlock:(dispatch_block_t)block {
  block();
}

- (void)_dispatchToRust:(dispatch_block_t)block {
  [self _dispatchAsyncToCompositor:block];
}

- (void)_dispatchAsyncToCompositor:(dispatch_block_t)block {
  if (_compositorThread) {
    if ([NSThread currentThread] == _compositorThread) {
      block();
    } else {
      [self performSelector:@selector(_runBlock:) onThread:_compositorThread withObject:[block copy] waitUntilDone:NO];
    }
  } else {
    block();
  }
}

- (void)_dispatchSyncToCompositor:(dispatch_block_t)block {
  if (_compositorThread) {
    if ([NSThread currentThread] == _compositorThread) {
      block();
    } else {
      [self performSelector:@selector(_runBlock:) onThread:_compositorThread withObject:[block copy] waitUntilDone:YES];
    }
  } else {
    block();
  }
}

- (void)injectTouchDown:(NSInteger)touchId
                      x:(double)x
                      y:(double)y
              timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  WWNLog("BRIDGE", @"injectTouchDown id=%ld x=%.1f y=%.1f ts=%u",
         (long)touchId, x, y, timestampMs);
#endif
  [self _dispatchToRust:^{
    WWNCoreInjectTouchDown(self->_rustCore, (int32_t)touchId, x, y,
                           timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

- (void)injectTouchDownForWindow:(uint64_t)windowId
                         touchId:(NSInteger)touchId
                               x:(double)x
                               y:(double)y
                       timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInjectTouchDownForWindow(self->_rustCore, windowId, (int32_t)touchId,
                                    x, y, timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

- (void)injectTouchUp:(NSInteger)touchId timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  WWNLog("BRIDGE", @"injectTouchUp id=%ld ts=%u", (long)touchId, timestampMs);
#endif
  [self _dispatchToRust:^{
    WWNCoreInjectTouchUp(self->_rustCore, (int32_t)touchId, timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

- (void)injectTouchUpForWindow:(uint64_t)windowId
                       touchId:(NSInteger)touchId
                     timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInjectTouchUpForWindow(self->_rustCore, windowId, (int32_t)touchId,
                                  timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

- (void)injectTouchMotion:(NSInteger)touchId
                        x:(double)x
                        y:(double)y
                timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if (WWNShouldLogThrottledMotion(&s_lastTouchMotionLog)) {
    WWNLog("BRIDGE", @"injectTouchMotion id=%ld x=%.1f y=%.1f ts=%u",
           (long)touchId, x, y, timestampMs);
  }
#endif
  [self _dispatchToRust:^{
    WWNCoreInjectTouchMotion(self->_rustCore, (int32_t)touchId, x, y,
                             timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

- (void)injectTouchMotionForWindow:(uint64_t)windowId
                           touchId:(NSInteger)touchId
                                 x:(double)x
                                 y:(double)y
                         timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInjectTouchMotionForWindow(self->_rustCore, windowId,
                                      (int32_t)touchId, x, y, timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

- (void)injectTouchCancel {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInjectTouchCancel(self->_rustCore);
  }];
}

- (void)injectTouchFrame {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInject_touch_frame(self->_rustCore);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

// MARK: - Text Input (IME / Emoji)

- (void)textInputCommitString:(NSString *)text {
  if (!_rustCore || !text) {
    return;
  }
  const char *utf8 = [text UTF8String];
  if (!utf8) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreTextInputCommit(self->_rustCore, utf8);
  }];
}

- (BOOL)isTextInputEnabled {
  // Read-only poll; safe off the compositor queue (RwLock). Avoid
  // dispatch_sync here. InsertText runs on main and can deadlock the tick.
  if (!_rustCore) {
    return NO;
  }
  return WWNCoreTextInputIsEnabled(_rustCore) != 0;
}

- (BOOL)textEntryWanted {
  if (!_rustCore) {
    return NO;
  }
  return WWNCoreTextEntryWanted(_rustCore) != 0;
}

- (void)textInputPreeditString:(NSString *)text
                   cursorBegin:(int32_t)cursorBegin
                     cursorEnd:(int32_t)cursorEnd {
  if (!_rustCore || !text) {
    return;
  }
  const char *utf8 = [text UTF8String];
  if (!utf8) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreTextInputPreedit(self->_rustCore, utf8, cursorBegin, cursorEnd);
  }];
}

- (void)textInputDeleteSurrounding:(uint32_t)beforeLength
                       afterLength:(uint32_t)afterLength {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreTextInputDeleteSurrounding(self->_rustCore, beforeLength,
                                      afterLength);
  }];
}

- (CGRect)textInputCursorRect {
  if (!_rustCore) {
    return CGRectZero;
  }
  int32_t x = 0, y = 0, w = 0, h = 0;
  WWNCoreTextInputGetCursorRect(_rustCore, &x, &y, &w, &h);
  return CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h);
}

- (void)injectPointerMotionForWindow:(uint64_t)windowId
                                   x:(double)x
                                   y:(double)y
                           timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if (WWNShouldLogThrottledMotion(&s_lastPointerMotionLog)) {
    WWNLog("BRIDGE",
           @"injectPointerMotion win=%llu x=%.1f y=%.1f ts=%u",
           windowId, x, y, timestampMs);
  }
#endif
  [self _dispatchToRust:^{
    WWNCoreInjectPointerMotion(self->_rustCore, windowId, x, y, timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

- (void)injectPointerEnterForWindow:(uint64_t)windowId
                                  x:(double)x
                                  y:(double)y
                          timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  WWNLog("BRIDGE", @"injectPointerEnter win=%llu x=%.1f y=%.1f ts=%u",
         windowId, x, y, timestampMs);
#endif
  [self _dispatchToRust:^{
    WWNCoreInjectPointerEnter(self->_rustCore, windowId, x, y, timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}

- (void)injectPointerLeaveForWindow:(uint64_t)windowId
                          timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  WWNLog("BRIDGE", @"injectPointerLeave win=%llu ts=%u", windowId, timestampMs);
#endif
  [self _dispatchToRust:^{
    WWNCoreInjectPointerLeave(self->_rustCore, windowId, timestampMs);
  }];
}

- (void)injectPointerButtonForWindow:(uint64_t)windowId
                              button:(uint32_t)button
                             pressed:(BOOL)pressed
                           timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  WWNLog("BRIDGE",
         @"injectPointerButton win=%llu btn=%u pressed=%d ts=%u", windowId,
         button, pressed, timestampMs);
#endif
  uint32_t state = pressed ? 1 : 0;
  [self _dispatchToRust:^{
    WWNCoreInjectPointerButton(self->_rustCore, windowId, button, state,
                               timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}
- (void)injectPointerAxisForWindow:(uint64_t)windowId
                              axis:(uint32_t)axis
                             value:(double)value
                          discrete:(int32_t)discrete
                         timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if (WWNShouldLogThrottledMotion(&s_lastPointerMotionLog)) {
    WWNLog("BRIDGE",
           @"injectPointerAxis win=%llu axis=%u value=%.2f ts=%u", windowId,
           axis, value, timestampMs);
  }
#endif
  [self _dispatchToRust:^{
    WWNCoreInjectPointerAxis(self->_rustCore, windowId, axis, value,
                             timestampMs);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    WWNCoreFlushClients(self->_rustCore);
#endif
  }];
}
- (void)injectKeyWithKeycode:(uint32_t)keycode
                     pressed:(BOOL)pressed
                   timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
  uint32_t state = pressed ? 1 : 0;
  [self _dispatchToRust:^{
    WWNCoreInjectKey(self->_rustCore, keycode, state, timestampMs);
  }];
}

- (void)injectKeyboardEnterForWindow:(uint64_t)windowId
                                keys:(NSArray<NSNumber *> *)keys {
  if (!_rustCore) {
    return;
  }
  // Copy array for the async block
  NSArray *keysCopy = [keys copy];
  [self _dispatchToRust:^{
    size_t count = keysCopy.count;
    uint32_t *keyArray = malloc(sizeof(uint32_t) * count);
    for (size_t i = 0; i < count; i++) {
      keyArray[i] = [keysCopy[i] unsignedIntValue];
    }
    WWNCoreInjectKeyboardEnter(self->_rustCore, windowId, keyArray, count, 0);
    free(keyArray);
  }];
}

- (void)injectKeyboardLeaveForWindow:(uint64_t)windowId {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInjectKeyboardLeave(self->_rustCore, windowId);
  }];
}

- (BOOL)shouldFollowHostSizeForWindowId:(uint64_t)windowId {
#if TARGET_OS_IPHONE
  id view = _windows[@(windowId)];
  NSString *title = nil;
  if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
    title = ((WWNCompositorView_ios *)view).accessibilityLabel;
  }
  NSString *clientId =
      WWNIosResolveBundledClientIdForWindow(self, windowId);
  if (WWNWestonDemoPrefersFixedSquare(clientId, title)) {
    return NO;
  }
  if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
    WWNCompositorView_ios *iosView = (WWNCompositorView_ios *)view;
    return iosView.hostLocked || iosView.followHostSize;
  }
  return NO;
#else
  WWNWindow *host = _windows[@(windowId)];
  if ([host isKindOfClass:[WWNWindow class]] &&
      (host.prefersFixedSquare ||
       WWNWestonDemoPrefersFixedSquare(nil, host.title))) {
    return NO;
  }
  return YES;
#endif
}

- (void)injectWindowResize:(uint64_t)windowId
                     width:(uint32_t)width
                    height:(uint32_t)height {
  if (!_rustCore)
    return;

  NSNumber *key = @(windowId);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *hostWindow = _windows[key];
  if (hostWindow &&
      (hostWindow.isMiniaturized || hostWindow.wwnMiniaturizeInProgress)) {
    WWNLog("BRIDGE",
           @"Skipping injectWindowResize window=%llu (miniaturized/in-progress)",
           windowId);
    return;
  }
  if (hostWindow &&
      (hostWindow.prefersFixedSquare ||
       WWNWestonDemoPrefersFixedSquare(nil, hostWindow.title))) {
    WWNLog("BRIDGE",
           @"Skipping injectWindowResize window=%llu (fixed-square weston demo)",
           windowId);
    return;
  }
#endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  {
    id iosHost = _windows[key];
    NSString *iosTitle = nil;
    if ([iosHost isKindOfClass:[WWNCompositorView_ios class]]) {
      iosTitle = ((WWNCompositorView_ios *)iosHost).accessibilityLabel;
    }
    NSString *iosClient =
        WWNIosResolveBundledClientIdForWindow(self, windowId);
    if (WWNWestonDemoPrefersFixedSquare(iosClient, iosTitle)) {
      WWNLog("BRIDGE",
             @"Skipping injectWindowResize window=%llu (fixed-square weston demo)",
             windowId);
      return;
    }
  }
#endif
  CGSize dims = CGSizeMake(width, height);
  _latestResizeDims[key] = [NSValue value:&dims withObjCType:@encode(CGSize)];
  NSTimeInterval debounce = kWWNResizeDebounceSeconds;
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  NSWindow *window = [self.windows objectForKey:key];
  if ([window isKindOfClass:[WWNWindow class]]) {
    WWNWindow *wwn = (WWNWindow *)window;
    // AppKit SSD edge drag sets inLiveResize; CSD xdg_toplevel.resize track
    // sets interactiveResizeInProgress. Both must stream configures mid-drag.
    if (wwn.inLiveResize || wwn.interactiveResizeInProgress) {
      debounce = 0.0;
    }
  }
#endif
  WWNLog("BRIDGE",
         @"Queue injectWindowResize window=%llu latest=%.0fx%.0f debounce=%.3fs live=%@",
         windowId, dims.width, dims.height, debounce,
         debounce == 0.0 ? @"yes" : @"no");
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(_drainPendingWindowResizeForId:)
                                             object:key];
  // Schedule on common modes; on macOS also include tracking mode so live edge-drag
  // continues delivering synchronized configure events while the mouse is down.
  NSArray<NSString *> *runLoopModes = @[ NSRunLoopCommonModes ];
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  runLoopModes = @[ NSRunLoopCommonModes, NSEventTrackingRunLoopMode ];
#endif
  [self performSelector:@selector(_drainPendingWindowResizeForId:)
             withObject:key
             afterDelay:debounce
                inModes:runLoopModes];
}

- (void)beginInteractiveResize:(uint64_t)windowId {
  if (!_rustCore || windowId == 0)
    return;
  WWNLog("BRIDGE", @"beginInteractiveResize window=%llu", windowId);
  WWNCoreBeginInteractiveResize(self->_rustCore, windowId);
}

- (void)endInteractiveResize:(uint64_t)windowId
                       width:(uint32_t)width
                      height:(uint32_t)height {
  if (!_rustCore || windowId == 0)
    return;
  WWNLog("BRIDGE", @"endInteractiveResize window=%llu size=%ux%u", windowId,
         width, height);
  WWNCoreEndInteractiveResize(self->_rustCore, windowId, width, height);
}

- (void)settleInteractiveResizeForId:(NSNumber *)windowIdNumber {
  if (![windowIdNumber isKindOfClass:[NSNumber class]])
    return;
  [self reconcileWindowResizeNow:windowIdNumber.unsignedLongLongValue];
}

- (void)reconcileWindowResizeNow:(uint64_t)windowId {
  if (!_rustCore)
    return;
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(windowId)];
  if (!window)
    return;
  NSSize contentSize = WWNWaylandContentSizeForWindow(window);
  uint32_t width = (uint32_t)MAX(1, lround(contentSize.width));
  uint32_t height = (uint32_t)MAX(1, lround(contentSize.height));
  // Settle configure clears xdg_toplevel.state.resizing even when size is
  // unchanged (required by xdg-shell / niri interactive-resize pattern).
  [self endInteractiveResize:windowId width:width height:height];
  NSNumber *key = @(windowId);
  CGSize dims = CGSizeMake(width, height);
  BOOL hasInFlightResize = [_resizeInFlightWindows containsObject:key];
  BOOL alreadySent = NO;
  NSValue *sentVal = _sentResizeDims[key];
  if (sentVal) {
    CGSize sentDims;
    [sentVal getValue:&sentDims];
    alreadySent = CGSizeEqualToSize(sentDims, dims);
  }
  if (alreadySent && !hasInFlightResize) {
    WWNLog("BRIDGE",
           @"Reconcile resize skipped window=%llu content=%ux%u (already sent, no in-flight)",
           windowId, width, height);
    return;
  }
  _latestResizeDims[key] = [NSValue value:&dims withObjCType:@encode(CGSize)];
  // Force one authoritative post-resize dispatch when stale/in-flight state
  // could leave host/client out of sync.
  [_sentResizeDims removeObjectForKey:key];
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(_drainPendingWindowResizeForId:)
                                             object:key];
  WWNLog("BRIDGE",
         @"Reconcile resize now window=%llu content=%ux%u inLive=%d",
         windowId, width, height, window.inLiveResize);
  [self _drainPendingWindowResizeForId:key];
#else
  // iOS/iPadOS/tvOS/watchOS/visionOS: settle configure after host layout resize.
  NSValue *dimsVal = _latestResizeDims[@(windowId)];
  uint32_t width = 0;
  uint32_t height = 0;
  if (dimsVal) {
    CGSize dims;
    [dimsVal getValue:&dims];
    width = (uint32_t)MAX(1, lround(dims.width));
    height = (uint32_t)MAX(1, lround(dims.height));
  }
  [self endInteractiveResize:windowId width:width height:height];
  NSNumber *key = @(windowId);
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(_drainPendingWindowResizeForId:)
                                             object:key];
  [self _drainPendingWindowResizeForId:key];
#endif
}

- (BOOL)requestHostCloseForWindowId:(uint64_t)windowId {
  if (!_rustCore || !_compositorThread) {
    return NO;
  }
  __block BOOL found = NO;
  [self _dispatchSyncToCompositor:^{
    found = WWNCoreRequestWindowClose(self->_rustCore, windowId);
  }];
  return found;
}

- (NSArray<NSNumber *> *)allHostWindowIds {
  return [_windows.allKeys copy] ?: @[];
}

#if TARGET_OS_IPHONE
- (void)_notifyHostWindowsDidChange {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:WWNHostWindowsDidChangeNotification
                      object:self];
  });
}

- (NSArray<NSNumber *> *)tabbedClientWindowIds {
  // iPadOS / visionOS: one scene per client. No in-window tab strip.
  if (_iosPerWindowHostingEnabled) {
    return @[];
  }
  NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
  NSArray<NSNumber *> *keys =
      [[_windows allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSNumber *key in keys) {
    UIView *view = _windows[key];
    // fullscreen_shell surfaces are display-only kiosk layers, not tabs.
    if ([view.accessibilityIdentifier
            isEqualToString:@"wwn.compositor.fullscreen-shell"]) {
      continue;
    }
    [ids addObject:key];
  }
  return ids;
}

- (NSString *)titleForHostWindowId:(uint64_t)windowId {
  UIView *view = _windows[@(windowId)];
  if (view.accessibilityLabel.length > 0) {
    return view.accessibilityLabel;
  }
  NSString *bundled =
      [WWNWaypipeRunner sharedRunner].activeIOSBundledClientId;
  if (bundled.length > 0) {
    return bundled;
  }
  return [NSString stringWithFormat:@"Client %llu", windowId];
}

- (void)focusTabbedClientWindowId:(uint64_t)windowId {
  UIView *view = _windows[@(windowId)];
  if (view.superview) {
    [view.superview bringSubviewToFront:view];
  }
  // In-window tabs (#84): only the selected client's surface is visible; the
  // others are hidden so switching tabs actually swaps what the user sees
  // (fill-primary surfaces otherwise stack opaquely and the raise alone is not
  // enough once a client repaints). fullscreen_shell kiosk layers are display
  // surfaces, not tabs. Leave their visibility untouched.
  NSArray<NSNumber *> *tabbed = [self tabbedClientWindowIds];
  NSSet<NSNumber *> *tabbedSet = [NSSet setWithArray:tabbed];
  for (NSNumber *wid in _windows.allKeys) {
    if (![tabbedSet containsObject:wid]) {
      continue;
    }
    UIView *client = _windows[wid];
    BOOL active = wid.unsignedLongLongValue == windowId;
    client.hidden = !active;
    [self setWindowActivated:wid.unsignedLongLongValue active:active];
  }
  [self injectKeyboardEnterForWindow:windowId keys:@[]];
}

- (UIView *)takePendingSceneClientViewForWindowId:(uint64_t)windowId {
  NSNumber *key = @(windowId);
  UIView *view = _pendingSceneClientViews[key];
  if (view) {
    [_pendingSceneClientViews removeObjectForKey:key];
  }
  return view;
}

- (void)registerClientHostWindow:(UIWindow *)window
                     forWindowId:(uint64_t)windowId {
  if (!window) {
    return;
  }
  _iosHostWindows[@(windowId)] = window;
}

- (BOOL)perWindowHostingEnabled {
  return _iosPerWindowHostingEnabled;
}

- (void)setClientHostWindowsHidden:(BOOL)hidden
                     forMachineId:(NSString *)machineId {
  for (NSNumber *key in _iosHostWindows.allKeys) {
    if (machineId.length > 0) {
      NSString *owner = _windowOwnerMachineIdByWindowId[key];
      if (owner.length > 0 && ![owner isEqualToString:machineId]) {
        continue;
      }
    }
    UIWindow *hostWindow = _iosHostWindows[key];
    hostWindow.hidden = hidden;
    if (!hidden) {
      [hostWindow makeKeyAndVisible];
    }
  }
}

- (void)setClientHostWindowHidden:(BOOL)hidden forWindowId:(uint64_t)windowId {
  UIWindow *hostWindow = _iosHostWindows[@(windowId)];
  if (!hostWindow) {
    return;
  }
  hostWindow.hidden = hidden;
  if (!hidden) {
    [hostWindow makeKeyAndVisible];
  }
}

- (BOOL)focusClientWindowsForMachineId:(NSString *)machineId {
  NSMutableArray<NSNumber *> *owned = [NSMutableArray array];
  for (NSNumber *key in _windows.allKeys) {
    if (machineId.length == 0) {
      [owned addObject:key];
      continue;
    }
    NSString *owner = _windowOwnerMachineIdByWindowId[key];
    if (owner.length == 0 || [owner isEqualToString:machineId]) {
      [owned addObject:key];
    }
  }
  if (owned.count == 0) {
    return NO;
  }
  [self setClientHostWindowsHidden:NO forMachineId:machineId];
  uint64_t focusId = owned.lastObject.unsignedLongLongValue;
  for (NSNumber *key in owned) {
    UIView *view = _windows[key];
    if (view.superview) {
      [view.superview bringSubviewToFront:view];
    }
  }
  [self focusTabbedClientWindowId:focusId];
  return YES;
}
#endif

- (BOOL)requestForceDestroyHostWindowForWindowId:(uint64_t)windowId {
  if (!_rustCore || !_compositorThread) {
    return NO;
  }
  __block BOOL ok = NO;
  [self _dispatchSyncToCompositor:^{
    ok = WWNCoreForceDestroyHostWindow(self->_rustCore, windowId);
  }];
  if (ok) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self pollAndHandleWindowEvents];
    });
  }
  return ok;
}

/// Dispatch at most one resize block per window to the compositor queue.
/// When the block completes, it checks whether newer dimensions arrived
/// for that window while it was running and re-dispatches if necessary.
- (void)_drainPendingWindowResizeForId:(NSNumber *)key {
  if ([_resizeInFlightWindows containsObject:key]) {
    WWNLog("BRIDGE", @"Resize drain skipped (in-flight) window=%llu",
           key.unsignedLongLongValue);
    return;
  }

  NSValue *latestVal = _latestResizeDims[key];
  NSValue *sentVal = _sentResizeDims[key];
  if (!latestVal)
    return;
  CGSize latestDims, sentDims;
  [latestVal getValue:&latestDims];
  if (sentVal) {
    [sentVal getValue:&sentDims];
    if (CGSizeEqualToSize(latestDims, sentDims)) {
      WWNLog("BRIDGE",
             @"Resize drain skipped (already sent) window=%llu dims=%.0fx%.0f",
             key.unsignedLongLongValue, latestDims.width, latestDims.height);
      return;
    }
  }

  [_resizeInFlightWindows addObject:key];
  _sentResizeDims[key] = latestVal;
  CGSize dims = latestDims;
  uint32_t w = (uint32_t)MAX(1, lround(dims.width));
  uint32_t h = (uint32_t)MAX(1, lround(dims.height));
  uint64_t wid = key.unsignedLongLongValue;
  WWNLog("BRIDGE",
         @"Dispatching injectWindowResize window=%llu raw=%.2fx%.2f rounded=%ux%u",
         wid, dims.width, dims.height, w, h);

  [self _dispatchToRust:^{
    WWNCoreInjectWindowResize(self->_rustCore, wid, w, h);
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_resizeInFlightWindows removeObject:key];
      [self _drainPendingWindowResizeForId:key];
    });
  }];
}

- (void)setWindowActivated:(uint64_t)windowId active:(BOOL)active {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreSetWindowActivated(self->_rustCore, windowId, active);
  }];
}
- (void)injectModifiersWithDepressed:(uint32_t)depressed
                             latched:(uint32_t)latched
                              locked:(uint32_t)locked
                               group:(uint32_t)group {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNLog("BRIDGE",
           @"Injecting modifiers: depressed=0x%x latched=0x%x "
           @"locked=0x%x",
           depressed, latched, locked);
    WWNCoreInjectModifiers(self->_rustCore, depressed, latched, locked, group);
  }];
}

// MARK: - Configuration

- (void)setOutputWidth:(uint32_t)w height:(uint32_t)h scale:(float)s {
  if (!_rustCore)
    return;

  _latestOutputW = w;
  _latestOutputH = h;
  _latestOutputScale = s;
  if (w > 0 && h > 0) {
    _hasObservedRealOutputSize = YES;
  }
  [self _drainPendingOutputResize];
}

/// Seed wl_output from the live host surface (window / compositor container /
/// main screen). Prefer this over inventing a phone-portrait fallback.
- (BOOL)seedOutputSizeFromLiveHostSurface {
  uint32_t w = 0;
  uint32_t h = 0;
  float s = 1.0f;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIView *host = self.containerView;
  if (host) {
    CGSize sz = host.bounds.size;
    if (sz.width > 1.0 && sz.height > 1.0) {
      w = (uint32_t)lround(sz.width);
      h = (uint32_t)lround(sz.height);
      CGFloat scale = host.traitCollection.displayScale;
      if (scale <= 0.0 && host.window) {
        scale = host.window.traitCollection.displayScale;
      }
      if (scale <= 0.0) {
        scale = 1.0;
      }
      s = (float)scale;
    }
  }
#if !TARGET_OS_VISION
  if ((w == 0 || h == 0) && [UIScreen mainScreen]) {
    CGRect bounds = [UIScreen mainScreen].bounds;
    if (bounds.size.width > 1.0 && bounds.size.height > 1.0) {
      w = (uint32_t)lround(bounds.size.width);
      h = (uint32_t)lround(bounds.size.height);
      s = (float)[UIScreen mainScreen].scale;
    }
  }
#endif
#else
  for (NSNumber *key in [_windows allKeys]) {
    id candidate = [_windows objectForKey:key];
    if (![candidate isKindOfClass:[WWNWindow class]]) {
      continue;
    }
    NSWindow *window = (NSWindow *)candidate;
    NSSize size = [window contentRectForFrameRect:window.frame].size;
    if (size.width > 1.0 && size.height > 1.0) {
      w = (uint32_t)lround(size.width);
      h = (uint32_t)lround(size.height);
      s = (float)(window.backingScaleFactor > 0 ? window.backingScaleFactor
                                               : 1.0);
      break;
    }
  }
  if ((w == 0 || h == 0) && [NSApp keyWindow]) {
    NSWindow *appWin = [NSApp keyWindow];
    if (![appWin isKindOfClass:[WWNWindow class]]) {
      NSSize size = [appWin contentRectForFrameRect:appWin.frame].size;
      if (size.width > 1.0 && size.height > 1.0) {
        w = (uint32_t)lround(size.width);
        h = (uint32_t)lround(size.height);
        s = (float)(appWin.backingScaleFactor > 0 ? appWin.backingScaleFactor
                                                  : 1.0);
      }
    }
  }
  if ((w == 0 || h == 0) && [NSApp mainWindow]) {
    NSWindow *appWin = [NSApp mainWindow];
    if (![appWin isKindOfClass:[WWNWindow class]]) {
      NSSize size = [appWin contentRectForFrameRect:appWin.frame].size;
      if (size.width > 1.0 && size.height > 1.0) {
        w = (uint32_t)lround(size.width);
        h = (uint32_t)lround(size.height);
        s = (float)(appWin.backingScaleFactor > 0 ? appWin.backingScaleFactor
                                                  : 1.0);
      }
    }
  }
  // Do not seed from the full NSScreen. That made nested niri's first
  // configure huge, then AppKit/OWL shrank the NSWindow during init and
  // niri kept drawing the large output.
  if ((w == 0 || h == 0)) {
    w = 1024;
    h = 768;
    s = [NSScreen mainScreen] ? (float)[NSScreen mainScreen].backingScaleFactor
                              : 1.0f;
  }
#endif

  if (w == 0 || h == 0) {
    return NO;
  }
  if (s <= 0) {
    s = 1.0f;
  }
  if (w == _latestOutputW && h == _latestOutputH &&
      fabsf(s - _latestOutputScale) < 0.001f) {
    _hasObservedRealOutputSize = YES;
    return YES;
  }
  WWNLog("BRIDGE", @"Seeding output from live host surface: %ux%u @ %.1fx", w,
         h, s);
  [self setOutputWidth:w height:h scale:s];
  return YES;
}

- (void)currentOutputWidth:(uint32_t *)width
                    height:(uint32_t *)height
                     scale:(float *)scale {
  uint32_t w = _sentOutputW ?: _latestOutputW;
  uint32_t h = _sentOutputH ?: _latestOutputH;
  float s = _sentOutputScale > 0 ? _sentOutputScale : _latestOutputScale;
  if ((w == 0 || h == 0) && !_hasObservedRealOutputSize) {
    [self seedOutputSizeFromLiveHostSurface];
    w = _sentOutputW ?: _latestOutputW;
    h = _sentOutputH ?: _latestOutputH;
    s = _sentOutputScale > 0 ? _sentOutputScale : _latestOutputScale;
  }
  // Last-resort phone portrait only before any real host size is known.
  if (!_hasObservedRealOutputSize) {
    if (w == 0)
      w = 420;
    if (h == 0)
      h = 912;
  }
  if (s <= 0)
    s = 1.0f;
  if (width)
    *width = w;
  if (height)
    *height = h;
  if (scale)
    *scale = s;
}

- (void)latestOutputWidth:(uint32_t *)width
                   height:(uint32_t *)height
                    scale:(float *)scale {
  uint32_t w = _latestOutputW;
  uint32_t h = _latestOutputH;
  float s = _latestOutputScale;
  if ((w == 0 || h == 0) && !_hasObservedRealOutputSize) {
    [self seedOutputSizeFromLiveHostSurface];
    w = _latestOutputW;
    h = _latestOutputH;
    s = _latestOutputScale;
  }
  // Last-resort phone portrait only before any real host size is known.
  if (!_hasObservedRealOutputSize) {
    if (w == 0)
      w = 420;
    if (h == 0)
      h = 912;
  }
  if (s <= 0)
    s = 1.0f;
  if (width)
    *width = w;
  if (height)
    *height = h;
  if (scale)
    *scale = s;
}

#if TARGET_OS_IPHONE
- (void)prepareOutputSizeForNativeClientLaunch {
  [self prepareOutputSizeForNativeClientLaunchWithClientId:nil];
}

- (void)prepareOutputSizeForNativeClientLaunchWithClientId:(NSString *)clientId {
#else
- (void)prepareOutputSizeForNativeClientLaunch {
  [self prepareOutputSizeForNativeClientLaunchWithClientId:nil];
}

- (void)prepareOutputSizeForNativeClientLaunchWithClientId:(NSString *)clientId {
#endif
  // Per-window hosting: the global wl_output stays at the real display size.
  // A client's window size comes from first-commit trust (0x0 initial
  // configure) and per-window output geometry (SetOutputGeometryForWindow),
  // never from pre-sizing the global output to a demo launch size, which
  // reconfigured every other connected client.

  void (^seedOnMain)(void) = ^{
#if TARGET_OS_IPHONE
    NSDictionary *userInfo = clientId ? @{@"clientId" : clientId} : nil;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:WWNNativeClientWillLaunchNotification
                      object:nil
                    userInfo:userInfo];
#endif
    [self seedOutputSizeFromLiveHostSurface];
  };
  const BOOL onMain = [NSThread isMainThread];
  if (onMain) {
    seedOnMain();
  } else {
    dispatch_sync(dispatch_get_main_queue(), seedOnMain);
  }

  // Never sleep the main thread waiting for the async Rust drain. Kmscube
  // Start prepares from the main queue.
  if (onMain) {
    uint32_t w = _latestOutputW;
    uint32_t h = _latestOutputH;
    if (w > 0 && h > 0) {
      WWNLog("BRIDGE",
             @"Native client launch output ready (main): %ux%u @ %.1fx", w, h,
             _latestOutputScale > 0 ? _latestOutputScale : 1.0f);
    } else {
      WWNLog("BRIDGE",
             @"Native client launch on main with unset output. Client will "
             @"negotiate size");
    }
    return;
  }

  const NSTimeInterval step = 0.01;
  NSTimeInterval waited = 0;
  const NSTimeInterval timeout = 0.35;
  uint32_t lastW = 0;
  uint32_t lastH = 0;
  int stableFrames = 0;

  while (waited < timeout) {
    uint32_t w = _latestOutputW;
    uint32_t h = _latestOutputH;
    BOOL synced = (w > 0 && h > 0 && w == _sentOutputW && h == _sentOutputH &&
                   !_outputResizeInFlight);
    if (synced && w == lastW && h == lastH) {
      stableFrames++;
      if (stableFrames >= 1) {
        WWNLog("BRIDGE",
               @"Native client launch output ready: %ux%u @ %.1fx", w, h,
               _latestOutputScale > 0 ? _latestOutputScale : 1.0f);
        return;
      }
    } else {
      stableFrames = 0;
    }
    lastW = w;
    lastH = h;
    [NSThread sleepForTimeInterval:step];
    waited += step;
  }

  if (_latestOutputW == 0 || _latestOutputH == 0) {
    void (^reseed)(void) = ^{
      [self seedOutputSizeFromLiveHostSurface];
    };
    if ([NSThread isMainThread]) {
      reseed();
    } else {
      dispatch_sync(dispatch_get_main_queue(), reseed);
    }
  }

  WWNLog("BRIDGE",
         @"Native client launch output wait timed out; using latest %ux%u @ %.1fx",
         _latestOutputW, _latestOutputH,
         _latestOutputScale > 0 ? _latestOutputScale : 1.0f);
}
/// block on the compositor queue at a time.
- (void)_drainPendingOutputResize {
  if (_outputResizeInFlight)
    return;
  uint32_t w = _latestOutputW;
  uint32_t h = _latestOutputH;
  float s = _latestOutputScale;
  if (w == _sentOutputW && h == _sentOutputH && s == _sentOutputScale)
    return;

  _outputResizeInFlight = YES;
  _sentOutputW = w;
  _sentOutputH = h;
  _sentOutputScale = s;

  [self _dispatchToRust:^{
    WWNCoreSetOutputSize(self->_rustCore, w, h, s);
    WWNLog("BRIDGE", @"Output: %ux%u @ %.1fx", w, h, s);
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_outputResizeInFlight = NO;
      [self _drainPendingOutputResize];
    });
  }];
}

- (void)setSafeAreaInsetsTop:(int32_t)top
                       right:(int32_t)right
                      bottom:(int32_t)bottom
                        left:(int32_t)left {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreSetSafeAreaInsets(self->_rustCore, top, right, bottom, left);
    WWNLog("BRIDGE", @"Safe area insets: top=%d right=%d bottom=%d left=%d",
           top, right, bottom, left);
  }];
}

- (void)setForceSSD:(BOOL)enabled {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreSetForceSSD(self->_rustCore, enabled);
    WWNLog("BRIDGE", @"Force SSD set to: %d", enabled);
  }];
}

// Force SSD per-machine (#120): stage the decoration policy for the NEXT
// machine's client launch. Unlike -setForceSSD:, this does not touch the
// global default or restyle any already-connected machine, so concurrent
// CSD + SSD machines never stomp each other.
- (void)setForceSSDForClientLaunch:(BOOL)enabled {
  if (!_rustCore) {
    return;
  }
  // Must be on the compositor thread before NSTask connects. Async dispatch
  // raced nested weston mapping against a still-empty pending policy.
  [self _dispatchSyncToCompositor:^{
    WWNCoreSetForceSSDForClientLaunch(self->_rustCore, enabled);
    WWNLog("BRIDGE", @"Force SSD staged for next client launch: %d", enabled);
  }];
}

- (void)setFillsHostForClientLaunch:(BOOL)fillsHost {
  if (!_rustCore) {
    return;
  }
  [self _dispatchSyncToCompositor:^{
    WWNCoreSetFillsHostForClientLaunch(self->_rustCore, fillsHost);
    WWNLog("BRIDGE", @"Fill-host staged for next client launch: %d", fillsHost);
  }];
}
- (void)setKeyboardRepeatRate:(int32_t)rate delay:(int32_t)delay {
}
- (void)notifyFrameComplete {
}
- (void)notifyFramePresentedForSurface:(uint32_t)surfaceId
                                buffer:(uint64_t)bufferId
                             timestamp:(uint32_t)timestamp {
  if (_rustCore) {
    [self _dispatchToRust:^{
      WWNCoreNotifyFramePresented(self->_rustCore, surfaceId, bufferId, timestamp);
    }];
  }
}
- (void)flushFrameCallbacks {
}
- (NSArray<NSNumber *> *)pollRedrawRequests {
  return @[];
}

// MARK: - Window Event Polling

// C FFI for window events
typedef enum : uint32_t {
  CWindowEventTypeCreated = 0,
  CWindowEventTypeDestroyed = 1,
  CWindowEventTypeTitleChanged = 2,
  CWindowEventTypeSizeChanged = 3,
  CWindowEventTypePopupCreated = 4,
  CWindowEventTypePopupRepositioned = 5,
  CWindowEventTypeMoveRequested = 6,
  CWindowEventTypeResizeRequested = 7,
  CWindowEventTypeDecorationModeChanged = 8,
  CWindowEventTypeMinimizeRequested = 9,
  CWindowEventTypeMaximizeRequested = 10,
  CWindowEventTypeUnmaximizeRequested = 11,
  CWindowEventTypeCursorShapeChanged = 12,
  CWindowEventTypeHostLocked = 13,
  CWindowEventTypeFullscreenRequested = 14,
  CWindowEventTypeUnfullscreenRequested = 15,
  CWindowEventTypeCloseRequested = 16,
} CWindowEventType;

typedef struct CWindowEvent {
  uint64_t event_type;
  uint64_t window_id;
  uint32_t surface_id;
  char *title;
  uint32_t width;
  uint32_t height;
  uint64_t parent_id;
  int32_t x;
  int32_t y;
  uint8_t decoration_mode;  // 0 = ClientSide, 1 = ServerSide
  uint8_t fullscreen_shell; // 0 = no, 1 = yes (kiosk - no host chrome)
  uint8_t host_locked;      // 0 = no, 1 = yes (embedded / non-floating)
  uint8_t edges;            // xdg_toplevel resize_edge
  uint8_t size_kind;        // 0=Frame, 1=Content, 2=Buffer
  uint8_t size_cause;       // 0=Unknown, 1=HostConfigure, 2=ClientCommit, 3=OutputModeChange
  uint8_t fills_host;       // nested weston/niri / terminals
  uint32_t configure_serial;
  uint64_t transaction_id;
} CWindowEvent;

extern CWindowEvent *WWNCorePopWindowEvent(void *core);
extern void WWNWindowEventFree(CWindowEvent *event);

// Legacy struct for compatibility if needed
typedef struct CWindowInfo {
  uint64_t window_id;
  uint32_t width;
  uint32_t height;
  char *title;
} CWindowInfo;

extern uint32_t WWNCorePendingWindowCount(const void *core);
extern CWindowInfo *WWNCorePopPendingWindow(void *core);
extern void WWNWindowInfoFree(CWindowInfo *info);

/// Route a single window event to the appropriate handler.
/// Must be called on the main thread (handlers create/modify UIKit/AppKit
/// views).
- (void)_dispatchWindowEvent:(CWindowEvent *)event {
  switch (event->event_type) {
  case CWindowEventTypeCreated:
    [self handleWindowCreated:event];
    break;
  case CWindowEventTypeDestroyed:
    [self handleWindowDestroyed:event];
    break;
  case CWindowEventTypeTitleChanged:
    [self handleWindowTitleChanged:event];
    break;
  case CWindowEventTypeSizeChanged:
    [self handleWindowSizeChanged:event];
    break;
  case CWindowEventTypePopupCreated:
    [self handlePopupCreated:event];
    break;
  case CWindowEventTypePopupRepositioned:
    [self handlePopupRepositioned:event];
    break;
  case CWindowEventTypeMoveRequested:
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [self handleWindowMoveRequested:event];
#endif
    break;
  case CWindowEventTypeResizeRequested:
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [self handleWindowResizeRequested:event];
#endif
    break;
  case CWindowEventTypeDecorationModeChanged:
    [self handleDecorationModeChanged:event];
    break;
  case CWindowEventTypeMinimizeRequested:
    [self handleWindowMinimizeRequested:event];
    break;
  case CWindowEventTypeMaximizeRequested:
    [self handleWindowMaximizeRequested:event];
    break;
  case CWindowEventTypeUnmaximizeRequested:
    [self handleWindowUnmaximizeRequested:event];
    break;
  case CWindowEventTypeFullscreenRequested:
    [self handleWindowFullscreenRequested:event];
    break;
  case CWindowEventTypeUnfullscreenRequested:
    [self handleWindowUnfullscreenRequested:event];
    break;
  case CWindowEventTypeCloseRequested:
    [self handleWindowCloseRequested:event];
    break;
  case CWindowEventTypeCursorShapeChanged:
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [self handleCursorShapeChanged:event];
#endif
    break;
  case CWindowEventTypeHostLocked:
    [self handleWindowHostLocked:event];
    break;
  }
}

/// Legacy entry point: pops and handles all pending window events
/// synchronously.  In the new architecture the compositor tick handles
/// this via _dispatchWindowEvent:, but this method is kept for any
/// external callers that need manual polling.
- (void)pollAndHandleWindowEvents {
  if (!_rustCore) {
    return;
  }

  while (true) {
    CWindowEvent *event = WWNCorePopWindowEvent(_rustCore);
    if (!event)
      break;

    [self _dispatchWindowEvent:event];
    WWNWindowEventFree(event);
  }
}

// Window Management
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (NSMutableDictionary<NSNumber *, id> *)windows {
  return _windows;
#else
- (NSMutableDictionary<NSNumber *, WWNWindow *> *)windows {
  return (NSMutableDictionary<NSNumber *, WWNWindow *> *)_windows;
#endif
}

// Defined for all platforms: on desktop macOS it miniaturizes the AppKit
// window; on iOS/simulator (and other UIKit targets) it posts a notification
// so the scene delegate can return to the Wawona UI while keeping the session
// alive. Kept outside the desktop-only block so the unguarded dispatch call in
// _dispatchWindowEvent: resolves on every target.
- (void)handleWindowMinimizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowMinimizeRequested: id=%llu", event->window_id);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (window && !window.isMiniaturized && !window.wwnMiniaturizeInProgress) {
    [window miniaturize:nil];
  }
#else
  NSNumber *windowId = @(event->window_id);
  NSString *owner =
      _windowOwnerMachineIdByWindowId[windowId]
          ?: [WWNMachineProfileStore activeMachineId] ?: @"";
  if (_iosPerWindowHostingEnabled) {
    [self setClientHostWindowHidden:YES forWindowId:event->window_id];
  } else {
    [self setClientHostWindowsHidden:YES forMachineId:owner];
  }
  NSMutableDictionary *info =
      [NSMutableDictionary dictionaryWithObject:windowId forKey:@"windowId"];
  if (owner.length > 0) {
    info[@"machineId"] = owner;
  }
  [[NSNotificationCenter defaultCenter]
      postNotificationName:WWNClientMinimizeRequestedNotification
                    object:self
                  userInfo:info];
#endif
}

// Shared across Apple hosts (must stay outside the desktop-only block so the
// unguarded DecorationModeChanged dispatch resolves on iOS/tvOS/watch/vision).
- (void)handleDecorationModeChanged:(CWindowEvent *)event {
  BOOL useServerDecorations = (event->decoration_mode == 1);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // UIKit hosts: ServerSide → opaque fill plate; ClientSide → clear so CSD
  // alpha / content_rect crop can composite (WSLg shadow-strip analogue).
  id host = _windows[@(event->window_id)];
  if ([host isKindOfClass:[WWNCompositorView_ios class]]) {
    [(WWNCompositorView_ios *)host setWaylandFrameOpaque:useServerDecorations];
  } else if ([self.containerView isKindOfClass:[WWNCompositorView_ios class]]) {
    [(WWNCompositorView_ios *)self.containerView
        setWaylandFrameOpaque:useServerDecorations];
  }
  WWNLog("BRIDGE", @"Decoration mode changed for window %llu: %s (UIKit)",
         event->window_id,
         useServerDecorations ? "ServerSide" : "ClientSide");
#else
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || ![window isKindOfClass:[WWNWindow class]] || window.hostLocked)
    return;
  NSWindowStyleMask styleMask;
  if (useServerDecorations) {
    styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable;
  } else {
    styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskMiniaturizable;
  }
  if (!window.prefersFixedSquare) {
    styleMask |= NSWindowStyleMaskResizable;
  }
  // Avoid styleMask thrash (#53): compare chrome-relevant bits only so leftover
  // FullSizeContentView / textured bits from kiosk transitions don't block SSD.
  NSWindowStyleMask chromeBits =
      NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
      NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
      NSWindowStyleMaskBorderless | NSWindowStyleMaskFullSizeContentView;
  BOOL styleNeedsUpdate =
      ((window.styleMask & chromeBits) != (styleMask & chromeBits));
  BOOL presentationNeedsUpdate =
      (window.clientSideDecorated == useServerDecorations);
  if (styleNeedsUpdate) {
    window.processingResize = YES;
    [window setStyleMask:styleMask];
    window.processingResize = NO;
  }
  if (styleNeedsUpdate || presentationNeedsUpdate) {
    [window applyPresentationPolicyForServerSideDecorations:useServerDecorations];
    [self wwnApplySurfaceDragPolicyForWindow:window];
  }

  BOOL sizeSynced =
      [_windowsWithInitialSizeSynced containsObject:@(event->window_id)];
  NSSize contentSize = [window contentRectForFrameRect:window.frame].size;
  if (sizeSynced && contentSize.width > 0 && contentSize.height > 0 &&
      !window.prefersFixedSquare) {
    WWNLog("BRIDGE",
           @"Decoration mode changed for window %llu: %s. Injecting "
           @"content resize %.0fx%.0f",
           event->window_id,
           useServerDecorations ? "ServerSide" : "ClientSide",
           contentSize.width, contentSize.height);
    [self injectWindowResize:event->window_id
                       width:(uint32_t)contentSize.width
                      height:(uint32_t)contentSize.height];
  } else {
    WWNLog("BRIDGE", @"Decoration mode changed for window %llu: %s",
           event->window_id,
           useServerDecorations ? "ServerSide" : "ClientSide");
  }
#endif
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static inline NSSize WWNWaylandContentSizeForWindow(NSWindow *window) {
  // Keep Wayland<->AppKit resize math based on the actual frame->content
  // conversion. contentLayoutRect may exclude layout-managed title/toolbar
  // regions and can drift during edge-resize loops.
  return [window contentRectForFrameRect:window.frame].size;
}

static inline NSString *WWNSizeCauseString(uint8_t cause) {
  switch (cause) {
  case 1:
    return @"HostConfigure";
  case 2:
    return @"ClientCommit";
  case 3:
    return @"OutputModeChange";
  default:
    return @"Unknown";
  }
}

static inline NSString *WWNSizeKindString(uint8_t kind) {
  switch (kind) {
  case 0:
    return @"Frame";
  case 1:
    return @"Content";
  case 2:
    return @"Buffer";
  default:
    return @"Unknown";
  }
}

- (void)handleWindowCreated:(CWindowEvent *)event {
  WWNLog("BRIDGE",
         @"handleWindowCreated: id=%llu size=%ux%u decoration_mode=%u "
         @"fullscreen_shell=%u host_locked=%u",
         event->window_id, event->width, event->height, event->decoration_mode,
         event->fullscreen_shell, event->host_locked);

  BOOL shouldInjectResize = NO;
  BOOL shouldUpdateOutput = NO; // Whether wl_output.mode must also change.

  BOOL kiosk = event->host_locked || event->fullscreen_shell;
  BOOL useServerDecorations = !kiosk && (event->decoration_mode == 1);

  NSString *createdTitle = (event->title && strlen(event->title) > 0)
                               ? [NSString stringWithUTF8String:event->title]
                               : @"";
  NSString *bundledClient = WWNResolveActiveMachineBundledClientId();
  // Same fill set as iOS: nested weston/niri (and terminals) need a non-zero
  // xdg configure. Weston's wayland backend copies configure_width/height into
  // its output; 0x0 means no mode and a blank parent window. Demos stay OWL
  // client-pick (64px placeholder, configure 0x0).
  BOOL fillHost = event->fills_host ||
      (!kiosk && !WWNWestonDemoPrefersFixedSquare(bundledClient, createdTitle) &&
       (WWNBundledClientFillsHost(bundledClient) ||
        WWNTitleIndicatesNestedCompositor(createdTitle)));

  NSRect contentRect;
  if (kiosk) {
    uint32_t kw = _latestOutputW > 0 ? _latestOutputW : event->width;
    uint32_t kh = _latestOutputH > 0 ? _latestOutputH : event->height;
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    contentRect =
        NSMakeRect(screenFrame.origin.x, screenFrame.origin.y, kw, kh);
    shouldInjectResize = YES;
    if (event->fullscreen_shell) {
      shouldUpdateOutput = YES;
    }
  } else if (fillHost) {
    // Match the first xdg configure already sent (event size). A second
    // inject at a different _latestOutputW during init is what left nested
    // niri drawing the large mode into a shrunken NSWindow.
    uint32_t fw = event->width > 0 ? event->width
                                   : (_latestOutputW > 0 ? _latestOutputW : 1024);
    uint32_t fh = event->height > 0 ? event->height
                                    : (_latestOutputH > 0 ? _latestOutputH : 768);
    contentRect = NSMakeRect(100, 100, fw, fh);
    shouldInjectResize = NO;
    shouldUpdateOutput = YES;
    WWNLog("BRIDGE",
           @"macOS fill-host window=%llu client='%@' title='%@' %ux%u "
           @"(same as first configure; no map inject)",
           event->window_id, bundledClient ?: @"(nil)", createdTitle, fw, fh);
  } else {
    // OWL / xdg-shell: WindowCreated carries 0×0 until the client commits.
    // Use a tiny placeholder and never inject a configure here. Injecting
    // output/placeholder size forces weston-simple-shm to grow and leaves
    // weston-flower/smoke (fixed 200×200) inside a giant host window.
    uint32_t placeholderW = event->width > 0 ? event->width : 64;
    uint32_t placeholderH = event->height > 0 ? event->height : 64;
    if (_latestOutputW > 0 && _latestOutputH > 0 &&
        placeholderW == _latestOutputW && placeholderH == _latestOutputH) {
      placeholderW = 64;
      placeholderH = 64;
    }
    contentRect = NSMakeRect(100, 100, placeholderW, placeholderH);
    shouldInjectResize = NO;
  }
  NSString *title = createdTitle;
  BOOL fixedSquare = WWNWestonDemoPrefersFixedSquare(bundledClient, title);
  NSWindowStyleMask styleMask;
  if (useServerDecorations) {
    styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable;
  } else {
    styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskMiniaturizable;
  }
  if (!fixedSquare) {
    styleMask |= NSWindowStyleMaskResizable;
  }

  WWNWindow *window =
      [[WWNWindow alloc] initWithContentRect:contentRect
                                   styleMask:styleMask
                                     backing:NSBackingStoreBuffered
                                       defer:NO];

  window.wwnWindowId = event->window_id;
  window.hostLocked = kiosk;
  [window setTitle:title];
  window.prefersFixedSquare = fixedSquare;
  window.fillsHost = fillHost;
  if (fillHost) {
    [_windowsWithInitialSizeSynced addObject:@(event->window_id)];
  }

  // Create content view in window-local coordinates.
  // `contentRect` includes screen-space origin; using it directly as an NSView
  // frame can offset the compositor host view and leave visible borders.
  NSRect contentViewRect =
      NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height);
  WWNView *contentView = [[WWNView alloc] initWithFrame:contentViewRect];
  contentView.wantsLayer = YES;
  contentView.layer.backgroundColor =
      fillHost ? [[NSColor blackColor] CGColor] : [[NSColor clearColor] CGColor];
  // Never upscale a smaller Wayland buffer into the content view. Host
  // content size must track the committed buffer (xdg / OWL); Resize would
  // silently stretch flower/smoke 200×200 into a wrong-sized window.
  contentView.layer.contentsGravity = kCAGravityTopLeft;
  contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  [window setContentView:contentView];
  [window makeFirstResponder:contentView];
  [window applyPresentationPolicyForServerSideDecorations:useServerDecorations];
  if (!kiosk) {
    [window setCollectionBehavior:(NSWindowCollectionBehaviorFullScreenPrimary |
                                   NSWindowCollectionBehaviorManaged)];
  }

  if (kiosk) {
    [window setFrame:contentRect display:NO];
    [window setMovable:NO];
    [window setMovableByWindowBackground:NO];
  } else {
    [window center];
    [self wwnApplySurfaceDragPolicyForWindow:window];
  }
  // Content stays transparent until the first buffer, but show the frame so
  // macOS users can see/focus the client window immediately.
  if (!kiosk) {
    [window orderFrontRegardless];
  }
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNKeepServiceHostOutOfDock();
#endif

  [_windows setObject:window forKey:@(event->window_id)];
  NSString *ownerMachineId = [WWNMachineProfileStore activeMachineId];
  if (ownerMachineId.length > 0) {
    _windowOwnerMachineIdByWindowId[@(event->window_id)] = ownerMachineId;
  }
  if (!kiosk) {
    WWNMachineProfile *ownerProfile =
        ownerMachineId.length > 0 ? [WWNMachineProfileStore profileById:ownerMachineId]
                                   : nil;
    if ([WWNMachineProfileStore resolvedAlwaysOnTopForProfile:ownerProfile]) {
      window.level = NSFloatingWindowLevel;
    }
  }
  WWNLog("BRIDGE", @"Created window %llu: %@ (total windows: %lu)",
         event->window_id, title, (unsigned long)[_windows count]);

  // Send activated configure immediately so subprocess clients (weston-terminal,
  // demo clients) commit their first buffer without waiting for keyboard focus.
  {
    uint64_t windowId = event->window_id;
    [self _dispatchToRust:^{
      WWNCoreSetWindowActivatedSilent(self->_rustCore, windowId, true);
      WWNCoreFlushClients(self->_rustCore);
    }];
  }

  // If the window was placed at a default size (smaller than what the
  // Wayland client requested), update wl_output.mode first, then inject
  // the xdg_toplevel configure resize.
  //
  // Order matters: the output-mode update must arrive at the Rust core
  // BEFORE the configure so that nested compositors (Weston) see a
  // consistent wl_output.mode matching the configure dimensions.  Both
  // calls use the same serial compositor queue, so FIFO ordering is
  // guaranteed as long as we call setOutputWidth:… before injectWindowResize:.
  if (shouldInjectResize) {
    NSSize contentSize = WWNWaylandContentSizeForWindow(window);
    WWNLog("BRIDGE", @"Injecting initial resize for window %llu: %.0fx%.0f%@",
           event->window_id, contentSize.width, contentSize.height,
           shouldUpdateOutput ? @" (+ output mode update)" : @"");

    if (shouldUpdateOutput && contentSize.width > 0 && contentSize.height > 0) {
      // Update wl_output.mode for **this** window's client only so nested compositors
      // see the drawable size. Global setOutputWidth reconfigured every xdg_toplevel
      // and broadcast output mode to all clients, freezing unrelated sessions.
      uint64_t wid = event->window_id;
      uint32_t ow = (uint32_t)MAX(1, lround(contentSize.width));
      uint32_t oh = (uint32_t)MAX(1, lround(contentSize.height));
      // Nested compositors size from wl_output.mode and xdg in points.
      // Advertising backingScale here created a 2x framebuffer and made
      // later configures fail mode-switch. Direct clients still see the
      // global HiDPI output.
      float s = 1.0f;
      [self _dispatchToRust:^{
        WWNCoreSetOutputGeometryForWindow(self->_rustCore, wid, ow, oh, s);
      }];
    }

    [self injectWindowResize:event->window_id
                       width:(uint32_t)MAX(1, lround(contentSize.width))
                      height:(uint32_t)MAX(1, lround(contentSize.height))];
  } else if (fillHost && shouldUpdateOutput) {
    NSSize contentSize = WWNWaylandContentSizeForWindow(window);
    if (contentSize.width > 0 && contentSize.height > 0) {
      uint64_t wid = event->window_id;
      uint32_t ow = (uint32_t)MAX(1, lround(contentSize.width));
      uint32_t oh = (uint32_t)MAX(1, lround(contentSize.height));
      [self _dispatchToRust:^{
        WWNCoreSetOutputGeometryForWindow(self->_rustCore, wid, ow, oh, 1.0f);
      }];
    }
  }
}

- (void)handleWindowHostLocked:(CWindowEvent *)event {
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || ![window isKindOfClass:[WWNWindow class]])
    return;

  window.hostLocked = YES;
  [window setStyleMask:NSWindowStyleMaskBorderless |
                       NSWindowStyleMaskFullSizeContentView];
  [window setMovable:NO];
  [window setMovableByWindowBackground:NO];

  uint32_t kw = event->width > 0 ? event->width
                                 : (_latestOutputW > 0 ? _latestOutputW : 800);
  uint32_t kh = event->height > 0 ? event->height
                                  : (_latestOutputH > 0 ? _latestOutputH : 600);
  NSRect screenFrame = [[NSScreen mainScreen] frame];
  NSRect frame = NSMakeRect(screenFrame.origin.x, screenFrame.origin.y, kw, kh);
  window.processingResize = YES;
  [window setFrame:frame display:NO];
  window.processingResize = NO;

  [self injectWindowResize:event->window_id width:kw height:kh];
  WWNLog("BRIDGE", @"Host-locked window %llu to %.0fx%.0f (kiosk)",
         event->window_id, (CGFloat)kw, (CGFloat)kh);
}

/// Apply host chrome drag policy from xdg-decoration mode. Never from app_id.
///
/// Weston flower/simple-egl drag by calling `xdg_toplevel.move` on BTN_LEFT
/// (see upstream `window_move` / flower `button_handler`). Smoke has no such
/// handler. The host must not invent whole-surface drag via
/// `movableByWindowBackground` or mouseDown `performWindowDrag`.
- (void)wwnApplySurfaceDragPolicyForWindow:(WWNWindow *)window {
  if (!window || window.hostLocked) {
    return;
  }
  [window setMovable:YES];
  // SSD: AppKit titlebar only. CSD: borderless; content-drag only when the
  // client issues xdg_toplevel.move (WindowMoveRequested).
  [window setMovableByWindowBackground:NO];
}

- (void)refreshMacOSSurfaceDragPolicyForWindow:(NSWindow *)window {
  if (![window isKindOfClass:[WWNWindow class]]) {
    return;
  }
  [self wwnApplySurfaceDragPolicyForWindow:(WWNWindow *)window];
}

- (void)handleWindowMoveRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowMoveRequested: id=%llu (xdg_toplevel.move)",
         event->window_id);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || window.hostLocked)
    return;
  if (window.interactiveResizeInProgress) {
    WWNLog("BRIDGE", @"Ignoring move request during interactive resize: id=%llu",
           event->window_id);
    return;
  }

  // Protocol path: client button → xdg_toplevel.move(seat, serial) → here.
  // Mirror the button's NSEvent into AppKit interactive move (same as a
  // Linux compositor starting an interactive move grab).
  NSEvent *currentEvent = [NSApp currentEvent];
  BOOL leftMouseDown = (([NSEvent pressedMouseButtons] & 0x1) != 0);
  BOOL validCurrentEvent =
      currentEvent && currentEvent.window == window &&
      (currentEvent.type == NSEventTypeLeftMouseDown ||
       currentEvent.type == NSEventTypeLeftMouseDragged);
  if (validCurrentEvent) {
    [window performWindowDragWithEvent:currentEvent];
  } else if (window.lastMouseDownEvent &&
             window.lastMouseDownEvent.window == window &&
             (window.lastMouseDownEvent.type == NSEventTypeLeftMouseDown ||
              window.lastMouseDownEvent.type == NSEventTypeLeftMouseDragged) &&
             leftMouseDown) {
    [window performWindowDragWithEvent:window.lastMouseDownEvent];
  } else {
    WWNLog("BRIDGE",
           @"Ignoring move request: no valid drag event window=%llu current=%@ last=%@ leftDown=%d",
           event->window_id,
           currentEvent ? NSStringFromClass([currentEvent class]) : @"nil",
           window.lastMouseDownEvent ? NSStringFromClass([window.lastMouseDownEvent class]) : @"nil",
           leftMouseDown);
  }
#endif
}

- (void)handleWindowResizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowResizeRequested: id=%llu edges=%u",
         event->window_id, event->edges);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || window.hostLocked)
    return;

  NSEvent *mouseEvent = [NSApp currentEvent];
  if (!mouseEvent || (mouseEvent.type != NSEventTypeLeftMouseDown &&
                      mouseEvent.type != NSEventTypeLeftMouseDragged)) {
    mouseEvent = window.lastMouseDownEvent;
  }
  if (!mouseEvent)
    return;

  uint8_t edges = event->edges;
  NSPoint startLoc = [NSEvent mouseLocation];
  NSRect startFrame = window.frame;
  uint64_t windowId = event->window_id;
  window.interactiveResizeInProgress = YES;
  [self beginInteractiveResize:windowId];

  // CSD xdg_toplevel.resize: stream host frame + Wayland configure every drag
  // tick (WSLg WindowMove-style continuous geometry). Never wait for mouse-up.
  __weak typeof(self) weakSelf = self;
  [window
      trackEventsMatchingMask:(NSEventMaskLeftMouseDragged |
                               NSEventMaskLeftMouseUp)
                      timeout:NSEventDurationForever
                         mode:NSEventTrackingRunLoopMode
                      handler:^(NSEvent *trackEvent, BOOL *stop) {
                        if (trackEvent.type == NSEventTypeLeftMouseUp) {
                          *stop = YES;
                          return;
                        }

                        NSPoint curLoc = [NSEvent mouseLocation];
                        CGFloat dx = curLoc.x - startLoc.x;
                        CGFloat dy = curLoc.y - startLoc.y;

                        NSRect newFrame = startFrame;

                        // Horizontal edges
                        if (edges & 8) { // Right
                          newFrame.size.width =
                              MAX(100, startFrame.size.width + dx);
                        } else if (edges & 4) { // Left
                          CGFloat newW = MAX(100, startFrame.size.width - dx);
                          newFrame.origin.x = startFrame.origin.x +
                                              startFrame.size.width - newW;
                          newFrame.size.width = newW;
                        }

                        // Vertical edges (macOS y is flipped: origin is
                        // bottom-left)
                        if (edges & 1) { // Top (Wayland top → macOS top →
                                         // increase height, keep top)
                          CGFloat newH = MAX(100, startFrame.size.height + dy);
                          newFrame.size.height = newH;
                        } else if (edges & 2) { // Bottom (Wayland bottom →
                                                // macOS bottom)
                          CGFloat newH = MAX(100, startFrame.size.height - dy);
                          newFrame.origin.y = startFrame.origin.y +
                                              startFrame.size.height - newH;
                          newFrame.size.height = newH;
                        }

                        [window setFrame:newFrame display:YES];
                        NSSize contentSize =
                            WWNWaylandContentSizeForWindow(window);
                        uint32_t width =
                            (uint32_t)MAX(1, lround(contentSize.width));
                        uint32_t height =
                            (uint32_t)MAX(1, lround(contentSize.height));
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        [strongSelf injectWindowResize:windowId
                                                 width:width
                                                height:height];
                      }];
  window.interactiveResizeInProgress = NO;
  [self reconcileWindowResizeNow:windowId];
#endif
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (void)handleCursorShapeChanged:(CWindowEvent *)event {
  if (_windows.count == 0)
    return;
  if (![WWNMachineProfileStore resolvedShowHostCursorActive])
    return;
  uint32_t shape = event->surface_id;
  [self _ensureCursorRenderingEnabled];

  NSCursor *cursor = NSCursorFromWaylandShape(shape);
  [cursor set];
}

- (void)_ensureCursorRenderingEnabled {
  if (_windows.count == 0)
    return;
  if (!_clientWantsCursorRendered) {
    _clientWantsCursorRendered = YES;
    WWNLog("BRIDGE",
           @"Client requested cursor management. Enabling host cursor rendering");
    for (NSNumber *key in _windows) {
      NSWindow *w = _windows[key];
      if ([w isKindOfClass:[WWNWindow class]]) {
        NSView *cv = ((WWNWindow *)w).contentView;
        if (cv) {
          [w invalidateCursorRectsForView:cv];
        }
      }
    }
  }
}

- (void)_applyBitmapCursorFromScene:(CRenderScene *)scene {
  if (!scene || !scene->has_cursor)
    return;

  if (_windows.count == 0)
    return;

  if (![WWNMachineProfileStore resolvedShowHostCursorActive])
    return;

  if (scene->cursor_buffer_id == 0)
    return;

  if (scene->cursor_buffer_id == _lastCursorBufferId &&
      scene->cursor_surface_id == _lastCursorSurfaceId)
    return;
  _lastCursorBufferId = scene->cursor_buffer_id;
  _lastCursorSurfaceId = scene->cursor_surface_id;

  [self _ensureCursorRenderingEnabled];

  NSString *cacheKey =
      WWNBufferCacheKey(scene->cursor_surface_id, scene->cursor_buffer_id);
  id cached = _bufferCache[cacheKey];
  if (!cached)
    return;

  CGImageRef cgImage = NULL;
  CFTypeRef cfRef = (__bridge CFTypeRef)cached;
  if (CFGetTypeID(cfRef) == CGImageGetTypeID()) {
    cgImage = (CGImageRef)cfRef;
  }
  if (!cgImage)
    return;

  // Cursor buffer is SHM pixels; hotspot is already surface-local (logical).
  // Do not divide by backingScaleFactor: that halved weston's 1x cursor on
  // Retina and shifted the hotspot.
  NSSize size = NSMakeSize(scene->cursor_width, scene->cursor_height);
  NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size:size];
  NSPoint hotSpot = NSMakePoint(scene->cursor_hotspot_x,
                                scene->cursor_hotspot_y);
  NSCursor *cursor = [[NSCursor alloc] initWithImage:image hotSpot:hotSpot];
  [cursor set];
}
#endif

- (void)handleWindowDestroyed:(CWindowEvent *)event {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  NSWindow *window = [_windows objectForKey:@(event->window_id)];
  if (window) {
    NSString *activeMachineId = [WWNMachineProfileStore activeMachineId];
    WWNMachineProfile *activeProfile =
        [WWNMachineProfileStore profileById:activeMachineId];
    if (activeProfile &&
        [WWNMachineProfileStore isMachineThumbnailEnabledForProfile:activeProfile]) {
      Class thumbnailStoreClass = NSClassFromString(@"WWNMachineThumbnailStore");
      SEL saveSelector = NSSelectorFromString(@"saveThumbnailFromWindow:machineId:");
      if (thumbnailStoreClass && [thumbnailStoreClass respondsToSelector:saveSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [thumbnailStoreClass performSelector:saveSelector
                                  withObject:window
                                  withObject:activeMachineId];
#pragma clang diagnostic pop
      }
    }
    @try {
      if ([window isKindOfClass:[WWNWindow class]]) {
        WWNWindow *wwn = (WWNWindow *)window;
        wwn.suppressCompositorCallbacks = YES;
        [wwn cancelPendingHostCloseEscalation];
        if (wwn.isMiniaturized || wwn.wwnMiniaturizeInProgress) {
          wwn.wwnMiniaturizeInProgress = NO;
          id contentView = [window contentView];
          if ([contentView isKindOfClass:[WWNView class]]) {
            CALayer *hostLayer = ((WWNView *)contentView).contentLayer;
            NSArray<CALayer *> *children = [hostLayer.sublayers copy];
            for (CALayer *layer in children) {
              [layer removeFromSuperlayer];
            }
          }
          [_windows removeObjectForKey:@(event->window_id)];
          [_windowOwnerMachineIdByWindowId
              removeObjectForKey:@(event->window_id)];
          [_latestResizeDims removeObjectForKey:@(event->window_id)];
          [_sentResizeDims removeObjectForKey:@(event->window_id)];
          [_resizeInFlightWindows removeObject:@(event->window_id)];
          [_windowsWithInitialSizeSynced removeObject:@(event->window_id)];
          [_windowsAutoShownAfterFirstBuffer removeObject:@(event->window_id)];
          [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                   selector:@selector(
                                                       _drainPendingWindowResizeForId:)
                                                     object:@(event->window_id)];
          // The client is gone: a miniaturized host window would linger as a
          // dead dock tile that restores to an empty frame. Close it so the
          // dock tile disappears with the client.
          WWNLog("BRIDGE",
                 @"Client disconnected during minimize. Closing host window "
                 @"%llu (removing dock tile)",
                 event->window_id);
          [window close];
          return;
        }
      }

      // Detach known surface layers from this host view before teardown.
      // This prevents stale layer tree references after client disconnect.
      id contentView = [window contentView];
      if ([contentView isKindOfClass:[WWNView class]]) {
        CALayer *hostLayer = ((WWNView *)contentView).contentLayer;
        NSArray<CALayer *> *children = [hostLayer.sublayers copy];
        for (CALayer *layer in children) {
          [layer removeFromSuperlayer];
        }
      }

      [_windows removeObjectForKey:@(event->window_id)];
      [_windowOwnerMachineIdByWindowId removeObjectForKey:@(event->window_id)];
      [_latestResizeDims removeObjectForKey:@(event->window_id)];
      [_sentResizeDims removeObjectForKey:@(event->window_id)];
      [_resizeInFlightWindows removeObject:@(event->window_id)];
      [_windowsWithInitialSizeSynced removeObject:@(event->window_id)];
      [_windowsAutoShownAfterFirstBuffer removeObject:@(event->window_id)];
      [NSObject cancelPreviousPerformRequestsWithTarget:self
                                               selector:@selector(_drainPendingWindowResizeForId:)
                                                 object:@(event->window_id)];

      // Avoid NSWindow close-time delegate/first-responder cascades when the
      // Wayland client has already been torn down. Hiding + detaching keeps
      // host alive without touching potentially invalid compositor state.
      [window setDelegate:nil];
      WWNCloseHostWindowSafely(window);
    } @catch (NSException *exception) {
      WWNLog("BRIDGE",
             @"Exception while destroying window %llu: %@ (%@)",
             event->window_id, exception.name, exception.reason);
      [_windows removeObjectForKey:@(event->window_id)];
      [_windowOwnerMachineIdByWindowId removeObjectForKey:@(event->window_id)];
      [_latestResizeDims removeObjectForKey:@(event->window_id)];
      [_sentResizeDims removeObjectForKey:@(event->window_id)];
      [_resizeInFlightWindows removeObject:@(event->window_id)];
      [NSObject cancelPreviousPerformRequestsWithTarget:self
                                               selector:@selector(_drainPendingWindowResizeForId:)
                                                 object:@(event->window_id)];
      @try {
        [window orderOut:nil];
      } @catch (NSException *inner) {
        WWNLog("BRIDGE", @"Suppressed orderOut exception for window %llu: %@",
               event->window_id, inner.reason);
      }
    }
    WWNLog("BRIDGE", @"Destroyed window %llu", event->window_id);
  }

  if (_windows.count == 0) {
    if (_clientWantsCursorRendered) {
      _clientWantsCursorRendered = NO;
      _lastCursorBufferId = 0;
      _lastCursorSurfaceId = 0;
      WWNLog("BRIDGE",
             @"All windows destroyed. Resetting cursor rendering flag");
    }
    [_surfaceLayers removeAllObjects];
    [_bufferCache removeAllObjects];
    [_latestBufferBySurface removeAllObjects];
    [_lastPresentedBufferBySurface removeAllObjects];
    [_staleSceneSelectionsBySurface removeAllObjects];
    [[NSCursor arrowCursor] set];
  }
#endif

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  id popup = [_popups objectForKey:@(event->window_id)];
  if (popup) {
    [self wwnRemovePopupHost:popup windowId:event->window_id];
    WWNLog("BRIDGE", @"Destroyed popup %llu", event->window_id);
  }
#endif
}

- (void)handleWindowTitleChanged:(CWindowEvent *)event {
  if (!event->title)
    return;
  NSString *newTitle = [NSString stringWithUTF8String:event->title];

  NSWindow *window = [self.windows objectForKey:@(event->window_id)];
  if (window) {
    [window setTitle:newTitle];
    WWNLog("BRIDGE", @"Updated title for window %llu to '%@'", event->window_id,
           newTitle);
    if (WWNWestonDemoPrefersFixedSquare(nil, newTitle)) {
      window.styleMask = window.styleMask & ~NSWindowStyleMaskResizable;
      if ([window isKindOfClass:[WWNWindow class]]) {
        WWNWindow *wwnWin = (WWNWindow *)window;
        wwnWin.prefersFixedSquare = YES;
        wwnWin.fillsHost = NO;
        NSSize contentSize = WWNWaylandContentSizeForWindow(window);
        if (contentSize.width > 256.0 || contentSize.height > 256.0) {
          uint32_t dw = 200;
          uint32_t dh = 200;
          WWNLog("BRIDGE",
                 @"macOS demo shrink on title '%@' window=%llu (was %.0fx%.0f)",
                 newTitle, event->window_id, contentSize.width, contentSize.height);
          NSRect frame =
              [window frameRectForContentRect:NSMakeRect(0, 0, dw, dh)];
          frame.origin = window.frame.origin;
          wwnWin.processingResize = YES;
          [window setFrame:frame display:NO];
          wwnWin.processingResize = NO;
          uint64_t wid = event->window_id;
          [self _dispatchToRust:^{
            WWNCoreSetOutputGeometryForWindow(self->_rustCore, wid, dw, dh, 1.0f);
          }];
          [self injectWindowResize:wid width:dw height:dh];
        }
      }
    }
    if (newTitle.length > 0) {
      [[NSProcessInfo processInfo] setProcessName:newTitle];
    }
    // Title/app_id often land together; refresh demo surface-drag allowlist.
    [self refreshMacOSSurfaceDragPolicyForWindow:window];
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    // Weston sets "Weston Compositor - <output>" after map. If Start raced
    // NativeClientId empty, WindowCreated left a 64px 0x0 seed. Fill now.
    if (WWNTitleIndicatesNestedCompositor(newTitle) &&
        [window isKindOfClass:[WWNWindow class]] &&
        !((WWNWindow *)window).hostLocked) {
      NSSize contentSize = WWNWaylandContentSizeForWindow(window);
      if (contentSize.width <= 64.0 && contentSize.height <= 64.0) {
        uint32_t ow = _latestOutputW > 0 ? _latestOutputW : 1024;
        uint32_t oh = _latestOutputH > 0 ? _latestOutputH : 768;
        WWNLog("BRIDGE",
               @"macOS fill-host on title '%@' window=%llu %ux%u (was %.0fx%.0f)",
               newTitle, event->window_id, ow, oh, contentSize.width,
               contentSize.height);
        NSRect frame = [window frameRectForContentRect:NSMakeRect(0, 0, ow, oh)];
        frame.origin = window.frame.origin;
        ((WWNWindow *)window).processingResize = YES;
        [window setFrame:frame display:NO];
        ((WWNWindow *)window).processingResize = NO;
        uint64_t wid = event->window_id;
        [self _dispatchToRust:^{
          WWNCoreSetOutputGeometryForWindow(self->_rustCore, wid, ow, oh, 1.0f);
        }];
        [self injectWindowResize:wid width:ow height:oh];
      }
    }
#endif
  } else {
    WWNLog("BRIDGE",
           @"Warning: handleWindowTitleChanged for unknown window %llu",
           event->window_id);
  }
}

- (void)handleWindowSizeChanged:(CWindowEvent *)event {
  WWNWindow *window = [self.windows objectForKey:@(event->window_id)];
  if (window) {
    if (window.hostLocked) {
      uint32_t kw = event->width > 0 ? event->width
                                     : (_latestOutputW > 0 ? _latestOutputW : 800);
      uint32_t kh = event->height > 0 ? event->height
                                      : (_latestOutputH > 0 ? _latestOutputH : 600);
      NSRect screenFrame = [[NSScreen mainScreen] frame];
      NSRect frame =
          NSMakeRect(screenFrame.origin.x, screenFrame.origin.y, kw, kh);
      window.processingResize = YES;
      [window setFrame:frame display:NO];
      window.processingResize = NO;
      return;
    }
    // Check if size actually changed to avoid loop
    NSSize contentSize = WWNWaylandContentSizeForWindow(window);
    // Host-originated configure/output updates are acknowledgements of a resize
    // AppKit already performed. Re-applying them can create host resize loops.
    if (event->size_cause == 1 || event->size_cause == 3) {
      WWNLog("BRIDGE",
             @"Ignoring non-authoritative SizeChanged window=%llu event=%ux%u "
             @"current=%.0fx%.0f cause=%@ kind=%@ serial=%u txn=%llu",
             event->window_id, event->width, event->height, contentSize.width,
             contentSize.height, WWNSizeCauseString(event->size_cause),
             WWNSizeKindString(event->size_kind), event->configure_serial,
             event->transaction_id);
      return;
    }
    // #111: during live SSD/CSD edge drag the host frame is authoritative.
    // Applying a lagging ClientCommit via setFrame yankes AppKit back to the
    // pre-resize size and flashes nested niri/weston framebuffers.
    if (window.inLiveResize || window.interactiveResizeInProgress) {
      WWNLog("BRIDGE",
             @"Ignoring SizeChanged during live host resize window=%llu "
             @"event=%ux%u current=%.0fx%.0f cause=%@ serial=%u txn=%llu",
             event->window_id, event->width, event->height, contentSize.width,
             contentSize.height, WWNSizeCauseString(event->size_cause),
             event->configure_serial, event->transaction_id);
      return;
    }
    // Nested weston/niri: host size is the fill-host configure. A smaller
    // first ClientCommit is init, not a refuse. Applying it shrinks the
    // NSWindow while the nested compositor still has the large output.
    if (window.fillsHost && event->size_cause == 2) {
      WWNLog("BRIDGE",
             @"Ignoring ClientCommit SizeChanged for fill-host nested "
             @"compositor window=%llu event=%ux%u current=%.0fx%.0f",
             event->window_id, event->width, event->height, contentSize.width,
             contentSize.height);
      return;
    }
    // OWL rule: every ClientCommit SizeChanged drives host content size
    // (OwlSurface commit → setFrameSize:buffer). Do not ignore "untracked"
    // commits. That left weston-flower/smoke at a giant placeholder while
    // the buffer stayed 200×200.
    //
    // Placement (center) is separate from sizing: after the first real
    // client size lands, recenter the NSWindow so fixed-size clients
    // (weston-flower/smoke 200×200) are not stuck at the placeholder origin.
    BOOL firstClientSizeSync =
        ![_windowsWithInitialSizeSynced containsObject:@(event->window_id)];
    [_windowsWithInitialSizeSynced addObject:@(event->window_id)];
    if (contentSize.width != event->width ||
        contentSize.height != event->height) {
      CGFloat deltaW = fabs(contentSize.width - (CGFloat)event->width);
      CGFloat deltaH = fabs(contentSize.height - (CGFloat)event->height);
      WWNLog(
          "BRIDGE",
          @"Applying SizeChanged window=%llu event=%ux%u current=%.0fx%.0f "
          @"delta=%.0fx%.0f cause=%@ kind=%@ serial=%u txn=%llu firstSync=%@",
          event->window_id, event->width, event->height, contentSize.width,
          contentSize.height, deltaW, deltaH,
          WWNSizeCauseString(event->size_cause),
          WWNSizeKindString(event->size_kind), event->configure_serial,
          event->transaction_id, firstClientSizeSync ? @"yes" : @"no");

      window.processingResize = YES;
      NSRect frame =
          [window frameRectForContentRect:NSMakeRect(0, 0, event->width,
                                                     event->height)];
      frame.origin = window.frame.origin; // Keep origin unless first sync
      // Avoid visible one-frame flash when applying final size correction.
      [window setFrame:frame display:NO];
      if (firstClientSizeSync) {
        [window center];
      }
      if (window.prefersFixedSquare && event->width > 0 && event->height > 0) {
        NSSize locked = NSMakeSize(event->width, event->height);
        window.contentMinSize = locked;
        window.contentMaxSize = locked;
        window.styleMask = window.styleMask & ~NSWindowStyleMaskResizable;
      }
      window.processingResize = NO;
    } else {
      if (firstClientSizeSync) {
        [window center];
      }
      if (firstClientSizeSync && window.prefersFixedSquare &&
          event->width > 0 && event->height > 0) {
        NSSize locked = NSMakeSize(event->width, event->height);
        window.contentMinSize = locked;
        window.contentMaxSize = locked;
        window.styleMask = window.styleMask & ~NSWindowStyleMaskResizable;
      }
      WWNLog("BRIDGE",
             @"Ignoring SizeChanged window=%llu event=%ux%u (already applied) "
             @"cause=%@ kind=%@ serial=%u txn=%llu firstSync=%@",
             event->window_id, event->width, event->height,
             WWNSizeCauseString(event->size_cause),
             WWNSizeKindString(event->size_kind), event->configure_serial,
             event->transaction_id, firstClientSizeSync ? @"yes" : @"no");
    }
  }
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (WWNView *)wwnParentViewForPopupId:(uint64_t)parentId {
  id parent = _windows[@(parentId)];
  if ([parent isKindOfClass:[WWNWindow class]]) {
    NSView *content = [(WWNWindow *)parent contentView];
    return [content isKindOfClass:[WWNView class]] ? (WWNView *)content : nil;
  }
  if ([parent isKindOfClass:[WWNView class]]) {
    return (WWNView *)parent;
  }
  id parentPopup = _popups[@(parentId)];
  if ([parentPopup isKindOfClass:[WWNView class]]) {
    return (WWNView *)parentPopup;
  }
  if ([parentPopup conformsToProtocol:@protocol(WWNPopupHost)]) {
    NSView *content = ((id<WWNPopupHost>)parentPopup).contentView;
    return [content isKindOfClass:[WWNView class]] ? (WWNView *)content : nil;
  }
  return nil;
}

static NSRect WWNScreenFrameForPopupInParentView(WWNView *parentView, CGFloat x,
                                                 CGFloat y, CGFloat w,
                                                 CGFloat h) {
  if (!parentView || !parentView.window) {
    return NSMakeRect(x, y, w, h);
  }
  NSRect localRect = NSMakeRect(x, y, w, h);
  NSRect inWindow = [parentView convertRect:localRect toView:nil];
  return [parentView.window convertRectToScreen:inWindow];
}

- (void)wwnRemovePopupHost:(id)popup windowId:(uint64_t)windowId {
  if (!popup) {
    return;
  }
  // Remove from the tracking dictionaries before invoking -dismiss: dismiss
  // synchronously fires onDismiss -> handlePopupDismissed:, which looks the
  // popup back up by windowId. Clearing it first means that re-entrant
  // lookup finds nothing and safely no-ops instead of calling -dismiss
  // again on the same popup (which previously recursed until stack
  // overflow). -[WWNPopupWindow dismiss] is also idempotent as a backstop.
  [_popups removeObjectForKey:@(windowId)];
  [_windows removeObjectForKey:@(windowId)];
  [_latestResizeDims removeObjectForKey:@(windowId)];
  [_sentResizeDims removeObjectForKey:@(windowId)];
  [_resizeInFlightWindows removeObject:@(windowId)];
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(_drainPendingWindowResizeForId:)
                                             object:@(windowId)];
  if ([popup conformsToProtocol:@protocol(WWNPopupHost)]) {
    [(id<WWNPopupHost>)popup dismiss];
  } else if ([popup isKindOfClass:[WWNView class]]) {
    [(WWNView *)popup removeFromSuperview];
  }
}

- (void)handlePopupCreated:(CWindowEvent *)event {
  WWNLog("BRIDGE",
         @"Popup create request: surface %u, window %llu, parent %llu",
         event->surface_id, event->window_id, event->parent_id);

  WWNView *parentView = [self wwnParentViewForPopupId:event->parent_id];
  if (!parentView) {
    WWNLog("BRIDGE",
           @"Warning: Popup parent %llu not found, falling back to key window",
           event->parent_id);
    NSWindow *keyWindow = [NSApp keyWindow];
    if ([keyWindow.contentView isKindOfClass:[WWNView class]]) {
      parentView = (WWNView *)keyWindow.contentView;
    }
  }
  if (!parentView) {
    WWNLog("BRIDGE", @"Error: No parent view available for popup %llu",
           event->window_id);
    return;
  }

  CGFloat x = (CGFloat)event->x;
  CGFloat y = (CGFloat)event->y;
  CGFloat w = MAX((CGFloat)event->width, 1.0);
  CGFloat h = MAX((CGFloat)event->height, 1.0);

  WWNPopupWindow *popup =
      [[WWNPopupWindow alloc] initWithParentView:parentView];
  popup.windowId = event->window_id;
  [popup setContentSize:CGSizeMake(w, h)];

  NSRect screenFrame =
      WWNScreenFrameForPopupInParentView(parentView, x, y, w, h);
  [popup showAtScreenRect:screenFrame];

  __weak typeof(self) weakSelf = self;
  popup.onDismiss = ^{
    [weakSelf handlePopupDismissed:event->window_id];
  };

  [_popups setObject:popup forKey:@(event->window_id)];
  [_windows setObject:popup.window forKey:@(event->window_id)];

  WWNLog("BRIDGE",
         @"macOS popup %llu shown as child window (parent %llu local "
         @"%.0f,%.0f screen %.0f,%.0f %.0fx%.0f)",
         event->window_id, event->parent_id, x, y, screenFrame.origin.x,
         screenFrame.origin.y, w, h);

  [self injectKeyboardEnterForWindow:event->window_id keys:@[]];
}

- (void)handlePopupDismissed:(uint64_t)windowId {
  WWNLog("BRIDGE", @"Popup dismissed locally: %llu", windowId);
  id popup = [_popups objectForKey:@(windowId)];
  [self wwnRemovePopupHost:popup windowId:windowId];
  // Tell the client via xdg_popup.popup_done so it destroys the popup
  // instead of leaving a ghost grab.
  if (_rustCore) {
    [self _dispatchToRust:^{
      WWNCoreNotifyPopupDismissed(self->_rustCore, windowId);
    }];
  }
}

- (void)handlePopupRepositioned:(CWindowEvent *)event {
  id popupObj = [_popups objectForKey:@(event->window_id)];
  if (![popupObj conformsToProtocol:@protocol(WWNPopupHost)]) {
    WWNLog("BRIDGE", @"Warning: PopupRepositioned for unknown window %llu",
           event->window_id);
    return;
  }

  id<WWNPopupHost> popup = (id<WWNPopupHost>)popupObj;
  WWNView *parentView = (WWNView *)popup.parentView;
  if (![parentView isKindOfClass:[WWNView class]]) {
    WWNLog("BRIDGE", @"Error: Popup %llu has no WWNView parent",
           event->window_id);
    return;
  }

  CGFloat x = (CGFloat)event->x;
  CGFloat y = (CGFloat)event->y;
  CGFloat w = MAX((CGFloat)event->width, 1.0);
  CGFloat h = MAX((CGFloat)event->height, 1.0);

  [popup setContentSize:CGSizeMake(w, h)];
  NSRect screenFrame =
      WWNScreenFrameForPopupInParentView(parentView, x, y, w, h);
  [popup showAtScreenRect:screenFrame];

  WWNLog("BRIDGE",
         @"macOS popup %llu repositioned (local %.0f,%.0f screen "
         @"%.0f,%.0f %.0fx%.0f)",
         event->window_id, x, y, screenFrame.origin.x, screenFrame.origin.y, w,
         h);
}

#endif // !TARGET_OS_IPHONE

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
/// Host chrome title for iland KMS clients. Must match the Machines catalog -
/// never brand every DRM client as "KMSCube".
static NSString *WWNIlandGpuClientDisplayTitle(NSString *clientId) {
  if ([clientId isEqualToString:@"gbm-es2-demo"]) {
    return @"GBM ES2 Demo";
  }
  if ([clientId isEqualToString:@"kmscube"]) {
    return @"KMS Cube";
  }
  return clientId.length > 0 ? clientId : @"Iland GPU Client";
}

/// Prefer an existing Wayland host view; otherwise create a dedicated Metal
/// presentation window so iland KMS clients can present before any toplevel exists.
- (WWNView *)ensureIlandPresentationViewForClientId:(NSString *)clientId {
  NSString *title = WWNIlandGpuClientDisplayTitle(clientId);
  for (NSNumber *key in _windows) {
    id w = _windows[key];
    if ([w isKindOfClass:[WWNWindow class]]) {
      WWNView *view = (WWNView *)[(WWNWindow *)w contentView];
      if ([view isKindOfClass:[WWNView class]]) {
        NSSize size = view.bounds.size;
        if (size.width > 1.0 && size.height > 1.0) {
          ((WWNWindow *)w).title = title;
          view.accessibilityLabel = clientId.length > 0 ? clientId : title;
          return view;
        }
      }
    }
  }

  if (_ilandHostWindow) {
    WWNView *view = (WWNView *)_ilandHostWindow.contentView;
    if ([view isKindOfClass:[WWNView class]]) {
      _ilandHostWindow.title = title;
      view.accessibilityLabel = clientId.length > 0 ? clientId : title;
      [_ilandHostWindow makeKeyAndOrderFront:nil];
      return view;
    }
  }

  [self seedOutputSizeFromLiveHostSurface];
  uint32_t w = _latestOutputW > 0 ? _latestOutputW : 1280;
  uint32_t h = _latestOutputH > 0 ? _latestOutputH : 720;
  NSRect contentRect = NSMakeRect(80, 80, (CGFloat)w, (CGFloat)h);
  NSWindow *window =
      [[NSWindow alloc] initWithContentRect:contentRect
                                  styleMask:(NSWindowStyleMaskTitled |
                                             NSWindowStyleMaskClosable |
                                             NSWindowStyleMaskResizable |
                                             NSWindowStyleMaskMiniaturizable)
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  window.title = title;
  window.releasedWhenClosed = NO;
  WWNView *view =
      [[WWNView alloc] initWithFrame:NSMakeRect(0, 0, contentRect.size.width,
                                                contentRect.size.height)];
  view.wantsLayer = YES;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  view.accessibilityLabel = clientId.length > 0 ? clientId : title;
  window.contentView = view;
  [window makeKeyAndOrderFront:nil];
  _ilandHostWindow = window;
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNKeepServiceHostOutOfDock();
#endif
  WWNLog("BRIDGE",
         @"Created iland presentation host %ux%u for %@ ", w, h,
         clientId ?: @"(nil)");
  return view;
}

- (BOOL)launchNestedIlandGpuClientOnPrimaryView:(NSString *)clientId {
  WWNView *view = [self ensureIlandPresentationViewForClientId:clientId];
  if (!view) {
    return NO;
  }
  return [view launchNestedIlandGpuClient:clientId];
}

- (BOOL)launchNestedKmscubeOnPrimaryView {
  return [self launchNestedIlandGpuClientOnPrimaryView:@"kmscube"];
}

- (BOOL)prepareIlandMetalPresentationOnPrimaryView {
  return [self prepareIlandMetalPresentationOnPrimaryViewForClientId:@"weston"];
}

- (BOOL)prepareIlandMetalPresentationOnPrimaryViewForClientId:(NSString *)clientId {
  WWNView *view = [self ensureIlandPresentationViewForClientId:clientId];
  if (!view) {
    return NO;
  }
  return [view prepareIlandMetalPresentation];
}

- (void)stopIlandGpuClientOnPrimaryView {
  for (NSNumber *key in _windows) {
    id w = _windows[key];
    if ([w isKindOfClass:[WWNWindow class]]) {
      WWNView *view = (WWNView *)[(WWNWindow *)w contentView];
      if ([view isKindOfClass:[WWNView class]]) {
        [view stopIlandMetalPresentation];
      }
    }
  }
  if (_ilandHostWindow) {
    WWNView *view = (WWNView *)_ilandHostWindow.contentView;
    if ([view isKindOfClass:[WWNView class]]) {
      [view stopIlandMetalPresentation];
    }
  }
}
#endif

#endif // !TARGET_OS_IPHONE. Close block opened at WWNWaylandContentSizeForWindow

// Shared AppKit + UIKit: host → xdg maximized/fullscreen sync.
- (void)syncHostFullscreen:(BOOL)fullscreen
                forWindowId:(uint64_t)windowId
                      width:(uint32_t)width
                     height:(uint32_t)height {
  if (!_rustCore)
    return;
  uint64_t wid = windowId;
  uint32_t w = width;
  uint32_t h = height;
  bool fs = fullscreen ? true : false;
  [self _dispatchToRust:^{
    WWNCoreApplyHostWindowFullscreen(self->_rustCore, wid, fs, w, h);
  }];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  _iosHostFullscreenByWindowId[@(windowId)] = @(fullscreen);
  if (fullscreen) {
    _iosHostMaximizedByWindowId[@(windowId)] = @NO;
  }
#endif
}

- (void)syncHostMaximized:(BOOL)maximized
             forWindowId:(uint64_t)windowId
                   width:(uint32_t)width
                  height:(uint32_t)height {
  if (!_rustCore)
    return;
  uint64_t wid = windowId;
  uint32_t w = width;
  uint32_t h = height;
  bool mz = maximized ? true : false;
  [self _dispatchToRust:^{
    WWNCoreApplyHostWindowMaximized(self->_rustCore, wid, mz, w, h);
  }];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  _iosHostMaximizedByWindowId[@(windowId)] = @(maximized);
  if (maximized) {
    _iosHostFullscreenByWindowId[@(windowId)] = @NO;
  }
#endif
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
/// Resolve the active UIKit host surface bounds for fill-primary WM sync.
/// Dedicated UIWindowScene clients use their own host window, not the primary
/// Machines scene container.
- (CGSize)_iosFillPrimaryHostSizeForWindowId:(uint64_t)windowId {
  UIWindow *hostWindow = _iosHostWindows[@(windowId)];
  if (hostWindow && hostWindow.rootViewController) {
    [hostWindow.rootViewController.view layoutIfNeeded];
    CGSize size = hostWindow.rootViewController.view.bounds.size;
    if (size.width > 0 && size.height > 0) {
      return size;
    }
  }
  UIView *host = nil;
  id winObj = _windows[@(windowId)];
  if ([winObj isKindOfClass:[UIView class]]) {
    host = (UIView *)winObj;
  } else if ([self.containerView isKindOfClass:[UIView class]]) {
    host = self.containerView;
  }
  if (host) {
    [host layoutIfNeeded];
    return host.bounds.size;
  }
  return CGSizeMake(640, 480);
}

- (void)_iosClearHostCloseDeferredForWindowId:(uint64_t)windowId {
  [_iosHostCloseDeferred removeObject:@(windowId)];
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(_iosForceDestroyIfCloseStillDeferred:)
                                             object:@(windowId)];
}

- (void)_iosForceDestroyIfCloseStillDeferred:(NSNumber *)windowIdKey {
  if (![_iosHostCloseDeferred containsObject:windowIdKey]) {
    return;
  }
  [_iosHostCloseDeferred removeObject:windowIdKey];
  [self requestForceDestroyHostWindowForWindowId:windowIdKey.unsignedLongLongValue];
}

/// Mirror macOS WWNWindow windowShouldClose:. Ask the Wayland client to exit,
/// then force-destroy if it does not tear down within the grace window.
- (void)_iosBeginGracefulHostCloseForWindowId:(uint64_t)windowId {
  NSNumber *key = @(windowId);
  if ([_iosHostCloseDeferred containsObject:key]) {
    WWNLog("BRIDGE",
           @"iOS host close: second close for window %llu. Force-destroy",
           windowId);
    [self _iosClearHostCloseDeferredForWindowId:windowId];
    [self requestForceDestroyHostWindowForWindowId:windowId];
    return;
  }
  BOOL sent = [self requestHostCloseForWindowId:windowId];
  if (!sent) {
    [self requestForceDestroyHostWindowForWindowId:windowId];
    return;
  }
  [_iosHostCloseDeferred addObject:key];
  WWNLog("BRIDGE",
         @"iOS host close: sent xdg_toplevel.close for window %llu. Deferring "
         @"scene teardown",
         windowId);
  [self performSelector:@selector(_iosForceDestroyIfCloseStillDeferred:)
             withObject:key
             afterDelay:1.5];
}

- (void)_iosSetFollowHostSizeForFillPrimaryWindowId:(uint64_t)windowId {
  NSString *clientId = WWNIosResolveBundledClientIdForWindow(self, windowId);
  id view = _windows[@(windowId)];
  NSString *title = nil;
  if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
    title = ((WWNCompositorView_ios *)view).accessibilityLabel;
  }
  if (WWNWestonDemoPrefersFixedSquare(clientId, title)) {
    return;
  }
  if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
    ((WWNCompositorView_ios *)view).followHostSize = YES;
  }
}

- (void)resyncFillPrimaryHostStateForWindowId:(uint64_t)windowId {
  BOOL fullscreen = [_iosHostFullscreenByWindowId[@(windowId)] boolValue];
  BOOL maximized = [_iosHostMaximizedByWindowId[@(windowId)] boolValue];
  if (!fullscreen && !maximized) {
    return;
  }
  [self _iosInjectFillPrimaryForWindowId:windowId
                              maximized:maximized && !fullscreen
                             fullscreen:fullscreen];
}

/// Fill-primary window policy (iOS / iPadOS / tvOS / visionOS / phone):
/// UIKit owns the host window(s); Wawona cannot spawn floating AppKit-style
/// frames or true OS zoom. Maximize and fullscreen both mean: configure the
/// Wayland toplevel to the active host surface bounds and advertise the
/// matching xdg state. Unmaximize/unfullscreen clear state bits but keep
/// fill-primary geometry (no floating restore size. Host has none).
/// Minimize is handled separately (park session → Machines; Focus restores).
- (void)_iosInjectFillPrimaryForWindowId:(uint64_t)windowId
                              maximized:(BOOL)maximized
                             fullscreen:(BOOL)fullscreen {
  CGSize size = [self _iosFillPrimaryHostSizeForWindowId:windowId];
  uint32_t width = (uint32_t)MAX(1, lround(size.width));
  uint32_t height = (uint32_t)MAX(1, lround(size.height));
  [self injectWindowResize:windowId width:width height:height];
  if (fullscreen) {
    [self syncHostFullscreen:YES forWindowId:windowId width:width height:height];
  } else if (maximized) {
    [self syncHostMaximized:YES forWindowId:windowId width:width height:height];
  } else {
    // Unmaximize / unfullscreen: clear both states at fill-primary size.
    [self syncHostFullscreen:NO forWindowId:windowId width:width height:height];
    [self syncHostMaximized:NO forWindowId:windowId width:width height:height];
  }
}
#endif

- (void)handleWindowCloseRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowCloseRequested: id=%llu", event->window_id);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [self _iosBeginGracefulHostCloseForWindowId:event->window_id];
#else
  WWNWindow *window = _windows[@(event->window_id)];
  if (window) {
    [window performClose:nil];
  }
#endif
}

// Shared AppKit + UIKit (must stay outside the macOS-only block above).
- (void)handleWindowMaximizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowMaximizeRequested: id=%llu", event->window_id);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [self _iosSetFollowHostSizeForFillPrimaryWindowId:event->window_id];
  [self _iosInjectFillPrimaryForWindowId:event->window_id
                              maximized:YES
                             fullscreen:NO];
#else
  WWNWindow *window = _windows[@(event->window_id)];
  if (window) {
    if (![window isZoomed]) {
      window.processingResize = YES;
      window.suppressCompositorCallbacks = YES;
      [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [window zoom:nil];
      }
          completionHandler:^{
            NSSize contentSize = WWNWaylandContentSizeForWindow(window);
            uint32_t width = (uint32_t)MAX(1, lround(contentSize.width));
            uint32_t height = (uint32_t)MAX(1, lround(contentSize.height));
            window.wwnLastZoomed = [window isZoomed];
            window.processingResize = NO;
            window.suppressCompositorCallbacks = NO;
            [self injectWindowResize:event->window_id width:width height:height];
            [self syncHostMaximized:YES
                        forWindowId:event->window_id
                              width:width
                             height:height];
          }];
    }
  }
#endif
}

- (void)handleWindowUnmaximizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowUnmaximizeRequested: id=%llu",
         event->window_id);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [self _iosInjectFillPrimaryForWindowId:event->window_id
                              maximized:NO
                             fullscreen:NO];
#else
  WWNWindow *window = _windows[@(event->window_id)];
  if (window) {
    if ([window isZoomed]) {
      window.processingResize = YES;
      window.suppressCompositorCallbacks = YES;
      [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [window zoom:nil];
      }
          completionHandler:^{
            NSSize contentSize = WWNWaylandContentSizeForWindow(window);
            uint32_t width = (uint32_t)MAX(1, lround(contentSize.width));
            uint32_t height = (uint32_t)MAX(1, lround(contentSize.height));
            window.wwnLastZoomed = [window isZoomed];
            window.processingResize = NO;
            window.suppressCompositorCallbacks = NO;
            [self injectWindowResize:event->window_id width:width height:height];
            [self syncHostMaximized:NO
                        forWindowId:event->window_id
                              width:width
                             height:height];
          }];
    }
  }
#endif
}

- (void)handleWindowFullscreenRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowFullscreenRequested: id=%llu", event->window_id);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [self _iosSetFollowHostSizeForFillPrimaryWindowId:event->window_id];
  [self _iosInjectFillPrimaryForWindowId:event->window_id
                              maximized:NO
                             fullscreen:YES];
#else
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || window.hostLocked)
    return;
  if ((window.styleMask & NSWindowStyleMaskFullScreen) != 0)
    return;
  // Nested weston/niri call xdg_toplevel.set_fullscreen to fill the parent
  // Wayland output. That is not macOS Spaces fullscreen. Mapping it here
  // fullscreened a 64px placeholder and left a blank space.
  NSString *bundledClient = WWNResolveActiveMachineBundledClientId();
  if (WWNBundledClientFillsHost(bundledClient) ||
      WWNTitleIndicatesNestedCompositor(window.title)) {
    WWNLog("BRIDGE",
           @"xdg fullscreen for nested compositor window %llu fills the "
           @"NSWindow, not Spaces",
           event->window_id);
    NSSize contentSize = WWNWaylandContentSizeForWindow(window);
    uint32_t ow = _latestOutputW > 0 ? _latestOutputW : 1024;
    uint32_t oh = _latestOutputH > 0 ? _latestOutputH : 768;
    if (contentSize.width <= 64.0 || contentSize.height <= 64.0 ||
        contentSize.width + 1.0 < (CGFloat)ow ||
        contentSize.height + 1.0 < (CGFloat)oh) {
      NSRect frame = [window frameRectForContentRect:NSMakeRect(0, 0, ow, oh)];
      frame.origin = window.frame.origin;
      window.processingResize = YES;
      [window setFrame:frame display:NO];
      window.processingResize = NO;
      uint64_t wid = event->window_id;
      [self _dispatchToRust:^{
        WWNCoreSetOutputGeometryForWindow(self->_rustCore, wid, ow, oh, 1.0f);
      }];
      [self injectWindowResize:wid width:ow height:oh];
    }
    return;
  }
  window.processingResize = YES;
  [window toggleFullScreen:nil];
  window.processingResize = NO;
#endif
}

- (void)handleWindowUnfullscreenRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowUnfullscreenRequested: id=%llu",
         event->window_id);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [self _iosInjectFillPrimaryForWindowId:event->window_id
                              maximized:NO
                             fullscreen:NO];
#else
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || window.hostLocked)
    return;
  if ((window.styleMask & NSWindowStyleMaskFullScreen) == 0)
    return;
  window.processingResize = YES;
  [window toggleFullScreen:nil];
  window.processingResize = NO;
#endif
}

- (NSUInteger)pendingWindowCount {
  if (!_rustCore) {
    return 0;
  }
  return WWNCorePendingWindowCount(_rustCore);
}

- (NSDictionary *)popPendingWindow {
  return nil;
}

- (void)_runCompositorEventPumpWithIterations:(int)iterations {
  if (!_rustCore || iterations <= 0) {
    return;
  }
  void (^pump)(void) = ^{
    for (int i = 0; i < iterations; i++) {
      WWNCoreProcessEvents(self->_rustCore);
      WWNCoreFlushClients(self->_rustCore);
    }
  };
  if (dispatch_get_specific(kWWNCompositorQueueKey)) {
    pump();
    return;
  }
  if (_compositorThread) {
    [self _dispatchSyncToCompositor:pump];
  } else {
    pump();
  }
}

- (void)_pumpHostCompositorFromQueue {
  [self _runCompositorEventPumpWithIterations:8];
}

- (void)pumpHostCompositorEvents {
  if (!_rustCore) {
    return;
  }
  // Run Wayland dispatch off the main thread so nested clients can connect
  // without blocking AppKit (weston.ini, NSTask launch, UI).
  [self _pumpHostCompositorFromQueue];
  void (^drainOnMain)(void) = ^{
    if (!self->_rustCore) {
      return;
    }
    // Pop/handle on main only. Never spin ProcessEvents in a while-loop here:
    // configure churn can enqueue events faster than we drain and freeze the UI.
    NSUInteger handled = 0;
    for (; handled < 32; handled++) {
      CWindowEvent *event = WWNCorePopWindowEvent(self->_rustCore);
      if (!event) {
        break;
      }
      [self _dispatchWindowEvent:event];
      WWNWindowEventFree(event);
    }
    if (handled > 0) {
      WWNLog("BRIDGE", @"Drained %lu window event(s) after host pump",
             (unsigned long)handled);
    }
  };
  if ([NSThread isMainThread]) {
    drainOnMain();
  } else {
    dispatch_sync(dispatch_get_main_queue(), drainOnMain);
  }
}

- (void)scheduleFollowUpHostCompositorPumps:(NSUInteger)count
                                 interval:(NSTimeInterval)intervalSeconds {
  if (count == 0 || intervalSeconds <= 0) {
    return;
  }
  for (NSUInteger i = 1; i <= count; i++) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(intervalSeconds * (NSTimeInterval)i *
                                NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          [[WWNCompositorBridge sharedBridge] pumpHostCompositorEvents];
        });
  }
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR

/// Forward Wayland cursor surface info to all iOS compositor views so they
/// can render a cursor layer in touchpad mode.
- (void)_updateCursorFromScene:(CRenderScene *)scene {
  if (!scene)
    return;

  // Look up the cached cursor image (keyed by surface_id + buffer_id)
  id cursorImage = nil;
  if (scene->has_cursor && scene->cursor_surface_id > 0 &&
      scene->cursor_buffer_id > 0) {
    NSString *cacheKey =
        WWNBufferCacheKey(scene->cursor_surface_id, scene->cursor_buffer_id);
    cursorImage = _bufferCache[cacheKey];
  }

  for (NSNumber *key in _windows) {
    id view = _windows[key];
    if (![view isKindOfClass:[WWNCompositorView_ios class]]) {
      continue;
    }
    WWNCompositorView_ios *iosView = (WWNCompositorView_ios *)view;
    if (!iosView.window && !iosView.superview) {
      continue;
    }
    if (scene->has_cursor) {
      [iosView updateCursorImage:cursorImage
                           width:scene->cursor_width
                          height:scene->cursor_height
                        hotspotX:scene->cursor_hotspot_x
                        hotspotY:scene->cursor_hotspot_y];
    } else {
      [iosView updateCursorImage:nil width:0 height:0 hotspotX:0 hotspotY:0];
    }
  }
}

/// Stop rendering into live compositor views before native clients exit.
- (void)tearDownActiveIOSCompositorViews {
  if (_rustCore && _compositorThread) {
    [self _dispatchSyncToCompositor:^{
      uint32_t disconnected = WWNCoreDisconnectAllClients(self->_rustCore);
      if (disconnected > 0) {
        WWNLog("BRIDGE", @"Disconnected %u in-process Wayland client(s)",
               disconnected);
      }
      WWNCoreFlushClients(self->_rustCore);
    }];
  }

  for (NSNumber *key in [_windows copy]) {
    UIView *view = _windows[key];
    if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
      [(WWNCompositorView_ios *)view prepareForSessionTeardown];
    }
  }
  for (NSNumber *key in [_popups copy]) {
    UIView *popup = (UIView *)_popups[key];
    if ([popup isKindOfClass:[WWNCompositorView_ios class]]) {
      [(WWNCompositorView_ios *)popup prepareForSessionTeardown];
    }
  }
  if (_ilandHostView) {
    [_ilandHostView prepareForSessionTeardown];
    [_ilandHostView removeFromSuperview];
    _ilandHostView = nil;
  }
  [_surfaceLayers removeAllObjects];
  [_bufferCache removeAllObjects];
  [_latestBufferBySurface removeAllObjects];
  [_presentGenerationBySurface removeAllObjects];
  _waylandPresentGeneration = 0;
}

/// Prefer a dedicated Metal presentation view. Do NOT hijack an arbitrary
/// Wayland toplevel view. Those tear down CAMetalLayer on the first SHM/
/// Wayland frame and leave kmscube blank.
- (WWNCompositorView_ios *)ensureIlandPresentationView {
  if (![NSThread isMainThread]) {
    __block WWNCompositorView_ios *view = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
      view = [self ensureIlandPresentationView];
    });
    return view;
  }
  if (_ilandHostView) {
    return _ilandHostView;
  }

  for (NSNumber *key in _windows) {
    id candidate = _windows[key];
    if (![candidate isKindOfClass:[WWNCompositorView_ios class]]) {
      continue;
    }
    WWNCompositorView_ios *view = (WWNCompositorView_ios *)candidate;
    if ([view.accessibilityIdentifier isEqualToString:@"wwn.compositor.iland-host"]) {
      CGSize size = view.bounds.size;
      if (size.width > 1.0 && size.height > 1.0) {
        _ilandHostView = view;
        return view;
      }
    }
  }

  if ([self.containerView isKindOfClass:[WWNCompositorView_ios class]] &&
      [((WWNCompositorView_ios *)self.containerView).accessibilityIdentifier
          isEqualToString:@"wwn.compositor.iland-host"]) {
    _ilandHostView = (WWNCompositorView_ios *)self.containerView;
    return _ilandHostView;
  }

  if (!self.containerView && !_iosPerWindowHostingEnabled) {
    WWNLog("BRIDGE",
           @"ensureIlandPresentationView: containerView is nil. Cannot host "
           @"iland/kmscube");
    return nil;
  }

  [self seedOutputSizeFromLiveHostSurface];
  CGRect frame = self.containerView ? self.containerView.bounds
                                    : CGRectMake(0, 0, 1024, 768);
  if (frame.size.width < 1.0 || frame.size.height < 1.0) {
    uint32_t w = _latestOutputW > 0 ? _latestOutputW : 1024;
    uint32_t h = _latestOutputH > 0 ? _latestOutputH : 768;
    frame = CGRectMake(0, 0, (CGFloat)w, (CGFloat)h);
  }

  WWNCompositorView_ios *view =
      [[WWNCompositorView_ios alloc] initWithFrame:frame];
  view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  view.accessibilityIdentifier = @"wwn.compositor.iland-host";
  // Real client id is applied in launchNestedIlandGpuClientOnPrimaryView -
  // do not brand every iland host as kmscube.
  view.accessibilityLabel = @"iland-host";
  view.hostLocked = YES;
  view.followHostSize = YES;
  _ilandHostView = view;

  if (_iosPerWindowHostingEnabled) {
    // iPadOS / visionOS: do NOT attach under the primary Machines container -
    // launchNestedIlandGpuClient requests a dedicated UIWindowScene instead.
    WWNLog("BRIDGE",
           @"Created iland presentation host %.0fx%.0f (deferred dedicated scene)",
           frame.size.width, frame.size.height);
  } else if (self.containerView) {
    // Phone / single-scene: above any race-created Wayland window views -
    // insertSubview:atIndex:0 left the Metal plate covered by a later opaque
    // SHM window (black screen).
    [self.containerView addSubview:view];
    [self.containerView bringSubviewToFront:view];
    WWNLog("BRIDGE",
           @"Created iland presentation host %.0fx%.0f for nested GL client",
           frame.size.width, frame.size.height);
  } else {
    WWNLog("BRIDGE",
           @"ensureIlandPresentationView: containerView is nil. Cannot host "
           @"iland/kmscube");
    _ilandHostView = nil;
    return nil;
  }
  return view;
}

/// iPadOS / visionOS: put the iland Metal host in its own UIWindowScene so
/// kmscube is visible while Machines stays on the primary scene. Mirrors the
/// Wayland toplevel path in handleWindowCreated (no xdg_toplevel for KMS).
- (void)requestDedicatedSceneForIlandHostView:(WWNCompositorView_ios *)view
                                        title:(NSString *)title {
  if (!_iosPerWindowHostingEnabled || !view) {
    return;
  }
#if !TARGET_OS_TV
  if (@available(iOS 17.0, visionOS 1.0, *)) {
    uint64_t wid = kWWNIlandHostSceneWindowId;
    if (title.length > 0) {
      view.accessibilityLabel = title;
    }
    if (view.superview == self.containerView) {
      [view removeFromSuperview];
    }
    _windows[@(wid)] = view;
    _pendingSceneClientViews[@(wid)] = view;

    NSUserActivity *activity = [[NSUserActivity alloc]
        initWithActivityType:WWNClientWindowSceneActivityType];
    activity.userInfo = @{WWNClientWindowSceneWindowIdKey : @(wid)};

    UISceneSessionActivationRequest *request = [UISceneSessionActivationRequest
        requestWithRole:UIWindowSceneSessionRoleApplication];
    request.userActivity = activity;
    [UIApplication.sharedApplication
        activateSceneSessionForRequest:request
                          errorHandler:^(NSError *err) {
                            WWNLog("BRIDGE",
                                   @"Scene activation failed for iland host "
                                   @"%llu: %@. Falling back to primary container",
                                   wid, err);
                            dispatch_async(dispatch_get_main_queue(), ^{
                              UIView *pending = [self
                                  takePendingSceneClientViewForWindowId:wid];
                              if (!pending) {
                                pending = self->_ilandHostView;
                              }
                              if (pending && self.containerView) {
                                if (pending.superview != self.containerView) {
                                  [self.containerView addSubview:pending];
                                }
                                [self.containerView bringSubviewToFront:pending];
                                // Primary-scene fallback: Machines would cover
                                // the plate. Reveal compositor like phone.
                                [[NSNotificationCenter defaultCenter]
                                    postNotificationName:
                                        WWNNativeClientWillLaunchNotification
                                                  object:self
                                                userInfo:@{
                                                  @"clientId" : title ?: @"kmscube",
                                                  @"forceRevealPrimary" : @YES
                                                }];
                              }
                            });
                          }];
    WWNLog("BRIDGE",
           @"Requested dedicated UIWindowScene for iland host %llu (%@)", wid,
           title ?: @"kmscube");
    return;
  }
#endif
  // Pre-iOS 17: attach to primary container.
  if (self.containerView && view.superview != self.containerView) {
    [self.containerView addSubview:view];
    [self.containerView bringSubviewToFront:view];
  }
}

- (BOOL)launchNestedIlandGpuClientOnPrimaryView:(NSString *)clientId {
  const char *logMod = "CLIENT";
  if ([clientId isEqualToString:@"kmscube"]) {
    logMod = "KMSCUBE";
  } else if ([clientId isEqualToString:@"gbm-es2-demo"]) {
    logMod = "GBM_ES2_DEMO";
  }
  WWNCompositorView_ios *view = [self ensureIlandPresentationView];
  if (!view) {
    WWNLog(logMod,
           @"%@ launch failed: no Metal host view (containerView=%@)",
           clientId, self.containerView ? @"set" : @"nil");
    return NO;
  }
  if (clientId.length > 0) {
    view.accessibilityLabel = clientId;
  }
  [self requestDedicatedSceneForIlandHostView:view title:clientId];
  BOOL ok = [view launchNestedIlandGpuClient:clientId];
  if (!ok) {
    WWNLog(logMod,
           @"%@ launch failed after host view ready (%@ %.0fx%.0f). "
           @"check iland presenter / entry point link",
           clientId, NSStringFromClass([view class]), view.bounds.size.width,
           view.bounds.size.height);
  }
  return ok;
}

- (BOOL)launchNestedKmscubeOnPrimaryView {
  return [self launchNestedIlandGpuClientOnPrimaryView:@"kmscube"];
}

- (BOOL)prepareIlandMetalPresentationOnPrimaryView {
  // ensureIlandPresentationView + prepareIlandMetalPresentation touch UIKit and
  // CAMetalLayer (view creation, layer.hidden/frame, self.opaque,
  // resignFirstResponder, insertSublayer). Nested weston runs its launch on a
  // background QoS queue (wwnLaunchWestonCompositorWithBackend) and calls in
  // here directly, so this must hop to the main thread or UIKit aborts the app
  // on the iOS Simulator. kmscube's own call sites are already main-thread.
  if (![NSThread isMainThread]) {
    __block BOOL ok = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
      ok = [self prepareIlandMetalPresentationOnPrimaryView];
    });
    return ok;
  }
  WWNCompositorView_ios *view = [self ensureIlandPresentationView];
  if (!view) {
    return NO;
  }
  return [view prepareIlandMetalPresentation];
}

- (BOOL)prepareIlandMetalPresentationOnPrimaryViewForClientId:(NSString *)clientId {
  (void)clientId;
  return [self prepareIlandMetalPresentationOnPrimaryView];
}

- (void)stopIlandGpuClientOnPrimaryView {
  if (![NSThread isMainThread]) {
    dispatch_sync(dispatch_get_main_queue(), ^{
      [self stopIlandGpuClientOnPrimaryView];
    });
    return;
  }
  void (^stopView)(id) = ^(id candidate) {
    if ([candidate isKindOfClass:[WWNCompositorView_ios class]]) {
      [(WWNCompositorView_ios *)candidate stopIlandMetalPresentation];
    }
  };
  if (_ilandHostView) {
    stopView(_ilandHostView);
    if (_ilandHostView != self.containerView &&
        [_ilandHostView.accessibilityIdentifier
            isEqualToString:@"wwn.compositor.iland-host"]) {
      [_ilandHostView removeFromSuperview];
    }
    _ilandHostView = nil;
  }
  for (NSNumber *key in _windows) {
    stopView(_windows[key]);
  }
}

- (void)handleWindowHostLocked:(CWindowEvent *)event {
  NSNumber *winKey = @(event->window_id);
  [_hostLockedWindowIds addObject:winKey];
  UIView *view = _windows[winKey];
  if (view && self.containerView) {
    view.frame = self.containerView.bounds;
  }
  CGRect bounds = self.containerView ? self.containerView.bounds
                                     : CGRectMake(0, 0, event->width, event->height);
  [self injectWindowResize:event->window_id
                     width:(uint32_t)bounds.size.width
                    height:(uint32_t)bounds.size.height];
  WWNLog("BRIDGE", @"iOS host-locked window %llu to %.0fx%.0f",
         event->window_id, bounds.size.width, bounds.size.height);
}

- (void)handleWindowCreated:(CWindowEvent *)event {
  WWNLog(
      "BRIDGE", @"iOS handleWindowCreated: id=%llu %ux%u fullscreen_shell=%u host_locked=%u",
      event->window_id, event->width, event->height, event->fullscreen_shell,
      event->host_locked);

  if (!self.containerView) {
    WWNLog("BRIDGE",
           @"WARNING: handleWindowCreated id=%llu but containerView is nil. "
           @"surface will not be visible",
           event->window_id);
  }

  if (event->host_locked || event->fullscreen_shell) {
    [_hostLockedWindowIds addObject:@(event->window_id)];
  }

  // Use the container's current bounds so the surface fills it edge-to-edge.
  // fullscreen_shell (kiosk) and normal toplevels both fill the container;
  // iOS has no separate window chrome.
  // autoresizingMask keeps the surface view in sync when the container
  // resizes (e.g. on device rotation or safe-area toggle).
  CGRect frame = self.containerView ? self.containerView.bounds
                                    : CGRectMake(0, 0, event->width, event->height);
  WWNCompositorView_ios *view =
      [[WWNCompositorView_ios alloc] initWithFrame:frame];
  view.wwnWindowId = event->window_id;
  // OWL: host_locked/fullscreen_shell own size; ordinary toplevels wait for
  // ClientCommit (0×0 seed). Never inject fill-to-container on map.
  view.hostLocked = (event->host_locked || event->fullscreen_shell) ? YES : NO;
  view.followHostSize = view.hostLocked;
  view.clientCommittedSize = CGSizeZero;
  view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  view.accessibilityIdentifier = event->fullscreen_shell
                                     ? @"wwn.compositor.fullscreen-shell"
                                     : @"wwn.compositor.surface";
  // Seed tab/VoiceOver title from xdg title or the active bundled client id.
  // Never use "Shell". Shell/Machines is host chrome, not a Wayland client.
  if (event->title && strlen(event->title) > 0) {
    view.accessibilityLabel = [NSString stringWithUTF8String:event->title];
  } else {
    NSString *bundled =
        [WWNWaypipeRunner sharedRunner].activeIOSBundledClientId;
    if (bundled.length > 0) {
      view.accessibilityLabel = bundled;
    }
  }

  if (_iosPerWindowHostingEnabled && !event->host_locked &&
      !event->fullscreen_shell) {
    // iPadOS / visionOS multi-window (#120): request a DEDICATED UIWindowScene
    // for this client and attach its view only once that scene actually
    // connects (in -scene:willConnectToSession:). Attaching a UIWindow to the
    // existing scene synchronously. As the old code did. Stacked every client
    // onto the primary scene instead of giving each its own OS window/scene.
    BOOL requestedScene = NO;
#if !TARGET_OS_TV
    if (@available(iOS 17.0, visionOS 1.0, *)) {
      uint64_t widForScene = event->window_id;
      _pendingSceneClientViews[@(widForScene)] = view;

      NSUserActivity *activity = [[NSUserActivity alloc]
          initWithActivityType:WWNClientWindowSceneActivityType];
      activity.userInfo = @{WWNClientWindowSceneWindowIdKey : @(widForScene)};

      UISceneSessionActivationRequest *request = [UISceneSessionActivationRequest
          requestWithRole:UIWindowSceneSessionRoleApplication];
      request.userActivity = activity;
      [UIApplication.sharedApplication
          activateSceneSessionForRequest:request
                            errorHandler:^(NSError *err) {
                              WWNLog("BRIDGE",
                                     @"Scene activation failed for window %llu: %@. "
                                     @"falling back to shared container",
                                     widForScene, err);
                              // Falling back to the shared container: this
                              // window is no longer independently scened, so
                              // let it participate in the shared-output
                              // resize sweep again.
                              WWNCoreSetWindowHostSceneIndependent(
                                  self->_rustCore, widForScene, false);
                              dispatch_async(dispatch_get_main_queue(), ^{
                                UIView *pending = [self
                                    takePendingSceneClientViewForWindowId:widForScene];
                                if (pending && self.containerView) {
                                  [self.containerView insertSubview:pending
                                                            atIndex:0];
                                }
                              });
                            }];
      requestedScene = YES;
      // This window now lives in its own independent UIWindowScene. Never
      // let the shared/global output resize sweep (primary scene rotation,
      // safe-area/keyboard changes, …) snap it back to the primary window's
      // size. See ipad-scene-parity / vision-shell-parity (#120).
      WWNCoreSetWindowHostSceneIndependent(self->_rustCore, widForScene, true);
      WWNLog("BRIDGE",
             @"Requested dedicated UIWindowScene for window %llu (deferred attach)",
             widForScene);
    }
#endif
    if (!requestedScene) {
      // Pre-iOS 17 (no multi-scene activation API): host in the shared
      // container so the client is still visible.
      if (self.containerView) {
        [self.containerView insertSubview:view atIndex:0];
        WWNLog("BRIDGE",
               @"Per-window hosting unavailable; container fallback for window %llu",
               event->window_id);
      } else {
        WWNLog("BRIDGE",
               @"Warning: No containerView set, window %llu not visible",
               event->window_id);
      }
    }
  } else if (self.containerView) {
    [self.containerView insertSubview:view atIndex:0];
    WWNLog("BRIDGE", @"Added window %llu to container (%.0fx%.0f)",
           event->window_id, frame.size.width, frame.size.height);
  } else {
    WWNLog("BRIDGE", @"Warning: No containerView set, window %llu not visible",
           event->window_id);
  }

  [_windows setObject:view forKey:@(event->window_id)];
  // Record which machine owns this toplevel so per-machine focus / minimize /
  // hide (focusClientWindowsForMachineId:, setClientHostWindowsHidden:) work
  // when multiple machines run concurrently on iOS. Mirrors the macOS path.
  // Without this, every window has an empty owner and "focus machine" matches
  // all clients (#84 / concurrent machines).
  NSString *iosOwnerMachineId = [WWNMachineProfileStore activeMachineId];
  if (iosOwnerMachineId.length > 0) {
    _windowOwnerMachineIdByWindowId[@(event->window_id)] = iosOwnerMachineId;
  }
  [self _notifyHostWindowsDidChange];

  // Fullscreen shell (kiosk) windows are display-only surfaces presented
  // behind the primary toplevel.  Activating them would steal keyboard
  // focus from the toplevel, sending a deactivation configure that makes
  // nested compositors like weston exit.  Skip activation entirely.
  if (event->fullscreen_shell) {
    WWNLog("BRIDGE", @"Fullscreen shell window %llu. Skipping activation",
           event->window_id);
    return;
  }

  // First native toplevel: activate immediately. Soft OSK is deferred
  // (async accessory / text-input Expand) so UIKit keyboard animation does
  // not stall configure delivery.
  //
  // Sizing:
  // - host_locked / fullscreen_shell → fill container
  // - weston-terminal / foot (shell apps) → fill container on phone/tablet
  //   so the PTY grid matches the compositor view (not a floating 80×25)
  // - nested compositors (niri, weston) → fill container. niri's nested
  //   backend ignores configure(0,0) and never commits a buffer.
  // - demos (flower/smoke/simple-shm/simple-egl) → client-preferred via xdg
  //   0×0 seed; never inject output size (keeps 200×200 / 250×250 correct)
  BOOL firstNativeToplevel = (_windows.count == 1);
  NSString *bundledClientForSize =
      [WWNWaypipeRunner sharedRunner].activeIOSBundledClientId;
  if (bundledClientForSize.length == 0) {
    // WindowCreated can race the runner ivar; resolve from active machine.
    // Top-level defaults NativeClientId is often unset. Only the profile JSON
    // carries bundledAppID / NativeClientId (see agent-device-set-client-ios).
    NSString *mid = [WWNMachineProfileStore activeMachineId];
    WWNMachineProfile *profile =
        mid.length > 0 ? [WWNMachineProfileStore profileById:mid] : nil;
    id runtimeBundled = profile.runtimeOverrides[@"bundledAppID"];
    id settingsNative = profile.settingsOverrides[@"NativeClientId"];
    if ([runtimeBundled isKindOfClass:[NSString class]] &&
        [(NSString *)runtimeBundled length] > 0) {
      bundledClientForSize = (NSString *)runtimeBundled;
    } else if ([settingsNative isKindOfClass:[NSString class]]) {
      bundledClientForSize = (NSString *)settingsNative;
    }
  }
  BOOL fillShellToHost = event->fills_host ||
      WWNIosBundledClientFillsHost(bundledClientForSize);
  // Only the machine's primary shell/compositor window fills the host. Extra
  // toplevels from in-process zsh (weston-simple-shm / simple-egl / flower)
  // keep the preferred square, like weston-flower.
  NSUInteger windowsForMachine = 0;
  if (iosOwnerMachineId.length > 0) {
    for (NSNumber *wid in _windowOwnerMachineIdByWindowId) {
      if ([_windowOwnerMachineIdByWindowId[wid] isEqualToString:iosOwnerMachineId]) {
        windowsForMachine++;
      }
    }
  }
  BOOL primaryFillShell = fillShellToHost && (windowsForMachine <= 1);
#if TARGET_OS_TV
  // Fill-primary on the TV: the first toplevel fills even when NativeClientId
  // races empty. That left default weston-terminal floating at cell-snap 80x25
  // with the rest of the 1920x1080 surface black.
  if (!WWNIosBundledClientPrefersFixedSize(bundledClientForSize) &&
      windowsForMachine <= 1 && firstNativeToplevel) {
    fillShellToHost = YES;
    primaryFillShell = YES;
  }
#endif
  BOOL injectFillConfigure = event->host_locked || primaryFillShell;
  if (injectFillConfigure && [view isKindOfClass:[WWNCompositorView_ios class]]) {
    view.followHostSize = YES;
    // Treat fill shells as host-owned for presentation/placement even when
    // smithay did not mark host_locked (ordinary xdg toplevel). Prevents OWL
    // "client refused" adoption of cell-snap buffers from re-centering gutters.
    if (fillShellToHost) {
      view.hostLocked = YES;
      [_hostLockedWindowIds addObject:@(event->window_id)];
    }
  } else if (WWNIosBundledClientPrefersFixedSize(bundledClientForSize) &&
             [view isKindOfClass:[WWNCompositorView_ios class]]) {
    // Explicit guard: fixed weston demos must stay Client-authoritative even
    // if a prior session left followHostSize set on a recycled view (should
    // not happen) or a race mis-classifies the bundled id.
    ((WWNCompositorView_ios *)view).followHostSize = NO;
  }
  WWNLog("BRIDGE",
         @"iOS size policy window=%llu client='%@' fillShell=%d followHost=%d",
         event->window_id, bundledClientForSize ?: @"(nil)", fillShellToHost,
         (injectFillConfigure && [view isKindOfClass:[WWNCompositorView_ios class]])
             ? 1
             : 0);

  if (event->host_locked || firstNativeToplevel) {
    uint64_t windowId = event->window_id;
    CGRect viewFrame = self.containerView ? self.containerView.bounds
                                          : CGRectMake(0, 0, event->width, event->height);
    uint32_t w = (uint32_t)MAX(1, viewFrame.size.width);
    uint32_t h = (uint32_t)MAX(1, viewFrame.size.height);
    WWNLog("BRIDGE",
           @"%@ window %llu. Immediate activate%@ (defer accessory keyboard)",
           event->host_locked ? @"Host-locked" : @"First native toplevel",
           windowId,
           injectFillConfigure
               ? [NSString stringWithFormat:@" + fill configure %ux%u%@", w, h,
                                            fillShellToHost && !event->host_locked
                                                ? @" (shell)"
                                                : @""]
               : @" (client-preferred size)");
    if (_compositorThread) {
      [self _dispatchSyncToCompositor:^{
        WWNCoreSetWindowActivatedSilent(self->_rustCore, windowId, true);
        if (injectFillConfigure) {
          WWNCoreInjectWindowResize(self->_rustCore, windowId, w, h);
        }
        WWNCoreFlushClients(self->_rustCore);
      }];
    } else {
      WWNCoreSetWindowActivatedSilent(_rustCore, windowId, true);
      if (injectFillConfigure) {
        WWNCoreInjectWindowResize(_rustCore, windowId, w, h);
      }
      WWNCoreFlushClients(_rustCore);
    }
    // Shell fill: advertise maximized so weston-terminal skips floating
    // cell-snap and keeps SHM at the host configure size.
    if (fillShellToHost && !event->host_locked) {
      [self syncHostMaximized:YES forWindowId:windowId width:w height:h];
    }
    [self injectPointerEnterForWindow:windowId
                                     x:viewFrame.size.width / 2.0
                                     y:viewFrame.size.height / 2.0
                             timestamp:0];
    // Nested compositors (niri, etc.) need wl_keyboard focus for hotkeys like
    // Mod+D → fuzzel. Weston-terminal only uses a PTY and must skip this.
    NSString *bundledClient =
        [WWNWaypipeRunner sharedRunner].activeIOSBundledClientId;
    BOOL needsCompositorKeyboard =
        !event->host_locked && [bundledClient isEqualToString:@"niri"];
    if (needsCompositorKeyboard) {
      [self injectKeyboardEnterForWindow:windowId keys:@[]];
      if (_compositorThread) {
        [self _dispatchSyncToCompositor:^{
          WWNCoreFlushClients(self->_rustCore);
        }];
      } else {
        WWNCoreFlushClients(_rustCore);
      }
      // Soft OSK expands via zwp_text_input_v3 Enable (tick sync). Always
      // show the Wawona extra keyboard (accessory bar) so Mod/Esc/arrows
      // remain available for niri / nested clients.
      if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
        WWNCompositorView_ios *cv = (WWNCompositorView_ios *)view;
      // Nested compositor: accessory-only until the first Wayland frame.
      // Immediate activateKeyboard shrinks the host output (soft OSK) and
      // stalls ticks the same way it did for weston-terminal. Fill configure
      // must land first.
      [cv applyHostKeyboardForTextInputEnabled:NO];
      }
    } else if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
      // Terminal / demo toplevels: do NOT activateKeyboard here. Soft OSK or
      // even accessory FR before the first buffer stalls ticks and leaves
      // weston-terminal under the startup log forever. First frame arms KB.
      WWNCompositorView_ios *cv = (WWNCompositorView_ios *)view;
      [cv applyHostKeyboardForTextInputEnabled:NO];
    }
    return;
  }

  // Activate synchronously BEFORE any layoutSubviews can fire.
  // Silent activation + flush; size comes from xdg-shell client negotiation
  // (not a forced fill-to-container configure).
  uint64_t windowId = event->window_id;
  WWNLog("BRIDGE", @"Activating new window %llu (client-preferred size)",
         windowId);

  // 1. Set activated=true in Rust without sending a configure.
  [self _dispatchToRust:^{
    WWNCoreSetWindowActivatedSilent(self->_rustCore, windowId, true);
  }];

  // 2. Input focus events (no injectWindowResize. ClientPreferred sizing).
  UIView *hostView = view.superview ?: self.containerView;
  CGRect viewFrame = hostView ? hostView.bounds : CGRectMake(0, 0, 800, 600);
  [self injectKeyboardEnterForWindow:windowId keys:@[]];

  double cx = viewFrame.size.width / 2.0;
  double cy = viewFrame.size.height / 2.0;
  [self injectPointerEnterForWindow:windowId x:cx y:cy timestamp:0];

  // 4. Flush immediately so events reach the wire NOW, before
  //    activateKeyboard triggers a UIKit keyboard animation that
  //    blocks the main queue and prevents _compositorTick from firing.
  //    Without this, mode_successful feedback is delayed ~2s and
  //    weston times out waiting for it.
  [self _dispatchToRust:^{
    WWNCoreFlushClients(self->_rustCore);
  }];

  // 5. Mode only. First Wayland frame arms accessory / soft OSK
  //    (see -[WWNCompositorView_ios armHostKeyboardAfterFirstFrame]).
  if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
    WWNCompositorView_ios *cv = (WWNCompositorView_ios *)view;
    [cv applyHostKeyboardForTextInputEnabled:NO];
  }
}

- (void)handleWindowDestroyed:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"iOS handleWindowDestroyed: id=%llu", event->window_id);
  NSNumber *winKey = @(event->window_id);
  UIView *window = [_windows objectForKey:winKey];
  if ([window isKindOfClass:[WWNCompositorView_ios class]]) {
    [(WWNCompositorView_ios *)window prepareForSessionTeardown];
  }
  if (window) {
    [window removeFromSuperview];
    [_windows removeObjectForKey:winKey];
  }
  UIWindow *hostWindow = _iosHostWindows[winKey];
  if (hostWindow) {
    hostWindow.hidden = YES;
    hostWindow.rootViewController = nil;
#if !TARGET_OS_TV
    // iPadOS / visionOS multi-window (#120): tear down the client's dedicated
    // UIWindowScene so the OS window actually closes instead of lingering empty.
    if (_iosPerWindowHostingEnabled) {
      UISceneSession *session = hostWindow.windowScene.session;
      if (session) {
        [UIApplication.sharedApplication
            requestSceneSessionDestruction:session
                              options:nil
                         errorHandler:^(NSError *err) {
                           WWNLog("BRIDGE",
                                  @"Scene destruction failed for window %llu: %@",
                                  event->window_id, err);
                         }];
      }
    }
#endif
    [_iosHostWindows removeObjectForKey:winKey];
  }

  // Also check if it's a popup
  UIView *popup = (UIView *)[_popups objectForKey:winKey];
  if (popup) {
    if ([popup isKindOfClass:[WWNCompositorView_ios class]]) {
      [(WWNCompositorView_ios *)popup prepareForSessionTeardown];
    }
    [popup removeFromSuperview];
    [_popups removeObjectForKey:winKey];
    WWNLog("BRIDGE", @"iOS popup %llu destroyed", event->window_id);
  }

  [_latestResizeDims removeObjectForKey:winKey];
  [_sentResizeDims removeObjectForKey:winKey];
  [_resizeInFlightWindows removeObject:winKey];
  [_hostLockedWindowIds removeObject:winKey];
  [_windowOwnerMachineIdByWindowId removeObjectForKey:winKey];
  [_pendingSceneClientViews removeObjectForKey:winKey];
  [self _iosClearHostCloseDeferredForWindowId:event->window_id];
  [_iosHostMaximizedByWindowId removeObjectForKey:winKey];
  [_iosHostFullscreenByWindowId removeObjectForKey:winKey];
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(_drainPendingWindowResizeForId:)
                                             object:winKey];

  if (_windows.count == 0 && _popups.count == 0) {
    [_surfaceLayers removeAllObjects];
    [_bufferCache removeAllObjects];
    [_latestBufferBySurface removeAllObjects];
    [_presentGenerationBySurface removeAllObjects];
    _waylandPresentGeneration = 0;
    _clientWantsCursorRendered = NO;
    _lastCursorBufferId = 0;
    _lastCursorSurfaceId = 0;
    WWNLog("BRIDGE", @"All iOS windows destroyed. Cleared presentation caches");
  }
  [self _notifyHostWindowsDidChange];
}

- (void)handleWindowTitleChanged:(CWindowEvent *)event {
  if (!event->title)
    return;
  NSString *newTitle = [NSString stringWithUTF8String:event->title];
  WWNLog("BRIDGE", @"iOS handleWindowTitleChanged: window %llu → '%@'",
         event->window_id, newTitle);

  // VoiceOver + tab chrome: keep the compositor surface's label in sync with
  // the client's window title. Never invent a "Shell" tab from host UI.
  UIView *clientView = [_windows objectForKey:@(event->window_id)];
  if (clientView && newTitle.length > 0) {
    clientView.accessibilityLabel = newTitle;
    if (clientView.accessibilityIdentifier.length == 0) {
      clientView.accessibilityIdentifier = @"wwn.compositor.surface";
    }
  }

  // Late shell detection: if map-time fill missed (empty bundled id), adopt
  // followHost when the xdg title identifies weston-terminal / foot.
  // Inverse: weston-flower / simple-shm / simple-egl keep a preferred square.
  NSString *titleLower = newTitle.lowercaseString;
  BOOL titleLooksLikeDemo = WWNWestonDemoPrefersFixedSquare(nil, newTitle);
  BOOL titleLooksLikeShell =
      [titleLower containsString:@"weston terminal"] ||
      [titleLower containsString:@"wayland-terminal"] ||
      [titleLower hasPrefix:@"foot"] || [titleLower containsString:@"foot "] ||
      [titleLower containsString:@"niri"];
  if (titleLooksLikeDemo &&
      [clientView isKindOfClass:[WWNCompositorView_ios class]]) {
    WWNCompositorView_ios *cv = (WWNCompositorView_ios *)clientView;
    cv.followHostSize = NO;
    cv.hostLocked = NO;
    [_hostLockedWindowIds removeObject:@(event->window_id)];
    WWNLog("BRIDGE",
           @"iOS demo title '%@' → client-preferred square (no host fill)",
           newTitle);
  } else if (titleLooksLikeShell &&
      [clientView isKindOfClass:[WWNCompositorView_ios class]]) {
    WWNCompositorView_ios *cv = (WWNCompositorView_ios *)clientView;
    if (!cv.followHostSize && !cv.hostLocked && self.containerView) {
      cv.followHostSize = YES;
      uint32_t w = (uint32_t)MAX(1, self.containerView.bounds.size.width);
      uint32_t h = (uint32_t)MAX(1, self.containerView.bounds.size.height);
      WWNLog("BRIDGE",
             @"iOS shell title '%@' → followHost + fill configure %ux%u",
             newTitle, w, h);
      [self injectWindowResize:event->window_id width:w height:h];
      [self syncHostMaximized:YES
                  forWindowId:event->window_id
                        width:w
                       height:h];
    }
  }

  // Update the UIWindowScene title so it appears in the app switcher
  // and iPad Stage Manager.
  UIWindow *hostWindow = _iosHostWindows[@(event->window_id)];
  UIWindowScene *scene = hostWindow.windowScene;
  if (!scene) {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
      if ([s isKindOfClass:[UIWindowScene class]]) {
        scene = (UIWindowScene *)s;
        break;
      }
    }
  }
  if (scene) {
    scene.title = newTitle;
  }
  [self _notifyHostWindowsDidChange];
}

- (void)handleWindowSizeChanged:(CWindowEvent *)event {
  UIView *window = [_windows objectForKey:@(event->window_id)];
  if (!window) {
    return;
  }

  WWNCompositorView_ios *iosView =
      [window isKindOfClass:[WWNCompositorView_ios class]]
          ? (WWNCompositorView_ios *)window
          : nil;
  BOOL hostLocked =
      event->host_locked ||
      [_hostLockedWindowIds containsObject:@(event->window_id)] ||
      (iosView && iosView.hostLocked);

  // Host-originated configure/output acks. Do not re-apply (macOS parity).
  if (!hostLocked && (event->size_cause == 1 || event->size_cause == 3)) {
    WWNLog("BRIDGE",
           @"iOS ignoring non-authoritative SizeChanged window=%llu "
           @"event=%ux%u cause=%u",
           event->window_id, event->width, event->height, event->size_cause);
    return;
  }

  UIWindow *hostWindow = _iosHostWindows[@(event->window_id)];
  CGRect hostBounds = CGRectZero;
  if (hostWindow && hostWindow.rootViewController) {
    hostBounds = hostWindow.rootViewController.view.bounds;
  } else if (self.containerView) {
    hostBounds = self.containerView.bounds;
  } else {
    hostBounds = window.bounds;
  }

  BOOL clientChosen = event->size_cause == 2 /* ClientCommit */;
  if (iosView && clientChosen && event->width > 0 && event->height > 0) {
    iosView.clientCommittedSize = CGSizeMake(event->width, event->height);
    NSString *shellClient =
        [WWNWaypipeRunner sharedRunner].activeIOSBundledClientId;
    if (shellClient.length == 0) {
      NSString *mid = [WWNMachineProfileStore activeMachineId];
      WWNMachineProfile *profile =
          mid.length > 0 ? [WWNMachineProfileStore profileById:mid] : nil;
      id rb = profile.runtimeOverrides[@"bundledAppID"];
      id sn = profile.settingsOverrides[@"NativeClientId"];
      if ([rb isKindOfClass:[NSString class]] && [(NSString *)rb length] > 0)
        shellClient = (NSString *)rb;
      else if ([sn isKindOfClass:[NSString class]])
        shellClient = (NSString *)sn;
    }
    BOOL activeShell = event->fills_host ||
        WWNIosBundledClientFillsHost(shellClient);
    BOOL fixedSizeClient =
        WWNWestonDemoPrefersFixedSquare(shellClient, iosView.accessibilityLabel);
    if (fixedSizeClient) {
      iosView.followHostSize = NO;
    } else if (hostLocked || iosView.followHostSize || activeShell) {
      // Shells / host-locked always follow the compositor container. Do not
      // drop followHost when the first commit is still a floating cell-snap
      // (e.g. 80x25). That cleared full-bleed and re-centered gutters.
      // Do not use the machine-level shell id here: zsh-launched
      // weston-simple-shm / simple-egl inside a terminal machine must keep
      // their preferred square (flower/smoke refuse host fill the same way).
      iosView.followHostSize = YES;
      if (activeShell && iosView.followHostSize && hostBounds.size.width > 0 &&
          hostBounds.size.height > 0 &&
          (fabs((CGFloat)event->width - hostBounds.size.width) > 1.0 ||
           fabs((CGFloat)event->height - hostBounds.size.height) > 1.0)) {
        // Nudge on any >1pt mismatch. A 95% threshold missed 398×763 vs
        // 402×778 (~99%), so the refuse-echo configure stuck and drain
        // skipped "already sent" host dims.
        NSNumber *nudgeKey = @(event->window_id);
        [_sentResizeDims removeObjectForKey:nudgeKey];
        WWNLog("BRIDGE",
               @"iOS shell fill nudge window=%llu commit=%ux%u → host=%.0fx%.0f",
               event->window_id, event->width, event->height,
               hostBounds.size.width, hostBounds.size.height);
        [self injectWindowResize:event->window_id
                           width:(uint32_t)MAX(1, hostBounds.size.width)
                          height:(uint32_t)MAX(1, hostBounds.size.height)];
      }
    } else if (hostBounds.size.width > 0 && hostBounds.size.height > 0) {
      // Fillers (niri ≈ output) follow host layout; fixed demos do not.
      BOOL fillsHost = ((CGFloat)event->width >= hostBounds.size.width * 0.90 &&
                        (CGFloat)event->height >= hostBounds.size.height * 0.90);
      iosView.followHostSize = fillsHost;
    } else {
      iosView.followHostSize = NO;
    }
    WWNLog("BRIDGE",
           @"iOS ClientCommit SizeChanged window=%llu %ux%u followHost=%@ "
           @"hostLocked=%@ shell='%@'",
           event->window_id, event->width, event->height,
           iosView.followHostSize ? @"yes" : @"no",
           hostLocked ? @"yes" : @"no", shellClient ?: @"(nil)");
  }

  if (hostWindow && hostWindow.rootViewController) {
    // Hit-testing view still fills the scene; presentation centers via
    // presentWaylandFrame when followHostSize is NO.
    window.frame = hostBounds;
    UIWindowScene *scene = hostWindow.windowScene;
    if (scene && !hostLocked && clientChosen && event->width > 0 &&
        event->height > 0) {
      // Stage Manager: minimum tracks client size so fixed 200×200 is not
      // clipped; absolute scene size is OS-controlled.
      scene.sizeRestrictions.minimumSize =
          CGSizeMake(event->width, event->height);
    }
    return;
  }

  if (hostLocked || (iosView && iosView.followHostSize)) {
    if (self.containerView) {
      window.frame = self.containerView.bounds;
    }
  } else if (clientChosen && event->width > 0 && event->height > 0) {
    // Client-constrained: keep the host surface view filling the container
    // for input, but do not rewrite bounds to the event size (would fight
    // autoresizing). Presentation uses scene node + center placement.
    if (self.containerView && !CGRectEqualToRect(window.frame, hostBounds) &&
        hostBounds.size.width > 0) {
      window.frame = hostBounds;
    }
  } else if (!self.containerView) {
    window.frame = CGRectMake(window.frame.origin.x, window.frame.origin.y,
                              event->width, event->height);
  }
}

- (void)handlePopupCreated:(CWindowEvent *)event {
  WWNLog("BRIDGE",
         @"iOS handlePopupCreated: id=%llu parent=%llu at (%d,%d) "
         @"size=%ux%u",
         event->window_id, event->parent_id, event->x, event->y, event->width,
         event->height);

  // Find the parent view -- it can be a window or another popup
  UIView *parentView = nil;
  UIView *parentWindowView =
      (UIView *)[_windows objectForKey:@(event->parent_id)];
  UIView *parentPopupView =
      (UIView *)[_popups objectForKey:@(event->parent_id)];

  if (parentWindowView) {
    parentView = parentWindowView;
  } else if (parentPopupView) {
    parentView = parentPopupView;
  }

  if (!parentView) {
    WWNLog("BRIDGE",
           @"Warning: Popup parent %llu not found, using first window",
           event->parent_id);
    parentView = [_windows allValues].firstObject;
  }

  if (!parentView) {
    WWNLog("BRIDGE", @"Error: No parent view available for popup %llu",
           event->window_id);
    return;
  }

  // Create popup view as subview of parent; clamp to containerView bounds (iOS
  // kiosk)
  CGRect containerBounds =
      self.containerView ? self.containerView.bounds : parentView.bounds;
  CGFloat x = (CGFloat)event->x;
  CGFloat y = (CGFloat)event->y;
  CGFloat w = (CGFloat)event->width;
  CGFloat h = (CGFloat)event->height;
  x = fmax(0, fmin(x, containerBounds.size.width - w));
  y = fmax(0, fmin(y, containerBounds.size.height - h));
  CGRect popupFrame = CGRectMake(x, y, w, h);
  WWNCompositorView_ios *popupView =
      [[WWNCompositorView_ios alloc] initWithFrame:popupFrame];
  popupView.wwnWindowId = event->window_id;
  // Keep a single input owner (the root compositor view) so touchpad cursor
  // state and virtual cursor rendering do not split across parent/popup views.
  popupView.userInteractionEnabled = NO;
  popupView.backgroundColor = UIColor.clearColor;
  popupView.clipsToBounds = NO;
  [popupView setWaylandFrameOpaque:NO];

  // Add popup above all other content
  // If parent is a WWNCompositorView_ios, add as subview of that parent
  // This ensures proper relative positioning
  [parentView addSubview:popupView];

  [_popups setObject:popupView forKey:@(event->window_id)];
  [_windows setObject:popupView forKey:@(event->window_id)];

  WWNLog("BRIDGE",
         @"iOS popup %llu added as subview of parent (frame: "
         @"%.0f,%.0f %.0fx%.0f)",
         event->window_id, popupFrame.origin.x, popupFrame.origin.y,
         popupFrame.size.width, popupFrame.size.height);

  // Send keyboard enter to popup so it can receive input
  uint64_t windowId = event->window_id;
  [self injectKeyboardEnterForWindow:windowId keys:@[]];
}

- (void)handlePopupRepositioned:(CWindowEvent *)event {
  UIView *popupView = (UIView *)[_popups objectForKey:@(event->window_id)];
  if (!popupView) {
    WWNLog("BRIDGE", @"Warning: PopupRepositioned for unknown popup %llu",
           event->window_id);
    return;
  }

  // Clamp to container bounds (iOS kiosk)
  CGRect containerBounds = self.containerView ? self.containerView.bounds
                                              : popupView.superview.bounds;
  CGFloat x = (CGFloat)event->x;
  CGFloat y = (CGFloat)event->y;
  CGFloat w = (CGFloat)event->width;
  CGFloat h = (CGFloat)event->height;
  x = fmax(0, fmin(x, containerBounds.size.width - w));
  y = fmax(0, fmin(y, containerBounds.size.height - h));
  CGRect newFrame = CGRectMake(x, y, w, h);
  popupView.frame = newFrame;

  WWNLog("BRIDGE", @"iOS popup %llu repositioned to (%.0f,%.0f %.0fx%.0f)",
         event->window_id, newFrame.origin.x, newFrame.origin.y,
         newFrame.size.width, newFrame.size.height);
}

- (void)handlePopupDismissed:(uint64_t)windowId {
  WWNLog("BRIDGE", @"iOS popup dismissed: %llu", windowId);
  UIView *popupView = (UIView *)[_popups objectForKey:@(windowId)];
  if (popupView) {
    [popupView removeFromSuperview];
    [_popups removeObjectForKey:@(windowId)];
    [_windows removeObjectForKey:@(windowId)];
  }
  if (_rustCore) {
    [self _dispatchToRust:^{
      WWNCoreNotifyPopupDismissed(self->_rustCore, windowId);
    }];
  }
}
#endif

// MARK: - Buffer updates

- (nullable CBufferData *)popPendingBuffer {
  if (!_rustCore) {
    return NULL;
  }
  return WWNCorePopPendingBuffer(_rustCore);
}

- (void)freeBufferData:(CBufferData *)data {
  WWNBufferDataFree(data);
}

@end

#if TARGET_OS_IPHONE
void wwn_ios_pump_host_compositor(void) {
  [[WWNCompositorBridge sharedBridge] pumpHostCompositorEvents];
}
#endif
