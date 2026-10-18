#if canImport(Metal) && !os(watchOS)
import SwiftUI
import QuartzCore

/// SwiftUI host for CAMetalLayer compositor output with basic seat forwarding.
public struct CompositorHostView: View {
    private let core: UnsafeMutableRawPointer?

    public init(core: UnsafeMutableRawPointer? = nil) {
        self.core = core
    }

    public var body: some View {
        // Do NOT attach .accessibility(identifier:) on the Representable.
        // SwiftUI invents a 1x1 AX node that shadows the real NSView/UIView
        // (Mac2 element screenshots became 1x1 PNG). Contract id lives on
        // CompositorHostPlatformView only.
        #if os(macOS)
        CompositorHostNSViewRepresentable(core: core)
            .accessibilityElement(children: .contain)
        #elseif os(iOS) || os(tvOS) || os(visionOS)
        CompositorHostUIViewRepresentable(core: core)
            .accessibilityElement(children: .contain)
        #endif
    }
}

#if os(macOS)
import AppKit

private struct CompositorHostNSViewRepresentable: NSViewRepresentable {
    let core: UnsafeMutableRawPointer?

    func makeNSView(context: Context) -> CompositorHostPlatformView {
        let view = CompositorHostPlatformView(core: core ?? WWNCompositorBridge.sharedBridge.core)
        view.ensureIlandPresenter(reason: "makeNSView")
        return view
    }

    func updateNSView(_ nsView: CompositorHostPlatformView, context: Context) {
        nsView.core = core ?? WWNCompositorBridge.sharedBridge.core
        nsView.ensureIlandPresenter(reason: "updateNSView")
    }
}
#endif

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

private struct CompositorHostUIViewRepresentable: UIViewRepresentable {
    let core: UnsafeMutableRawPointer?

    func makeUIView(context: Context) -> CompositorHostPlatformView {
        let view = CompositorHostPlatformView(core: core ?? WWNCompositorBridge.sharedBridge.core)
        view.ensureIlandPresenter(reason: "makeUIView")
        return view
    }

    func updateUIView(_ uiView: CompositorHostPlatformView, context: Context) {
        uiView.core = core ?? WWNCompositorBridge.sharedBridge.core
        uiView.ensureIlandPresenter(reason: "updateUIView")
    }
}
#endif

#if os(macOS)
typealias PlatformView = NSView
typealias PlatformColor = NSColor
#elseif os(iOS) || os(tvOS) || os(visionOS)
typealias PlatformView = UIView
typealias PlatformColor = UIColor
#endif

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
final class CompositorHostPlatformView: PlatformView {
    var core: UnsafeMutableRawPointer?
    private var metalPresenter: MetalPresenter?
    private var ilandPresenter: IlandPresenterObjC?
    private var ensurePresenterObserver: NSObjectProtocol?
    private var didClearProof = false
    #if os(macOS)
    private var trackingArea: NSTrackingArea?
    #endif

    init(core: UnsafeMutableRawPointer?) {
        self.core = core
        #if os(macOS)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PlatformColor.black.cgColor
        // Appium Mac2 binds accessibilityIdentifier on the NSView itself.
        setAccessibilityElement(true)
        setAccessibilityIdentifier("wwn.compositor.surface")
        setAccessibilityLabel("Compositor surface")
        setAccessibilityRole(.image)
        #else
        super.init(frame: .zero)
        backgroundColor = .black
        isAccessibilityElement = true
        accessibilityIdentifier = "wwn.compositor.surface"
        accessibilityLabel = "Compositor surface"
        #endif
        // Build Metal after super.init so a presenter failure cannot abort NSView.
        let presenter = MetalPresenter()
        metalPresenter = presenter
        if let metalLayer = presenter.layer {
            metalLayer.frame = bounds
            #if os(macOS)
            layer?.addSublayer(metalLayer)
            #else
            layer.addSublayer(metalLayer)
            #endif
        }
        ensurePresenterObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("WWNEnsureIlandPresenterNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensureIlandPresenter(reason: "notify")
        }
        ensureIlandPresenter(reason: "init")
    }

    /// Mode A SHM drain needs a live `activePresenterForDrain`. SwiftUI can
    /// recreate this UIView while a sibling deinit clears the process-global
    /// presenter; RelayRunner then posts ShowSessionSurface and churns worse.
    /// Re-arm on every layout / representable update.
    func ensureIlandPresenter(reason: String) {
        WWNCompositorBridge.sharedBridge.containerView = self
        if let existing = ilandPresenter,
           IlandPresenterObjC.activePresenterForDrain() === existing {
            return
        }
        guard let metalLayer = metalPresenter?.layer else {
            NSLog("CompositorHost: ensureIlandPresenter(%@) no CAMetalLayer", reason)
            return
        }
        if let p = IlandPresenterObjC(layer: metalLayer, device: metalPresenter?.device) {
            ilandPresenter = p
            NSLog(
                "CompositorHost: IlandPresenter armed reason=%@ layer=%dx%d",
                reason,
                Int(metalLayer.drawableSize.width),
                Int(metalLayer.drawableSize.height)
            )
            maybePresentClearProof(reason: reason)
        } else {
            NSLog("CompositorHost: IlandPresenter init FAILED reason=%@", reason)
        }
    }

