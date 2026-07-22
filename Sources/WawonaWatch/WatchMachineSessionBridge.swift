#if os(watchOS)
import WawonaModel

/// watchOS machine connect: native → local compositor + bundled client; remote → waypipe only.
enum WatchMachineSessionBridge {
    static func connect(profile: MachineProfile) -> Bool {
        let bridge = WWNWatchCompositorBridge.shared()
        if !bridge.isRunning {
            guard bridge.start(withSocketName: "wayland-0") else {
                return false
            }
        }

        switch profile.type {
        case .native:
            let clientId = resolvedNativeClientId(for: profile)
            switch clientId {
            case "weston":
                bridge.launchWeston()
            case "weston-terminal":
                bridge.launchWestonTerminal()
            case "foot":
                bridge.launchFoot()
            default:
                bridge.launchWestonSimpleSHM()
            }
            return true
        case .sshWaypipe, .sshTerminal:
            guard !profile.sshHost.isEmpty, !profile.sshUser.isEmpty else {
                return false
            }
            let command = profile.remoteCommand.isEmpty ? "weston-simple-shm" : profile.remoteCommand
            bridge.launchWaypipe(
                withHost: profile.sshHost,
                user: profile.sshUser,
                port: profile.sshPort,
                password: profile.sshPassword,
                remoteCommand: command
            )
            return bridge.isWaypipeRunning
        case .virtualMachine, .container:
            return false
        }
    }

    static func disconnect(profile: MachineProfile) {
        let bridge = WWNWatchCompositorBridge.shared()
        switch profile.type {
        case .native:
            bridge.stopClient()
        case .sshWaypipe, .sshTerminal:
            bridge.stopWaypipe()
        default:
            bridge.stopClient()
            bridge.stopWaypipe()
        }
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
        // watchOS is shm-only for nested clients (no GPU stack). Prefer
        // weston-simple-shm over weston-terminal (compat shim / may refuse).
        return "weston-simple-shm"
    }
}
#endif
