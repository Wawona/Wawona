// WWNWatchCompositorBridge.m
// Wayland compositor bridge for watchOS.
//
// Compositor priority:
//   1. WWNMiniWaylandServer (libwayland-server.a compiled via Nix) - pure C,
//      no Rust required; works as soon as the Nix deps are linked.
//   2. libwawona.a Rust backend - used when available (tier-3 Rust target).

#import "WWNWatchCompositorBridge.h"
#import "WWNMiniWaylandServer.h"
#import "WWNWatchShellEnvironment.h"
#import "WWNLog.h"
#import <CoreGraphics/CoreGraphics.h>
#import <pthread.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#include <time.h>

// ── Client entry points ───────────────────────────────────────────────────────
// Provided by -force_load'd static libraries (weston, foot, etc.) built via Nix.
// Weak stubs in WWNWatchStubs.c allow compilation without Nix but should never
// be reached at runtime after a proper `nix run .#xcodegen` build.

extern int weston_simple_shm_main(int argc, char **argv) __attribute__((weak));
extern int weston_compositor_main(int argc, char **argv);
extern volatile sig_atomic_t wwn_weston_compositor_shutdown_requested;
extern int weston_terminal_main(int argc, char **argv) __attribute__((weak));
extern int foot_main(int argc, char **argv) __attribute__((weak));
extern int wwn_weston_is_compat_shim(void) __attribute__((weak));
extern int wwn_weston_terminal_is_compat_shim(void) __attribute__((weak));
extern int wwn_foot_is_compat_shim(void) __attribute__((weak));
extern int niri_main(void) __attribute__((weak));
extern int flower_main(int argc, char **argv) __attribute__((weak));
extern int smoke_main(int argc, char **argv) __attribute__((weak));
extern int clickdot_main(int argc, char **argv) __attribute__((weak));
extern int eventdemo_main(int argc, char **argv) __attribute__((weak));
extern int resizor_main(int argc, char **argv) __attribute__((weak));
extern int cliptest_main(int argc, char **argv) __attribute__((weak));
extern int transformed_main(int argc, char **argv) __attribute__((weak));
extern int stacking_main(int argc, char **argv) __attribute__((weak));
extern int dnd_main(int argc, char **argv) __attribute__((weak));
extern int image_main(int argc, char **argv) __attribute__((weak));
extern int scaler_main(int argc, char **argv) __attribute__((weak));
extern int editor_main(int argc, char **argv) __attribute__((weak));
extern int constraints_main(int argc, char **argv) __attribute__((weak));

// In-process waypipe with libssh2 (statically linked from Rust).
// Weak so the bridge can nil-check before calling.
extern int waypipe_main(int argc, char **argv) __attribute__((weak));

// wawona-pty: clear one-shot shell latch after Stop (weak for incomplete links).
void wwn_pty_ios_allow_new_shell_session(void) __attribute__((weak));
// ── Rust compositor C-API (optional - satisfied by stubs when not linked) ─────

typedef void *WawonaCompositorHandle;

typedef struct {
    uint64_t window_id;
    uint32_t surface_id;
    uint64_t buffer_id;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
    uint8_t * _Nullable pixels;
    size_t size;
    size_t capacity;
    uint32_t iosurface_id;
} WatchCBufferData;

WawonaCompositorHandle wawona_compositor_create(const char *socket_name);
int                    wawona_compositor_dispatch(WawonaCompositorHandle handle);
void                   wawona_compositor_destroy(WawonaCompositorHandle handle);
WatchCBufferData      *wawona_compositor_pop_buffer(WawonaCompositorHandle handle);
void                   wawona_buffer_free(WatchCBufferData *buf);

// ── @interface extensions. MUST appear before any C code that messages the class ──

NSNotificationName const WWNWatchCompositorFrameReadyNotification =
    @"WWNWatchCompositorFrameReadyNotification";

// Instance variable storage
@interface WWNWatchCompositorBridge () {
    WWNMiniWaylandServer   *_miniServer;
    WawonaCompositorHandle  _rustCompositor;
    dispatch_source_t       _displayLink;
    pthread_t               _dispatchThread;
    BOOL                    _dispatchRunning;
    BOOL                    _dispatchThreadValid;
    pthread_t               _clientThread;
    BOOL                    _clientRunning;
    BOOL                    _clientThreadValid;
    BOOL                    _loggedFirstFrame;
    CGImageRef              _latestFrame;
    // Waypipe
    pthread_t               _waypipeThread;
    BOOL                    _waypipeRunning;
    BOOL                    _waypipeThreadValid;
}
// Private method declarations visible to C callbacks defined further below.
- (void)_deliverPixelsCopy:(uint8_t *)pixels
                     width:(uint32_t)width
                    height:(uint32_t)height
                    stride:(uint32_t)stride;
