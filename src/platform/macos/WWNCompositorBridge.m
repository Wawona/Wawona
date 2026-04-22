//  WWNCompositorBridge.m
//  Direct C API - calling plain C exports from Rust

#import "WWNCompositorBridge.h"
#if !TARGET_OS_IPHONE
#import "WWNPopupWindow.h"
#endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import "WWNCompositorView_ios.h"
#import "WWNPopupHost.h"
#endif
#import "../../util/WWNLog.h"
#import "WWNPlatformCallbacks.h"
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
#include <string.h> // For strdup

static BOOL WWNForceSSDEnabled(void) {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:@"ForceServerSideDecorations"];
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
static BOOL WWNEnablePerWindowHostingOnIPad(void) {
  if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
    return NO;
  }
  NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
  return version.majorVersion >= 26;
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
extern void WWNCoreFree(void *core);
extern void WWNCoreInjectWindowResize(void *core, uint64_t window_id,
                                      uint32_t width, uint32_t height);
extern bool WWNCoreRequestWindowClose(void *core, uint64_t window_id);
extern bool WWNCoreForceDestroyHostWindow(void *core, uint64_t window_id);
extern void WWNCoreSetWindowActivated(void *core, uint64_t window_id,
                                      bool active);
extern void WWNCoreSetWindowActivatedSilent(void *core, uint64_t window_id,
                                            bool active);
extern void WWNCoreFlushClients(void *core);
extern void WWNCoreSetForceSSD(void *core, bool enabled);
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
extern void WWNCoreTextInputGetCursorRect(void *core, int32_t *out_x,
                                          int32_t *out_y, int32_t *out_width,
                                          int32_t *out_height);
extern CBufferData *WWNCorePopPendingBuffer(void *core);
extern void WWNBufferDataFree(CBufferData *data);
extern IOSurfaceRef IOSurfaceLookup(uint32_t csid);

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

// Coalesce AppKit live-resize bursts before emitting Wayland configure events.
// Slightly slower cadence reduces nested-compositor configure thrash on macOS.
static const NSTimeInterval kWWNResizeDebounceSeconds = 0.040;

