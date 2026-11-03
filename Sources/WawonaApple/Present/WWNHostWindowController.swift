#if os(macOS)
import AppKit
import SwiftUI

@_silgen_name("WWNCoreSetWindowHostSceneIndependent")
private func WWNCoreSetWindowHostSceneIndependent(
    _ core: UnsafeMutableRawPointer?,
    _ windowId: UInt64,
    _ independent: Bool
)

@_silgen_name("WWNCoreSetWindowActivated")
private func WWNCoreSetWindowActivated(
    _ core: UnsafeMutableRawPointer?,
    _ windowId: UInt64,
    _ active: Bool
)

/// Owns floating macOS `WWNWindow` hosts for standalone Wayland toplevels.
@MainActor
public final class WWNHostWindowController: NSObject {
    public static let shared = WWNHostWindowController()

    private var windows: [UInt64: WWNWindow] = [:]
    private var hostingControllers: [UInt64: NSHostingController<AnyView>] = [:]

    private override init() {
        super.init()
    }

    func handleCreated(_ event: WWNWindowEvent, preferStandalone: Bool) {
        let store = WWNNestedClientTabStore.shared
        let standalone = preferStandalone || store.preferStandaloneOnCreate
        store.preferStandaloneOnCreate = false
        store.upsertCreated(
            id: event.windowId,
            title: event.title,
            width: event.width,
            height: event.height,
            decorationMode: event.decorationMode,
            fillsHost: event.fillsHost != 0,
            standalone: standalone
        )
        let core = WWNCompositorBridge.sharedBridge.core
        if standalone {
            presentStandalone(event)
            WWNCoreSetWindowHostSceneIndependent(core, event.windowId, true)
        } else {
            WWNCoreSetWindowHostSceneIndependent(core, event.windowId, false)
            WWNCoreSetWindowActivated(core, event.windowId, true)
        }
    }

    public func handleDestroyed(windowId: UInt64) {
        closeStandalone(windowId: windowId, notifyStore: false)
        WWNNestedClientTabStore.shared.remove(id: windowId)
    }

    public func handleTitleChanged(windowId: UInt64, title: String) {
        WWNNestedClientTabStore.shared.updateTitle(id: windowId, title: title)
        if let window = windows[windowId] {
            window.title = title.isEmpty ? "Client" : title
        }
    }

    public func handleDecorationChanged(windowId: UInt64, mode: UInt8) {
        WWNNestedClientTabStore.shared.updateDecoration(id: windowId, mode: mode)
        windows[windowId]?.applyPresentationPolicy(forServerSideDecorations: mode == 1)
    }

    public func handleSizeChanged(windowId: UInt64, width: UInt32, height: UInt32) {
        WWNNestedClientTabStore.shared.updateSize(id: windowId, width: width, height: height)
    }

    /// Tear a nested tab into a floating `WWNWindow`.
    public func tearOff(windowId: UInt64) {
        let store = WWNNestedClientTabStore.shared
        guard let tab = store.tabs.first(where: { $0.id == windowId }), !tab.isStandalone else {
            return
        }
        store.markStandalone(id: windowId, standalone: true)
        let event = WWNWindowEvent(
            eventType: WWNWindowEvent.created,
            windowId: windowId,
            surfaceId: 0,
            title: tab.title,
            width: max(tab.width, 640),
            height: max(tab.height, 480),
            parentId: 0,
            x: 0,
            y: 0,
            decorationMode: tab.decorationMode,
            fullscreenShell: 0,
            hostLocked: 0,
            edges: 0,
            sizeKind: 1,
            sizeCause: 0,
            fillsHost: tab.fillsHost ? 1 : 0,
            configureSerial: 0,
            transactionId: 0
        )
        presentStandalone(event)
        let core = WWNCompositorBridge.sharedBridge.core
        WWNCoreSetWindowHostSceneIndependent(core, windowId, true)
        WWNCoreSetWindowActivated(core, windowId, true)
    }

