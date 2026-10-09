#if canImport(Metal) && !os(watchOS)
import Foundation
import IOSurface
import Metal
import QuartzCore
import simd

enum IlandMetalPipeline {
    static let textureCacheMax = 16

    // Mode A SHM / IOSurface: same Y-flip + content-rect uniforms on every
    // Metal host (macOS used to ignore bottomUp and looked empty/wrong).
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VOut { float4 pos [[position]]; float2 uv; };
    vertex VOut wwn_vs(uint vid [[vertex_id]], constant uint &bottomUp [[buffer(0)]]) {
      float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
      float2 top[4] = { float2(0,0), float2(1,0), float2(0,1), float2(1,1) };
      float2 bottom[4] = { float2(0,1), float2(1,1), float2(0,0), float2(1,0) };
      VOut o; o.pos = float4(p[vid], 0, 1);
      o.uv = bottomUp != 0 ? bottom[vid] : top[vid]; return o;
    }
    fragment float4 wwn_fs(VOut in [[stage_in]],
                           texture2d<float> tex [[texture(0)]],
                           constant float4 &rect [[buffer(0)]]) {
      constexpr sampler s(filter::linear, address::clamp_to_edge);
      return tex.sample(s, rect.xy + in.uv * rect.zw);
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
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
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
