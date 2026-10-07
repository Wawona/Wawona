#if canImport(Metal) && !os(watchOS)
import Foundation
import IOSurface
import Metal
import QuartzCore

private var activeIlandPresenter: IlandPresenterObjC?

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

    #if os(iOS)
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
    #endif

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
