//
//  WWNIlandPresenter.m
//  Wawona — macOS
//
//  See WWNIlandPresenter.h. Imports nested iland GL-client IOSurfaces into Metal
//  and composites them into a CAMetalLayer, in-window (Mode A).
//

#import "WWNIlandPresenter.h"
#import "WWNEDRSupport.h"
#import "ui/Settings/WWNPreferencesManager.h"
#import "../../util/WWNLog.h"
#import <AppKit/AppKit.h>
#import <IOSurface/IOSurfaceRef.h>
#import <errno.h>
#import <math.h>
#import <pthread.h>
#import <stdatomic.h>
#import <unistd.h>

// iland present hook. Declared here (rather than including iland_present.h) so
// this file compiles even when the iland headers aren't on the include path;
// the symbols are provided by libiland_userland.a at link time. The signature
// MUST match iland_present.h exactly.
typedef void (*iland_present_callback_t)(uint32_t crtc_id,
                                         uint32_t fb_id,
                                         IOSurfaceRef surface,
                                         uint32_t flags,
                                         void *user);
extern void iland_drm_set_present_callback(iland_present_callback_t cb, void *user);
extern void iland_drm_set_preferred_mode(uint32_t width, uint32_t height,
                                         uint32_t refresh_millihz);
extern void iland_drm_complete_page_flip(uint32_t crtc_id, uint32_t fb_id);
extern int g_drm_event_pipe_write;
#ifndef DRM_VIRTUAL_FD
#define DRM_VIRTUAL_FD 42
#endif

// In-process cube entry points (lib{kmscube,opengl_cube,vkcube}.a, each with
// main renamed via -Dmain=). Weakly imported so the app links even without the
// GL-clients packages.
extern int kmscube_main(int argc, char *argv[]) __attribute__((weak_import));
extern int gbm_es2_demo_main(int argc, char *argv[]) __attribute__((weak_import));
extern int opengl_cube_main(int argc, char *argv[]) __attribute__((weak_import));
extern int vkcube_main(int argc, char *argv[]) __attribute__((weak_import));

// Minimal fullscreen-textured-quad shader compiled at runtime. Samples the
// client's BGRA IOSurface texture and draws it flipped (GL origin is
// bottom-left; Metal/CoreAnimation is top-left).
static NSString *const kShaderSource = @""
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VOut { float4 pos [[position]]; float2 uv; };\n"
"vertex VOut wwn_vs(uint vid [[vertex_id]]) {\n"
"  float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };\n"
"  float2 t[4] = { float2(0,1),  float2(1,1),  float2(0,0), float2(1,0) };\n"
"  VOut o; o.pos = float4(p[vid], 0, 1); o.uv = t[vid]; return o;\n"
"}\n"
"fragment float4 wwn_fs(VOut in [[stage_in]],\n"
"                       texture2d<float> tex [[texture(0)]]) {\n"
"  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
"  return tex.sample(s, in.uv);\n"
"}\n";

// A GBM surface cycles through a handful of buffers, so the IOSurface passed to
// each present repeats. Importing it as a fresh MTLTexture every frame is pure
// overhead and was enough to miss vsync deadlines (~35 fps on a 60 Hz display,
// i.e. visibly uneven frame pacing). Cache by IOSurface instead. The bound is a
// safety valve: a mode change retires the old buffers, and nothing else should
// grow this map.
#define WWN_ILAND_TEXTURE_CACHE_MAX 16

@implementation WWNIlandPresenter {
    CAMetalLayer            *_layer;
    id<MTLDevice>            _device;
    id<MTLCommandQueue>      _queue;
    id<MTLRenderPipelineState> _pipeline;
    CFMutableDictionaryRef   _textureCache; // IOSurfaceRef -> id<MTLTexture>
    pthread_t               _clientThread;
    BOOL                    _clientThreadStarted;
    int                     _clientWidth;
    int                     _clientHeight;
    NSString               *_clientId;
    // Log tag for the present path. Presenting is not exclusive to the cubes
    // (the iland DRM Weston backend presents here too), so it starts neutral and
    // is narrowed when a known client is launched — reporting every present as
    // KMSCUBE made a running opengl-cube or vkcube look like kmscube.
    const char             *_presentLogModule;
}

