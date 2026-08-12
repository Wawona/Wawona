//
//  WWNIlandPresenter.m
//  Wawona — iOS
//
//  See WWNIlandPresenter.h. Imports nested iland GL-client IOSurfaces into Metal
//  and composites them into a CAMetalLayer (Mode A).
//

#import "WWNIlandPresenter.h"
#import "../macos/WWNEDRSupport.h"
#import "../macos/ui/Settings/WWNPreferencesManager.h"
#import "../../util/WWNLog.h"
#import <IOSurface/IOSurfaceRef.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>
#import <errno.h>
#import <math.h>
#import <pthread.h>
#import <stdatomic.h>
#import <unistd.h>

typedef void (*iland_present_callback_t)(uint32_t crtc_id,
                                         uint32_t fb_id,
                                         IOSurfaceRef surface,
                                         uint32_t flags,
                                         void *user);
extern void iland_drm_set_present_callback(iland_present_callback_t cb, void *user);
extern void iland_drm_set_preferred_mode(uint32_t w, uint32_t h,
                                         uint32_t refresh_millihz);
extern void iland_drm_complete_page_flip(uint32_t crtc_id, uint32_t fb_id);

/*
 * iland wants the mode's refresh in millihertz. Passing 0 makes it assume 60,
 * since it can only query the real rate through CoreGraphics on macOS — so a
 * 120 Hz ProMotion host published a 60 Hz mode and any client pacing off it
 * (Weston's DRM backend does) ran at half the display's cadence. visionOS does
 * not publish a comparable rate, so it stays on auto.
 */
static uint32_t WWNIlandRefreshMillihz(void) {
#if !TARGET_OS_VISION
    NSInteger fps = UIScreen.mainScreen.maximumFramesPerSecond;
    if (fps > 0) return (uint32_t)fps * 1000u;
#endif
    return 0;
}

extern int kmscube_main(int argc, char *argv[]) __attribute__((weak_import));
extern int gbm_es2_demo_main(int argc, char *argv[]) __attribute__((weak_import));
extern int opengl_cube_main(int argc, char *argv[]) __attribute__((weak_import));
extern int vkcube_main(int argc, char *argv[]) __attribute__((weak_import));
/* iland drm_linux.c — write end of the page-flip event pipe (fd 42 read end). */
extern int g_drm_event_pipe_write;
#ifndef DRM_VIRTUAL_FD
#define DRM_VIRTUAL_FD 42
#endif

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

// See the macOS presenter: a GBM ring reuses a handful of IOSurfaces, so
// importing a fresh MTLTexture per present is wasted work on the frame's
// critical path.
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
    // See the macOS presenter: presenting is not cube-exclusive, so this starts
    // neutral and narrows once a known client launches.
    const char             *_presentLogModule;
}

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
    // CSD / transparent host plate: clear+blend with alpha (macOS parity).
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

    // Edge-to-edge nested sizing: feed the host layer's physical-pixel size to
    // the iland DRM shim BEFORE Weston enumerates modes, so the nested output is
    // created at the exact host surface size (no Metal stretch, no 1920x1080
    // fallback). drawableSize is already in physical pixels.
    CGSize px = _layer.drawableSize;
    if (px.width < 1.0 || px.height < 1.0) {
        CGFloat s = _layer.contentsScale > 0.0 ? _layer.contentsScale : 1.0;
        px.width  = _layer.bounds.size.width  * s;
        px.height = _layer.bounds.size.height * s;
    }
    if (px.width >= 1.0 && px.height >= 1.0) {
        iland_drm_set_preferred_mode((uint32_t)(px.width + 0.5),
                                     (uint32_t)(px.height + 0.5),
                                     WWNIlandRefreshMillihz());
    }

    _textureCache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);

    gActivePresenter = self;
    iland_drm_set_present_callback(wwn_iland_present_trampoline, (__bridge void *)self);
    return self;
}

- (void)invalidate {
    iland_drm_set_present_callback(NULL, NULL);
    if (gActivePresenter == self) gActivePresenter = nil;
}

- (void)dealloc {
    if (_textureCache) CFRelease(_textureCache);
}

