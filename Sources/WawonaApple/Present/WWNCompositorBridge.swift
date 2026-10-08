import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@_silgen_name("WWNCoreNew")
private func WWNCoreNew() -> UnsafeMutableRawPointer?
@_silgen_name("WWNCoreStart")
private func WWNCoreStart(_ core: UnsafeMutableRawPointer?, _ socket: UnsafePointer<CChar>?) -> Bool
@_silgen_name("WWNCoreStop")
private func WWNCoreStop(_ core: UnsafeMutableRawPointer?) -> Bool
@_silgen_name("WWNCoreIsRunning")
private func WWNCoreIsRunning(_ core: UnsafeMutableRawPointer?) -> Bool
@_silgen_name("WWNCoreGetSocketPath")
private func WWNCoreGetSocketPath(_ core: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("WWNStringFree")
private func WWNStringFree(_ s: UnsafeMutablePointer<CChar>?)
@_silgen_name("WWNCoreFlushClients")
private func WWNCoreFlushClients(_ core: UnsafeMutableRawPointer?)
@_silgen_name("WWNCoreProcessEvents")
private func WWNCoreProcessEvents(_ core: UnsafeMutableRawPointer?) -> Bool

@objc(WWNCompositorBridge)
public final class WWNCompositorBridge: NSObject {
    @objc public static let sharedBridge = WWNCompositorBridge()
    @objc public static func shared() -> WWNCompositorBridge { sharedBridge }

    private var name = "wayland-0"
    public var core: UnsafeMutableRawPointer?
    private var eventPump: Timer?
    #if canImport(AppKit)
    @objc public weak var containerView: NSView?
    @objc public weak var externalMirrorView: NSView?
    #elseif canImport(UIKit)
    @objc public weak var containerView: UIView?
    @objc public weak var externalMirrorView: UIView?
    #endif

    @objc public func captureCurrentSessionThumbnailPNGData() -> Data? { nil }

    private var hostSeatMode: Int32 = 0

    @objc(setHostSeatMode:)
    public func setHostSeatMode(_ mode: Int32) { hostSeatMode = mode }

    @objc public func currentHostSeatMode() -> Int32 { hostSeatMode }

    @objc(focusClientWindowsForMachineId:)
    @discardableResult
    public func focusClientWindows(forMachineId machineId: String) -> Bool {
        _ = machineId
        return isRunning()
    }

    @objc(startWithSocketName:)
    @discardableResult
    public func start(withSocketName socketName: String?) -> Bool {
        name = (socketName?.isEmpty == false) ? socketName! : "wayland-0"
        if core == nil {
            core = WWNCoreNew()
        }
        guard let core else { return false }
        let ok = name.withCString { WWNCoreStart(core, $0) }
        let running = ok || WWNCoreIsRunning(core)
        if running {
            startEventPumpIfNeeded()
        }
        return running
    }

    @objc public func stop() {
        stopEventPump()
        if let core {
            _ = WWNCoreStop(core)
        }
    }

    private func startEventPumpIfNeeded() {
        guard eventPump == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.pollAndHandleWindowEvents()
        }
        RunLoop.main.add(timer, forMode: .common)
        eventPump = timer
    }

    private func stopEventPump() {
        eventPump?.invalidate()
        eventPump = nil
    }

    @objc public func isRunning() -> Bool {
        guard let core else { return false }
        guard WWNCoreIsRunning(core) else { return false }
        // Unlinked socket files leave the listen fd alive while clients get ENOENT.
        // Treat a missing path as not running so Start can rebind.
        return hasConnectableSocketPath()
    }

    /// True when the Wayland socket path exists on disk (connectable by name).
    @objc public func hasConnectableSocketPath() -> Bool {
        let path = socketPath()
        guard !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Ensure a live host compositor with a connectable socket path.
    @objc(ensureRunningWithSocketName:)
    @discardableResult
    public func ensureRunning(withSocketName socketName: String?) -> Bool {
        if isRunning() { return true }
        // Path gone or never started: tear down so Start can rebind.
        // WWNCoreStart refuses AlreadyStarted while the compositor object lives,
        // even when the socket inode was unlinked.
        if core != nil {
            stop()
        }
        return start(withSocketName: socketName)
    }

    @objc public func socketPath() -> String {
        if let core, let p = WWNCoreGetSocketPath(core) {
            let s = String(cString: p)
            WWNStringFree(p)
            if !s.isEmpty { return s }
        }
        let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
        return (runtime as NSString).appendingPathComponent(name)
    }

    @objc public func socketName() -> String { name }

    @objc public func flushClients() {
        WWNCoreFlushClients(core)
    }

    @objc public func pollAndHandleWindowEvents() {
        _ = WWNCoreProcessEvents(core)
    }

    @objc(injectPointerMotionForWindow:x:y:timestamp:)
    public func injectPointerMotion(forWindow windowId: UInt64, x: Double, y: Double, timestamp timestampMs: UInt32) {
        SeatForwarder.injectPointerMotion(
            core: core, windowId: windowId, timeMs: timestampMs, x: x, y: y)
    }

    @objc(injectPointerEnterForWindow:x:y:timestamp:)
    public func injectPointerEnter(forWindow windowId: UInt64, x: Double, y: Double, timestamp timestampMs: UInt32) {
        SeatForwarder.injectPointerEnter(
            core: core, windowId: windowId, timeMs: timestampMs, x: x, y: y)
    }

    @objc(injectPointerLeaveForWindow:timestamp:)
    public func injectPointerLeave(forWindow windowId: UInt64, timestamp timestampMs: UInt32) {
        SeatForwarder.injectPointerLeave(core: core, windowId: windowId, timeMs: timestampMs)
    }

    @objc(injectPointerButtonForWindow:button:pressed:timestamp:)
    public func injectPointerButton(forWindow windowId: UInt64, button: UInt32, pressed: Bool, timestamp timestampMs: UInt32) {
        SeatForwarder.injectPointerButton(
            core: core, windowId: windowId, timeMs: timestampMs, button: button, pressed: pressed)
    }

    @objc(injectPointerAxisForWindow:axis:value:discrete:timestamp:)
    public func injectPointerAxis(forWindow windowId: UInt64, axis: UInt32, value: Double, discrete: Int32, timestamp timestampMs: UInt32) {
        _ = discrete
        SeatForwarder.injectPointerAxis(
            core: core, windowId: windowId, timeMs: timestampMs, axis: axis, value: value)
    }

    @objc(injectKey:pressed:timestamp:)
    public func injectKey(_ keycode: UInt32, pressed: Bool, timestamp timestampMs: UInt32) {
        SeatForwarder.injectKey(core: core, timeMs: timestampMs, keycode: keycode, pressed: pressed)
    }

    @objc(injectTouchDown:x:y:timestamp:)
    public func injectTouchDown(_ id: Int32, x: Double, y: Double, timestamp timestampMs: UInt32) {
        SeatForwarder.injectTouchDown(core: core, timeMs: timestampMs, id: id, x: x, y: y)
    }

    @objc(injectTouchMotion:x:y:timestamp:)
    public func injectTouchMotion(_ id: Int32, x: Double, y: Double, timestamp timestampMs: UInt32) {
        SeatForwarder.injectTouchMotion(core: core, timeMs: timestampMs, id: id, x: x, y: y)
    }

    @objc(injectTouchUp:timestamp:)
    public func injectTouchUp(_ id: Int32, timestamp timestampMs: UInt32) {
        SeatForwarder.injectTouchUp(core: core, timeMs: timestampMs, id: id)
    }

    @objc public func injectTouchCancel() {
        SeatForwarder.injectTouchCancel(core: core)
    }

    @objc(injectWindowResizeForWindow:width:height:)
    public func injectWindowResize(forWindow windowId: UInt64, width: Int32, height: Int32) {
        SeatForwarder.injectWindowResize(
            core: core, windowId: windowId, width: UInt32(width), height: UInt32(height))
    }
}

@_cdecl("WWNCompositorBridgePumpFromC")
public func WWNCompositorBridgePumpFromC() {
    WWNCompositorBridge.sharedBridge.pollAndHandleWindowEvents()
}
