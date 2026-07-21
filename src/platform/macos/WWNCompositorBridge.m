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
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import "WWNWindow.h"
#import "ui/Machines/WWNMachineProfileStore.h"
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
  return [[WWNPreferencesManager sharedManager] forceServerSideDecorations];
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
extern bool WWNCoreWindowPrefersMacOSSurfaceDrag(const void *core,
                                                 uint64_t window_id);
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

static uint32_t WWNBridgeFrameTimestampMs(void *core) {
  if (core) {
    return WWNCoreGetTimestampMs(core);
  }
  return (uint32_t)(CACurrentMediaTime() * 1000.0);
}

// Marks blocks running on _compositorQueue (reentrancy + pump routing).
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
                 @"Fullscreen exit timed out during teardown — forcing close");
          finishOnce();
        }
      });
  [window toggleFullScreen:nil];
}
#endif

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
  dispatch_queue_t _compositorQueue;

  // Guards against frame pile-up: when YES, a compositor tick is in
  // flight and the next CADisplayLink/NSTimer callback is skipped.
  // Atomic because it is written on _compositorQueue and read on the
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
  // Last polled zwp_text_input_v3 enabled state (host soft-keyboard sync).
  BOOL _lastTextInputEnabled;
  BOOL _lastTextInputEnabledInitialized;
#endif

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSMutableDictionary<NSNumber *, id> *_windows;
  NSMutableDictionary<NSNumber *, id> *_popups;
  NSMutableDictionary<NSNumber *, UIWindow *> *_iosHostWindows;
  NSMutableSet<NSNumber *> *_hostLockedWindowIds;
  BOOL _iosPerWindowHostingEnabled;
#else
  NSMutableDictionary<NSNumber *, id>
      *_windows; /* WWNWindow toplevel or WWNView popup */
  NSMutableDictionary<NSNumber *, id> *_popups;
#endif
  // Scene Graph caches
  NSMutableDictionary<id<NSCopying>, id> *_bufferCache;
  NSMutableDictionary<NSNumber *, CALayer *> *_surfaceLayers;
  NSMutableDictionary<NSNumber *, NSNumber *> *_latestBufferBySurface;
  NSMutableDictionary<NSNumber *, NSNumber *> *_lastPresentedBufferBySurface;
  NSMutableDictionary<NSNumber *, NSNumber *> *_staleSceneSelectionsBySurface;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSMutableDictionary<NSNumber *, NSNumber *> *_presentGenerationBySurface;
  uint64_t _waylandPresentGeneration;