// Single active presenter for the C trampoline (one nested client at a time).
static WWNIlandPresenter *gActivePresenter = nil;

static void wwn_iland_present_trampoline(uint32_t crtc_id, uint32_t fb_id,
                                         IOSurfaceRef surface, uint32_t flags,
                                         void *user) {
    (void)flags; (void)user;
    @autoreleasepool {
        WWNIlandPresenter *p = gActivePresenter;
        if (p && surface) {
            [p presentIOSurface:surface
                         crtcID:crtc_id
                  framebufferID:fb_id];
        } else {
            iland_drm_complete_page_flip(crtc_id, fb_id);
        }
    }
}

- (instancetype)initWithLayer:(CAMetalLayer *)layer device:(id<MTLDevice>)device {
    self = [super init];
    if (!self) return nil;

    _layer = layer;
    _device = device ?: layer.device ?: MTLCreateSystemDefaultDevice();
    if (!_device) return nil;

    _layer.device = _device;
    _layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _layer.framebufferOnly = NO;
    WWNEDRConfigureMetalLayer(
        _layer, [[WWNPreferencesManager sharedManager] colorOperations]);

    _queue = [_device newCommandQueue];

    NSError *err = nil;
    id<MTLLibrary> lib = [_device newLibraryWithSource:kShaderSource
                                              options:nil
                                                error:&err];
    if (!lib) {
        NSLog(@"[iland] shader compile failed: %@", err);
        return nil;
    }
    // CSD / transparent host: alpha from client buffer must composite through
    // the Metal layer (opaque=NO + blend). Opaque clear would paint a black plate.
    _layer.opaque = NO;
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [lib newFunctionWithName:@"wwn_vs"];
    pd.fragmentFunction = [lib newFunctionWithName:@"wwn_fs"];
    pd.colorAttachments[0].pixelFormat = _layer.pixelFormat;
    pd.colorAttachments[0].blendingEnabled = YES;
    pd.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pd.colorAttachments[0].destinationRGBBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;
    pd.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pd.colorAttachments[0].destinationAlphaBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;
    _pipeline = [_device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (!_pipeline) {
        NSLog(@"[iland] pipeline creation failed: %@", err);
        return nil;
    }

    _textureCache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);

    gActivePresenter = self;
    iland_drm_set_present_callback(wwn_iland_present_trampoline, (__bridge void *)self);
    [self syncPreferredModeFromLayer];
    return self;
}

- (void)invalidate {
    iland_drm_set_present_callback(NULL, NULL);
    if (gActivePresenter == self) gActivePresenter = nil;
}

- (void)dealloc {
    if (_textureCache) CFRelease(_textureCache);
}

- (void)hostGeometryDidChange {
    // Main thread only: -syncPreferredModeFromLayer reads CALayer geometry, and
    // the client's render thread must not touch that while AppKit mutates it.
    [self syncPreferredModeFromLayer];
}

- (void)syncPreferredModeFromLayer {
    CGSize size = _layer.drawableSize;
    if (size.width <= 0 || size.height <= 0) {
        size = _layer.bounds.size;
        CGFloat scale = _layer.contentsScale > 0 ? _layer.contentsScale : 1.0;
        size.width *= scale;
        size.height *= scale;
    }
    if (size.width <= 0 || size.height <= 0) return;

    /*
     * Mode A has no WindowServer-plist authority for an app-sized surface, so
     * set this before stock DRM clients enumerate connectors, or KMS advertises
     * the 1920x1080 fallback (#94). It only affects *enumeration*: a client that
     * has already chosen a mode and sized its GBM surface (stock kmscube does
     * exactly that, once, and explicitly does not watch for hotplug) will not
     * pick up a later change. Calling this per present was therefore inert for
     * resize while still reading CALayer geometry off the render thread.
     *
     * Refresh is millihertz. This used to be a hardcoded 60000 while iland read
     * it as Hz, so KMS advertised a 60000 Hz mode with a matching nonsense pixel
     * clock. Ask the screen the layer is actually on: iland's own fallback probes
     * CGMainDisplayID, which is the wrong display in a multi-monitor setup.
     */
    uint32_t refresh_millihz = 60000;
    NSScreen *screen = nil;
    id delegate = _layer.delegate;
    if ([delegate isKindOfClass:[NSView class]]) {
        screen = ((NSView *)delegate).window.screen;
    }
    if (!screen) screen = NSScreen.mainScreen;
    if (screen.maximumFramesPerSecond > 0) {
        refresh_millihz = (uint32_t)screen.maximumFramesPerSecond * 1000u;
    }

    iland_drm_set_preferred_mode((uint32_t)llround(size.width),
                                 (uint32_t)llround(size.height),
                                 refresh_millihz);
}