@implementation WWNCompositorBridge {
  void *_rustCore;
  NSTimer *_eventTimer;
  CADisplayLink *_displayLink;

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

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSMutableDictionary<NSNumber *, id> *_windows;
  NSMutableDictionary<NSNumber *, id> *_popups;
  NSMutableDictionary<NSNumber *, UIWindow *> *_iosHostWindows;
  BOOL _iosPerWindowHostingEnabled;
#else
  NSMutableDictionary<NSNumber *, id>
      *_windows; /* WWNWindow or NSWindow (popup) */
  NSMutableDictionary<NSNumber *, id<WWNPopupHost>> *_popups;
#endif
  // Scene Graph caches
  NSMutableDictionary<id<NSCopying>, id> *_bufferCache;
  NSMutableDictionary<NSNumber *, CALayer *> *_surfaceLayers;
  NSMutableDictionary<NSNumber *, NSNumber *> *_latestBufferBySurface;
  NSMutableDictionary<NSNumber *, NSNumber *> *_lastPresentedBufferBySurface;
  NSMutableDictionary<NSNumber *, NSNumber *> *_staleSceneSelectionsBySurface;
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  NSMutableDictionary<NSNumber *, NSString *> *_windowOwnerMachineIdByWindowId;
#endif

  // Per-window resize coalescing.  Each window gets its own "latest"
  // dimensions so concurrent resizes of different windows never collide.
  // Key = window_id (NSNumber wrapping uint64_t).
  NSMutableDictionary<NSNumber *, NSValue *> *_latestResizeDims;
  NSMutableDictionary<NSNumber *, NSValue *> *_sentResizeDims;
  NSMutableSet<NSNumber *> *_resizeInFlightWindows;

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

    WWNLog("BRIDGE", @"WWNCore created successfully via C API!");
    _windows = [NSMutableDictionary dictionary];
    _popups = [NSMutableDictionary dictionary];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    _iosHostWindows = [NSMutableDictionary dictionary];
    _iosPerWindowHostingEnabled = WWNEnablePerWindowHostingOnIPad();
    WWNLog("BRIDGE", @"iOS per-window hosting %@", _iosPerWindowHostingEnabled ? @"enabled" : @"disabled");
#endif
    _bufferCache = [NSMutableDictionary dictionary];
    _surfaceLayers = [NSMutableDictionary dictionary];
    _latestBufferBySurface = [NSMutableDictionary dictionary];
    _lastPresentedBufferBySurface = [NSMutableDictionary dictionary];
    _staleSceneSelectionsBySurface = [NSMutableDictionary dictionary];
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    _windowOwnerMachineIdByWindowId = [NSMutableDictionary dictionary];
#endif
    _latestResizeDims = [NSMutableDictionary dictionary];
    _sentResizeDims = [NSMutableDictionary dictionary];
    _resizeInFlightWindows = [NSMutableSet set];
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
  // On iOS, use NSTemporaryDirectory() (sandboxed).
  NSString *runtimeDir;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#if TARGET_OS_SIMULATOR
  // Simulator: use a short path to stay within the 104-byte Unix socket
  // sun_path limit.  NSTemporaryDirectory() on the simulator maps to the
  // host's CoreSimulator container which can be 150+ chars.
  runtimeDir =
      [NSString stringWithFormat:@"/tmp/wawona_sim_%u", (unsigned)getuid()];
#else
  // Device: NSTemporaryDirectory()/w — matches WWNPreferredSharedRuntimeDir()
  // in WWNPreferencesManager.m so the waypipe runner finds the socket.
  runtimeDir = NSTemporaryDirectory();
  if (!runtimeDir) {
    runtimeDir = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp"];
  }
  runtimeDir = [runtimeDir stringByAppendingPathComponent:@"w"];
#endif
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
    // macOS: NSTimer at ~60fps for frame pacing
    // (CADisplayLink.displayLinkWithTarget:selector: is unavailable on macOS;
    //  CVDisplayLink is the macOS alternative but adds complexity.
    //  NSTimer at 60fps is sufficient for the compositor event loop.)
    _eventTimer =
        [NSTimer scheduledTimerWithTimeInterval:0.016
                                         target:self
                                       selector:@selector(onTimerTick:)
                                       userInfo:nil
                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_eventTimer forMode:NSRunLoopCommonModes];
    WWNLog("BRIDGE", @"Using NSTimer for frame pacing (60fps)");
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
#endif

  // 2. Drain the compositor queue: wait for any in-flight tick to finish,
  //    then stop the Rust compositor.  dispatch_sync is safe here because
  //    the in-flight tick only uses dispatch_async to bounce back to main
  //    (no deadlock — the async block will simply run after we return).
  if (_rustCore && _compositorQueue) {
    dispatch_sync(_compositorQueue, ^{
      WWNCoreStop(self->_rustCore);
      self->_rustCore = NULL;
      WWNLog("BRIDGE", @"Compositor stopped on compositor queue");
    });
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
      [window orderOut:nil]; // Hide window
      [window close];        // Close window
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
    bool processed = WWNCoreProcessEvents(self->_rustCore);
    if (!processed) {
      WWNLog("TICK",
             @"Skipping compositor tick after non-fatal event-loop failure");
      dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store(&self->_compositorBusy, false);
      });
      return;
    }

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
      WWNLog("TICK",
             @"Popped buffer: win=%llu surf=%u buf=%llu %ux%u pixels=%p "
             @"iosurface=%u",
             buffer->window_id, buffer->surface_id, buffer->buffer_id,
             buffer->width, buffer->height, buffer->pixels,
             buffer->iosurface_id);
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

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
      // WWNView uses NSViewLayerContentsRedrawNever; AppKit only picks up
      // child CALayer.contents updates when the view is marked dirty.
      if (presentedBuffers.count > 0) {
        [self _invalidateMacSurfaceHostViews];
      }
