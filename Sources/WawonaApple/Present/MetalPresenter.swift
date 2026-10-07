#if canImport(Metal) && !os(watchOS)
import Foundation
import Metal
import QuartzCore

/// Metal present helpers for iland DRM. Full ObjC API lives in `WWNIlandPresenter` (Swift).
@MainActor
public final class MetalPresenter {
    public private(set) var device: MTLDevice?
    public private(set) var layer: CAMetalLayer?

    public init() {
        device = MTLCreateSystemDefaultDevice()
        if let device {
            let metalLayer = CAMetalLayer()
            metalLayer.device = device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = false
            layer = metalLayer
        }
    }

    public func attach(to hostLayer: CALayer) {
        guard let layer else { return }
        layer.frame = hostLayer.bounds
        layer.contentsScale = hostLayer.contentsScale
        hostLayer.addSublayer(layer)
    }

    public func setPreferredMode(width: Int, height: Int, refreshMillihz: UInt32 = 60_000) {
        IlandDrmBindings.setPreferredMode(UInt32(width), UInt32(height), refreshMillihz)
        layer?.drawableSize = CGSize(width: width, height: height)
    }

    public func resize(_ size: CGSize) {
        guard let layer else { return }
        layer.frame = CGRect(origin: .zero, size: size)
        let scale = layer.contentsScale > 0 ? layer.contentsScale : 1
        layer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        setPreferredMode(width: Int(layer.drawableSize.width), height: Int(layer.drawableSize.height))
    }

    @objc
    public func makeIlandPresenter() -> IlandPresenterObjC? {
        guard let layer, let device else { return nil }
        return IlandPresenterObjC(layer: layer, device: device)
    }
}
#else
import Foundation

@MainActor
public final class MetalPresenter {
    public init() {}
    public func setPreferredMode(width: Int, height: Int, refreshMillihz: UInt32 = 60_000) {
        _ = width
        _ = height
        _ = refreshMillihz
    }
    public func resize(_ size: CGSize) { _ = size }
}
#endif
