#if os(macOS)
import AppKit
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// macOS process role for the single Wawona.app Mach-O.
///
/// LaunchAgents pass `--compositor-host` / `--menubar`. Those must stay
/// accessory (no Dock tile, no Machines WindowGroup). Only the Regular UI
/// process holds `instance.lock`. A second UI launch activates the existing
/// instance and exits.
enum WawonaLaunchMode: Equatable {
    case compositorHost
    case menuBar
    case ui(showSettings: Bool, settingsSection: String?)
    case help
    case version

    static let reopenNotification = Notification.Name("WWNReopenUINotification")

    static func parse(_ arguments: [String] = CommandLine.arguments) -> WawonaLaunchMode {
        var compositorHost = false
        var menuBar = false
        var showSettings = false
        var settingsSection: String?
        var help = false
        var version = false

        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--compositor-host":
                compositorHost = true
            case "--menubar":
                menuBar = true
            case "--show-settings":
                showSettings = true
            case "--help", "-h":
                help = true
            case "--version", "-v":
                version = true
            default:
                if arg.hasPrefix("--settings-section=") {
                    settingsSection = String(arg.dropFirst("--settings-section=".count))
                    showSettings = true
                } else if arg == "--settings-section", i + 1 < arguments.count {
                    i += 1
                    settingsSection = arguments[i]
                    showSettings = true
                }
            }
            i += 1
        }

        if help { return .help }
        if version { return .version }
        if compositorHost && menuBar {
            fputs("Wawona: --compositor-host and --menubar are mutually exclusive\n", stderr)
            return .help
        }
        if compositorHost { return .compositorHost }
        if menuBar { return .menuBar }
        return .ui(showSettings: showSettings, settingsSection: settingsSection)
    }

    static func activateExistingUI(panel: String = "machines") {
        DistributedNotificationCenter.default().postNotificationName(
            reopenNotification,
            object: nil,
            userInfo: ["panel": panel],
            deliverImmediately: true
        )
        // Also nudge Launch Services in case the UI is asleep.
        let bundleURL = URL(fileURLWithPath: "/Applications/Wawona.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
    }

    /// Launch a Regular UI process only when `instance.lock` is free.
    /// Prefer activate-existing over `open -n` / NSTask of this Mach-O.
    static func openOrActivateUI(arguments: [String] = []) {
        if WawonaProcessLock.isHeld("instance.lock") {
            let panel: String
            if arguments.contains("--show-settings") {
                panel = "settings"
            } else if arguments.contains("--show-about") {
                panel = "about"
            } else if arguments.contains("--show-machines") {
                panel = "machines"
            } else {
                panel = "machines"
            }
            activateExistingUI(panel: panel)
            return
        }
        let bundleURL = URL(fileURLWithPath: "/Applications/Wawona.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        if !arguments.isEmpty {
            config.arguments = arguments
        }
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
    }

    static func printHelp() {
        // Prefer Rust help (full CLI). Fallback is the short LaunchAgent set.
        typealias Fn = @convention(c) () -> UnsafeMutablePointer<CChar>?
        typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "wawona_darwin_cli_help"),
           let freeSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "wawona_domain_string_free")
        {
            let fn = unsafeBitCast(sym, to: Fn.self)
            let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
            if let raw = fn() {
                defer { freeFn(raw) }
                print(String(cString: raw), terminator: "")
                return
            }
        }
        print(
            """
            Wawona. Wayland compositor for macOS

            Usage:
              Wawona run <recipe>
              Wawona machines list|show <id>
              Wawona [options]

            Service modes (LaunchAgents):
              --compositor-host       Compositor service without Machines UI
              --menubar               Menu-bar agent

            UI:
              (default)               Machines window (single instance)
              --show-settings         Open in-app Global Settings
              --settings-section=NAME Prefer a Settings section title

            Other:
              -h, --help              Show this help
              -v, --version           Print version
              --list-clients          Bundled client ids
              --list-machines         Saved Machines profiles
            """
        )
    }

    static func printVersion() {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        print("Wawona \(version) (\(build))")
    }
}

/// Holds flock fds for the lifetime of agent / UI processes.
enum WawonaLaunchLockState {
    private static var instanceFD: Int32 = -1
    private static var hostFD: Int32 = -1
    private static var menubarFD: Int32 = -1

    static func acquireUIInstance() -> Bool {
        if let fd = WawonaProcessLock.acquire("instance.lock") {
            instanceFD = fd
            return true
        }
        return false
    }

    static func acquireCompositorHost() -> Bool {
        if let fd = WawonaProcessLock.acquire("compositor-host.lock") {
            hostFD = fd
            return true
        }
        return false
    }

    static func acquireMenuBar() -> Bool {
        if let fd = WawonaProcessLock.acquire("menubar.lock") {
            menubarFD = fd
            return true
        }
        return false
    }

    static func releaseAll() {
        WawonaProcessLock.release(&instanceFD)
        WawonaProcessLock.release(&hostFD)
        WawonaProcessLock.release(&menubarFD)
    }
}
#endif