#endif

      // Acknowledge wl_surface.frame/buffer release only after scene/layer
      // updates have consumed this tick's buffers.
      if (presentedBuffers.count > 0 && self->_rustCore) {
        uint32_t ts =
            (uint32_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
        for (NSValue *val in presentedBuffers) {
          WWNPresentedBuffer presented = {0};
          [val getValue:&presented];
          [self notifyFramePresentedForSurface:presented.surface_id
                                        buffer:presented.buffer_id
                                     timestamp:ts];
        }
        WWNCoreFlushClients(self->_rustCore);
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
  [self _compositorTick];
}

/// macOS: NSTimer fallback (pre-macOS 14)
- (void)onTimerTick:(NSTimer *)timer {
  [self _compositorTick];
}

// MARK: - Rendering

- (void)processPendingBuffers {
  if (!_rustCore) {
    return;
  }

  CBufferData *buffer;
  while ((buffer = WWNCorePopPendingBuffer(_rustCore)) != NULL) {
    [self cacheBuffer:buffer];

    // Notify Rust immediately (legacy behavior, can be refined with FrameClock)
    uint32_t ts = (uint32_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
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
      WWNLog("CACHE", @"Cached IOSurface buf=%llu", buffer->buffer_id);
    } else {
      WWNLog("CACHE", @"FAILED IOSurface lookup for buf=%llu iosurface=%u",
             buffer->buffer_id, buffer->iosurface_id);
    }
    return;
  }

  // 2. SHM (Software)
  if (buffer->pixels) {
    CFDataRef pixelData =
        CFDataCreate(NULL, buffer->pixels, (CFIndex)buffer->size);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(pixelData);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo =
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;

    CGImageRef image = CGImageCreate(
        buffer->width, buffer->height, 8, 32, buffer->stride, colorSpace,
        bitmapInfo, provider, NULL, false, kCGRenderingIntentDefault);

    if (image) {
      _bufferCache[cacheKey] = (__bridge_transfer id)image;
      WWNLog("CACHE", @"Cached SHM CGImage buf=%llu %ux%u stride=%u",
             buffer->buffer_id, buffer->width, buffer->height, buffer->stride);
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

- (void)updateLayerForNode:(CRenderNode *)node {
  NSNumber *winId = @(node->window_id);
  NSNumber *surfId = @(node->surface_id);

  // 1. Find or Create Layer
  CALayer *layer = _surfaceLayers[surfId];
  if (!layer) {
    layer = [CALayer layer];
    layer.contentsScale = node->scale;
    layer.contentsGravity = kCAGravityResize;
    _surfaceLayers[surfId] = layer;

    // Attach to window hierarchy (toplevels and popups both in _windows)
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    id host = _windows[winId];
    if (!host) {
      id<WWNPopupHost> popup = _popups[winId];
      host = popup.contentView;
    } else if ([host isKindOfClass:[NSWindow class]]) {
      host = [(NSWindow *)host contentView];
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
      [((WWNCompositorView_ios *)hostView).contentLayer addSublayer:layer];
      WWNLog("RENDER",
             @"Created layer for surf=%@ → attached to win=%@ contentLayer",
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
  if (node->buffer_id != 0) {
    id w = _windows[winId];
    if (w && [w isKindOfClass:[NSWindow class]]) {
      NSWindow *window = (NSWindow *)w;
      if (![window isVisible] && ![window isMiniaturized]) {
        [window makeKeyAndOrderFront:nil];
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
  float scaleDiff = layer.contentsScale - node->scale;
  if (scaleDiff < 0.0f) {
    scaleDiff = -scaleDiff;
  }
  if (scaleDiff > 0.001f) {
    layer.contentsScale = node->scale;
  }
  float localX = node->x - node->anchor_output_x;
  float localY = node->y - node->anchor_output_y;
  // Use explicit frame assignment to avoid subpixel position/bounds drift that
  // can leave thin gutters at content-view edges.
  layer.frame = CGRectMake(localX, localY, node->width, node->height);
  layer.contentsScale = MAX(1.0, node->scale);
  layer.opacity = node->opacity;
  layer.cornerRadius = node->corner_radius;

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
    // Clear first so Core Animation cannot skip an update when the same
    // buffer id is re-used with new SHM pixels (new CGImage, same key).
    layer.contents = nil;
    layer.contents = content;
  }

  [CATransaction commit];
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
  CGBitmapInfo bmpInfo =
      kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
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
extern void WWNCoreInjectTouchUp(void *core, int32_t id, uint32_t timestamp);
extern void WWNCoreInjectTouchMotion(void *core, int32_t id, double x, double y,
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
  [self _dispatchToRust:^{
    WWNCoreInjectTouchDown(self->_rustCore, (int32_t)touchId, x, y,
                           timestampMs);
  }];
}

- (void)injectTouchUp:(NSInteger)touchId timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInjectTouchUp(self->_rustCore, (int32_t)touchId, timestampMs);
  }];
}

- (void)injectTouchMotion:(NSInteger)touchId
                        x:(double)x
                        y:(double)y
                timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInjectTouchMotion(self->_rustCore, (int32_t)touchId, x, y,
                             timestampMs);
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
  [self _dispatchToRust:^{
    WWNCoreInjectPointerMotion(self->_rustCore, windowId, x, y, timestampMs);
  }];
}

- (void)injectPointerEnterForWindow:(uint64_t)windowId
                                  x:(double)x
                                  y:(double)y
                          timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
  [self _dispatchToRust:^{
    WWNCoreInjectPointerEnter(self->_rustCore, windowId, x, y, timestampMs);
  }];
}

- (void)injectPointerLeaveForWindow:(uint64_t)windowId
                          timestamp:(uint32_t)timestampMs {
  if (!_rustCore) {
    return;
  }
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
  uint32_t state = pressed ? 1 : 0;
  [self _dispatchToRust:^{
    WWNCoreInjectPointerButton(self->_rustCore, windowId, button, state,
                               timestampMs);
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
  [self _dispatchToRust:^{
    WWNCoreInjectPointerAxis(self->_rustCore, windowId, axis, value,
                             timestampMs);
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
  CGSize dims = CGSizeMake(width, height);
  _latestResizeDims[key] = [NSValue value:&dims withObjCType:@encode(CGSize)];
  NSTimeInterval debounce = kWWNResizeDebounceSeconds;
  NSWindow *window = [self.windows objectForKey:key];
  if ([window isKindOfClass:[WWNWindow class]] &&
      ((WWNWindow *)window).inLiveResize) {
    // During edge drag, dispatch immediately so Wayland configure cadence tracks
    // AppKit's live size changes instead of waiting for debounce expiry.
    debounce = 0.0;
  }
  WWNLog("BRIDGE",
         @"Queue injectWindowResize window=%llu latest=%.0fx%.0f debounce=%.3fs live=%@",
         windowId, dims.width, dims.height, debounce,
         debounce == 0.0 ? @"yes" : @"no");
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(_drainPendingWindowResizeForId:)
                                             object:key];
  // Schedule on common + tracking modes so live edge-drag (NSEventTrackingRunLoopMode)
  // continues delivering synchronized configure events while the mouse is down.
  [self performSelector:@selector(_drainPendingWindowResizeForId:)
             withObject:key
             afterDelay:debounce
                inModes:@[ NSRunLoopCommonModes, NSEventTrackingRunLoopMode ]];
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

/// Same coalescing pattern as window resize — at most one output-resize
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
    WWNCoreNotifyFramePresented(_rustCore, surfaceId, bufferId, timestamp);
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
  uint8_t edges;            // xdg_toplevel resize_edge
  uint8_t padding;
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
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [self handleDecorationModeChanged:event];
#endif
    break;
  case CWindowEventTypeMinimizeRequested:
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [self handleWindowMinimizeRequested:event];
#endif
    break;
  case CWindowEventTypeMaximizeRequested:
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [self handleWindowMaximizeRequested:event];
#endif
    break;
  case CWindowEventTypeUnmaximizeRequested:
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [self handleWindowUnmaximizeRequested:event];
#endif
    break;
  case CWindowEventTypeCursorShapeChanged:
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [self handleCursorShapeChanged:event];
#endif
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
         @"fullscreen_shell=%u",
         event->window_id, event->width, event->height, event->decoration_mode,
         event->fullscreen_shell);

  BOOL shouldInjectResize = NO;
  BOOL shouldUpdateOutput = NO; // Whether wl_output.mode must also change.

  BOOL forceSSD = WWNForceSSDEnabled();
  BOOL useServerDecorations = forceSSD || event->decoration_mode == 1;

  NSRect contentRect;
  if (event->fullscreen_shell) {
    // Fullscreen-shell surfaces fill the output at whatever size the output
    // reports.  When Force SSD is active the NSWindow gets a native macOS
    // titlebar, which consumes height from the content area and shrinks the
    // drawable region below the output dimensions Weston expects.
    //
    // We must inject a resize after window creation so that:
    //   • wl_output.mode is updated to the actual content area (not the
    //     full output including the titlebar region), and
    //   • the fullscreen_shell surface receives a configure at the correct
    //     drawable size.
    //
    // Without this, Weston renders its desktop shell at the full output size
    // and the bottom strip is clipped/hidden behind the window chrome.
    contentRect = NSMakeRect(100, 100, event->width, event->height);
    if (useServerDecorations) {
      // Force SSD: titlebar will eat into the content rect after window init.
      shouldInjectResize = YES;
      shouldUpdateOutput = YES;
    }
  } else {
    contentRect = NSMakeRect(100, 100, event->width, event->height);
    // For SSD windows the actual content area must be communicated back
    // to the Rust compositor so wl_output stays in sync.  Nested
    // compositors like Weston rely on wl_output.mode matching the
    // content area.
    if (useServerDecorations) {
      shouldInjectResize = YES;
    }
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

  [window center];
  // Deferred: Window remains hidden until a buffer is attached (xdg-shell
  // semantics)

  [_windows setObject:window forKey:@(event->window_id)];
  NSString *ownerMachineId = [WWNMachineProfileStore activeMachineId];
  if (ownerMachineId.length > 0) {
    _windowOwnerMachineIdByWindowId[@(event->window_id)] = ownerMachineId;
  }
  WWNLog("BRIDGE", @"Created window %llu: %@ (total windows: %lu)",
         event->window_id, title, (unsigned long)[_windows count]);

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
      float s = _latestOutputScale > 0 ? _latestOutputScale : 1.0f;
      [self _dispatchToRust:^{
        WWNCoreSetOutputGeometryForWindow(self->_rustCore, wid, ow, oh, s);
      }];
    }

    [self injectWindowResize:event->window_id
                       width:(uint32_t)MAX(1, lround(contentSize.width))
                      height:(uint32_t)MAX(1, lround(contentSize.height))];
  }
}

- (void)handleWindowMoveRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowMoveRequested: id=%llu", event->window_id);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window)
    return;
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

- (void)handleDecorationModeChanged:(CWindowEvent *)event {
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window || ![window isKindOfClass:[WWNWindow class]])
    return;
  BOOL forceSSD = WWNForceSSDEnabled();
  BOOL useServerDecorations = forceSSD || event->decoration_mode == 1;
  NSWindowStyleMask styleMask;
  if (useServerDecorations) {
    styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
  } else {
    styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable |
                NSWindowStyleMaskMiniaturizable;
  }
  [window setStyleMask:styleMask];

  // After changing the style mask the content area may have shrunk (e.g. a
  // titlebar was added for SSD mode).  Inject the new content-area size
  // immediately so the Rust compositor state is correct before
  // reconfigure_window_decorations sends an xdg_toplevel.configure to the
  // client.  Without this, nested compositors receive the pre-titlebar
  // dimensions and render at the wrong size.
  NSSize contentSize = WWNWaylandContentSizeForWindow(window);
  if (contentSize.width > 0 && contentSize.height > 0) {
    WWNLog("BRIDGE",
           @"Decoration mode changed for window %llu: %s (force_ssd=%d) — injecting "
           @"content resize %.0fx%.0f",
           event->window_id,
           useServerDecorations ? "ServerSide" : "ClientSide", forceSSD,
           contentSize.width, contentSize.height);
    [self injectWindowResize:event->window_id
                       width:(uint32_t)contentSize.width
                      height:(uint32_t)contentSize.height];
  } else {
    WWNLog("BRIDGE", @"Decoration mode changed for window %llu: %s (force_ssd=%d)",
           event->window_id,
           useServerDecorations ? "ServerSide" : "ClientSide", forceSSD);
  }
}

- (void)handleWindowResizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowResizeRequested: id=%llu edges=%u",
         event->window_id, event->edges);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (!window)
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
  window.interactiveResizeInProgress = YES;

  // Track the mouse and resize the window according to the requested edge
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
                      }];
  window.interactiveResizeInProgress = NO;
#endif
}

- (void)handleWindowMinimizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowMinimizeRequested: id=%llu", event->window_id);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (window) {
    [window miniaturize:nil];
  }