/*
 * The present callback hands over an IOSurface and nothing else, so the surface's
 * own pixel format is the only statement of what the client rendered. Importing
 * everything as BGRA8Unorm silently reinterpreted a 10-bit framebuffer — which
 * iland's GBM will hand out for the 2101010 fourccs as 'l10r' — as 8-bit, giving
 * wrong colours rather than a diagnosable failure. 0 means "refuse".
 */
static MTLPixelFormat WWNMetalFormatForIOSurface(uint32_t fourcc) {
    switch (fourcc) {
        case 'BGRA': return MTLPixelFormatBGRA8Unorm;
        case 'l10r': return MTLPixelFormatBGR10A2Unorm;
        case 'w30r': return MTLPixelFormatBGR10_XR;
        case 'l64r': return MTLPixelFormatRGBA16Unorm;
        case 'RGhA': return MTLPixelFormatRGBA16Float;
        case 'RGfA': return MTLPixelFormatRGBA32Float;
        default: return (MTLPixelFormat)0;
    }
}

// Wrap the presented IOSurface as a Metal texture and draw it into the layer.
- (id<MTLTexture>)cachedTextureForIOSurface:(IOSurfaceRef)surface
                                       width:(NSUInteger)w
                                      height:(NSUInteger)h {
    MTLPixelFormat fmt =
        WWNMetalFormatForIOSurface(IOSurfaceGetPixelFormat(surface));
    if (fmt == (MTLPixelFormat)0) {
        static uint32_t s_lastRejected = 0;
        uint32_t fourcc = IOSurfaceGetPixelFormat(surface);
        if (fourcc != s_lastRejected) {
            s_lastRejected = fourcc;
            WWNLog(_presentLogModule ?: "ILAND",
                   @"refusing present: IOSurface fcc=0x%08x has no Metal mapping",
                   fourcc);
        }
        return nil;
    }

    id<MTLTexture> cached =
        (__bridge id<MTLTexture>)CFDictionaryGetValue(_textureCache, surface);
    // A resized client reuses IOSurfaces at a new size, so validate the extent
    // and format rather than trusting the key alone.
    if (cached && cached.width == w && cached.height == h &&
        cached.pixelFormat == fmt) {
        return cached;
    }

    if (CFDictionaryGetCount(_textureCache) >= WWN_ILAND_TEXTURE_CACHE_MAX) {
        CFDictionaryRemoveAllValues(_textureCache);
    }

    MTLTextureDescriptor *td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:fmt
                                                          width:w
                                                         height:h
                                                      mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;

    id<MTLTexture> tex = [_device newTextureWithDescriptor:td
                                                iosurface:surface
                                                    plane:0];
    if (tex) CFDictionarySetValue(_textureCache, surface, (__bridge void *)tex);
    return tex;
}

