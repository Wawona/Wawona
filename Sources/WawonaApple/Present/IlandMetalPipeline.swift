#if canImport(Metal) && !os(watchOS)
import Foundation
import IOSurface
import Metal
import QuartzCore
import simd

enum IlandMetalPipeline {
    static let textureCacheMax = 16

    // Wayland SHM / top-down IOSurface: row0 = image top. Metal NDC y=-1 is
    // viewport bottom, so upright present uses the `waylandTopDown` UV map
    // (historical uniform name: bottomUp). Nested weston GL that already
    // Y-corrected for Wayland passes bottomUp=0.
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VOut { float4 pos [[position]]; float2 uv; };
    vertex VOut wwn_vs(uint vid [[vertex_id]], constant uint &bottomUp [[buffer(0)]]) {
      float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
      // Identity UV in clip space (wrong for Wayland top-down → upside-down).
      float2 alreadyCorrected[4] = { float2(0,0), float2(1,0), float2(0,1), float2(1,1) };
      // Map texture top (v=0) to viewport top (ndc y=+1).
      float2 waylandTopDown[4] = { float2(0,1), float2(1,1), float2(0,0), float2(1,0) };
      VOut o; o.pos = float4(p[vid], 0, 1);
      o.uv = bottomUp != 0 ? waylandTopDown[vid] : alreadyCorrected[vid]; return o;
    }
    fragment float4 wwn_fs(VOut in [[stage_in]],
                           texture2d<float> tex [[texture(0)]],
                           constant float4 &rect [[buffer(0)]]) {
      constexpr sampler s(filter::linear, address::clamp_to_edge);
      float4 c = tex.sample(s, rect.xy + in.uv * rect.zw);
      // wl_shm XRGB / many clients leave A=0. With srcAlpha blend that
      // composites to clear black and the session surface stays empty.
      return float4(c.rgb, 1.0);
    }
    """

    private static func fourCC(_ s: String) -> UInt32 {
        var value: UInt32 = 0
        for (index, byte) in s.utf8.prefix(4).enumerated() {
            value |= UInt32(byte) << (8 * index)
        }
        return value
    }

    static func metalFormat(forFourCC fourcc: UInt32) -> MTLPixelFormat {
        switch fourcc {
        case fourCC("BGRA"):
            return .bgra8Unorm
        case fourCC("l10r"):
            return .bgr10a2Unorm
        case fourCC("w30r"):
            return .bgr10_xr
        case fourCC("l64r"):
            return .rgba16Unorm
        case fourCC("RGhA"):
            return .rgba16Float
        case fourCC("RGfA"):
            return .rgba32Float
        default:
            return .invalid
        }
    }

    static func makePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "wwn_vs")
            descriptor.fragmentFunction = library.makeFunction(name: "wwn_fs")
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            // Opaque host present. srcAlpha + A=0 SHM was painting black.
            descriptor.colorAttachments[0].isBlendingEnabled = false
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("[iland] pipeline failed: \(error)")
            return nil
        }
    }

    static func cachedTexture(
        device: MTLDevice,
        cache: inout [IOSurface: MTLTexture],
        surface: IOSurface,
        width: Int,
        height: Int
    ) -> MTLTexture? {
        let fourcc = IOSurfaceGetPixelFormat(surface)
        let fmt = metalFormat(forFourCC: fourcc)
        guard fmt != .invalid else { return nil }

        if let cached = cache[surface],
           cached.width == width,
           cached.height == height,
           cached.pixelFormat == fmt
        {
            return cached
        }

        if cache.count >= textureCacheMax {
            cache.removeAll(keepingCapacity: true)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fmt,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0)
        else { return nil }
        cache[surface] = texture
        return texture
    }

    static func letterboxViewport(
        targetWidth: Int,
        targetHeight: Int,
        sourceWidth: Int,
        sourceHeight: Int
    ) -> MTLViewport {
        let tw = Double(targetWidth)
        let th = Double(targetHeight)
        let w = Double(sourceWidth)
        let h = Double(sourceHeight)
        let scale = min(tw / w, th / h)
        let fitW = w * scale
        let fitH = h * scale
        return MTLViewport(
            originX: (tw - fitW) * 0.5,
            originY: (th - fitH) * 0.5,
            width: fitW,
            height: fitH,
            znear: 0,
            zfar: 1
        )
    }
}
#endif