- (void)_waypipeThreadDidExit;
- (BOOL)_isCompatShimEnabledForClient:(const char *)name;
@end

// ── Server dispatch thread ────────────────────────────────────────────────────
// Runs a blocking event loop for WWNMiniWaylandServer so client requests are
// processed as soon as they arrive (not polled at a timer interval).

typedef struct {
    WWNMiniWaylandServer *srv;
    BOOL                 *running;
} DispatchThreadArgs;

static void *dispatchThreadFunc(void *ctx) {
    DispatchThreadArgs *args = (DispatchThreadArgs *)ctx;
    WWNLog("WATCH", @"Dispatch thread started");
    while (*(args->running)) {
        wwn_wls_dispatch(args->srv, 16);
    }
    WWNLog("WATCH", @"Dispatch thread exiting");
    free(args);
    return NULL;
}

// ── Client thread helper ──────────────────────────────────────────────────────
// Runs the selected Wayland client entry point on a background thread.

typedef struct {
    int argc;
    char **argv;
} CompositorThreadArgs;

static void *compositorThreadFunc(void *ctx) {
    CompositorThreadArgs *args = (CompositorThreadArgs *)ctx;
    WWNLog("WATCH", @"weston_compositor_main starting");
    int rc = weston_compositor_main(args->argc, args->argv);
    WWNLog("WATCH", @"weston_compositor_main exited with code %d", rc);
    if (args->argv) {
        for (int i = 0; i < args->argc; i++)
            free(args->argv[i]);
        free(args->argv);
    }
    free(args);
    return NULL;
}

typedef struct {
    int (*entry)(int argc, char **argv);
    const char *name;
    /* Optional owned argv (NULL-terminated). When set, used instead of {name}. */
    int argc;
    char **argv;
} ClientThreadArgs;

static void *clientThreadFunc(void *ctx) {
    ClientThreadArgs *args = (ClientThreadArgs *)ctx;
    char *fallback[] = { (char *)args->name, NULL };
    int argc = args->argv ? args->argc : 1;
    char **argv = args->argv ? args->argv : fallback;

    WWNLog("WATCH", @"Client '%s' starting", args->name);
    int rc = args->entry(argc, argv);
    WWNLog("WATCH", @"Client '%s' exited with code %d", args->name, rc);

    if (args->argv) {
        for (int i = 0; i < args->argc; i++)
            free(args->argv[i]);
        free(args->argv);
    }
    free(args);
    return NULL;
}

// ── CGDataProvider release callback (C function pointer, not a block) ─────────

static void wwn_release_pixel_buffer(void *info, const void *data, size_t size) {
    (void)info; (void)size;
    free((void *)data);
}

// ── Frame delivery from WWNMiniWaylandServer (C callback) ────────────────────
// Called from the compositor dispatch thread each time a buffer is committed.

static void miniServerFrameCallback(const uint8_t *pixels,
                                     uint32_t width,
                                     uint32_t height,
                                     uint32_t stride,
                                     void *userdata)
{
    __unsafe_unretained WWNWatchCompositorBridge *bridge =
        (__bridge WWNWatchCompositorBridge *)userdata;

    size_t size = (size_t)stride * height;
    uint8_t *copy = malloc(size);
    if (!copy) return;
    memcpy(copy, pixels, size);

    [bridge _deliverPixelsCopy:copy width:width height:height stride:stride];
}

// ── WWNWatchCompositorBridge implementation ───────────────────────────────────


static int wwn_watch_niri_entry(int argc, char **argv) {
    (void)argc;
    (void)argv;
    if (!niri_main) {
        return 127;
    }
    return niri_main();
}

@implementation WWNWatchCompositorBridge

// MARK: - Singleton

+ (instancetype)sharedBridge {
    static WWNWatchCompositorBridge *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _outputWidth  = 184;
        _outputHeight = 224;
        _isRunning    = NO;
        _dispatchRunning = NO;
        _dispatchThreadValid = NO;
        _clientRunning = NO;
        _clientThreadValid = NO;
        _loggedFirstFrame = NO;
        _waypipeRunning = NO;
        _waypipeThreadValid = NO;
        _latestFrame  = NULL;
        _miniServer   = NULL;
        _rustCompositor = NULL;
    }
    return self;
}

// MARK: - Lifecycle

