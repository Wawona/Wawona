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
#import <IOSurface/IOSurfaceRef.h>
#import <errno.h>
#import <pthread.h>
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
extern int g_drm_event_pipe_write;
#ifndef DRM_VIRTUAL_FD
#define DRM_VIRTUAL_FD 42
#endif

// In-process kmscube entry point (libkmscube.a, main renamed via -Dmain=).
// Weakly imported so the app links even without the GL-clients package.
extern int kmscube_main(int argc, char *argv[]) __attribute__((weak_import));

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

@implementation WWNIlandPresenter {
    CAMetalLayer            *_layer;
    id<MTLDevice>            _device;
    id<MTLCommandQueue>      _queue;
    id<MTLRenderPipelineState> _pipeline;
    pthread_t               _clientThread;
    BOOL                    _clientThreadStarted;
    int                     _clientWidth;
    int                     _clientHeight;
}

// Single active presenter for the C trampoline (one nested client at a time).
static WWNIlandPresenter *gActivePresenter = nil;

static void wwn_iland_present_trampoline(uint32_t crtc_id, uint32_t fb_id,
                                         IOSurfaceRef surface, uint32_t flags,
                                         void *user) {
    (void)crtc_id; (void)fb_id; (void)flags; (void)user;
    @autoreleasepool {
        WWNIlandPresenter *p = gActivePresenter;
        if (p && surface) {
            [p presentIOSurface:surface];
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

    gActivePresenter = self;
    iland_drm_set_present_callback(wwn_iland_present_trampoline, (__bridge void *)self);
    return self;
}

- (void)invalidate {
    iland_drm_set_present_callback(NULL, NULL);
    if (gActivePresenter == self) gActivePresenter = nil;
}

// Wrap the presented IOSurface as a Metal texture and draw it into the layer.
- (void)presentIOSurface:(IOSurfaceRef)surface {
    NSUInteger w = IOSurfaceGetWidth(surface);
    NSUInteger h = IOSurfaceGetHeight(surface);
    if (w == 0 || h == 0) return;

    MTLTextureDescriptor *td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                            width:w
                                                           height:h
                                                        mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;

    id<MTLTexture> srcTex = [_device newTextureWithDescriptor:td
                                                    iosurface:surface
                                                        plane:0];
    if (!srcTex) return;

    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    if (!drawable) return;

    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = drawable.texture;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc =
        [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:_pipeline];
    [enc setFragmentTexture:srcTex atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];
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

static void *wwn_kmscube_thread(void *arg) {
    WWNIlandPresenter *self = (__bridge WWNIlandPresenter *)arg;
    (void)self->_clientWidth;
    (void)self->_clientHeight;
    if (!wwn_prepare_iland_virtual_drm_fd()) {
        WWNLog("KMSCUBE", @"aborting kmscube_main — virtual DRM fd not ready");
        return NULL;
    }
    // kmscube reads /dev/dri/card0 (iland's virtual DRM) by default.
    char *argv[] = { (char *)"kmscube", NULL };
    WWNLog("KMSCUBE", @"kmscube_main enter (iland DRM present)");
    int rc = kmscube_main(1, argv);
    WWNLog("KMSCUBE", @"kmscube_main exit rc=%d", rc);
    return NULL;
}

- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height {
    if (kmscube_main == NULL) {
        WWNLog("KMSCUBE", @"kmscube_main unavailable (link libkmscube.a)");
        return NO;
    }
    if (_clientThreadStarted) return YES;
    if (!wwn_prepare_iland_virtual_drm_fd()) {
        WWNLog("KMSCUBE", @"virtual DRM fd prepare failed");
        return NO;
    }
    _clientWidth = width > 0 ? width : 1280;
    _clientHeight = height > 0 ? height : 720;
    int rc = pthread_create(&_clientThread, NULL, wwn_kmscube_thread,
                            (__bridge void *)self);
    if (rc != 0) {
        WWNLog("KMSCUBE", @"pthread_create failed: %d", rc);
        return NO;
    }
    _clientThreadStarted = YES;
    WWNLog("KMSCUBE", @"started in-process kmscube %dx%d via iland",
           _clientWidth, _clientHeight);
    return YES;
}

@end