/*
 * See the macOS presenter: the present callback carries only the IOSurface, so
 * its pixel format is the only statement of what the client rendered, and
 * importing a 10-bit surface as BGRA8Unorm gives wrong colours instead of a
 * diagnosable failure. 0 means "refuse".
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

- (void)syncPreferredModeFromLayer {
    if (!_layer) return;
    CGFloat scale = _layer.contentsScale > 0.0 ? _layer.contentsScale : 1.0;
    CGSize px = CGSizeMake(MAX(1.0, _layer.bounds.size.width * scale),
                           MAX(1.0, _layer.bounds.size.height * scale));
    _layer.drawableSize = px;
    iland_drm_set_preferred_mode((uint32_t)(px.width + 0.5),
                                 (uint32_t)(px.height + 0.5),
                                 WWNIlandRefreshMillihz());
    WWNLog(_presentLogModule ?: "ILAND",
           @"syncPreferredModeFromLayer %.0fx%.0f (scale=%.1f)",
           px.width, px.height, scale);
}

- (void)presentIOSurface:(IOSurfaceRef)surface
                  crtcID:(uint32_t)crtcID
           framebufferID:(uint32_t)framebufferID {
    // CAMetalLayer nextDrawable is unreliable off the main thread on UIKit;
    // hop the whole present so kmscube's render thread does not paint into a
    // nil drawable (permanent black plate).
    if (![NSThread isMainThread]) {
        if (!surface) {
            iland_drm_complete_page_flip(crtcID, framebufferID);
            return;
        }
        CFRetain(surface);
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                CFRelease(surface);
                iland_drm_complete_page_flip(crtcID, framebufferID);
                return;
            }
            [strongSelf presentIOSurface:surface
                                  crtcID:crtcID
                           framebufferID:framebufferID];
            CFRelease(surface);
        });
        return;
    }

    NSUInteger w = IOSurfaceGetWidth(surface);
    NSUInteger h = IOSurfaceGetHeight(surface);
    if (w == 0 || h == 0) {
        iland_drm_complete_page_flip(crtcID, framebufferID);
        return;
    }

    // Host geometry is deliberately NOT touched here. Reading — let alone
    // assigning — CALayer state from the client's render thread races AppKit/
    // UIKit during a resize, and republishing the preferred mode per present was
    // inert regardless: iland applies it when a client enumerates modes, and a
    // stock KMS client enumerates once. -hostGeometryDidChange owns that now.

    // First frames describe the buffer contract; the periodic frames after them
    // are what shows presentation is still running. Logging only the first few
    // made a healthy run look like it stalled at frame 5.
    static int s_presentCount = 0;
    const int kPresentLogPeriod = 300;
    if (s_presentCount < 5 || s_presentCount % kPresentLogPeriod == 0) {
        uint32_t fcc = 0;
        size_t bpr = IOSurfaceGetBytesPerRow(surface);
        IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
        const uint8_t *base = (const uint8_t *)IOSurfaceGetBaseAddress(surface);
        uint32_t px0 = 0;
        if (base && bpr >= 4)
            memcpy(&px0, base, 4);
        IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
        fcc = IOSurfaceGetPixelFormat(surface);
        WWNLog(_presentLogModule ?: "ILAND",
               @"iland present #%d IOSurface %lux%lu fcc=0x%08x px0=0x%08x "
               @"opaque=%d",
               s_presentCount, (unsigned long)w, (unsigned long)h, fcc, px0,
               (int)_layer.opaque);
    }
    // First iland frame: dismiss startup log (Wayland-path notification is
    // never posted for DRM/Metal nested clients).
    if (s_presentCount == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"WWNFirstWaylandFrameNotification"
                              object:nil];
        });
    }
    s_presentCount++;

    id<MTLTexture> srcTex = [self cachedTextureForIOSurface:surface
                                                      width:w
                                                     height:h];
    if (!srcTex) {
        static int s_texFail;
        if (s_texFail++ < 3) {
            WWNLog(_presentLogModule ?: "ILAND",
                   @"Metal IOSurface→texture failed %lux%lu",
                   (unsigned long)w, (unsigned long)h);
        }
        iland_drm_complete_page_flip(crtcID, framebufferID);
        return;
    }

    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    if (!drawable) {
        static int s_drawFail;
        if (s_drawFail++ < 3) {
            WWNLog(_presentLogModule ?: "ILAND",
                   @"Metal nextDrawable nil (layer %.0fx%.0f)",
                   _layer.drawableSize.width, _layer.drawableSize.height);
        }
        iland_drm_complete_page_flip(crtcID, framebufferID);
        return;
    }

    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = drawable.texture;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    // Opaque host plate for kmscube; CSD paths that need alpha keep blending
    // enabled on the pipeline but clear to black so empty frames aren't void.
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc =
        [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:_pipeline];

    // A stock KMS client keeps its startup framebuffer size for the whole run,
    // so after a host resize source and destination extents disagree. Letterbox
    // rather than stretch — a real display scaling a mode it cannot change.
    NSUInteger tw = drawable.texture.width;
    NSUInteger th = drawable.texture.height;
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

    // Complete on GPU finish. Pacing on the drawable's presented handler instead
    // was measured on macOS and halved throughput: iland allows one outstanding
    // flip per CRTC, so waiting for scanout leaves nothing in flight and each
    // frame costs several vblanks. See the macOS presenter.
    [cb addCompletedHandler:^(__unused id<MTLCommandBuffer> completed) {
        iland_drm_complete_page_flip(crtcID, framebufferID);
    }];
    [cb presentDrawable:drawable];
    [cb commit];
}

/// Mirror wayland-mac constructor: pipe → DRM_VIRTUAL_FD so select/poll work
/// for in-process kmscube (Apple mobile has no Dobby open/ioctl hooks).
static BOOL wwn_prepare_iland_virtual_drm_fd(void) {
    if (g_drm_event_pipe_write >= 0) {
        return YES;
    }
    int p[2];
    if (pipe(p) != 0) {
        WWNLog("ILAND", @"pipe() for DRM virtual fd failed errno=%d", errno);
        return NO;
    }
    if (dup2(p[0], DRM_VIRTUAL_FD) < 0) {
        WWNLog("ILAND", @"dup2(DRM_VIRTUAL_FD) failed errno=%d", errno);
        close(p[0]);
        close(p[1]);
        return NO;
    }
    close(p[0]);
    g_drm_event_pipe_write = p[1];
    WWNLog("ILAND", @"prepared iland virtual DRM fd=%d (event pipe)",
           DRM_VIRTUAL_FD);
    return YES;
}

typedef int (*wwn_cube_entry_t)(int argc, char *argv[]);

typedef struct {
    const char *clientId;
    const char *logModule;
    // Extra argv beyond argv[0]; NULL-terminated.
    const char *const *argv;
} wwn_cube_client_t;

// kmscube / gbm-es2-demo drive iland's virtual DRM. opengl-cube and vkcube are Wayland
// clients and are launched through the compositor, not this presenter.
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
               @"%@ unavailable — archive not linked "
               @"(-Wl,-u,_%s_main)", clientId, client->clientId);
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