- (BOOL)startWithSocketName:(nullable NSString *)socketName {
    if (_isRunning) return YES;

    // Ensure XDG_RUNTIME_DIR is set to a path that fits in the Unix socket limit.
    // Darwin's sun_path is char[104]; simulator's TMPDIR is typically 150+ chars.
    // We let the C layer (wwn_wls_create) pick the shortest viable path, but prime
    // it with NSTemporaryDirectory() so on-device builds use the sandbox container.
    {
        const char *existing = getenv("XDG_RUNTIME_DIR");
        if (!existing || existing[0] == '\0') {
            NSString *tmp = NSTemporaryDirectory();
            if ([tmp hasSuffix:@"/"]) tmp = [tmp substringToIndex:tmp.length - 1];
            setenv("XDG_RUNTIME_DIR", tmp.fileSystemRepresentation, 0); // 0 = don't overwrite
        }
    }

    const char *name = socketName ? [socketName UTF8String] : "wayland-0";
    WWNLog("WATCH", @"Starting compositor. Socket='%s' size=%ux%u XDG_RUNTIME_DIR='%s'",
          name, _outputWidth, _outputHeight,
          getenv("XDG_RUNTIME_DIR") ?: "(unset)");

    // ── Path 1: Mini Wayland server (libwayland-server.a) ────────────────────
    _miniServer = wwn_wls_create(
        name,
        _outputWidth, _outputHeight,
        miniServerFrameCallback,
        (__bridge void *)self
    );

    if (_miniServer) {
        WWNLog("WATCH", @"Started mini Wayland server on socket '%s' (%u×%u). XDG_RUNTIME_DIR='%s'",
              name, _outputWidth, _outputHeight,
              getenv("XDG_RUNTIME_DIR") ?: "(unset)");
        _isRunning = YES;
        [self _startDispatchThread];
        // Let the dispatch thread park on wl_display_run before the first client
        // connects. Otherwise Start can race and look like a blank surface until
        // the next relaunch.
        usleep(80 * 1000);
        // Do not auto-launch here. Swift `WatchMachineSessionBridge.connect`
        // (and WAWONA_WATCH_AUTO_CLIENT via WawonaWatchMain) owns client Start.
        // Dual auto-launch raced: connect → launch, then env block → stopClient.
        return YES;
    }

    // ── Path 2: Rust compositor backend (libwawona.a) ─────────────────────────
    _rustCompositor = wawona_compositor_create(name);
    if (_rustCompositor) {
        WWNLog("WATCH", @"Started Rust compositor on socket '%s'", name);
        _isRunning = YES;
        [self _startDispatchTimer];
        return YES;
    }

    // Neither mini server nor Rust backend started. Something is wrong with the build.
    WWNLog("WATCH", @"ERROR: No compositor backend available. "
          "Ensure libwayland-server.a is linked: nix run .#xcodegen");
    return NO;
}

- (void)stop {
    if (!_isRunning) return;
    _isRunning = NO;

    [self _stopDispatchThread];
    [self _stopDispatchTimer];
    [self stopClient];
    [self stopWaypipe];

    if (_miniServer) {
        wwn_wls_destroy(_miniServer);
        _miniServer = NULL;
    }

    if (_rustCompositor) {
        wawona_compositor_destroy(_rustCompositor);
        _rustCompositor = NULL;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_latestFrame) {
            CGImageRelease(self->_latestFrame);
            self->_latestFrame = NULL;
        }
    });
}

// MARK: - Dedicated server dispatch thread (mini server)

- (void)_startDispatchThread {
    if (_dispatchThreadValid) return;
    _dispatchRunning = YES;
    DispatchThreadArgs *args = malloc(sizeof(DispatchThreadArgs));
    args->srv     = _miniServer;
    args->running = &_dispatchRunning;
    int rc = pthread_create(&_dispatchThread, NULL, dispatchThreadFunc, args);
    if (rc == 0) {
        _dispatchThreadValid = YES;
    } else {
        free(args);
        _dispatchRunning = NO;
        WWNLog("WATCH", @"Failed to create dispatch thread (rc=%d)", rc);
    }
}

- (void)_stopDispatchThread {
    if (!_dispatchThreadValid) return;
    _dispatchRunning = NO;
    pthread_join(_dispatchThread, NULL);
    _dispatchThreadValid = NO;
    WWNLog("WATCH", @"Dispatch thread stopped");
}

// MARK: - Dispatch timer (Rust compositor fallback)

- (void)_startDispatchTimer {
    if (_displayLink) return;
    _displayLink = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
    dispatch_source_set_timer(_displayLink,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              NSEC_PER_SEC / 30,
                              NSEC_PER_MSEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_displayLink, ^{
        [weakSelf _tick];
    });
    dispatch_resume(_displayLink);
}