    private func maybePresentClearProof(reason: String) {
        guard !didClearProof else { return }
        guard let metalLayer = metalPresenter?.layer,
              metalLayer.drawableSize.width >= 1,
              metalLayer.drawableSize.height >= 1
        else { return }
        if ilandPresenter?.presentClearProof(reason: reason) == true {
            didClearProof = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    #if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        syncMetalLayerGeometry()
        ensureIlandPresenter(reason: "layoutSubviews")
    }
    #else
    override func layout() {
        super.layout()
        syncMetalLayerGeometry()
        ensureIlandPresenter(reason: "layout")
        // Keep AX frame in sync with Metal bounds for Mac2 screenshots.
        if let window {
            setAccessibilityFrame(window.convertToScreen(convert(bounds, to: nil)))
        }
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let window else { return super.accessibilityHitTest(point) }
        let inWindow = window.convertPoint(fromScreen: point)
        let local = convert(inWindow, from: nil)
        if bounds.contains(local) { return self }
        return super.accessibilityHitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
    #endif

    private func syncMetalLayerGeometry() {
        // Match CompositorView: frame alone leaves drawableSize at 0, so
        // nextDrawable fails, SHM drain frees buffers without frame_done, and
        // waypipe clients stall on a black session surface.
        #if os(macOS)
        var scale = window?.backingScaleFactor ?? 0
        if scale < 1 {
            scale = layer?.contentsScale ?? 0
        }
        if scale < 1 { scale = 2 }
        #else
        var scale = window?.screen.scale ?? 0
        if scale < 1 { scale = contentScaleFactor }
        if scale < 1 { scale = 2 }
        #endif
        if let metalLayer = metalPresenter?.layer {
            metalLayer.contentsScale = scale
            metalLayer.isOpaque = true
        }
        metalPresenter?.resize(bounds.size)
        // Rotation / safe-area changes: publish wl_output mode so clients resize.
        ilandPresenter?.hostGeometryDidChange()
        maybePresentClearProof(reason: "layout")
    }

    #if os(iOS) || os(visionOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        forwardTouches(touches, ended: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        forwardTouches(touches, ended: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        forwardTouches(touches, ended: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        SeatForwarder.injectTouchCancel(core: core)
    }

    private func forwardTouches(_ touches: Set<UITouch>, ended: Bool) {
        let timeMs = UInt32((ProcessInfo.processInfo.systemUptime * 1000).rounded())
        for touch in touches {
            let point = touch.location(in: self)
            let id = Int32(truncatingIfNeeded: touch.hashValue)
            if ended {
                SeatForwarder.injectTouchUp(core: core, timeMs: timeMs, id: id)
            } else if touch.phase == .began {
                SeatForwarder.injectTouchDown(
                    core: core,
                    timeMs: timeMs,
                    id: id,
                    x: point.x,
                    y: point.y
                )
            } else {
                SeatForwarder.injectTouchMotion(
                    core: core,
                    timeMs: timeMs,
                    id: id,
                    x: point.x,
                    y: point.y
                )
            }
        }
    }
    #endif

    #if os(macOS)
    override func mouseMoved(with event: NSEvent) {
        let timeMs = UInt32((ProcessInfo.processInfo.systemUptime * 1000).rounded())
        let point = convert(event.locationInWindow, from: nil)
        SeatForwarder.injectPointerMotion(core: core, windowId: 0, timeMs: timeMs, x: point.x, y: point.y)
    }

    override func mouseDown(with event: NSEvent) {
        injectButton(0, pressed: true, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        injectButton(0, pressed: false, event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        injectButton(1, pressed: true, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        injectButton(1, pressed: false, event: event)
    }

    private func injectButton(_ button: UInt32, pressed: Bool, event: NSEvent) {
        let timeMs = UInt32((ProcessInfo.processInfo.systemUptime * 1000).rounded())
        let point = convert(event.locationInWindow, from: nil)
        SeatForwarder.injectPointerMotion(core: core, windowId: 0, timeMs: timeMs, x: point.x, y: point.y)
        SeatForwarder.injectPointerButton(
            core: core, windowId: 0, timeMs: timeMs, button: button, pressed: pressed)
    }
    #endif

    deinit {
        if let ensurePresenterObserver {
            NotificationCenter.default.removeObserver(ensurePresenterObserver)
        }
        // Only tear down if we still own the process-global. A newer Host may
        // already have re-armed; clearing that would leave Mode A SHM dry.
        if let p = ilandPresenter, IlandPresenterObjC.activePresenterForDrain() === p {
            p.invalidate()
        }
    }
}
#endif
#endif