#endif
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  NSMutableDictionary<NSNumber *, NSString *> *_windowOwnerMachineIdByWindowId;
#endif

  // Per-window resize coalescing.  Each window gets its own "latest"
  // dimensions so concurrent resizes of different windows never collide.
  // Key = window_id (NSNumber wrapping uint64_t).
  NSMutableDictionary<NSNumber *, NSValue *> *_latestResizeDims;
  NSMutableDictionary<NSNumber *, NSValue *> *_sentResizeDims;
  NSMutableSet<NSNumber *> *_resizeInFlightWindows;

  // Windows whose AppKit frame has been authoritatively sized at least once
  // (either via an initial injected resize, or the client's first committed
  // buffer). Until a window is in this set, its first ClientCommit size is
  // always trusted — the host defers the initial xdg_toplevel configure to
  // (0, 0), so the client's first commit is its real preferred size for
  // every Wayland client, not just a known allowlist.
  NSMutableSet<NSNumber *> *_windowsWithInitialSizeSynced;

  // Windows already auto-shown after their first presented buffer. The render
  // loop must never re-order-front (or steal key status from) a window on
  // subsequent frames — focus changes come only from explicit activation.
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

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // Saved gamma for restore (nested compositor may not use; main display only)
  CGGammaValue *_savedGammaRed;
  CGGammaValue *_savedGammaGreen;
  CGGammaValue *_savedGammaBlue;
  uint32_t _savedGammaSize;
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
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(
        DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
    _compositorQueue = dispatch_queue_create("com.wawona.compositor", attr);
    dispatch_queue_set_specific(_compositorQueue, kWWNCompositorQueueKey,
                                kWWNCompositorQueueKey, NULL);

    WWNLog("BRIDGE", @"WWNCore created successfully via C API!");
    _windows = [NSMutableDictionary dictionary];
    _popups = [NSMutableDictionary dictionary];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    _iosHostWindows = [NSMutableDictionary dictionary];
    _hostLockedWindowIds = [NSMutableSet set];
    _iosPerWindowHostingEnabled = WWNEnablePerWindowHosting();
    WWNLog("BRIDGE", @"iOS/vision per-window hosting %@", _iosPerWindowHostingEnabled ? @"enabled" : @"disabled");
#endif
    _bufferCache = [NSMutableDictionary dictionary];
    _surfaceLayers = [NSMutableDictionary dictionary];
    _latestBufferBySurface = [NSMutableDictionary dictionary];
    _lastPresentedBufferBySurface = [NSMutableDictionary dictionary];
    _staleSceneSelectionsBySurface = [NSMutableDictionary dictionary];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    _presentGenerationBySurface = [NSMutableDictionary dictionary];
    _waylandPresentGeneration = 0;
#endif
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    _windowOwnerMachineIdByWindowId = [NSMutableDictionary dictionary];
#endif
    _latestResizeDims = [NSMutableDictionary dictionary];
    _sentResizeDims = [NSMutableDictionary dictionary];
    _resizeInFlightWindows = [NSMutableSet set];
    _windowsWithInitialSizeSynced = [NSMutableSet set];
    _windowsAutoShownAfterFirstBuffer = [NSMutableSet set];
    [self setForceSSD:WWNForceSSDEnabled()];
  }
  return self;
}