#endif
}

- (void)handleWindowMaximizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowMaximizeRequested: id=%llu", event->window_id);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (window) {
    if (![window isZoomed]) {
      window.processingResize = YES;
      [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [window zoom:nil];
      }
          completionHandler:^{
            window.processingResize = NO;
            NSNotification *note = [NSNotification
                notificationWithName:NSWindowDidResizeNotification
                              object:window];
            [window windowDidResize:note];
          }];
    }
  }
#endif
}

- (void)handleWindowUnmaximizeRequested:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"handleWindowUnmaximizeRequested: id=%llu",
         event->window_id);
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  WWNWindow *window = _windows[@(event->window_id)];
  if (window) {
    if ([window isZoomed]) {
      window.processingResize = YES;
      [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [window zoom:nil];
      }
          completionHandler:^{
            window.processingResize = NO;
            NSNotification *note = [NSNotification
                notificationWithName:NSWindowDidResizeNotification
                              object:window];
            [window windowDidResize:note];
          }];
    }
  }
#endif
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (void)handleCursorShapeChanged:(CWindowEvent *)event {
  if (_windows.count == 0)
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
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIView *view = [_windows objectForKey:@(event->window_id)];
  if (view) {
    [view removeFromSuperview];
    [_windows removeObjectForKey:@(event->window_id)];
    WWNLog("BRIDGE", @"Removed iOS view for window %llu", event->window_id);
  }
#else
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
      [NSObject cancelPreviousPerformRequestsWithTarget:self
                                               selector:@selector(_drainPendingWindowResizeForId:)
                                                 object:@(event->window_id)];

      // Avoid NSWindow close-time delegate/first-responder cascades when the
      // Wayland client has already been torn down. Hiding + detaching keeps
      // host alive without touching potentially invalid compositor state.
      [window setDelegate:nil];
      [window orderOut:nil];
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
    [_staleSceneSelectionsBySurface removeAllObjects];
    [[NSCursor arrowCursor] set];
  }
