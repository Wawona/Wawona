import Foundation

/// Extra inject helpers used by WWNCompositorBridge / views.
extension SeatForwarder {
    public enum TouchPhase {
        case down, motion, up
    }

    public static func injectPointer(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        x: Double,
        y: Double,
        timestampMs: UInt32
    ) {
        injectPointerMotion(core: core, windowId: windowId, timeMs: timestampMs, x: x, y: y)
    }

    public static func injectButton(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        button: UInt32,
        pressed: Bool,
        timestampMs: UInt32
    ) {
        injectPointerButton(
            core: core, windowId: windowId, timeMs: timestampMs, button: button, pressed: pressed)
    }

    public static func injectAxis(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        axis: UInt32,
        value: Double,
        discrete: Int32,
        timestampMs: UInt32
    ) {
        _ = discrete
        injectPointerAxis(
            core: core, windowId: windowId, timeMs: timestampMs, axis: axis, value: value)
    }

    public static func injectKeycode(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        key: UInt32,
        pressed: Bool,
        timestampMs: UInt32
    ) {
        _ = windowId
        injectKey(core: core, timeMs: timestampMs, keycode: key, pressed: pressed)
    }

    public static func injectTouch(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        touchId: Int32,
        x: Double,
        y: Double,
        phase: TouchPhase,
        timestampMs: UInt32
    ) {
        _ = windowId
        switch phase {
        case .down:
            injectTouchDown(core: core, timeMs: timestampMs, id: touchId, x: x, y: y)
        case .motion:
            injectTouchMotion(core: core, timeMs: timestampMs, id: touchId, x: x, y: y)
        case .up:
            injectTouchUp(core: core, timeMs: timestampMs, id: touchId)
        }
    }

    public static func injectPointerEnter(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        x: Double,
        y: Double,
        timestampMs: UInt32
    ) {
        injectPointerEnter(core: core, windowId: windowId, timeMs: timestampMs, x: x, y: y)
    }

    public static func injectPointerLeave(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        timestampMs: UInt32
    ) {
        injectPointerLeave(core: core, windowId: windowId, timeMs: timestampMs)
    }

    public static func insertText(core: UnsafeMutableRawPointer?, text: String) {
        // Printable text goes through zwp_text_input_v3 on the Rust side when wired.
        _ = (core, text)
    }

    public static func deleteBackward(core: UnsafeMutableRawPointer?) {
        injectKey(core: core, timeMs: 0, keycode: 14, pressed: true)
        injectKey(core: core, timeMs: 0, keycode: 14, pressed: false)
    }

    public static func injectConfigure(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        width: Int32,
        height: Int32
    ) {
        guard width > 0, height > 0 else { return }
        injectWindowResize(
            core: core, windowId: windowId, width: UInt32(width), height: UInt32(height))
    }
}
