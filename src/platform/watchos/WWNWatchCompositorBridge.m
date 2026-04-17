// WWNWatchCompositorBridge.m
// Wayland compositor bridge for watchOS.
//
// Compositor priority:
//   1. WWNMiniWaylandServer (libwayland-server.a compiled via Nix) – pure C,
//      no Rust required; works as soon as the Nix deps are linked.
//   2. libwawona.a Rust backend – used when available (tier-3 Rust target).

#import "WWNWatchCompositorBridge.h"
#import "WWNMiniWaylandServer.h"
#import <CoreGraphics/CoreGraphics.h>
#import <pthread.h>
#import <stdlib.h>
#import <string.h>

// ── Client entry points ───────────────────────────────────────────────────────
// Provided by -force_load'd static libraries (weston, foot, etc.) built via Nix.
// Weak stubs in WWNWatchStubs.c allow compilation without Nix but should never
// be reached at runtime after a proper `nix run .#xcodegen` build.

extern int weston_simple_shm_main(int argc, char **argv);
extern int weston_main(int argc, char **argv);
extern int weston_terminal_main(int argc, char **argv);
extern int foot_main(int argc, char **argv);
extern int wwn_weston_is_compat_shim(void) __attribute__((weak));
extern int wwn_weston_terminal_is_compat_shim(void) __attribute__((weak));
extern int wwn_foot_is_compat_shim(void) __attribute__((weak));

// In-process waypipe with libssh2 (statically linked from Rust).
// Weak so the bridge can nil-check before calling.
extern int waypipe_main(int argc, char **argv) __attribute__((weak));

// ── Rust compositor C-API (optional – satisfied by stubs when not linked) ─────

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

// ── @interface extensions — MUST appear before any C code that messages the class ──

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
    NSLog(@"[WatchCompositor] Dispatch thread started");
    while (*(args->running)) {
        wwn_wls_dispatch(args->srv, 16);
    }
    NSLog(@"[WatchCompositor] Dispatch thread exiting");
    free(args);
    return NULL;
}

// ── Client thread helper ──────────────────────────────────────────────────────
// Runs the selected Wayland client entry point on a background thread.

typedef struct {
    int (*entry)(int argc, char **argv);
    const char *name;
} ClientThreadArgs;

static void *clientThreadFunc(void *ctx) {
    ClientThreadArgs *args = (ClientThreadArgs *)ctx;
    char *argv[] = { (char *)args->name, NULL };

    NSLog(@"[WatchCompositor] Client '%s' starting", args->name);
    int rc = args->entry(1, argv);
    NSLog(@"[WatchCompositor] Client '%s' exited with code %d", args->name, rc);

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
    NSLog(@"[WatchCompositor] Starting compositor — socket='%s' size=%ux%u XDG_RUNTIME_DIR='%s'",
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
        NSLog(@"[WatchCompositor] Started mini Wayland server on socket '%s' (%u×%u) — XDG_RUNTIME_DIR='%s'",
              name, _outputWidth, _outputHeight,
              getenv("XDG_RUNTIME_DIR") ?: "(unset)");
        _isRunning = YES;
        [self _startDispatchThread];
        return YES;
    }

    // ── Path 2: Rust compositor backend (libwawona.a) ─────────────────────────
    _rustCompositor = wawona_compositor_create(name);
    if (_rustCompositor) {
        NSLog(@"[WatchCompositor] Started Rust compositor on socket '%s'", name);
        _isRunning = YES;
        [self _startDispatchTimer];
        return YES;
    }

    // Neither mini server nor Rust backend started — something is wrong with the build.
    NSLog(@"[WatchCompositor] ERROR: No compositor backend available. "
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
        NSLog(@"[WatchCompositor] Failed to create dispatch thread (rc=%d)", rc);
    }
}

- (void)_stopDispatchThread {
    if (!_dispatchThreadValid) return;
    _dispatchRunning = NO;
    pthread_join(_dispatchThread, NULL);
    _dispatchThreadValid = NO;
    NSLog(@"[WatchCompositor] Dispatch thread stopped");
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
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;

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

- (void)_launchClient:(int (*)(int, char **))entry name:(const char *)name {
    [self stopClient];

    ClientThreadArgs *args = malloc(sizeof(ClientThreadArgs));
    args->entry = entry;
    args->name  = name;

    int rc = pthread_create(&_clientThread, NULL, clientThreadFunc, args);
    if (rc == 0) {
        _clientRunning = YES;
        _clientThreadValid = YES;
        NSLog(@"[WatchCompositor] Launched client '%s'", name);
    } else {
        free(args);
        NSLog(@"[WatchCompositor] Failed to launch client '%s' (pthread_create=%d)", name, rc);
    }
}

- (void)launchWestonSimpleSHM   { [self _launchClient:weston_simple_shm_main name:"weston-simple-shm"]; }
- (void)launchWeston {
    if ([self _isCompatShimEnabledForClient:"weston"]) {
        return;
    }
    [self _launchClient:weston_main name:"weston"];
}

- (void)launchWestonTerminal {
    if ([self _isCompatShimEnabledForClient:"weston-terminal"]) {
        return;
    }
    [self _launchClient:weston_terminal_main name:"weston-terminal"];
}

- (void)launchFoot {
    if ([self _isCompatShimEnabledForClient:"foot"]) {
        return;
    }
    [self _launchClient:foot_main name:"foot"];
}

- (void)stopClient {
    if (!_clientRunning || !_clientThreadValid) return;
    _clientRunning = NO;
    _clientThreadValid = NO;
    pthread_cancel(_clientThread);
    pthread_join(_clientThread, NULL);
    NSLog(@"[WatchCompositor] Client stopped");
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
    NSLog(@"[WatchCompositor] waypipe_main starting (%d args)", args->argc);
    int result = waypipe_main(args->argc, args->argv);
    NSLog(@"[WatchCompositor] waypipe_main exited with code %d", result);
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
        NSLog(@"[WatchCompositor] launchWaypipe ignored: compositor is not running.");
        return;
    }

    if (!waypipe_main) {
        NSLog(@"[WatchCompositor] waypipe_main not linked — waypipe unavailable. "
              "Run nix run .#xcodegen after building watchOS deps.");
        return;
    }

    NSString *trimmedHost = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *trimmedUser = [user stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedHost.length == 0 || trimmedUser.length == 0) {
        NSLog(@"[WatchCompositor] launchWaypipe requires non-empty host and user.");
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

    NSLog(@"[WatchCompositor] Launching waypipe: %@", [argsList componentsJoinedByString:@" "]);

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
        NSLog(@"[WatchCompositor] Waypipe thread started");
    } else {
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        free(args);
        NSLog(@"[WatchCompositor] Failed to create waypipe thread (rc=%d)", rc);
    }
}

- (void)stopWaypipe {
    if (!_waypipeThreadValid) return;
    _waypipeRunning = NO;
    pthread_cancel(_waypipeThread);
    pthread_join(_waypipeThread, NULL);
    _waypipeThreadValid = NO;
    unsetenv("WAYPIPE_SSH_PASSWORD");
    NSLog(@"[WatchCompositor] Waypipe stopped");
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
        NSLog(@"[WatchCompositor] Refusing to launch '%s': client is still compiled as weston-simple-shm compatibility shim.", name);
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