#endif

  id<WWNPopupHost> popup = [_popups objectForKey:@(event->window_id)];
  if (popup) {
    [popup dismiss];
    [_popups removeObjectForKey:@(event->window_id)];
    [_windows removeObjectForKey:@(event->window_id)];
    [_latestResizeDims removeObjectForKey:@(event->window_id)];
    [_sentResizeDims removeObjectForKey:@(event->window_id)];
    [_resizeInFlightWindows removeObject:@(event->window_id)];
    WWNLog("BRIDGE", @"Destroyed popup %llu", event->window_id);
  }
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
  } else {
    WWNLog("BRIDGE",
           @"Warning: handleWindowTitleChanged for unknown window %llu",
           event->window_id);
  }
}

- (void)handleWindowSizeChanged:(CWindowEvent *)event {
  WWNWindow *window = [self.windows objectForKey:@(event->window_id)];
  if (window) {
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
    // Guard against untracked client-driven resize oscillation.
    // If size change is not tied to a known configure/transaction, treat it
    // as non-authoritative and never drive AppKit sizing from it.
    //
    // Nested compositors (e.g. Weston + weston-simple-shm) can oscillate
    // between transient client sizes (e.g. 250x250 vs 1024x768) without an
    // active host resize transaction. Applying those updates on host reopens
    // resize ping-pong loops and visible flashing.
    if (event->size_cause == 2 && event->configure_serial == 0 &&
        event->transaction_id == 0) {
      CGFloat deltaW = fabs(contentSize.width - (CGFloat)event->width);
      CGFloat deltaH = fabs(contentSize.height - (CGFloat)event->height);
      WWNLog("BRIDGE",
             @"Ignoring untracked ClientCommit SizeChanged window=%llu "
             @"event=%ux%u current=%.0fx%.0f delta=%.0fx%.0f",
             event->window_id, event->width, event->height, contentSize.width,
             contentSize.height, deltaW, deltaH);
      return;
    }
    if (contentSize.width != event->width ||
        contentSize.height != event->height) {
      CGFloat deltaW = fabs(contentSize.width - (CGFloat)event->width);
      CGFloat deltaH = fabs(contentSize.height - (CGFloat)event->height);
      WWNLog(
          "BRIDGE",
          @"Applying SizeChanged window=%llu event=%ux%u current=%.0fx%.0f "
          @"delta=%.0fx%.0f cause=%@ kind=%@ serial=%u txn=%llu",
          event->window_id, event->width, event->height, contentSize.width,
          contentSize.height, deltaW, deltaH,
          WWNSizeCauseString(event->size_cause),
          WWNSizeKindString(event->size_kind), event->configure_serial,
          event->transaction_id);

      window.processingResize = YES;
      NSRect frame =
          [window frameRectForContentRect:NSMakeRect(0, 0, event->width,
                                                     event->height)];
      frame.origin = window.frame.origin; // Keep origin
      // Avoid visible one-frame flash when applying final size correction.
      [window setFrame:frame display:NO];
      window.processingResize = NO;
    } else {
      WWNLog("BRIDGE",
             @"Ignoring SizeChanged window=%llu event=%ux%u (already applied) "
             @"cause=%@ kind=%@ serial=%u txn=%llu",
             event->window_id, event->width, event->height,
             WWNSizeCauseString(event->size_cause),
             WWNSizeKindString(event->size_kind), event->configure_serial,
             event->transaction_id);
    }
  }
}

