#if os(macOS)
import AppKit
import Foundation

/// Accessory compositor service (`Wawona --compositor-host`).
/// Owns the Wayland socket. No Machines WindowGroup, no Dock tile.
enum WawonaCompositorHostApp {
    static func run() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { run() }
            return
        }
        MainActor.assumeIsolated { runOnMain() }
    }

    @MainActor
    private static func runOnMain() {
        if !WawonaLaunchLockState.acquireCompositorHost() {
            fputs("Wawona: compositor host already running; exiting.\n", stderr)
            return
        }
        atexit {
            WawonaLaunchLockState.releaseAll()
        }

        ProcessInfo.processInfo.processName = "WawonaCompositor"
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let runtimeDir = WawonaProcessLock.ensureRuntimeDirectory()
        setenv("XDG_RUNTIME_DIR", runtimeDir, 1)

        var agentError: NSError?
        _ = WWNLaunchAgentManager.sharedManager.ensureMenuBarAgent(&agentError)

        let bridge = WWNCompositorBridge.sharedBridge
        guard bridge.start(withSocketName: "wayland-0") else {
            writeRuntimeState(healthy: false, error: "failed to start compositor")
            WawonaLaunchLockState.releaseAll()
            exit(1)
        }
        setenv("WAYLAND_DISPLAY", "wayland-0", 1)
        writeRuntimeExports()
        writeRuntimeState(healthy: true, error: nil)

        // Keep accessory when any client window appears (old WWNKeepServiceHostOutOfDock).
        let nc = NotificationCenter.default
        let keepAccessory: (Notification) -> Void = { _ in
            NSApp.setActivationPolicy(.accessory)
        }
        nc.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main,
            using: keepAccessory
        )
        nc.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
            using: keepAccessory
        )

        let delegate = CompositorHostDelegate()
        app.delegate = delegate
        objc_setAssociatedObject(
            app,
            "wawona.compositorhost.delegate",
            delegate,
            .OBJC_ASSOCIATION_RETAIN
        )
        app.run()
        bridge.stop()
        WawonaLaunchLockState.releaseAll()
    }

    private static func writeRuntimeExports() {
        let dir = WawonaProcessLock.runtimeDirectory()
        let body = """
        #!/bin/sh
        export XDG_RUNTIME_DIR="\(dir)"
        export WAYLAND_DISPLAY="wayland-0"
        """
        let path = (dir as NSString).appendingPathComponent("wawona-env.sh")
        try? body.write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o700)
    }

    private static func writeRuntimeState(healthy: Bool, error: String?) {
        let dir = WawonaProcessLock.ensureRuntimeDirectory()
        var state: [String: Any] = [
            "healthy": healthy,
            "pid": Int(getpid()),
            "mode": "compositor-host",
            "xdgRuntimeDir": dir,
            "waylandDisplay": "wayland-0",
            "socketPath": (dir as NSString).appendingPathComponent("wayland-0"),
            "startedAt": Date().timeIntervalSince1970,
        ]
        if let error, !error.isEmpty {
            state["lastError"] = error
        }
        let path = (dir as NSString).appendingPathComponent("wawona-runtime-state.plist")
        (state as NSDictionary).write(toFile: path, atomically: true)
    }
}

private final class CompositorHostDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        _ = sender
        _ = flag
        // Host must never become a Regular Dock UI. Hand off to the UI instance.
        WawonaLaunchMode.openOrActivateUI(arguments: [])
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        WWNCompositorBridge.sharedBridge.stop()
        WawonaLaunchLockState.releaseAll()
    }
}
#endif
