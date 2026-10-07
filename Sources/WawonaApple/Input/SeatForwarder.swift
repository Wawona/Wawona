import Foundation

/// Seat inject trampolines into `WWNCore*`. Signatures match `src/ffi/c_api.rs`.
public enum SeatForwarder {
    @_silgen_name("WWNCoreInjectKey")
    private static func WWNCoreInjectKey(
        _ core: UnsafeMutableRawPointer?,
        _ keycode: UInt32,
        _ state: UInt32,
        _ timeMs: UInt32
    )

    @_silgen_name("WWNCoreInjectPointerMotion")
    private static func WWNCoreInjectPointerMotion(
        _ core: UnsafeMutableRawPointer?,
        _ windowId: UInt64,
        _ x: Double,
        _ y: Double,
        _ timeMs: UInt32
    )

    @_silgen_name("WWNCoreInjectPointerButton")
    private static func WWNCoreInjectPointerButton(
        _ core: UnsafeMutableRawPointer?,
        _ windowId: UInt64,
        _ button: UInt32,
        _ state: UInt32,
        _ timeMs: UInt32
    )

    @_silgen_name("WWNCoreInjectPointerAxis")
    private static func WWNCoreInjectPointerAxis(
        _ core: UnsafeMutableRawPointer?,
        _ windowId: UInt64,
        _ axis: UInt32,
        _ value: Double
    )

    @_silgen_name("WWNCoreInjectPointerEnter")
    private static func WWNCoreInjectPointerEnter(
        _ core: UnsafeMutableRawPointer?,
        _ windowId: UInt64,
        _ x: Double,
        _ y: Double,
        _ timeMs: UInt32
    )

    @_silgen_name("WWNCoreInjectPointerLeave")
    private static func WWNCoreInjectPointerLeave(
        _ core: UnsafeMutableRawPointer?,
        _ windowId: UInt64,
        _ timeMs: UInt32
    )

    @_silgen_name("WWNCoreInjectTouchDown")
    private static func WWNCoreInjectTouchDown(
        _ core: UnsafeMutableRawPointer?,
        _ id: Int32,
        _ x: Double,
        _ y: Double,
        _ timeMs: UInt32
    )

    @_silgen_name("WWNCoreInjectTouchMotion")
    private static func WWNCoreInjectTouchMotion(
        _ core: UnsafeMutableRawPointer?,
        _ id: Int32,
        _ x: Double,
        _ y: Double,
        _ timeMs: UInt32
    )

    @_silgen_name("WWNCoreInjectTouchUp")
    private static func WWNCoreInjectTouchUp(
        _ core: UnsafeMutableRawPointer?,
        _ id: Int32,
        _ timeMs: UInt32
    )

    @_silgen_name("WWNCoreInjectTouchCancel")
    private static func WWNCoreInjectTouchCancel(_ core: UnsafeMutableRawPointer?)

    @_silgen_name("WWNCoreInjectWindowResize")
    private static func WWNCoreInjectWindowResize(
        _ core: UnsafeMutableRawPointer?,
        _ windowId: UInt64,
        _ width: UInt32,
        _ height: UInt32
    )

    public static func injectKey(
        core: UnsafeMutableRawPointer?,
        timeMs: UInt32,
        keycode: UInt32,
        pressed: Bool
    ) {
        WWNCoreInjectKey(core, keycode, pressed ? 1 : 0, timeMs)
    }

    public static func injectPointerMotion(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        timeMs: UInt32,
        x: Double,
        y: Double
    ) {
        WWNCoreInjectPointerMotion(core, windowId, x, y, timeMs)
    }

    public static func injectPointerButton(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        timeMs: UInt32,
        button: UInt32,
        pressed: Bool
    ) {
        WWNCoreInjectPointerButton(core, windowId, button, pressed ? 1 : 0, timeMs)
    }

    public static func injectPointerAxis(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        timeMs: UInt32,
        axis: UInt32,
        value: Double
    ) {
        _ = timeMs
        WWNCoreInjectPointerAxis(core, windowId, axis, value)
    }

    public static func injectPointerEnter(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        timeMs: UInt32,
        x: Double,
        y: Double
    ) {
        WWNCoreInjectPointerEnter(core, windowId, x, y, timeMs)
    }

    public static func injectPointerLeave(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        timeMs: UInt32
    ) {
        WWNCoreInjectPointerLeave(core, windowId, timeMs)
    }

    public static func injectTouchDown(
        core: UnsafeMutableRawPointer?,
        timeMs: UInt32,
        id: Int32,
        x: Double,
        y: Double
    ) {
        WWNCoreInjectTouchDown(core, id, x, y, timeMs)
    }

    public static func injectTouchMotion(
        core: UnsafeMutableRawPointer?,
        timeMs: UInt32,
        id: Int32,
        x: Double,
        y: Double
    ) {
        WWNCoreInjectTouchMotion(core, id, x, y, timeMs)
    }

    public static func injectTouchUp(
        core: UnsafeMutableRawPointer?,
        timeMs: UInt32,
        id: Int32
    ) {
        WWNCoreInjectTouchUp(core, id, timeMs)
    }

    public static func injectTouchCancel(core: UnsafeMutableRawPointer?) {
        WWNCoreInjectTouchCancel(core)
    }

    public static func injectWindowResize(
        core: UnsafeMutableRawPointer?,
        windowId: UInt64,
        width: UInt32,
        height: UInt32
    ) {
        WWNCoreInjectWindowResize(core, windowId, width, height)
    }
}
