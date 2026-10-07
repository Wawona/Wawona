#if canImport(Metal) && (os(macOS) || os(iOS)) && !os(watchOS)
import SwiftUI
import QuartzCore

/// SwiftUI host for CAMetalLayer compositor output with basic seat forwarding.
public struct CompositorHostView: View {
    private let core: UnsafeMutableRawPointer?

    public init(core: UnsafeMutableRawPointer? = nil) {
        self.core = core
    }

    public var body: some View {
        #if os(macOS)
        CompositorHostNSViewRepresentable(core: core)
        #elseif os(iOS)
        CompositorHostUIViewRepresentable(core: core)
        #endif
    }
}

#if os(macOS)
import AppKit

private struct CompositorHostNSViewRepresentable: NSViewRepresentable {
    let core: UnsafeMutableRawPointer?

    func makeNSView(context: Context) -> CompositorHostPlatformView {
        CompositorHostPlatformView(core: core)
    }

    func updateNSView(_ nsView: CompositorHostPlatformView, context: Context) {
        nsView.core = core
    }
}
#endif

#if os(iOS)
import UIKit

private struct CompositorHostUIViewRepresentable: UIViewRepresentable {
    let core: UnsafeMutableRawPointer?

    func makeUIView(context: Context) -> CompositorHostPlatformView {
        CompositorHostPlatformView(core: core)
    }

    func updateUIView(_ uiView: CompositorHostPlatformView, context: Context) {
        uiView.core = core
    }
}
#endif

#if os(macOS)
typealias PlatformView = NSView
typealias PlatformColor = NSColor
#elseif os(iOS)
typealias PlatformView = UIView
typealias PlatformColor = UIColor
#endif

#if os(macOS) || os(iOS)
final class CompositorHostPlatformView: PlatformView {
    var core: UnsafeMutableRawPointer?
    private let metalPresenter = MetalPresenter()
    private var ilandPresenter: IlandPresenterObjC?
    #if os(macOS)
    private var trackingArea: NSTrackingArea?
    #endif

    init(core: UnsafeMutableRawPointer?) {
        self.core = core
        #if os(macOS)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PlatformColor.black.cgColor
        #else
        super.init(frame: .zero)
        backgroundColor = .black
        #endif
        if let metalLayer = metalPresenter.layer {
            metalLayer.frame = bounds
            #if os(macOS)
            layer?.addSublayer(metalLayer)
            #else
            layer.addSublayer(metalLayer)
            #endif
            ilandPresenter = IlandPresenterObjC(layer: metalLayer, device: metalPresenter.device)
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
    }
    #else
    override func layout() {
        super.layout()
        syncMetalLayerGeometry()
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
        metalPresenter.layer?.frame = bounds
        #if os(macOS)
        ilandPresenter?.hostGeometryDidChange()
        #else
        ilandPresenter?.syncPreferredModeFromLayer()
        #endif
    }

    #if os(iOS)
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
        ilandPresenter?.invalidate()
    }
}
#endif
#endif