// Wrap the presented IOSurface as a Metal texture and draw it into the layer.
- (void)presentIOSurface:(IOSurfaceRef)surface
                  crtcID:(uint32_t)crtcID
           framebufferID:(uint32_t)framebufferID {
    NSUInteger w = IOSurfaceGetWidth(surface);
    NSUInteger h = IOSurfaceGetHeight(surface);
    if (w == 0 || h == 0) {
        iland_drm_complete_page_flip(crtcID, framebufferID);
        return;
    }

    id<MTLTexture> srcTex = [self cachedTextureForIOSurface:surface
                                                      width:w
                                                     height:h];
    if (!srcTex) {
        iland_drm_complete_page_flip(crtcID, framebufferID);
        return;
    }

    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    if (!drawable) {
        iland_drm_complete_page_flip(crtcID, framebufferID);
        return;
    }

    // The drawable is the authoritative destination extent and is safe to read
    // here; _layer.drawableSize is CALayer state owned by the main thread.
    NSUInteger tw = drawable.texture.width;
    NSUInteger th = drawable.texture.height;

    // Golden present contract (docs/iland-graphics-stack.md I/O verify table):
    // size + fourcc + frame id are what acceptance grades, so record the first
    // frames and then a periodic frame proving presentation is still running.
    static int s_presentCount = 0;
    const int kPresentLogPeriod = 300;
    if (s_presentCount < 5 || s_presentCount % kPresentLogPeriod == 0) {
        WWNLog(_presentLogModule ?: "ILAND",
               @"iland present #%d IOSurface %lux%lu fcc=0x%08x "
               @"drawable=%lux%lu opaque=%d",
               s_presentCount, (unsigned long)w, (unsigned long)h,
               IOSurfaceGetPixelFormat(surface), (unsigned long)tw,
               (unsigned long)th, (int)_layer.opaque);
    }
    s_presentCount++;

    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = drawable.texture;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc =
        [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:_pipeline];

    // A stock KMS client picks one mode and keeps that framebuffer size for its
    // whole run, so after a host resize the source and destination extents
    // disagree. Stretching to fill distorted the cube; letterbox instead, which
    // is what a real display does when it scales a mode it cannot change.
    if (tw > 0 && th > 0 && (tw != w || th != h)) {
        double scale = fmin((double)tw / (double)w, (double)th / (double)h);
        double fitW = (double)w * scale;
        double fitH = (double)h * scale;
        static NSUInteger s_lastFitW = 0, s_lastFitH = 0;
        if (tw != s_lastFitW || th != s_lastFitH) {
            s_lastFitW = tw;
            s_lastFitH = th;
            WWNLog(_presentLogModule ?: "ILAND",
                   @"host resized to %lux%lu; client mode is fixed at %lux%lu — "
                   @"letterboxing to %.0fx%.0f",
                   (unsigned long)tw, (unsigned long)th, (unsigned long)w,
                   (unsigned long)h, fitW, fitH);
        }
        MTLViewport vp = {
            .originX = ((double)tw - fitW) * 0.5,
            .originY = ((double)th - fitH) * 0.5,
            .width = fitW,
            .height = fitH,
            .znear = 0.0,
            .zfar = 1.0,
        };
        [enc setViewport:vp];
    }

    [enc setFragmentTexture:srcTex atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];

    /*
     * Complete on GPU finish, not on the drawable's presented handler. Gating on
     * actual scanout looks like the textbook way to lock a client to vsync, and
     * it was measured: throughput halved (~37 fps to ~18, unchanged when the
     * window was frontmost, so not background throttling). iland allows a single
     * outstanding flip per CRTC, so waiting for scanout serializes the client
     * behind presentation with nothing left in flight, and each frame costs
     * several vblanks instead of one. Decoupling the client's cadence from
     * presentation needs more than one in-flight flip, which is an iland ABI
     * change, not a presenter change.
     */
    [cb addCompletedHandler:^(__unused id<MTLCommandBuffer> completed) {
        iland_drm_complete_page_flip(crtcID, framebufferID);
    }];
    [cb presentDrawable:drawable];
    [cb commit];
}

// --- in-process nested client launcher ---

static BOOL wwn_prepare_iland_virtual_drm_fd(void) {
    if (g_drm_event_pipe_write >= 0)
        return YES;
    int p[2];
    if (pipe(p) != 0)
        return NO;
    if (dup2(p[0], DRM_VIRTUAL_FD) < 0) {
        close(p[0]);
        close(p[1]);
        return NO;
    }
    close(p[0]);
    g_drm_event_pipe_write = p[1];
    return YES;
}

typedef int (*wwn_cube_entry_t)(int argc, char *argv[]);

typedef struct {
    const char *clientId;
    const char *logModule;
    // Extra argv beyond argv[0]; NULL-terminated.
    const char *const *argv;
} wwn_cube_client_t;

