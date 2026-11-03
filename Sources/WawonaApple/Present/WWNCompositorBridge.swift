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
@_silgen_name("WWNCoreGetClientCount")
private func WWNCoreGetClientCount(_ core: UnsafeMutableRawPointer?) -> UInt32
@_silgen_name("WWNCorePopWindowEvent")
private func WWNCorePopWindowEvent(_ core: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
@_silgen_name("WWNWindowEventFree")
private func WWNWindowEventFree(_ event: UnsafeMutableRawPointer?)
@_silgen_name("wawona_wayland_socket_is_live")
private func wawona_wayland_socket_is_live(_ path: UnsafePointer<CChar>?) -> Int32

@objc(WWNCompositorBridge)
public final class WWNCompositorBridge: NSObject {
    @objc public static let sharedBridge = WWNCompositorBridge()
    @objc public static func shared() -> WWNCompositorBridge { sharedBridge }

    private var name = "wayland-0"
    public var core: UnsafeMutableRawPointer?
    /// #223: compositor-host LaunchAgent already owns the Wayland socket.
    /// Local bind must not unlink it; UI adopts the external host.
    private var usingExternalHostCompositor = false
    private var eventPump: Timer?
    private static let eventQueueKey = DispatchSpecificKey<UInt8>()
    /// Compositor event work matches Rust worker QoS (.utility). Never call
    /// WWNCoreProcessEvents on the main/.userInteractive thread or Thread
    /// Performance Checker reports Hang Risk priority inversions.
    private let eventQueue: DispatchQueue = {
        let q = DispatchQueue(
            label: "com.aspauldingcode.wawona.compositor-events",
            qos: .utility
        )
        q.setSpecific(key: WWNCompositorBridge.eventQueueKey, value: 1)
        return q
    }()
    /// Last seen Wayland client count. Rising edge reveals Present (Terminal
    /// may spawn clients; one-shot would miss the second `wasm` launch).
    private var lastWaylandClientCount: UInt32 = 0
    /// Mapped toplevel/popup count. Hits zero → clear frozen last SHM frame.
    private var mappedWaylandWindowCount: Int = 0
    #if canImport(AppKit)
    @objc public weak var containerView: NSView?
    @objc public weak var externalMirrorView: NSView?
    #elseif canImport(UIKit)
    @objc public weak var containerView: UIView?
    @objc public weak var externalMirrorView: UIView?
    #endif

    /// Last guest frame as PNG (from Iland present). Nil until a SHM/IOSurface
    /// present lands. Used by Machines / Tab Overview thumbnails.
    @objc public func captureCurrentSessionThumbnailPNGData() -> Data? {
        #if canImport(Metal) && !os(watchOS)
        return IlandPresenterObjC.activePresenterForDrain()?.lastThumbnailPNGData()
        #else
        return nil
        #endif
    }

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
        // #223: host LaunchAgent may already own wayland-0. Do not bind
        // (bind_primary used to unlink the live path and orphan the host fd).
        if core == nil && isExternalHostSocketLive() {
            usingExternalHostCompositor = true
            return true
        }
        usingExternalHostCompositor = false
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
        // Quitting Machines must leave the compositor-host socket up (#223).
        if usingExternalHostCompositor {
        usingExternalHostCompositor = false
        lastWaylandClientCount = 0
        mappedWaylandWindowCount = 0
        return
        }
        stopEventPump()
        if let core {
            _ = WWNCoreStop(core)
        }
        lastWaylandClientCount = 0
        mappedWaylandWindowCount = 0
        DispatchQueue.main.async {
            WWNNestedClientTabStore.shared.clearAll()
        }
        clearGuestPresent(reason: "bridge-stop")
    }

    private func startEventPumpIfNeeded() {
        guard eventPump == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.eventQueue.async {
                self.pollAndHandleWindowEvents()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        eventPump = timer
    }

    private func stopEventPump() {
        eventPump?.invalidate()
        eventPump = nil
    }

    @objc public func isRunning() -> Bool {
        if usingExternalHostCompositor || (core == nil && isExternalHostSocketLive()) {
            usingExternalHostCompositor = true
            return true
        }
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

    /// True when a peer accepts connect (live compositor-host), not a stale inode.
    @objc public func isExternalHostSocketLive() -> Bool {
        let path = resolvedSocketPath()
        guard !path.isEmpty else { return false }
        return path.withCString { wawona_wayland_socket_is_live($0) != 0 }
    }

    private func resolvedSocketPath() -> String {
        let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
        return (runtime as NSString).appendingPathComponent(name)
    }

    /// Ensure a live host compositor with a connectable socket path.
    @objc(ensureRunningWithSocketName:)
    @discardableResult
    public func ensureRunning(withSocketName socketName: String?) -> Bool {
        if let socketName, !socketName.isEmpty {
            name = socketName
        }
        if isRunning() { return true }
        // External host owns a live socket: adopt it. Do not stop/rebind.
        if core == nil && isExternalHostSocketLive() {
            usingExternalHostCompositor = true
            return true
        }
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
        // May run on eventQueue (timer) or an external caller. Keep Smithay
        // ProcessEvents off the main thread; hop to main for UI / Metal.
        let process: () -> Void = { [weak self] in
            guard let self else { return }
            _ = WWNCoreProcessEvents(self.core)
            let drainResult = self.drainWindowEvents()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if drainResult.mappedWindow {
                    self.requestSessionSurface(reason: "wayland-window")
                }
                if drainResult.clearedLastWindow {
                    self.clearGuestPresent(reason: "last-wayland-window-destroyed")
                }
                self.syncClientCountPresent()
                // SHM / IOSurface clients need PopPendingBuffer → Metal.
                #if canImport(Metal) && !os(watchOS)
                if let presenter = self.activeIlandPresenterRef() {
                    presenter.drainPendingBuffers(fromCore: self.core)
                }
                #endif
            }
        }
        if DispatchQueue.getSpecific(key: Self.eventQueueKey) != nil {
            process()
        } else {
            eventQueue.async(execute: process)
        }
    }

    private struct WindowDrainResult {
        var mappedWindow = false
        var clearedLastWindow = false
    }

    /// Pop `CWindowEvent`s. Parse full layout (window_id, title, decoration).
    /// Created / PopupCreated reveal Present; macOS routes toplevels through
    /// `WWNHostWindowController` (nest vs standalone `WWNWindow`).
    private func drainWindowEvents() -> WindowDrainResult {
        var result = WindowDrainResult()
        guard let core else { return result }
        var parsed: [WWNWindowEvent] = []
        while let raw = WWNCorePopWindowEvent(core) {
            let event = WWNWindowEvent.parse(raw)
            parsed.append(event)
            if event.eventType == WWNWindowEvent.created
                || event.eventType == WWNWindowEvent.popupCreated
            {
                mappedWaylandWindowCount += 1
                result.mappedWindow = true
            } else if event.eventType == WWNWindowEvent.destroyed {
                mappedWaylandWindowCount = max(0, mappedWaylandWindowCount - 1)
                if mappedWaylandWindowCount == 0 {
                    result.clearedLastWindow = true
                }
            }
            WWNWindowEventFree(raw)
        }
        if !parsed.isEmpty {
            let events = parsed
            DispatchQueue.main.async {
                self.dispatchWindowEvents(events)
            }
        }
        return result
    }

    @MainActor
    private func dispatchWindowEvents(_ events: [WWNWindowEvent]) {
        let preferStandalone = WWNNestedClientTabStore.shared.preferStandaloneOnCreate
        for event in events {
            switch event.eventType {
            case WWNWindowEvent.created:
                #if os(macOS)
                WWNHostWindowController.shared.handleCreated(
                    event,
                    preferStandalone: preferStandalone
                )
                #else
                WWNNestedClientTabStore.shared.upsertCreated(
                    id: event.windowId,
                    title: event.title,
                    width: event.width,
                    height: event.height,
                    decorationMode: event.decorationMode,
                    fillsHost: event.fillsHost != 0,
                    standalone: false
                )
                #endif
            case WWNWindowEvent.popupCreated:
                // Popups stay parent-attached; never sidebar tabs.
                break
            case WWNWindowEvent.destroyed:
                #if os(macOS)
                WWNHostWindowController.shared.handleDestroyed(windowId: event.windowId)
                #else
                WWNNestedClientTabStore.shared.remove(id: event.windowId)
                #endif
            case WWNWindowEvent.titleChanged:
                #if os(macOS)
                WWNHostWindowController.shared.handleTitleChanged(
                    windowId: event.windowId,
                    title: event.title
                )
                #else
                WWNNestedClientTabStore.shared.updateTitle(
                    id: event.windowId,
                    title: event.title
                )
                #endif
            case WWNWindowEvent.decorationsModeChanged:
                #if os(macOS)
                WWNHostWindowController.shared.handleDecorationChanged(
                    windowId: event.windowId,
                    mode: event.decorationMode
                )
                #else
                WWNNestedClientTabStore.shared.updateDecoration(
                    id: event.windowId,
                    mode: event.decorationMode
                )
                #endif
            case WWNWindowEvent.sizeChanged:
                #if os(macOS)
                WWNHostWindowController.shared.handleSizeChanged(
                    windowId: event.windowId,
                    width: event.width,
                    height: event.height
                )
                #else
                WWNNestedClientTabStore.shared.updateSize(
                    id: event.windowId,
                    width: event.width,
                    height: event.height
                )
                #endif
            default:
                break
            }
        }
    }

    private func clearGuestPresent(reason: String) {
        #if canImport(Metal) && !os(watchOS)
        activeIlandPresenterRef()?.clearGuestPresent(reason: reason)
        #endif
        NSLog("[WWNCompositorBridge] cleared guest present reason=%@", reason)
    }

    /// CLI MicroVM / external waypipe / Native Shell `wasm` never should
    /// leave the user stuck on Wawona Terminal. When client count rises,
    /// reveal Present (parks Terminal chrome; keeps the PTY alive).
    /// When count drops to zero (waypipe kill, guest crash), clear Metal even
    /// if a Destroy window event was missed so the last compositor plate
    /// (e.g. sway) cannot linger under the next guest's label.
    private func syncClientCountPresent() {
        guard let core else { return }
        let count = WWNCoreGetClientCount(core)
        let grew = count > lastWaylandClientCount
        let droppedToEmpty = lastWaylandClientCount > 0 && count == 0
        lastWaylandClientCount = count
        if droppedToEmpty {
            mappedWaylandWindowCount = 0
            clearGuestPresent(reason: "wayland-client-count-zero")
            return
        }
        guard grew, count > 0 else { return }
        requestSessionSurface(reason: "client-count=\(count)")
    }

    private func requestSessionSurface(reason: String) {
        let userInfo: [AnyHashable: Any] = [
            "source": "compositor-client-attach",
            "reason": reason,
        ]
        NotificationCenter.default.post(
            name: Notification.Name("WWNShowSessionSurfaceNotification"),
            object: nil,
            userInfo: userInfo
        )
        #if os(macOS)
        DistributedNotificationCenter.default().post(
            name: Notification.Name("WWNShowSessionSurfaceNotification"),
            object: nil,
            userInfo: userInfo
        )
        #endif
        NSLog("[WWNCompositorBridge] requested session surface (%@)", reason)
    }

    #if canImport(Metal) && !os(watchOS)
    private func activeIlandPresenterRef() -> IlandPresenterObjC? {
        // Same process-global as IlandPresenterObjC.init (Mode A present owner).
        return IlandPresenterObjC.activePresenterForDrain()
    }
    #endif

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
