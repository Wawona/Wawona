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
#import <IOSurface/IOSurfaceRef.h>
#import <pthread.h>

typedef void (*iland_present_callback_t)(uint32_t crtc_id,
                                         uint32_t fb_id,
                                         IOSurfaceRef surface,
                                         uint32_t flags,
                                         void *user);
extern void iland_drm_set_present_callback(iland_present_callback_t cb, void *user);
extern void iland_drm_set_preferred_mode(uint32_t w, uint32_t h, uint32_t refresh);

extern int kmscube_main(int argc, char *argv[]) __attribute__((weak_import));

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
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [lib newFunctionWithName:@"wwn_vs"];
    pd.fragmentFunction = [lib newFunctionWithName:@"wwn_fs"];
    pd.colorAttachments[0].pixelFormat = _layer.pixelFormat;
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
                                     (uint32_t)(px.height + 0.5), 0);
    }

    gActivePresenter = self;
    iland_drm_set_present_callback(wwn_iland_present_trampoline, (__bridge void *)self);
    return self;
}

- (void)invalidate {
    iland_drm_set_present_callback(NULL, NULL);
    if (gActivePresenter == self) gActivePresenter = nil;
}

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
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
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

static void *wwn_kmscube_thread(void *arg) {
    WWNIlandPresenter *self = (__bridge WWNIlandPresenter *)arg;
    (void)self->_clientWidth;
    (void)self->_clientHeight;
    char *argv[] = { (char *)"kmscube", NULL };
    kmscube_main(1, argv);
    return NULL;
}

- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height {
    if (kmscube_main == NULL) {
        NSLog(@"[iland] kmscube_main unavailable (link libkmscube.a)");
        return NO;
    }
    if (_clientThreadStarted) return YES;
    _clientWidth = width > 0 ? width : 1280;
    _clientHeight = height > 0 ? height : 720;
    int rc = pthread_create(&_clientThread, NULL, wwn_kmscube_thread,
                            (__bridge void *)self);
    if (rc != 0) {
        NSLog(@"[iland] pthread_create failed: %d", rc);
        return NO;
    }
    _clientThreadStarted = YES;
    return YES;
}

@end