    /// Nest a floating `WWNWindow` back into Tab Overview.
    public func nest(windowId: UInt64) {
        closeStandalone(windowId: windowId, notifyStore: false)
        WWNNestedClientTabStore.shared.markStandalone(id: windowId, standalone: false)
        let core = WWNCompositorBridge.sharedBridge.core
        WWNCoreSetWindowHostSceneIndependent(core, windowId, false)
        WWNCoreSetWindowActivated(core, windowId, true)
        NotificationCenter.default.post(
            name: Notification.Name("WWNShowSessionSurfaceNotification"),
            object: nil,
            userInfo: [
                "source": "nest-into-tab-overview",
                "reason": "window-\(windowId)",
            ]
        )
    }

    public func focusNested(windowId: UInt64) {
        WWNNestedClientTabStore.shared.focus(id: windowId)
        let core = WWNCompositorBridge.sharedBridge.core
        WWNCoreSetWindowActivated(core, windowId, true)
        NotificationCenter.default.post(
            name: Notification.Name("WWNShowSessionSurfaceNotification"),
            object: nil,
            userInfo: [
                "source": "focus-nested-tab",
                "reason": "window-\(windowId)",
            ]
        )
    }

    public func closeTab(windowId: UInt64) {
        // Destroy path usually follows client exit; request close via destroy count.
        closeStandalone(windowId: windowId, notifyStore: false)
        WWNNestedClientTabStore.shared.remove(id: windowId)
        WWNCompositorBridge.sharedBridge.flushClients()
    }

    private func presentStandalone(_ event: WWNWindowEvent) {
        if let existing = windows[event.windowId] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = WWNWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CGFloat(max(event.width, 640)),
                height: CGFloat(max(event.height, 480))
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.wwnWindowId = event.windowId
        window.fillsHost = event.fillsHost != 0
        window.hostLocked = event.hostLocked != 0
        window.applyPresentationPolicy(forServerSideDecorations: event.decorationMode == 1)
        window.title = event.title.isEmpty ? "Client" : event.title
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self

        let root = AnyView(
            WWNStandalonePresentRoot(windowId: event.windowId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        let hosting = NSHostingController(rootView: root)
        window.contentViewController = hosting
        windows[event.windowId] = window
        hostingControllers[event.windowId] = hosting
        WWNPlatformCallbacks.sharedCallbacks.registerWindow(window, forId: event.windowId)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeStandalone(windowId: UInt64, notifyStore: Bool) {
        if let window = windows.removeValue(forKey: windowId) {
            WWNPlatformCallbacks.sharedCallbacks.unregisterWindowId(windowId)
            window.delegate = nil
            window.orderOut(nil)
            window.contentViewController = nil
        }
        hostingControllers.removeValue(forKey: windowId)
        if notifyStore {
            WWNNestedClientTabStore.shared.markStandalone(id: windowId, standalone: false)
        }
    }
}

extension WWNHostWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? WWNWindow else { return }
        let id = window.wwnWindowId
        windows.removeValue(forKey: id)
        hostingControllers.removeValue(forKey: id)
        WWNPlatformCallbacks.sharedCallbacks.unregisterWindowId(id)
        // Closing the host nests the client back into Tab Overview.
        WWNNestedClientTabStore.shared.markStandalone(id: id, standalone: false)
        let core = WWNCompositorBridge.sharedBridge.core
        WWNCoreSetWindowHostSceneIndependent(core, id, false)
    }
}

/// Metal Present host for one floating Wayland toplevel.
private struct WWNStandalonePresentRoot: View {
    let windowId: UInt64

    var body: some View {
        #if !SWIFT_PACKAGE
        CompositorBridge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WindowIdBinder(windowId: windowId))
        #else
        Color.black
        #endif
    }
}

private struct WindowIdBinder: NSViewRepresentable {
    let windowId: UInt64

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window as? WWNWindow {
                window.wwnWindowId = windowId
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window as? WWNWindow {
            window.wwnWindowId = windowId
        }
    }
}
#endif