- (void)handlePopupCreated:(CWindowEvent *)event {
  NSView *parentView = nil;
  NSWindow *parentWindow = [self.windows objectForKey:@(event->parent_id)];

  WWNLog("BRIDGE",
         @"Popup create request: surface %u, window %llu, parent %llu",
         event->surface_id, event->window_id, event->parent_id);

  if (parentWindow) {
    WWNLog("BRIDGE", @"Found parent as Window: %p", parentWindow);
    parentView = parentWindow.contentView;
  } else {
    id<WWNPopupHost> parentPopup = [_popups objectForKey:@(event->parent_id)];
    if (parentPopup) {
      WWNLog("BRIDGE", @"Found parent as Popup: %p", parentPopup);
      parentView = parentPopup.contentView;
    } else {
      WWNLog("BRIDGE", @"Parent %llu NOT found in windows or popups",
             event->parent_id);
    }
  }

  if (!parentView) {
    WWNLog("BRIDGE",
           @"Warning: Popup created for unknown parent %llu, falling "
           @"back to key "
           @"window",
           event->parent_id);
    parentWindow = [NSApp keyWindow];
    parentView = parentWindow.contentView;
  }

  if (parentView) {
    WWNLog("BRIDGE",
           @"Creating popup (NSWindow) for surface %u (window %llu) "
           @"anchored to parent %llu at %d,%d (%ux%u)",
           event->surface_id, event->window_id, event->parent_id, event->x,
           event->y, event->width, event->height);

    id<WWNPopupHost> popup =
        [[WWNPopupWindow alloc] initWithParentView:parentView];

    [popup setContentSize:CGSizeMake(event->width, event->height)];
    [popup setWindowId:event->window_id];

    [_popups setObject:popup forKey:@(event->window_id)];
    _windows[@(event->window_id)] = ((WWNPopupWindow *)popup).window;

    // Handle dismissal
    __unsafe_unretained typeof(self) weakSelf = self;
    popup.onDismiss = ^{
      [weakSelf handlePopupDismissed:event->window_id];
    };

    // Compute screen point for popup top-left (Wayland x,y is parent-relative)
    NSRect windowRect =
        [parentView convertRect:CGRectMake(event->x, event->y, 1, 1)
                         toView:nil];
    NSRect screenRect = [parentView.window convertRectToScreen:windowRect];
    CGPoint topLeft =
        CGPointMake(screenRect.origin.x, screenRect.origin.y - event->height);

    [popup showAtScreenPoint:topLeft];
  }
}

