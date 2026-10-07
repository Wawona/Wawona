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
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.isOpaque = false
        guard let queue = dev.makeCommandQueue(),
              let pipeline = IlandMetalPipeline.makePipeline(device: dev, pixelFormat: layer.pixelFormat)
        else { return nil }
        self.queue = queue
        self.pipeline = pipeline
        configureEDR(on: layer)
        publishPreferredModeFromLayer()
    }

    func invalidate() {
        IlandDrmBindings.setPresentCallback(nil, nil)
    }

    func syncPreferredModeFromLayer() {
        publishPreferredModeFromLayer()
    }

    #if os(macOS)
    func hostGeometryDidChange() {
        syncPreferredModeFromLayer()
    }
    #endif

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
        ), let drawable = layer.nextDrawable() else {
            IlandDrmBindings.completePageFlip(crtcID, framebufferID)
            return
        }

        draw(source: source, drawable: drawable, bottomUp: true, contentRect: vector_float4(0, 0, 1, 1)) {
            IlandDrmBindings.completePageFlip(crtcID, framebufferID)
        }
    }

    #if os(iOS)
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
        draw(source: source, drawable: drawable, bottomUp: bottomUpRows, contentRect: rect, onComplete: nil)
        return true
    }
    #endif

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
        #if !os(macOS)
        var bottomUpFlag: UInt32 = bottomUp ? 1 : 0
        encoder.setVertexBytes(&bottomUpFlag, length: MemoryLayout<UInt32>.size, index: 0)
        var rect = contentRect
        encoder.setFragmentBytes(&rect, length: MemoryLayout<vector_float4>.size, index: 0)
        #endif

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

    private func configureEDR(on layer: CAMetalLayer) {
        #if !SWIFT_PACKAGE
        let hdr = WWNPreferencesManager.sharedManager().colorOperations()
        if hdr {
            if #available(iOS 16.0, macOS 14.0, visionOS 1.0, *) {
                layer.wantsExtendedDynamicRangeContent = true
                layer.pixelFormat = .rgba16Float
                if let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) {
                    layer.colorspace = cs
                }
            }
        }
        #else
        _ = layer
        #endif
    }
}
#endif
