#if WWN_PREFPANE && os(macOS)
import Foundation

/// PrefPane-only stubs so `PreferencesSectionsBuilder` links without the
/// full Wawona app graph. Writes go through the app's preferences domain.

public let WWNRootfsICloudSyncPreferenceKey = "wawona.pref.localShellICloudSyncEnabled"

// Mirror MachineConstants for Desktop Machine picker (PrefPane has no Machines target).
public let kWWNNativeShellKindTerminal = "terminal"
public let kWWNNativeShellKindWayland = "wayland"
public let kWWNNativeShellKindWasm = "wasm"
public let kWWNNativeShellKindWaypipe = "waypipe"
public let kWWNPrefsNativeShellKind = "NativeShellKind"
public let kWWNPrefsNativeShellUseSSH = "NativeShellUseSSH"

@objc(WWNRootfsICloudSync)
public final class WWNRootfsICloudSync: NSObject {
    private static var suite: UserDefaults {
        UserDefaults(suiteName: "com.aspauldingcode.Wawona") ?? .standard
    }

    @objc public static func isEnabled() -> Bool {
        suite.bool(forKey: WWNRootfsICloudSyncPreferenceKey)
    }

    @objc public static func isSupported() -> Bool { true }

    @objc public static func isContainerAvailable() -> Bool { false }

    @objc public static func statusSummary() -> String {
        isEnabled() ? "Enabled" : "Disabled"
    }
}

@objc(WWNWaypipeRunner)
public final class WWNWaypipeRunner: NSObject {
    @objc public static let shared = WWNWaypipeRunner()

    @objc public func findWaypipeBinary() -> String { "" }
}
#endif