- (void)handlePopupDismissed:(uint64_t)windowId {
  WWNLog("BRIDGE", @"Popup dismissed locally: %llu", windowId);
  [_popups removeObjectForKey:@(windowId)];
  [_windows removeObjectForKey:@(windowId)];
  // TODO: Notify Rust core of dismissal if needed (xdg_popup.popup_done)
}

- (void)handlePopupRepositioned:(CWindowEvent *)event {
  id<WWNPopupHost> popup = [_popups objectForKey:@(event->window_id)];
  if (!popup) {
    WWNLog("BRIDGE", @"Warning: PopupRepositioned for unknown window %llu",
           event->window_id);
    return;
  }

  WWNLog("BRIDGE", @"Repositioning popup %llu to %d,%d (%ux%u)",
         event->window_id, event->x, event->y, event->width, event->height);

  [popup setContentSize:CGSizeMake(event->width, event->height)];

  NSView *parentView = popup.parentView;
  if (!parentView || !parentView.window) {
    WWNLog("BRIDGE", @"Error: Popup %llu has no parent view/window",
           event->window_id);
    return;
  }

  NSRect windowRect =
      [parentView convertRect:CGRectMake(event->x, event->y, 1, 1) toView:nil];
  NSRect screenRect = [parentView.window convertRectToScreen:windowRect];
  CGPoint topLeft =
      CGPointMake(screenRect.origin.x, screenRect.origin.y - event->height);

  [popup showAtScreenPoint:topLeft];
}

