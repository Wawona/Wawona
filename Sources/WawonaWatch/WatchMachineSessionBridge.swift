#if os(watchOS)
import WatchKit
import WawonaModel

/// watchOS machine connect: native → local compositor + bundled client; remote → waypipe only.
enum WatchMachineSessionBridge {
    static func connectBundledClient(_ clientId: String) -> Bool {
        var overrides = MachineRuntimeOverrides()
        overrides.bundledAppID = clientId
        let profile = MachineProfile(
            id: "wawona-auto-client",
            name: "Auto Client",
            type: .native,
            runtimeOverrides: overrides
        )
        return connect(profile: profile)
    }

    static func connect(profile: MachineProfile) -> Bool {
        let logger = WWNStartupLogger.shared()
        // Capture before compositor/client start so early lines aren't missed
        // (same contract as iOS showStartupLogForClient:).
        logger.beginCapture()

        let bridge = WWNWatchCompositorBridge.shared()
        applyScreenOutputSize(bridge)
        if !bridge.isRunning {
            guard bridge.start(withSocketName: "wayland-0") else {
                logger.appendLine("[LAUNCH] Compositor start failed")
                NSLog("WATCH: compositor start failed (mini server and Rust backend both unavailable)")
                logger.endCapture()
                return false
            }
        }

        // Always clear prior client frame + in-process shell latch before Start.
        bridge.stopClient()

        switch profile.type {
        case .native:
            let clientId = resolvedNativeClientId(for: profile)
            guard !clientId.isEmpty else {
                logger.appendLine("[LAUNCH] No bundled client configured on this machine")
                logger.endCapture()
                return false
            }
            logger.appendLine("[LAUNCH] Starting \(clientId) …")
            bridge.launchClient(withId: clientId)
            return true
        case .sshWaypipe, .sshTerminal:
            guard !profile.sshHost.isEmpty, !profile.sshUser.isEmpty else {
                logger.endCapture()
                return false
            }
            let command = profile.remoteCommand.isEmpty ? "weston-simple-shm" : profile.remoteCommand
            logger.appendLine("[LAUNCH] Starting waypipe → \(command) …")
            bridge.launchWaypipe(
                withHost: profile.sshHost,
                user: profile.sshUser,
                port: profile.sshPort,
                password: profile.sshPassword,
                remoteCommand: command
            )
            let ok = bridge.isWaypipeRunning
            if !ok {
                logger.endCapture()
            }
            return ok
        case .virtualMachine, .container:
            logger.endCapture()
            return false
        }
    }

    static func disconnect(profile: MachineProfile) {
        _ = profile
        WWNStartupLogger.shared().endCapture()
        // Full compositor teardown. stopClient() alone leaves the mini
        // server with a pthread_cancel'd Wayland connection; the next
        // Start reconnects to a half-dead display and stays black.
        WWNWatchCompositorBridge.shared().stop()
    }

    /// Mini server advertises this as wl_output.mode and xdg_toplevel configure.
    /// Default 184×224 is a leftover point-size guess; use the real pixel size.
    private static func applyScreenOutputSize(_ bridge: WWNWatchCompositorBridge) {
        let device = WKInterfaceDevice.current()
        let scale = max(device.screenScale, 1)
        let width = UInt32(max(1, (device.screenBounds.width * scale).rounded()))
        let height = UInt32(max(1, (device.screenBounds.height * scale).rounded()))
        bridge.outputWidth = width
        bridge.outputHeight = height
    }

    private static func resolvedNativeClientId(for profile: MachineProfile) -> String {
        let override = profile.runtimeOverrides.bundledAppID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty {
            return override
        }
        if let launcher = profile.launchers.first?.name, !launcher.isEmpty {
            return launcher
        }
        return ""
    }
}
#endif
