#if os(macOS)
import AppKit

@objc(WWNWindow)
public final class WWNWindow: NSWindow, NSWindowDelegate {
    @objc public var wwnWindowId: UInt64 = 0
    @objc public var hostLocked = false
    @objc public var processingResize = false
    @objc public var interactiveResizeInProgress = false
    @objc public var suppressCompositorCallbacks = false
    @objc public var clientSideDecorated = false
    @objc public var wwnLastZoomed = false
    @objc public var wwnMiniaturizeInProgress = false
    @objc public var wwnFullscreenTransitionInProgress = false
    @objc public var lastMouseDownEvent: NSEvent?
    @objc public var prefersFixedSquare = false
    @objc public var fillsHost = false

    @objc(applyPresentationPolicyForServerSideDecorations:)
    public func applyPresentationPolicy(forServerSideDecorations serverSide: Bool) {
        clientSideDecorated = !serverSide
        titlebarAppearsTransparent = clientSideDecorated
        styleMask = serverSide
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.borderless, .resizable]
    }

    @objc public func cancelPendingHostCloseEscalation() {}

    public func windowDidResize(_ notification: Notification) {
        _ = notification
        guard !suppressCompositorCallbacks, !wwnFullscreenTransitionInProgress else { return }
        let size = contentLayoutRect.size
        SeatForwarder.injectConfigure(
            core: WWNCompositorBridge.sharedBridge.core,
            windowId: wwnWindowId,
            width: Int32(size.width),
            height: Int32(size.height)
        )
    }
}
#endif