#endif // !TARGET_OS_IPHONE

- (NSUInteger)pendingWindowCount {
  if (!_rustCore) {
    return 0;
  }
  return WWNCorePendingWindowCount(_rustCore);
}

- (NSDictionary *)popPendingWindow {
  return nil;
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
    if ([view isKindOfClass:[WWNCompositorView_ios class]]) {
      WWNCompositorView_ios *iosView = (WWNCompositorView_ios *)view;
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
}

- (void)handleWindowCreated:(CWindowEvent *)event {
  WWNLog(
      "BRIDGE", @"iOS handleWindowCreated: id=%llu %ux%u fullscreen_shell=%u",
      event->window_id, event->width, event->height, event->fullscreen_shell);

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

  if (_iosPerWindowHostingEnabled) {
    UIWindowScene *scene = self.containerView.window.windowScene;
    if (!scene) {
      for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:[UIWindowScene class]]) {
          scene = (UIWindowScene *)candidate;
          break;
        }
      }
    }
    if (scene) {
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

  // Activate synchronously BEFORE any layoutSubviews can fire.
  // We use the "silent" variant that sets the activation flag without
  // emitting a configure, then injectWindowResize sends a single
  // configure with both the correct size AND activation state.
  // This avoids the ordering problem where calling them separately
  // produces either a deactivated or 0x0 configure.
  uint64_t windowId = event->window_id;
  WWNLog("BRIDGE", @"Activating new window %llu", windowId);

  // 1. Set activated=true in Rust without sending a configure.
  [self _dispatchToRust:^{
    WWNCoreSetWindowActivatedSilent(self->_rustCore, windowId, true);
  }];

  // 2. Resize sends ONE configure: correct size + Activated state.
  UIView *hostView = view.superview ?: self.containerView;
  CGRect viewFrame = hostView ? hostView.bounds : CGRectMake(0, 0, 800, 600);
  [self injectWindowResize:windowId
                     width:(uint32_t)viewFrame.size.width
                    height:(uint32_t)viewFrame.size.height];

  // 3. Input focus events.
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

  // 5. Make the view first responder (iOS keyboard).
  [view activateKeyboard];
}

- (void)handleWindowDestroyed:(CWindowEvent *)event {
  WWNLog("BRIDGE", @"iOS handleWindowDestroyed: id=%llu", event->window_id);
  UIView *window = [_windows objectForKey:@(event->window_id)];
  if (window) {
    [window removeFromSuperview];
    [_windows removeObjectForKey:@(event->window_id)];
  }
  UIWindow *hostWindow = _iosHostWindows[@(event->window_id)];
  if (hostWindow) {
    hostWindow.hidden = YES;
    hostWindow.rootViewController = nil;
    [_iosHostWindows removeObjectForKey:@(event->window_id)];
  }

  // Also check if it's a popup
  UIView *popup = (UIView *)[_popups objectForKey:@(event->window_id)];
  if (popup) {
    [popup removeFromSuperview];
    [_popups removeObjectForKey:@(event->window_id)];
    WWNLog("BRIDGE", @"iOS popup %llu destroyed", event->window_id);
  }
}

- (void)handleWindowTitleChanged:(CWindowEvent *)event {
  if (!event->title)
    return;
  NSString *newTitle = [NSString stringWithUTF8String:event->title];
  WWNLog("BRIDGE", @"iOS handleWindowTitleChanged: window %llu → '%@'",
         event->window_id, newTitle);

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
  popupView.clipsToBounds = YES;

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
