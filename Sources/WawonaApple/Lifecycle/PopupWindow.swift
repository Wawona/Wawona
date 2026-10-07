#if os(macOS)
import AppKit

@objc(WWNPopupWindow)
public final class WWNPopupWindow: NSPanel {
    @objc public init(parentView: NSView) {
        let rect = NSRect(x: 0, y: 0, width: 320, height: 240)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        _ = parentView
    }

    @objc public func dismiss() {
        orderOut(nil)
    }
}
#endif