- (void)_stopDispatchTimer {
    if (_displayLink) {
        dispatch_source_cancel(_displayLink);
        _displayLink = nil;
    }
}

// MARK: - Compositor tick

- (void)_tick {
    if (!_isRunning) return;

    if (_rustCompositor) {
        wawona_compositor_dispatch(_rustCompositor);

        WatchCBufferData *buf;
        while ((buf = wawona_compositor_pop_buffer(_rustCompositor)) != NULL) {
            if (buf->pixels && buf->width && buf->height) {
                size_t stride = buf->stride > 0 ? buf->stride : buf->width * 4;
                size_t size   = stride * buf->height;
                uint8_t *copy = malloc(size);
                if (copy) {
                    memcpy(copy, buf->pixels, size);
                    [self _deliverPixelsCopy:copy
                                       width:buf->width
                                      height:buf->height
                                      stride:(uint32_t)stride];
                }
            }
            wawona_buffer_free(buf);
        }
    }
}

// MARK: - Frame delivery

- (void)_deliverPixelsCopy:(uint8_t *)pixels
                     width:(uint32_t)width
                    height:(uint32_t)height
                    stride:(uint32_t)stride
{
    if (!pixels || !width || !height) { free(pixels); return; }

    size_t bytesPerRow = stride > 0 ? stride : (size_t)width * 4;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    // wl_shm ARGB8888 is stored as B8G8R8A8 in little-endian memory
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)(kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    CGDataProviderRef provider = CGDataProviderCreateWithData(
        NULL,
        pixels,
        bytesPerRow * height,
        wwn_release_pixel_buffer);

    CGImageRef image = CGImageCreate(
        width, height,
        8, 32, bytesPerRow,
        cs, bitmapInfo, provider,
        NULL, false, kCGRenderingIntentDefault);

    CGDataProviderRelease(provider);
    CGColorSpaceRelease(cs);

    if (!image) return;

    if (!self->_loggedFirstFrame) {
        self->_loggedFirstFrame = YES;
        WWNLog("WATCH", @"First frame %ux%u stride=%u", width, height, stride);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        CGImageRef old = self->_latestFrame;
        self->_latestFrame = image;
        if (old) CGImageRelease(old);
        [[NSNotificationCenter defaultCenter]
            postNotificationName:WWNWatchCompositorFrameReadyNotification
                          object:self];
    });
}

// MARK: - Client launch

/// Automation hook: `WAWONA_WATCH_AUTO_CLIENT=weston-simple-shm|weston-smoke|…`
/// launches a shm-class native client after compositor start (ISSUE-017 verify).
- (void)_maybeAutoLaunchBundledClientFromEnvironment {
    const char *autoClient = getenv("WAWONA_WATCH_AUTO_CLIENT");
    if (!autoClient || autoClient[0] == '\0') {
        return;
    }
    NSString *clientId = [NSString stringWithUTF8String:autoClient];
    WWNLog("WATCH", @"Auto-launching bundled client '%@' (WAWONA_WATCH_AUTO_CLIENT)",
          clientId);
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        [self launchClientWithId:clientId];
    });
}

- (void)_launchClient:(int (*)(int, char **))entry
                 name:(const char *)name
                 argc:(int)argc
                 argv:(char **)argv {
    [self stopClient];

    if (!entry) {
        WWNLog("WATCH", @"Refusing '%s': entry point is NULL", name);
        if (argv) {
            for (int i = 0; i < argc; i++)
                free(argv[i]);
            free(argv);
        }
        return;
    }

    // Clear weston shutdown latch so a fresh compositor client can run.
    wwn_weston_compositor_shutdown_requested = 0;

    ClientThreadArgs *args = malloc(sizeof(ClientThreadArgs));
    args->entry = entry;
    args->name  = name;
    args->argc  = argc;
    args->argv  = argv;

    int rc = pthread_create(&_clientThread, NULL, clientThreadFunc, args);
    if (rc == 0) {
        _clientRunning = YES;
        _clientThreadValid = YES;
        WWNLog("WATCH", @"Launched client '%s'", name);
    } else {
        if (argv) {
            for (int i = 0; i < argc; i++)
                free(argv[i]);
            free(argv);
        }
        free(args);
        WWNLog("WATCH", @"Failed to launch client '%s' (pthread_create=%d)", name, rc);
    }
}