// kmscube / gbm-es2-demo drive iland's virtual DRM. opengl-cube and vkcube are
// Wayland clients (IOSurface dmabuf winsys) and are launched through the
// compositor, not this presenter.
static const wwn_cube_client_t kCubeClients[] = {
    { "kmscube",       "KMSCUBE",       NULL },
    { "gbm-es2-demo",  "GBM_ES2_DEMO",  NULL },
};

static const wwn_cube_client_t *wwn_cube_client_for_id(NSString *clientId) {
    for (size_t i = 0; i < sizeof(kCubeClients) / sizeof(kCubeClients[0]); i++) {
        if ([clientId isEqualToString:@(kCubeClients[i].clientId)])
            return &kCubeClients[i];
    }
    return NULL;
}

static wwn_cube_entry_t wwn_cube_entry_for_id(NSString *clientId) {
    if ([clientId isEqualToString:@"kmscube"]) return kmscube_main;
    if ([clientId isEqualToString:@"gbm-es2-demo"]) return gbm_es2_demo_main;
    return NULL;
}

static void *wwn_cube_thread(void *arg) {
    WWNIlandPresenter *self = (__bridge WWNIlandPresenter *)arg;
    (void)self->_clientWidth;
    (void)self->_clientHeight;
    NSString *clientId = self->_clientId;
    const wwn_cube_client_t *client = wwn_cube_client_for_id(clientId);
    wwn_cube_entry_t entry = wwn_cube_entry_for_id(clientId);
    if (client == NULL || entry == NULL)
        return NULL;

    if (!wwn_prepare_iland_virtual_drm_fd()) {
        WWNLog(client->logModule,
               @"aborting %@ — virtual DRM fd not ready", clientId);
        return NULL;
    }

    // The clients open /dev/dri/card0 (iland's virtual DRM) by default.
    char *argv[8];
    int argc = 0;
    argv[argc++] = (char *)client->clientId;
    for (const char *const *extra = client->argv; extra && *extra; extra++) {
        if (argc >= (int)(sizeof(argv) / sizeof(argv[0])) - 1) break;
        argv[argc++] = (char *)*extra;
    }
    argv[argc] = NULL;

    WWNLog(client->logModule, @"%@ enter (iland DRM present)", clientId);
    int rc = entry(argc, argv);
    WWNLog(client->logModule, @"%@ exit rc=%d", clientId, rc);
    return NULL;
}

- (BOOL)launchNestedIlandGpuClient:(NSString *)clientId
                             width:(int)width
                            height:(int)height {
    const wwn_cube_client_t *client = wwn_cube_client_for_id(clientId);
    if (client == NULL) {
        WWNLog("CLIENT", @"unknown iland GPU client id %@", clientId);
        return NO;
    }
    if (wwn_cube_entry_for_id(clientId) == NULL) {
        WWNLog(client->logModule,
               @"%@ unavailable — archive not linked", clientId);
        return NO;
    }
    if (_clientThreadStarted) {
        if ([_clientId isEqualToString:clientId]) {
            return YES;
        }
        WWNLog(client->logModule,
               @"refusing %@ — in-process %@ still owns iland DRM", clientId,
               _clientId ?: @"(unknown)");
        return NO;
    }
    if (!wwn_prepare_iland_virtual_drm_fd()) {
        WWNLog(client->logModule, @"virtual DRM fd prepare failed");
        return NO;
    }
    _clientId = [clientId copy];
    _presentLogModule = client->logModule;
    _clientWidth = width > 0 ? width : 1280;
    _clientHeight = height > 0 ? height : 720;
    int rc = pthread_create(&_clientThread, NULL, wwn_cube_thread,
                            (__bridge void *)self);
    if (rc != 0) {
        WWNLog(client->logModule, @"pthread_create failed: %d", rc);
        return NO;
    }
    _clientThreadStarted = YES;
    WWNLog(client->logModule, @"started in-process %@ %dx%d via iland",
           clientId, _clientWidth, _clientHeight);
    return YES;
}

- (NSString *)runningClientId {
    return _clientThreadStarted ? _clientId : nil;
}

- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height {
    return [self launchNestedIlandGpuClient:@"kmscube"
                                      width:width
                                     height:height];
}

@end
