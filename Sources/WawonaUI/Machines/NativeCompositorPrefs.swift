import Foundation
import WawonaModel

#if SKIP && os(Android)
/// Maps `MachineProfile` native launcher choice to the boolean flags read by
/// `WawonaCompositorSurface` (SharedPreferences name `wawona_preferences`).
enum NativeCompositorPrefs {
    private static let suiteName = "wawona_preferences"

    private static var prefs: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func apply(for profile: MachineProfile) {
        guard profile.type == .native else { return }
        let launcher = profile.launchers.first?.name
            ?? ClientLauncher.presets.first?.name
            ?? "weston-simple-shm"
        prefs.set(false, forKey: "WestonTerminalEnabled")
        prefs.set(false, forKey: "FootEnabled")
        prefs.set(false, forKey: "WestonSimpleSHMEnabled")
        prefs.set(false, forKey: "WestonEnabled")
        switch launcher {
        case "weston-terminal":
            prefs.set(true, forKey: "WestonTerminalEnabled")
        case "foot":
            prefs.set(true, forKey: "FootEnabled")
        case "weston-simple-shm":
            prefs.set(true, forKey: "WestonSimpleSHMEnabled")
        case "weston":
            prefs.set(true, forKey: "WestonEnabled")
        default:
            prefs.set(true, forKey: "WestonSimpleSHMEnabled")
        }
    }

    static func clearLauncherFlags() {
        prefs.set(false, forKey: "WestonTerminalEnabled")
        prefs.set(false, forKey: "FootEnabled")
        prefs.set(false, forKey: "WestonSimpleSHMEnabled")
        prefs.set(false, forKey: "WestonEnabled")
    }
}
#endif