- (void)launchWestonSimpleSHM {
    [self _launchClient:weston_simple_shm_main name:"weston-simple-shm" argc:0 argv:NULL];
}
- (void)launchWeston {
    if ([self _isCompatShimEnabledForClient:"weston"]) {
        return;
    }
    [self stopClient];

    const char *parent_display = getenv("WAYLAND_DISPLAY");
    if (!parent_display || parent_display[0] == '\0')
        parent_display = "wayland-0";
    setenv("WAYLAND_DISPLAY", parent_display, 1);

    // Heap argv: compositorThreadFunc frees these after weston_main returns.
    char **argv = calloc(4, sizeof(char *));
    argv[0] = strdup("weston");
    argv[1] = strdup("--backend=wayland");
    argv[2] = strdup("--shell=desktop-shell.so");
    argv[3] = NULL;

    CompositorThreadArgs *args = malloc(sizeof(CompositorThreadArgs));
    args->argc = 3;
    args->argv = argv;

    wwn_weston_compositor_shutdown_requested = 0;

    int rc = pthread_create(&_clientThread, NULL, compositorThreadFunc, args);
    if (rc == 0) {
        _clientRunning = YES;
        _clientThreadValid = YES;
        WWNLog("WATCH", @"Launched nested Weston compositor (WAYLAND_DISPLAY=%s)", parent_display);
    } else {
        for (int i = 0; i < 3; i++)
            free(argv[i]);
        free(argv);
        free(args);
        WWNLog("WATCH", @"Failed to launch weston compositor (pthread_create=%d)", rc);
    }
}

- (void)launchWestonTerminal {
    if ([self _isCompatShimEnabledForClient:"weston-terminal"]) {
        return;
    }
    [WWNWatchShellEnvironment apply];
    const char *home_dir = getenv("HOME");
    if (home_dir && home_dir[0]) {
        chdir(home_dir);
    }
    const char *shell = getenv("WAWONA_SHELL");
    if (!shell || !shell[0]) {
        shell = "/usr/bin/zsh";
    }
    char **argv = calloc(6, sizeof(char *));
    argv[0] = strdup("weston-terminal");
    argv[1] = strdup("--shell");
    argv[2] = strdup(shell);
    argv[3] = strdup("--font");
    argv[4] = strdup("DejaVuSansM Nerd Font Mono");
    argv[5] = NULL;
    [self _launchClient:weston_terminal_main
                   name:"weston-terminal"
                   argc:5
                   argv:argv];
}

- (void)launchFoot {
    if ([self _isCompatShimEnabledForClient:"foot"]) {
        return;
    }
    [WWNWatchShellEnvironment apply];
    const char *home_dir = getenv("HOME");
    if (home_dir && home_dir[0]) {
        chdir(home_dir);
    }

    // Match iOS/macOS: write a tiny foot.ini with DejaVuSansM Nerd Font
    // Mono so fcft does not resolve to a blank first frame on watch.
    NSString *runtimeDir = NSTemporaryDirectory();
    const char *xdg = getenv("XDG_RUNTIME_DIR");
    if (xdg && xdg[0]) {
        runtimeDir = @(xdg);
    }
    NSString *iniPath =
        [runtimeDir stringByAppendingPathComponent:@"wawona-foot.ini"];
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *fontDir = [bundle pathForResource:@"share/fonts" ofType:nil];
    if (fontDir.length == 0) {
        fontDir = [[bundle.bundlePath stringByAppendingPathComponent:@"share"]
                      stringByAppendingPathComponent:@"fonts"];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *monoTtf = [fontDir
        stringByAppendingPathComponent:
            @"truetype/DejaVuSansMNerdFontMono-Regular.ttf"];
    if (![fm fileExistsAtPath:monoTtf]) {
      monoTtf = [fontDir
          stringByAppendingPathComponent:@"truetype/DejaVuSansMono.ttf"];
    }
    NSString *fontSpec = [fm fileExistsAtPath:monoTtf]
                             ? [NSString stringWithFormat:@"%@:size=11", monoTtf]
                             : @"DejaVuSansM Nerd Font Mono:size=11";
    NSString *ini = [NSString
        stringWithFormat:@"[main]\n"
                          "term=xterm-256color\n"
                          "font=%@\n"
                          "dpi-aware=yes\n"
                          "\n"
                          "[tweak]\n"
                          "font-monospace-warn=no\n",
                         fontSpec];
    [ini writeToFile:iniPath
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];

    const char *shell = getenv("WAWONA_SHELL");
    if (!shell || !shell[0]) {
        shell = "/usr/bin/zsh";
    }
    char **argv = calloc(9, sizeof(char *));
    argv[0] = strdup("foot");
    argv[1] = strdup("-t");
    argv[2] = strdup("xterm-256color");
    argv[3] = strdup("-o");
    argv[4] = strdup("tweak.font-monospace-warn=no");
    argv[5] = strdup("-c");
    argv[6] = strdup(iniPath.fileSystemRepresentation);
    argv[7] = strdup(shell);
    argv[8] = NULL;
    [self _launchClient:foot_main name:"foot" argc:8 argv:argv];
}

- (void)_launchNamedDemo:(int (*)(int, char **))entry name:(const char *)name {
    if (!entry) {
        WWNLog("WATCH", @"Demo '%s' not linked (weak stub / missing archive)", name);
        return;
    }
    [self _launchClient:entry name:name argc:0 argv:NULL];
}

- (void)launchNiri {
    if (!niri_main) {
        WWNLog("WATCH", @"niri_main not linked. Nested niri unavailable");
        return;
    }
    [self stopClient];
    [WWNWatchShellEnvironment apply];

    const char *parent_display = getenv("WAYLAND_DISPLAY");
    if (!parent_display || parent_display[0] == '\0')
        parent_display = "wayland-0";
    setenv("WAYLAND_DISPLAY", parent_display, 1);
    setenv("NIRI_BACKEND", "nested", 1);

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *kdl = [bundle pathForResource:@"share/niri/default-config" ofType:@"kdl"];
    if (kdl.length == 0) {
        kdl = [[bundle.bundlePath stringByAppendingPathComponent:@"share/niri"]
                  stringByAppendingPathComponent:@"default-config.kdl"];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:kdl]) {
        setenv("NIRI_CONFIG", kdl.fileSystemRepresentation, 1);
    }

    wwn_weston_compositor_shutdown_requested = 0;

    ClientThreadArgs *args = malloc(sizeof(ClientThreadArgs));
    args->entry = wwn_watch_niri_entry;
    args->name = "niri";
    args->argc = 0;
    args->argv = NULL;

    int rc = pthread_create(&_clientThread, NULL, clientThreadFunc, args);
    if (rc == 0) {
        _clientRunning = YES;
        _clientThreadValid = YES;
        WWNLog("WATCH", @"Launched nested niri (WAYLAND_DISPLAY=%s)", parent_display);
    } else {
        free(args);
        WWNLog("WATCH", @"Failed to launch niri (pthread_create=%d)", rc);
    }
}