- (void)dealloc {
  if (_rustCore) {
    WWNCoreFree(_rustCore);
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
  // and XDG_CONFIG_DIRS — never cwd. Without HOME the client gets NULL config
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
  if (_compositorQueue) {
    // Ensure any pre-start configuration enqueued via _dispatchToRust
    // (e.g. setOutputWidth/setForceSSD from main.m) is applied before start.
    dispatch_sync(_compositorQueue, ^{
      success = WWNCoreStart(self->_rustCore, name);
    });
  } else {
    success = WWNCoreStart(_rustCore, name);
  }

  if (success) {
    // Export WAYLAND_DISPLAY so child processes and logs can reference it
    NSString *displayName = socketName ?: @"wayland-0";
    setenv("WAYLAND_DISPLAY", [displayName UTF8String], 1);

    char *socketPath = WWNCoreGetSocketPath(_rustCore);
    if (socketPath) {
      WWNLog("BRIDGE", @"Compositor started — socket: %s", socketPath);
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
    // IMPORTANT: use NSDefaultRunLoopMode only — NOT NSRunLoopCommonModes.
    // CommonModes includes NSEventTrackingRunLoopMode, so a 60Hz compositor
    // tick steals the main thread while the user drags the Machines (or any)
    // window titlebar and feels like severe window-move jank. Live client
    // window resize still schedules configure drains in tracking mode via
    // injectWindowResize; frame pacing can wait until the drag ends.
    // Create unscheduled, then add ONLY to default mode (never CommonModes).
    _eventTimer = [NSTimer timerWithTimeInterval:0.016
                                          target:self
                                        selector:@selector(onTimerTick:)
                                        userInfo:nil
                                         repeats:YES];
    _eventTimer.tolerance = 0.004;
    [[NSRunLoop mainRunLoop] addTimer:_eventTimer
                              forMode:NSDefaultRunLoopMode];
    [self _installHostWindowInteractionPause];
    WWNLog("BRIDGE",
           @"Using NSTimer for frame pacing (60fps, default runloop mode)");
#endif

  } else {
    WWNLog("BRIDGE", @"Error: Start failed");
  }

  return success;
}

- (void)stop {
  WWNLog("BRIDGE", @"Stopping compositor bridge...");

  // 1. Stop timers first — no new ticks will be scheduled after this.
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
  //    (no deadlock — the async block will simply run after we return).
  if (_rustCore && _compositorQueue) {
    dispatch_semaphore_t stopSem = dispatch_semaphore_create(0);
    __block bool stopped = false;
    dispatch_async(_compositorQueue, ^{
      if (self->_rustCore) {
        WWNCoreStop(self->_rustCore);
        self->_rustCore = NULL;
        stopped = true;
        WWNLog("BRIDGE", @"Compositor stopped on compositor queue");
      }
      dispatch_semaphore_signal(stopSem);
    });
    dispatch_semaphore_wait(
        stopSem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
    if (!stopped && _rustCore) {
      WWNLog("BRIDGE", @"Compositor stop timed out — forcing teardown");
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
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  [_windowOwnerMachineIdByWindowId removeAllObjects];
#endif
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
    return [self focusClientWindows];
  }

  [NSApp activateIgnoringOtherApps:YES];
  for (NSWindow *window in clientWindows) {
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
#elif TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
#else
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
#endif
#if !TARGET_OS_TV
  NSInteger changeCount = pasteboard.changeCount;

  // A client (e.g. weston-terminal) copied text — push it to the native
  // pasteboard.
  char *clientText = WWNCorePollClipboardText(_rustCore);
  if (clientText) {
    NSString *text = [NSString stringWithUTF8String:clientText];
    WWNStringFree(clientText);
    if (text) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      pasteboard.string = text;
#else
      [pasteboard clearContents];
      [pasteboard setString:text forType:NSPasteboardTypeString];
#endif
      _lastPasteboardChangeCount = pasteboard.changeCount;
      _pasteboardChangeCountInitialized = YES;
      return;
    }
  }

  // Native copy (another app, or the user pasting into a text field outside
  // Wawona) — push it into the compositor so clients can paste it.
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
/// Drive host soft keyboard from Wayland `zwp_text_input_v3` Enable/Disable.
/// Clients (terminals, editors, password fields) Enable when they need input;
/// we Expand the OSK. On Disable we collapse to accessory-only (still toggleable).
- (void)_syncHostKeyboardWithTextInput {
  if (!_rustCore) {
    return;
  }
  BOOL enabled = WWNCoreTextInputIsEnabled(_rustCore) != 0;
  if (_lastTextInputEnabledInitialized && enabled == _lastTextInputEnabled) {
    return;
  }
  _lastTextInputEnabled = enabled;
  _lastTextInputEnabledInitialized = YES;

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

  if (enabled) {
    [focusView applyHostKeyboardForTextInputEnabled:YES];
  } else {
    [focusView applyHostKeyboardForTextInputEnabled:NO];
  }
}
#endif

/// Called from CADisplayLink (iOS) or NSTimer (macOS).  The callback fires
/// on the main thread but we immediately dispatch the heavy Rust work to
/// _compositorQueue, then bounce lightweight UI updates back to main.
- (void)_compositorTick {
  if (!_rustCore || atomic_load(&_compositorBusy)) {
    return;
  }
  atomic_store(&_compositorBusy, true);

  dispatch_async(_compositorQueue, ^{
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
               @"Compositor tick skipped (%lu times) — event loop not ready "
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
    // with updateLayerForNode: reading it — a data race on
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
  });
}

/// Runs on CADisplayLink (vsync-aligned frame callback) — iOS and macOS 14+
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
  (void)note;
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
      _bufferCache[cacheKey] = (__bridge_transfer id)surf;
      WWNPruneBufferCacheForSurface(_bufferCache, buffer->surface_id, cacheKey);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      _waylandPresentGeneration++;
      _presentGenerationBySurface[surfaceId] = @(_waylandPresentGeneration);
#endif
      WWNLog("CACHE", @"Cached IOSurface buf=%llu", buffer->buffer_id);
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
  if ([_hostLockedWindowIds containsObject:winId]) {
    CGRect hostBounds = iosView.superview
                            ? iosView.superview.bounds
                            : (self.containerView ? self.containerView.bounds
                                                  : iosView.bounds);
    frame = CGRectMake(0, 0, hostBounds.size.width, hostBounds.size.height);
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

  // IOSurface fallback: attach to legacy layer tree.
  CALayer *layer = _surfaceLayers[surfId];
  if (!layer) {
    layer = [CALayer layer];
    layer.geometryFlipped = YES;
    layer.opaque = YES;
    layer.contentsGravity = kCAGravityTopLeft;
    _surfaceLayers[surfId] = layer;
    [iosView prepareWaylandLayerSubpresentation];
    [iosView.waylandLayer addSublayer:layer];
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  layer.frame = frame;
  layer.contentsRect = contentRect;
  layer.opacity = node->opacity;
  layer.contents = content;
  [CATransaction commit];
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

  // 2. Update Geometry — use anchor for window-local coords (subsurfaces)
  float localX = node->x - node->anchor_output_x;
  float localY = node->y - node->anchor_output_y;
  // Use explicit frame assignment to avoid subpixel position/bounds drift that
  // can leave thin gutters at content-view edges.
  layer.frame = CGRectMake(localX, localY, node->width, node->height);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // #111: when the scene node tracks the host window and the client buffer
  // still lags (nested niri/weston mid-drag), stretch into the node so the
  // framebuffer does not jump between before/after sizes. Exact 1:1 uses the
  // same Resize gravity once the buffer catches up.
  float bufLogicalW =
      node->scale > 0 ? (float)node->buffer_width / node->scale : node->width;
  float bufLogicalH =
      node->scale > 0 ? (float)node->buffer_height / node->scale : node->height;
  BOOL bufferMatchesNode = node->buffer_width == 0 ||
                           (fabsf(bufLogicalW - node->width) <= 1.0f &&
                            fabsf(bufLogicalH - node->height) <= 1.0f);
  CGFloat backingScale = 0.0;
  id hostWin = _windows[winId] ?: _popups[winId];
  if ([hostWin isKindOfClass:[NSWindow class]]) {
    backingScale = ((NSWindow *)hostWin).backingScaleFactor;
  } else if ([hostWin conformsToProtocol:@protocol(WWNPopupHost)] &&
             [hostWin respondsToSelector:@selector(contentView)]) {
    backingScale = ((NSView *)((id<WWNPopupHost>)hostWin).contentView)
                       .window.backingScaleFactor;
  }
  if (backingScale < 1.0) {
    backingScale = MAX(1.0, node->scale);
  }
  // Always fill the node. Top-left natural-size presentation during lag was
  // the visible before/after flash for nested compositors (#111).
  layer.contentsGravity = kCAGravityResize;
  layer.contentsScale = bufferMatchesNode ? backingScale : MAX(1.0, node->scale);
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
- (void)_dispatchToRust:(dispatch_block_t)block {
  if (_compositorQueue) {
    dispatch_async(_compositorQueue, block);
  } else {
    // Fallback: queue not yet created (should not happen in practice)
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
  (void)windowId;
#endif
}

- (BOOL)requestHostCloseForWindowId:(uint64_t)windowId {
  if (!_rustCore || !_compositorQueue) {
    return NO;
  }
  __block BOOL found = NO;
  dispatch_sync(_compositorQueue, ^{
    found = WWNCoreRequestWindowClose(self->_rustCore, windowId);
  });
  return found;
}

- (NSArray<NSNumber *> *)allHostWindowIds {
  return [_windows.allKeys copy] ?: @[];
}

- (BOOL)requestForceDestroyHostWindowForWindowId:(uint64_t)windowId {
  if (!_rustCore || !_compositorQueue) {
    return NO;
  }
  __block BOOL ok = NO;
  dispatch_sync(_compositorQueue, ^{
    ok = WWNCoreForceDestroyHostWindow(self->_rustCore, windowId);
  });
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
  [self _drainPendingOutputResize];
}

- (void)currentOutputWidth:(uint32_t *)width
                    height:(uint32_t *)height
                     scale:(float *)scale {
  uint32_t w = _sentOutputW ?: _latestOutputW;
  uint32_t h = _sentOutputH ?: _latestOutputH;
  float s = _sentOutputScale > 0 ? _sentOutputScale : _latestOutputScale;
  if (w == 0)
    w = 420;
  if (h == 0)
    h = 912;
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
  if (w == 0)
    w = 420;
  if (h == 0)
    h = 912;
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

#if TARGET_OS_IPHONE
  NSDictionary *userInfo = clientId ? @{@"clientId": clientId} : nil;
  dispatch_sync(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:WWNNativeClientWillLaunchNotification
                      object:nil
                    userInfo:userInfo];
  });
#endif

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
  [[NSNotificationCenter defaultCenter]
      postNotificationName:WWNClientMinimizeRequestedNotification
                    object:self
                  userInfo:@{
                    @"windowId" : windowId,
                  }];
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
                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
  } else {
    styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable |
                NSWindowStyleMaskMiniaturizable;
  }
  // Avoid styleMask thrash (#53): only mutate when the negotiated mode actually
  // changes the host chrome bits.
  BOOL styleNeedsUpdate = (window.styleMask != styleMask);
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
  if (sizeSynced && contentSize.width > 0 && contentSize.height > 0) {
    WWNLog("BRIDGE",
           @"Decoration mode changed for window %llu: %s — injecting "
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
  } else {
    // OWL / xdg-shell: WindowCreated carries 0×0 until the client commits.
    // Use a tiny placeholder and never inject a configure here — injecting
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
  NSWindowStyleMask styleMask;
  if (useServerDecorations) {
    styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
  } else {
    styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable |
                NSWindowStyleMaskMiniaturizable;
  }

  WWNWindow *window =
      [[WWNWindow alloc] initWithContentRect:contentRect
                                   styleMask:styleMask
                                     backing:NSBackingStoreBuffered
                                       defer:NO];

  window.wwnWindowId = event->window_id;
  window.hostLocked = kiosk;

  NSString *title = (event->title && strlen(event->title) > 0)
                        ? [NSString stringWithUTF8String:event->title]
                        : @"";
  [window setTitle:title];

  // Create content view in window-local coordinates.
  // `contentRect` includes screen-space origin; using it directly as an NSView
  // frame can offset the compositor host view and leave visible borders.
  NSRect contentViewRect =
      NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height);
  WWNView *contentView = [[WWNView alloc] initWithFrame:contentViewRect];
  contentView.wantsLayer = YES;
  contentView.layer.backgroundColor = [[NSColor clearColor] CGColor];
  contentView.layer.contentsGravity = kCAGravityResize;
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
      // Per-window wl_output must carry the real backing scale so clients
      // render HiDPI buffers (crisp fonts) instead of 1x CALayer upscales.
      float s = _latestOutputScale > 0 ? _latestOutputScale
                                       : (float)window.backingScaleFactor;
      if (s < 1.0f) {
        s = 1.0f;
      }
      [self _dispatchToRust:^{
        WWNCoreSetOutputGeometryForWindow(self->_rustCore, wid, ow, oh, s);
      }];
    }

    [self injectWindowResize:event->window_id
                       width:(uint32_t)MAX(1, lround(contentSize.width))
                      height:(uint32_t)MAX(1, lround(contentSize.height))];
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

- (void)wwnApplySurfaceDragPolicyForWindow:(WWNWindow *)window {
  if (!window || window.hostLocked || !_rustCore) {
    return;
  }
  BOOL draggable =
      WWNCoreWindowPrefersMacOSSurfaceDrag(_rustCore, window.wwnWindowId);
  window.wwnSurfaceWindowDraggable = draggable;
  [window setMovable:YES];
  if (draggable) {
    [window setMovableByWindowBackground:YES];
  } else {
    [window setMovableByWindowBackground:!window.clientSideDecorated];
  }
}

- (void)handleWindowMoveRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowMoveRequested: id=%llu", event->window_id);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || window.hostLocked)
    return;
  [self wwnApplySurfaceDragPolicyForWindow:window];
  if (window.interactiveResizeInProgress) {
    WWNLog("BRIDGE", @"Ignoring move request during interactive resize: id=%llu",
           event->window_id);
    return;
  }

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
  if (![[WWNPreferencesManager sharedManager] renderMacOSPointer])
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
           @"Client requested cursor management — enabling host cursor rendering");
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

  if (![[WWNPreferencesManager sharedManager] renderMacOSPointer])
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

  CGFloat scale = NSScreen.mainScreen.backingScaleFactor;
  if (scale < 1.0)
    scale = 1.0;
  NSSize size =
      NSMakeSize(scene->cursor_width / scale, scene->cursor_height / scale);
  NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size:size];
  NSPoint hotSpot = NSMakePoint(scene->cursor_hotspot_x / scale,
                                scene->cursor_hotspot_y / scale);
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
                 @"Client disconnected during minimize — closing host window "
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
             @"All windows destroyed — resetting cursor rendering flag");
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
    if (newTitle.length > 0) {
      [[NSProcessInfo processInfo] setProcessName:newTitle];
    }
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
    // OWL rule: every ClientCommit SizeChanged drives host content size
    // (OwlSurface commit → setFrameSize:buffer). Do not ignore "untracked"
    // commits — that left weston-flower/smoke at a giant placeholder while
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
      window.processingResize = NO;
    } else {
      if (firstClientSizeSync) {
        [window center];
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
- (BOOL)launchNestedKmscubeOnPrimaryView {
  for (NSNumber *key in _windows) {
    id w = _windows[key];
    if ([w isKindOfClass:[WWNWindow class]]) {
      WWNView *view = (WWNView *)[(WWNWindow *)w contentView];
      if ([view isKindOfClass:[WWNView class]]) {
        return [view launchNestedKmscube];
      }
    }
  }
  return NO;
}

- (BOOL)prepareIlandMetalPresentationOnPrimaryView {
  for (NSNumber *key in _windows) {
    id w = _windows[key];
    if ([w isKindOfClass:[WWNWindow class]]) {
      WWNView *view = (WWNView *)[(WWNWindow *)w contentView];
      if ([view isKindOfClass:[WWNView class]] &&
          [view prepareIlandMetalPresentation]) {
        return YES;
      }
    }
  }
  return NO;
}
#endif

#endif // !TARGET_OS_IPHONE — close block opened at WWNWaylandContentSizeForWindow

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
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
/// Fill-primary host: max/fullscreen → configure to the active compositor view bounds.
/// Also syncs xdg maximized/fullscreen so clients see the negotiated state.
- (void)_iosInjectFillPrimaryForWindowId:(uint64_t)windowId
                              maximized:(BOOL)maximized
                             fullscreen:(BOOL)fullscreen {
  UIView *host = nil;
  id winObj = _windows[@(windowId)];
  if ([winObj isKindOfClass:[UIView class]]) {
    host = (UIView *)winObj;
  } else if ([self.containerView isKindOfClass:[UIView class]]) {
    host = self.containerView;
  }
  CGSize size = host ? host.bounds.size : CGSizeMake(640, 480);
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

// Shared AppKit + UIKit (must stay outside the macOS-only block above).
- (void)handleWindowMaximizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowMaximizeRequested: id=%llu", event->window_id);
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
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
  [self _iosInjectFillPrimaryForWindowId:event->window_id
                              maximized:NO
                             fullscreen:YES];
#else
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || window.hostLocked)
    return;
  if ((window.styleMask & NSWindowStyleMaskFullScreen) != 0)
    return;
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
  if (_compositorQueue) {
    dispatch_sync(_compositorQueue, pump);
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
  if (_rustCore && _compositorQueue) {
    dispatch_sync(_compositorQueue, ^{
      uint32_t disconnected = WWNCoreDisconnectAllClients(self->_rustCore);
      if (disconnected > 0) {
        WWNLog("BRIDGE", @"Disconnected %u in-process Wayland client(s)",
               disconnected);
      }
      WWNCoreFlushClients(self->_rustCore);
    });
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
  [_surfaceLayers removeAllObjects];
  [_bufferCache removeAllObjects];
  [_latestBufferBySurface removeAllObjects];
  [_presentGenerationBySurface removeAllObjects];
  _waylandPresentGeneration = 0;
}

- (BOOL)launchNestedKmscubeOnPrimaryView {
  for (NSNumber *key in _windows) {
    id view = _windows[key];
    if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
      return [(WWNCompositorView_ios *)view launchNestedKmscube];
    }
  }
  if ([self.containerView isKindOfClass:[WWNCompositorView_ios class]]) {
    return [(WWNCompositorView_ios *)self.containerView launchNestedKmscube];
  }
  return NO;
}

- (BOOL)prepareIlandMetalPresentationOnPrimaryView {
  for (NSNumber *key in _windows) {
    id view = _windows[key];
    if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
      return [(WWNCompositorView_ios *)view prepareIlandMetalPresentation];
    }
  }
  if ([self.containerView isKindOfClass:[WWNCompositorView_ios class]]) {
    return [(WWNCompositorView_ios *)self.containerView prepareIlandMetalPresentation];
  }
  return NO;
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
           @"WARNING: handleWindowCreated id=%llu but containerView is nil — "
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
  view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  if (_iosPerWindowHostingEnabled && !event->host_locked &&
      !event->fullscreen_shell) {
    UIWindowScene *scene = self.containerView.window.windowScene;
    if (!scene) {
      for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:[UIWindowScene class]]) {
          scene = (UIWindowScene *)candidate;
          break;
        }
      }
    }
#if !TARGET_OS_TV
    // Prefer activating an additional UIWindowScene (iPadOS / visionOS matrix).
    if (@available(iOS 17.0, visionOS 1.0, *)) {
      UISceneSessionActivationRequest *request = [UISceneSessionActivationRequest
          requestWithRole:UIWindowSceneSessionRoleApplication];
      [UIApplication.sharedApplication
          activateSceneSessionForRequest:request
                            errorHandler:^(NSError *err) {
                              WWNLog("BRIDGE",
                                     @"Scene activation failed for window %llu: %@",
                                     event->window_id, err);
                            }];
    }
#endif
    if (scene) {
      // Dedicated UIWindow on a scene (new session when activation succeeds).
      UIWindow *hostWindow = [[UIWindow alloc] initWithWindowScene:scene];
      UIViewController *hostController = [[UIViewController alloc] init];
      hostController.view.backgroundColor = UIColor.blackColor;
      hostController.view.frame = hostWindow.bounds;
      hostController.view.autoresizingMask =
          UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      hostWindow.rootViewController = hostController;
      view.frame = hostController.view.bounds;
      [hostController.view addSubview:view];
      hostWindow.hidden = NO;
      [hostWindow makeKeyAndVisible];
      _iosHostWindows[@(event->window_id)] = hostWindow;
      WWNLog("BRIDGE", @"Added window %llu in dedicated host UIWindow (%.0fx%.0f)",
             event->window_id, hostWindow.bounds.size.width, hostWindow.bounds.size.height);
    } else if (self.containerView) {
      [self.containerView insertSubview:view atIndex:0];
      WWNLog("BRIDGE", @"No UIWindowScene found; fell back to container for window %llu",
             event->window_id);
    } else {
      WWNLog("BRIDGE", @"Warning: No containerView/windowScene set, window %llu not visible",
             event->window_id);
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

  // Fullscreen shell (kiosk) windows are display-only surfaces presented
  // behind the primary toplevel.  Activating them would steal keyboard
  // focus from the toplevel, sending a deactivation configure that makes
  // nested compositors like weston exit.  Skip activation entirely.
  if (event->fullscreen_shell) {
    WWNLog("BRIDGE", @"Fullscreen shell window %llu — skipping activation",
           event->window_id);
    return;
  }

  // First native toplevel: activate immediately and skip activateKeyboard
  // (can block the main queue). Do NOT force an output-sized configure —
  // sizing is client-preferred via xdg-shell (0×0 seed); placement centers
  // after the first real client commit (weston-flower/smoke 200×200).
  BOOL firstNativeToplevel = (_windows.count == 1);

  if (event->host_locked || firstNativeToplevel) {
    uint64_t windowId = event->window_id;
    CGRect viewFrame = self.containerView ? self.containerView.bounds
                                          : CGRectMake(0, 0, event->width, event->height);
    uint32_t w = (uint32_t)MAX(1, viewFrame.size.width);
    uint32_t h = (uint32_t)MAX(1, viewFrame.size.height);
    WWNLog("BRIDGE",
           @"%@ window %llu — immediate activate%@ (skip keyboard)",
           event->host_locked ? @"Host-locked" : @"First native toplevel",
           windowId,
           event->host_locked
               ? [NSString stringWithFormat:@" + fill configure %ux%u", w, h]
               : @" (client-preferred size)");
    if (_compositorQueue) {
      dispatch_sync(_compositorQueue, ^{
        WWNCoreSetWindowActivatedSilent(self->_rustCore, windowId, true);
        if (event->host_locked) {
          WWNCoreInjectWindowResize(self->_rustCore, windowId, w, h);
        }
        WWNCoreFlushClients(self->_rustCore);
      });
    } else {
      WWNCoreSetWindowActivatedSilent(_rustCore, windowId, true);
      if (event->host_locked) {
        WWNCoreInjectWindowResize(_rustCore, windowId, w, h);
      }
      WWNCoreFlushClients(_rustCore);
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
      if (_compositorQueue) {
        dispatch_sync(_compositorQueue, ^{
          WWNCoreFlushClients(self->_rustCore);
        });
      } else {
        WWNCoreFlushClients(_rustCore);
      }
      // Soft OSK follows zwp_text_input_v3 Enable (tick sync), not forced here.
#if TARGET_OS_TV
      if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
        [(WWNCompositorView_ios *)view applyHostKeyboardForTextInputEnabled:NO];
      }
#endif
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

  // 2. Input focus events (no injectWindowResize — ClientPreferred sizing).
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

  // 5. Soft keyboard follows zwp_text_input_v3 Enable via
  //    -_syncHostKeyboardWithTextInput (polled each tick). Do not force
  //    OSK open on every window activate — terminals/editors will Enable.
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
    WWNLog("BRIDGE", @"All iOS windows destroyed — cleared presentation caches");
  }
}

- (void)handleWindowTitleChanged:(CWindowEvent *)event {
  if (!event->title)
    return;
  NSString *newTitle = [NSString stringWithUTF8String:event->title];
  WWNLog("BRIDGE", @"iOS handleWindowTitleChanged: window %llu → '%@'",
         event->window_id, newTitle);

  // VoiceOver: keep the compositor surface's accessibility label in sync with
  // the client's window title.
  UIView *clientView = [_windows objectForKey:@(event->window_id)];
  if (clientView && newTitle.length > 0) {
    clientView.accessibilityLabel = newTitle;
    if (clientView.accessibilityIdentifier.length == 0) {
      clientView.accessibilityIdentifier = @"wwn.compositor.surface";
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
}

- (void)handleWindowSizeChanged:(CWindowEvent *)event {
  UIView *window = [_windows objectForKey:@(event->window_id)];
  if (window) {
    UIWindow *hostWindow = _iosHostWindows[@(event->window_id)];
    if (hostWindow && hostWindow.rootViewController) {
      window.frame = hostWindow.rootViewController.view.bounds;
      // Per-window hosting (iPad Stage Manager): honor a client-chosen size
      // by steering the scene's minimum size toward it. iPadOS has no API to
      // set an absolute scene size; the minimum keeps Stage Manager from
      // clipping the client's buffer while the user can still grow the
      // window (host resizes flow back as configures).
      UIWindowScene *scene = hostWindow.windowScene;
      BOOL clientChosen = event->size_cause == 2 /* ClientCommit */;
      if (scene && !event->host_locked && clientChosen && event->width > 0 &&
          event->height > 0) {
        scene.sizeRestrictions.minimumSize =
            CGSizeMake(event->width, event->height);
      }
      return;
    }
    // Always fill the container — the Wayland client is told the output
    // dimensions via wl_output.mode so its buffer already matches.
    // Using the container's bounds ensures edge-to-edge drawing.
    if (self.containerView) {
      window.frame = self.containerView.bounds;
    } else {
      window.frame = CGRectMake(window.frame.origin.x, window.frame.origin.y,
                                event->width, event->height);
    }
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
