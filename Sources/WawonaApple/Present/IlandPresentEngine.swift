#if canImport(Metal) && !os(watchOS)
import Foundation
import IOSurface
import Metal
import QuartzCore
import simd

final class IlandPresentEngine {
    let layer: CAMetalLayer
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    var textureCache: [IOSurface: MTLTexture] = [:]
    var presentLogModule = "ILAND"
    private var presentCount = 0

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
        // Opaque: translucent CAMetalLayer + never-presented drawable reads as
        // empty black under SwiftUI. Host compositor present is always opaque.
        layer.isOpaque = true
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

    /// Prove Metal can present without a Wayland/SHM client (layout arm).
    /// Deep teal is never guest black, so a blank session is distinguishable.
    func presentClearProof(reason: String) -> Bool {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                _ = self?.presentClearProof(reason: reason)
            }
            return true
        }
        publishPreferredModeFromLayer()
        let dw = layer.drawableSize.width
        let dh = layer.drawableSize.height
        guard dw >= 1, dh >= 1, let drawable = layer.nextDrawable() else {
            NSLog(
                "[\(presentLogModule)] clearProof FAIL reason=\(reason) drawable=\(Int(dw))x\(Int(dh))"
            )
            return false
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        // Deep teal (not guest black). Proves CAMetalLayer + nextDrawable.
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.05, 0.22, 0.28, 1)
        pass.colorAttachments[0].storeAction = .store
        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return false }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        NSLog(
            "[\(presentLogModule)] clearProof OK reason=\(reason) drawable=\(Int(dw))x\(Int(dh))"
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
        draw(
            source: source,
            drawable: drawable,
            bottomUp: bottomUp,
            contentRect: vector_float4(0, 0, 1, 1),
            onComplete: nil
        )
        return true
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