- (void)launchClientWithId:(NSString *)clientId {
    NSString *cid = clientId.length > 0 ? clientId : @"weston-simple-shm";
    if ([cid isEqualToString:@"weston"]) {
        [self launchWeston];
    } else if ([cid isEqualToString:@"weston-terminal"]) {
        [self launchWestonTerminal];
    } else if ([cid isEqualToString:@"foot"]) {
        [self launchFoot];
    } else if ([cid isEqualToString:@"niri"]) {
        [self launchNiri];
    } else if ([cid isEqualToString:@"weston-flower"]) {
        [self _launchNamedDemo:flower_main name:"weston-flower"];
    } else if ([cid isEqualToString:@"weston-smoke"]) {
        [self _launchNamedDemo:smoke_main name:"weston-smoke"];
    } else if ([cid isEqualToString:@"weston-clickdot"]) {
        [self _launchNamedDemo:clickdot_main name:"weston-clickdot"];
    } else if ([cid isEqualToString:@"weston-eventdemo"]) {
        [self _launchNamedDemo:eventdemo_main name:"weston-eventdemo"];
    } else if ([cid isEqualToString:@"weston-resizor"]) {
        [self _launchNamedDemo:resizor_main name:"weston-resizor"];
    } else if ([cid isEqualToString:@"weston-cliptest"]) {
        [self _launchNamedDemo:cliptest_main name:"weston-cliptest"];
    } else if ([cid isEqualToString:@"weston-transformed"]) {
        [self _launchNamedDemo:transformed_main name:"weston-transformed"];
    } else if ([cid isEqualToString:@"weston-stacking"]) {
        [self _launchNamedDemo:stacking_main name:"weston-stacking"];
    } else if ([cid isEqualToString:@"weston-dnd"]) {
        [self _launchNamedDemo:dnd_main name:"weston-dnd"];
    } else if ([cid isEqualToString:@"weston-image"]) {
        [self _launchNamedDemo:image_main name:"weston-image"];
    } else if ([cid isEqualToString:@"weston-scaler"]) {
        [self _launchNamedDemo:scaler_main name:"weston-scaler"];
    } else if ([cid isEqualToString:@"weston-editor"]) {
        [self _launchNamedDemo:editor_main name:"weston-editor"];
    } else if ([cid isEqualToString:@"weston-constraints"]) {
        [self _launchNamedDemo:constraints_main name:"weston-constraints"];
    } else if ([cid isEqualToString:@"kmscube"] ||
               [cid isEqualToString:@"gbm-es2-demo"] ||
               [cid isEqualToString:@"opengl-cube"] ||
               [cid isEqualToString:@"vkcube"] ||
               [cid isEqualToString:@"weston-simple-egl"]) {
        WWNLog("WATCH",
               @"Refusing '%@': GPU client. WatchOS has no Metal/ANGLE stack",
               cid);
    } else {
        // Default / weston-simple-shm
        [self launchWestonSimpleSHM];
    }
}

