#if canImport(Metal) && !os(watchOS)
import Foundation
import IOSurface
import Metal
import QuartzCore

private var activeIlandPresenter: IlandPresenterObjC?

@_silgen_name("WWNCorePopPendingBuffer")
private func WWNCorePopPendingBuffer(_ core: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

@_silgen_name("WWNBufferDataFree")
private func WWNBufferDataFree(_ data: UnsafeMutableRawPointer?)

@_silgen_name("WWNCoreNotifyFramePresented")
private func WWNCoreNotifyFramePresented(
    _ core: UnsafeMutableRawPointer?,
    _ surfaceId: UInt32,
    _ bufferId: UInt64,
    _ timestamp: UInt32
)

@_silgen_name("WWNCoreGetTimestampMs")
private func WWNCoreGetTimestampMs(_ core: UnsafeMutableRawPointer?) -> UInt32

@_silgen_name("WWNCoreFlushClients")
private func WWNCoreFlushClientsDrain(_ core: UnsafeMutableRawPointer?)

/// Field offsets for Rust `#[repr(C)] CBufferData` (64-bit).
private enum CBufferDataLayout {
    static let surfaceId = 8
    static let bufferId = 16
    static let width = 24
    static let height = 28
    static let stride = 32
    static let pixels = 40
    static let iosurfaceId = 64
    static let cpuYFlip = 68
}

/// Drain Wayland SHM / IOSurface pending buffers into the host Metal layer.
/// Android does this in `android_jni.c`. Apple lost the ObjC `WWNView` loop.
private enum CompositorShmPresent {
    static func drain(core: UnsafeMutableRawPointer?, engine: IlandPresentEngine) {
        guard let core else { return }
        var presented = false
        while true {
            guard let raw = WWNCorePopPendingBuffer(core) else { break }
            let base = UnsafeRawPointer(raw)
            let surfaceId = base.load(fromByteOffset: CBufferDataLayout.surfaceId, as: UInt32.self)
            let bufferId = base.load(fromByteOffset: CBufferDataLayout.bufferId, as: UInt64.self)
            let width = Int(base.load(fromByteOffset: CBufferDataLayout.width, as: UInt32.self))
            let height = Int(base.load(fromByteOffset: CBufferDataLayout.height, as: UInt32.self))
            let stride = Int(base.load(fromByteOffset: CBufferDataLayout.stride, as: UInt32.self))
            let iosurfaceId = base.load(fromByteOffset: CBufferDataLayout.iosurfaceId, as: UInt32.self)
            let yFlip = base.load(fromByteOffset: CBufferDataLayout.cpuYFlip, as: UInt8.self) != 0
            let pixels = base.load(
                fromByteOffset: CBufferDataLayout.pixels, as: UnsafeMutablePointer<UInt8>?.self)

            var ok = false
            if iosurfaceId != 0, let surface = IOSurfaceLookup(IOSurfaceID(iosurfaceId)) {
                ok = engine.presentCompositorIOSurface(
                    surface,
                    bottomUpRows: yFlip,
                    normalizedContentRect: CGRect(x: 0, y: 0, width: 1, height: 1)
                )
            } else if let pixels, width > 0, height > 0, stride > 0 {
                ok = engine.presentBGRAPixels(
                    width: width,
                    height: height,
                    stride: stride,
                    pixels: pixels,
                    bottomUp: yFlip
                )
            }
            if ok {
                WWNCoreNotifyFramePresented(
                    core, surfaceId, bufferId, WWNCoreGetTimestampMs(core))
                presented = true
            }
            WWNBufferDataFree(raw)
        }
        if presented {
            WWNCoreFlushClientsDrain(core)
        }
    }
}

extension IlandPresenterObjC {
    /// Used by the compositor event pump to drain SHM frames.
    @objc public static func activePresenterForDrain() -> IlandPresenterObjC? {
        activeIlandPresenter
    }
}

private func ilandPresentTrampoline(
    crtcID: UInt32,
    framebufferID: UInt32,
    surface: IOSurface?,
    flags: UInt32,
    user: UnsafeMutableRawPointer?
) {
    _ = flags
    _ = user
    autoreleasepool {
        guard let presenter = activeIlandPresenter, let surface else {
            IlandDrmBindings.completePageFlip(crtcID, framebufferID)
            return
        }
        presenter.engine?.presentIOSurface(surface, crtcID: crtcID, framebufferID: framebufferID)
    }
}

@objc(WWNIlandPresenter)
public final class IlandPresenterObjC: NSObject {
    fileprivate var engine: IlandPresentEngine?
    private var clientThread: pthread_t?
    private var clientThreadStarted = false
    private var clientWidth = 1280
    private var clientHeight = 720
    private var clientId: String?

    @objc(initWithLayer:device:)
    public init?(layer: CAMetalLayer, device: MTLDevice?) {
        guard let engine = IlandPresentEngine(layer: layer, device: device) else { return nil }
        super.init()
        self.engine = engine
        activeIlandPresenter = self
        IlandDrmBindings.setPresentCallback(ilandPresentTrampoline, nil)
    }

    @objc
    public func invalidate() {
        IlandDrmBindings.setPresentCallback(nil, nil)
        if activeIlandPresenter === self {
            activeIlandPresenter = nil
        }
        engine?.invalidate()
    }

    #if os(macOS)
    @objc
    public func hostGeometryDidChange() {
        engine?.hostGeometryDidChange()
    }
    #endif

    @objc
    public func syncPreferredModeFromLayer() {
        engine?.syncPreferredModeFromLayer()
    }

    @objc(presentCompositorIOSurface:bottomUpRows:contentRect:)
    public func presentCompositorIOSurface(
        _ surface: IOSurface,
        bottomUpRows: Bool,
        contentRect: CGRect
    ) -> Bool {
        engine?.presentCompositorIOSurface(
            surface,
            bottomUpRows: bottomUpRows,
            normalizedContentRect: contentRect
        ) ?? false
    }

    @objc(drainPendingBuffersFromCore:)
    public func drainPendingBuffers(fromCore core: UnsafeMutableRawPointer?) {
        guard let engine else { return }
        CompositorShmPresent.drain(core: core, engine: engine)
    }

    @objc(launchNestedIlandGpuClient:width:height:)
    public func launchNestedIlandGpuClient(_ clientId: String, width: Int32, height: Int32) -> Bool {
        guard let client = IlandNestedGpuClients.client(for: clientId) else { return false }
        guard IlandNestedGpuClients.entry(for: clientId) != nil else { return false }
        if clientThreadStarted {
            return self.clientId == clientId
        }
        guard IlandNestedGpuClients.prepareVirtualDrmFd() else { return false }
        self.clientId = clientId
        engine?.presentLogModule = client.logModule
        clientWidth = width > 0 ? Int(width) : 1280
        clientHeight = height > 0 ? Int(height) : 720
        var thread: pthread_t?
        let rc = pthread_create(&thread, nil, { raw in
            let presenter = Unmanaged<IlandPresenterObjC>.fromOpaque(raw).takeUnretainedValue()
            if let id = presenter.clientId {
                IlandNestedGpuClients.runClient(id: id, logModule: presenter.engine?.presentLogModule ?? "ILAND")
            }
            return nil
        }, Unmanaged.passUnretained(self).toOpaque())
        if rc != 0 {
            return false
        }
        clientThread = thread
        clientThreadStarted = true
        return true
    }

    @objc
    public func runningClientId() -> String? {
        clientThreadStarted ? clientId : nil
    }

    @objc(launchNestedKmscubeWithWidth:height:)
    public func launchNestedKmscube(width: Int32, height: Int32) -> Bool {
        launchNestedIlandGpuClient("kmscube", width: width, height: height)
    }
}
#endif
