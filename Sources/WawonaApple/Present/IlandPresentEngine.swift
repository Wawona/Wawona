#if canImport(Metal) && !os(watchOS)
import CoreGraphics
import Foundation
import IOSurface
import Metal
import QuartzCore
import simd
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class IlandPresentEngine {
    let layer: CAMetalLayer
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    var textureCache: [IOSurface: MTLTexture] = [:]
    var presentLogModule = "ILAND"
    private var presentCount = 0
    /// Downscaled PNG of the last guest frame for Machines / Tab Overview.
    private(set) var lastThumbnailPNG: Data?

    init?(layer: CAMetalLayer, device: MTLDevice?) {
        guard let dev = device ?? layer.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        self.layer = layer
        self.device = dev
        layer.device = dev
        // SDR host present by default. Do not force rgba16Float / EDR from
        // Settings Color Operations. Clients negotiate via wp_color_manager_v1;
        // Metal EDR only follows HDR content (see maybeEnableEDRForHDRContent).
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        // Opaque once a guest frame exists. Stay invisible until then: a
        // clear-only present is not a Wayland frame and reads as a stuck plate
        // on every Apple host that shares this layer.
        layer.isOpaque = true
        layer.opacity = 0
        #if !os(tvOS)
        if #available(iOS 16.0, macOS 14.0, visionOS 1.0, *) {
            layer.wantsExtendedDynamicRangeContent = false
        }
        #endif
        guard let queue = dev.makeCommandQueue(),
              let pipeline = IlandMetalPipeline.makePipeline(device: dev, pixelFormat: layer.pixelFormat)
        else { return nil }
        self.queue = queue
        self.pipeline = pipeline
        publishPreferredModeFromLayer()
    }

    /// Layout arm: drawable is large enough for a later guest present.
    /// Does not call `nextDrawable` or `present`. A clear plate is not a frame.
    func presentClearProof(reason: String) -> Bool {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                _ = self?.presentClearProof(reason: reason)
            }
            return false
        }
        publishPreferredModeFromLayer()
        let dw = layer.drawableSize.width
        let dh = layer.drawableSize.height
        guard dw >= 1, dh >= 1 else {
            NSLog(
                "[\(presentLogModule)] layerReady FAIL reason=\(reason) drawable=\(Int(dw))x\(Int(dh))"
            )
            return false
        }
        NSLog(
            "[\(presentLogModule)] layerReady reason=\(reason) drawable=\(Int(dw))x\(Int(dh)) (no clear present)"
        )
        return true
    }

    func invalidate() {
        IlandDrmBindings.setPresentCallback(nil, nil)
    }

    func syncPreferredModeFromLayer() {
        publishPreferredModeFromLayer()
    }

    func hostGeometryDidChange() {
        syncPreferredModeFromLayer()
    }

    func presentIOSurface(_ surface: IOSurface, crtcID: UInt32, framebufferID: UInt32) {
        #if WWN_MODE_B
        if IlandModeBPresent.routeIfActive(surface: surface, crtcID: crtcID, framebufferID: framebufferID) {
            return
        }
        #endif
        #if os(iOS)
        if !Thread.isMainThread {
            let retained = surface
            DispatchQueue.main.async { [weak self] in
                self?.presentIOSurface(retained, crtcID: crtcID, framebufferID: framebufferID)
            }
            return
        }
        #endif

        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        guard width > 0, height > 0 else {
            IlandDrmBindings.completePageFlip(crtcID, framebufferID)
            return
        }

        logPresentIfNeeded(surface: surface, width: width, height: height)

        guard let source = IlandMetalPipeline.cachedTexture(
            device: device,
            cache: &textureCache,
            surface: surface,
            width: width,
            height: height
        ) else {
            NSLog("[\(presentLogModule)] presentIOSurface texture FAIL \(width)x\(height)")
            IlandDrmBindings.completePageFlip(crtcID, framebufferID)
            return
        }
        guard let drawable = layer.nextDrawable() else {
            struct Once { static var logged = false }
            if !Once.logged {
                Once.logged = true
                NSLog(
                    "[\(presentLogModule)] nextDrawable FAIL drawable=\(Int(layer.drawableSize.width))x\(Int(layer.drawableSize.height))"
                )
            }
            IlandDrmBindings.completePageFlip(crtcID, framebufferID)
            return
        }

        maybeEnableEDRForHDRContent(sourceFormat: source.pixelFormat)
        // Top-down DRM/IOSurface → Metal V remap (bottomUp UV).
        draw(source: source, drawable: drawable, bottomUp: true, contentRect: vector_float4(0, 0, 1, 1)) {
            IlandDrmBindings.completePageFlip(crtcID, framebufferID)
        }
    }

    func presentCompositorIOSurface(
        _ surface: IOSurface,
        bottomUpRows: Bool,
        normalizedContentRect: CGRect
    ) -> Bool {
        #if WWN_MODE_B
        if IlandModeBPresent.presentCompositorOnly(surface: surface) {
            return true
        }
        #endif
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                _ = self?.presentCompositorIOSurface(
                    surface,
                    bottomUpRows: bottomUpRows,
                    normalizedContentRect: normalizedContentRect
                )
            }
            return true
        }
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        guard let source = IlandMetalPipeline.cachedTexture(
            device: device,
            cache: &textureCache,
            surface: surface,
            width: width,
            height: height
        ), let drawable = layer.nextDrawable() else {
            return false
        }
        let rect = vector_float4(
            Float(normalizedContentRect.origin.x),
            Float(normalizedContentRect.origin.y),
            Float(normalizedContentRect.size.width),
            Float(normalizedContentRect.size.height)
        )
        maybeEnableEDRForHDRContent(sourceFormat: source.pixelFormat)
        draw(source: source, drawable: drawable, bottomUp: bottomUpRows, contentRect: rect, onComplete: nil)
        return true
    }

    /// CPU SHM path (`wl_shm`). Wayland ARGB8888 on LE is BGRA bytes.
    func presentBGRAPixels(
        width: Int,
        height: Int,
        stride: Int,
        pixels: UnsafeMutablePointer<UInt8>,
        bottomUp: Bool
    ) -> Bool {
        if !Thread.isMainThread {
            let byteCount = stride * height
            let copy = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
            copy.update(from: pixels, count: byteCount)
            DispatchQueue.main.async { [weak self] in
                _ = self?.presentBGRAPixels(
                    width: width, height: height, stride: stride, pixels: copy, bottomUp: bottomUp)
                copy.deallocate()
            }
            return true
        }
        guard width > 0, height > 0, stride >= width * 4 else { return false }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let source = device.makeTexture(descriptor: descriptor) else { return false }
        guard let drawable = layer.nextDrawable() else {
            struct Once { static var logged = false }
            if !Once.logged {
                Once.logged = true
                NSLog(
                    "[\(presentLogModule)] presentBGRA nextDrawable FAIL drawable=\(Int(layer.drawableSize.width))x\(Int(layer.drawableSize.height))"
                )
            }
            return false
        }
        source.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: stride
        )
        cacheThumbnailPNG(
            width: width,
            height: height,
            stride: stride,
            pixels: UnsafePointer(pixels),
            bottomUp: bottomUp
        )
        draw(
            source: source,
            drawable: drawable,
            bottomUp: bottomUp,
            contentRect: vector_float4(0, 0, 1, 1),
            onComplete: nil
        )
        return true
    }

    /// Nearest-neighbor downscale of BGRA8888 into a PNG for card banners.
    private func cacheThumbnailPNG(
        width: Int,
        height: Int,
        stride: Int,
        pixels: UnsafePointer<UInt8>,
        bottomUp: Bool
    ) {
        guard width > 0, height > 0, stride >= width * 4 else { return }
        let maxEdge = 320
        let scale = min(1.0, Double(maxEdge) / Double(max(width, height)))
        let outW = max(1, Int((Double(width) * scale).rounded(.down)))
        let outH = max(1, Int((Double(height) * scale).rounded(.down)))
        var out = [UInt8](repeating: 0, count: outW * outH * 4)
        for y in 0..<outH {
            let srcY: Int
            if bottomUp {
                let mapped = Int((Double(y) + 0.5) * Double(height) / Double(outH))
                srcY = min(height - 1, max(0, height - 1 - mapped))
            } else {
                srcY = min(height - 1, Int((Double(y) + 0.5) * Double(height) / Double(outH)))
            }
            for x in 0..<outW {
                let srcX = min(width - 1, Int((Double(x) + 0.5) * Double(width) / Double(outW)))
                let src = srcY * stride + srcX * 4
                let dst = (y * outW + x) * 4
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
                out[dst + 3] = pixels[src + 3]
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: &out,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let image = ctx.makeImage() else {
            return
        }
        #if canImport(UIKit)
        lastThumbnailPNG = UIImage(cgImage: image).pngData()
        #elseif canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: image)
        lastThumbnailPNG = rep.representation(using: .png, properties: [:])
        #endif
    }

    private func draw(
        source: MTLTexture,
        drawable: CAMetalDrawable,
        bottomUp: Bool,
        contentRect: vector_float4,
        onComplete: (() -> Void)?
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        pass.colorAttachments[0].storeAction = .store

        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else {
            onComplete?()
            return
        }

        encoder.setRenderPipelineState(pipeline)
        // bottomUp=true → Metal UV map for Wayland top-down rows (row0=top).
        // bottomUp=false → nested weston GL already Y-corrected for Wayland.
        var bottomUpFlag: UInt32 = bottomUp ? 1 : 0
        encoder.setVertexBytes(&bottomUpFlag, length: MemoryLayout<UInt32>.size, index: 0)
        var rect = contentRect
        encoder.setFragmentBytes(&rect, length: MemoryLayout<vector_float4>.size, index: 0)

        let tw = drawable.texture.width
        let th = drawable.texture.height
        if tw > 0, th > 0, tw != source.width || th != source.height {
            encoder.setViewport(
                IlandMetalPipeline.letterboxViewport(
                    targetWidth: tw,
                    targetHeight: th,
                    sourceWidth: source.width,
                    sourceHeight: source.height
                )
            )
        }

        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        if let onComplete {
            commands.addCompletedHandler { _ in onComplete() }
        }
        layer.opacity = 1
        commands.present(drawable)
        commands.commit()
    }

    private func publishPreferredModeFromLayer() {
        var px = layer.drawableSize
        if px.width < 1 || px.height < 1 {
            let scale = layer.contentsScale > 0 ? layer.contentsScale : 1
            px = CGSize(width: layer.bounds.width * scale, height: layer.bounds.height * scale)
        }
        guard px.width >= 1, px.height >= 1 else { return }
        layer.drawableSize = px
        #if os(macOS)
        let refresh = IlandDrmBindings.refreshMillihz(for: layer)
        #else
        let refresh = IlandDrmBindings.refreshMillihz()
        #endif
        IlandDrmBindings.setPreferredMode(
            UInt32(px.width.rounded()),
            UInt32(px.height.rounded()),
            refresh
        )
    }

    private func logPresentIfNeeded(surface: IOSurface, width: Int, height: Int) {
        let period = 300
        if presentCount == 0 {
            NotificationCenter.default.post(
                name: Notification.Name("WWNFirstWaylandFrameNotification"),
                object: nil
            )
        }
        if presentCount < 5 || presentCount % period == 0 {
            NSLog("[\(presentLogModule)] iland present #\(presentCount) \(width)x\(height)")
        }
        presentCount += 1
        _ = surface
    }

    /// Enable Metal EDR only when the presented buffer is an HDR pixel format
    /// and Settings still allows color operations. Never force EDR for SDR
    /// clients just because Color Operations is on.
    func maybeEnableEDRForHDRContent(sourceFormat: MTLPixelFormat) {
        #if !SWIFT_PACKAGE && !os(tvOS)
        let allow = WWNPreferencesManager.sharedManager().colorOperations()
        let isHDR: Bool = {
            switch sourceFormat {
            case .rgba16Float, .rgba32Float, .bgr10_xr, .bgr10_xr_srgb, .bgra10_xr, .bgra10_xr_srgb:
                return true
            default:
                return false
            }
        }()
        if #available(iOS 16.0, macOS 14.0, visionOS 1.0, *) {
            let wantEDR = allow && isHDR
            if layer.wantsExtendedDynamicRangeContent != wantEDR {
                layer.wantsExtendedDynamicRangeContent = wantEDR
            }
            if wantEDR {
                if let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) {
                    layer.colorspace = cs
                }
            }
        }
        #else
        _ = sourceFormat
        #endif
    }
}
#endif