- (void)stopClient {
    if (_clientRunning && _clientThreadValid) {
        wwn_weston_compositor_shutdown_requested = 1;
        _clientRunning = NO;
        _clientThreadValid = NO;
        // pthread_timedjoin_np is unavailable on Apple. Cancel + join.
        pthread_cancel(_clientThread);
        pthread_join(_clientThread, NULL);
        WWNLog("WATCH", @"Client stopped");
    }

    wwn_weston_compositor_shutdown_requested = 0;
    _loggedFirstFrame = NO;

    // Drop the last SHM frame so Start of another client does not paint the
    // previous weston-terminal pixels while waiting for the first commit.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_latestFrame) {
            CGImageRelease(self->_latestFrame);
            self->_latestFrame = NULL;
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:WWNWatchCompositorFrameReadyNotification
                          object:self];
    });

    // Allow Stop → Start without relaunching the whole watch app.
    if (wwn_pty_ios_allow_new_shell_session) {
        wwn_pty_ios_allow_new_shell_session();
    }

    // Brief settle so the mini server finishes disconnect cleanup before the
    // next client binds globals (fixes flaky Close → Start on watchOS).
    usleep(50 * 1000);
}

// MARK: - Keyboard input (WatchKit text entry → PTY)

- (void)sendText:(NSString *)text {
    if (text.length == 0) return;
    if (!_miniServer) {
        WWNLog("WATCH", @"sendText ignored: mini server not running "
              "(Rust backend keyboard path not yet wired)");
        return;
    }
    // wwn_wls_feed_text is thread-safe; it enqueues and the dispatch thread emits.
    wwn_wls_feed_text(_miniServer, text.UTF8String);
    WWNLog("WATCH", @"Injected %lu chars of keyboard input", (unsigned long)text.length);
}

- (void)sendKeyCode:(uint32_t)evdevKeycode pressed:(BOOL)pressed {
    if (!_miniServer) return;
    wwn_wls_feed_key(_miniServer, evdevKeycode, pressed ? 1 : 0);
}

// MARK: - Waypipe (SSH + Waypipe)

typedef struct {
    char **argv;
    int     argc;
    __unsafe_unretained WWNWatchCompositorBridge *bridge;
} WaypipeThreadArgs;

static void waypipeThreadCleanup(void *ctx) {
    WaypipeThreadArgs *args = (WaypipeThreadArgs *)ctx;
    if (!args) return;
    for (int i = 0; i < args->argc; i++) {
        free(args->argv[i]);
    }
    free(args->argv);
    WWNWatchCompositorBridge *bridge = args->bridge;
    free(args);
    if (bridge) {
        [bridge _waypipeThreadDidExit];
    }
}

static void *waypipeThreadFunc(void *ctx) {
    WaypipeThreadArgs *args = (WaypipeThreadArgs *)ctx;
    pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
    pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);

    pthread_cleanup_push(waypipeThreadCleanup, ctx);
    WWNLog("WATCH", @"waypipe_main starting (%d args)", args->argc);
    int result = waypipe_main(args->argc, args->argv);
    WWNLog("WATCH", @"waypipe_main exited with code %d", result);
    pthread_cleanup_pop(1);
    return NULL;
}

- (void)launchWaypipeWithHost:(NSString *)host
                         user:(NSString *)user
                         port:(NSInteger)port
                     password:(NSString *)password
                remoteCommand:(NSString *)remoteCommand
{
    if (!_isRunning) {
        WWNLog("WATCH", @"launchWaypipe ignored: compositor is not running.");
        return;
    }

    if (!waypipe_main) {
        WWNLog("WATCH", @"waypipe_main not linked. Waypipe unavailable. "
              "Run nix run .#xcodegen after building watchOS deps.");
        return;
    }

    NSString *trimmedHost = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *trimmedUser = [user stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedHost.length == 0 || trimmedUser.length == 0) {
        WWNLog("WATCH", @"launchWaypipe requires non-empty host and user.");
        return;
    }

    [self stopWaypipe];

    const char *xdgRuntimeDir = getenv("XDG_RUNTIME_DIR");
    NSString *socketDir = (xdgRuntimeDir && xdgRuntimeDir[0] != '\0')
        ? [NSString stringWithUTF8String:xdgRuntimeDir]
        : NSTemporaryDirectory();
    const char *waylandDisplay = getenv("WAYLAND_DISPLAY");
    NSString *display = (waylandDisplay && waylandDisplay[0] != '\0')
        ? [NSString stringWithUTF8String:waylandDisplay]
        : @"wayland-0";

    setenv("XDG_RUNTIME_DIR", socketDir.UTF8String, 1);
    setenv("WAYLAND_DISPLAY", display.UTF8String, 1);

    if (password.length > 0) {
        setenv("WAYPIPE_SSH_PASSWORD", password.UTF8String, 1);
    } else {
        unsetenv("WAYPIPE_SSH_PASSWORD");
    }

    // Build waypipe argv:
    //   waypipe --oneshot -s <socketDir>/wp ssh -p <port> user@host <remoteCommand>
    NSString *shortSocket = [socketDir stringByAppendingPathComponent:@"wp"];
    NSString *userAtHost = [NSString stringWithFormat:@"%@@%@", trimmedUser, trimmedHost];
    NSInteger effectivePort = port > 0 ? port : 22;
    NSString *portStr = [NSString stringWithFormat:@"%ld", (long)effectivePort];
    NSString *cmd = (remoteCommand.length > 0) ? remoteCommand : @"weston-simple-shm";

    NSArray<NSString *> *argsList = @[
        @"waypipe",
        @"--oneshot",
        @"-s", shortSocket,
        @"ssh",
        @"-o", @"StrictHostKeyChecking=accept-new",
        @"-o", @"BatchMode=no",
        @"-p", portStr,
        userAtHost,
        cmd,
    ];

    WWNLog("WATCH", @"Launching waypipe: %@", [argsList componentsJoinedByString:@" "]);

    int argc = (int)argsList.count;
    char **argv = malloc(sizeof(char *) * (argc + 1));
    for (int i = 0; i < argc; i++) {
        argv[i] = strdup(argsList[i].UTF8String);
    }
    argv[argc] = NULL;

    WaypipeThreadArgs *args = malloc(sizeof(WaypipeThreadArgs));
    args->argv = argv;
    args->argc = argc;
    args->bridge = self;

    int rc = pthread_create(&_waypipeThread, NULL, waypipeThreadFunc, args);
    if (rc == 0) {
        _waypipeRunning = YES;
        _waypipeThreadValid = YES;
        WWNLog("WATCH", @"Waypipe thread started");
    } else {
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        free(args);
        WWNLog("WATCH", @"Failed to create waypipe thread (rc=%d)", rc);
    }
}

- (void)stopWaypipe {
    if (!_waypipeThreadValid) return;
    _waypipeRunning = NO;
    pthread_cancel(_waypipeThread);
    pthread_join(_waypipeThread, NULL);
    _waypipeThreadValid = NO;
    unsetenv("WAYPIPE_SSH_PASSWORD");
    WWNLog("WATCH", @"Waypipe stopped");
}

- (BOOL)isWaypipeRunning { return _waypipeRunning; }

- (void)_waypipeThreadDidExit {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_waypipeRunning = NO;
        self->_waypipeThreadValid = NO;
        unsetenv("WAYPIPE_SSH_PASSWORD");
    });
}

- (BOOL)_isCompatShimEnabledForClient:(const char *)name {
    int isShim = 0;
    if (strcmp(name, "weston") == 0) {
        isShim = (wwn_weston_is_compat_shim && wwn_weston_is_compat_shim() != 0);
    } else if (strcmp(name, "weston-terminal") == 0) {
        isShim = (wwn_weston_terminal_is_compat_shim && wwn_weston_terminal_is_compat_shim() != 0);
    } else if (strcmp(name, "foot") == 0) {
        isShim = (wwn_foot_is_compat_shim && wwn_foot_is_compat_shim() != 0);
    }

    if (isShim) {
        WWNLog("WATCH", @"Refusing to launch '%s': client is still compiled as weston-simple-shm compatibility shim.", name);
        return YES;
    }
    return NO;
}

// MARK: - Properties

- (BOOL)isClientRunning { return _clientRunning; }

- (BOOL)isCompositorAvailable {
    return _miniServer != NULL || _rustCompositor != NULL;
}

- (nullable NSString *)socketPath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"wayland-0"];
}

- (CGImageRef)latestFrame { return _latestFrame; }

@end
