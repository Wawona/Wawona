import Foundation

/// How Machines Start presents a client when the host can open another window.
/// Stored prefs: `prompt` | `newTab` | `newWindow` (legacy `tab` / `window` accepted).
public enum MachineStartPlacement: String, Sendable, Equatable {
    case prompt
    case newTab
    case newWindow

    /// Normalize stored preference tokens to the canonical set.
    public static func normalize(_ raw: String?) -> MachineStartPlacement {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
        case "newWindow", "window":
            return .newWindow
        case "newTab", "tab":
            return .newTab
        case "prompt", "":
            return .prompt
        default:
            return .prompt
        }
    }

    /// True when this host can open a separate window/scene/task for Start.
    /// iPhone / tvOS / watchOS / Linux: false (tab only).
    /// iPad: multi-scene (SupportsMultipleScenes). Not gated on iOS 26;
    /// iPadOS 26 only adds window chrome controls.
    /// Android: API 24+ host tasks (caller may further gate with SessionActivity).
    public static func allowsWindowedStart(for host: GlobalSettingsHost) -> Bool {
        GlobalSettingsCatalog.allowsWindowedMachineStart(host)
    }

    /// Resolve the action for a Start tap. When windowing is unavailable,
    /// always `.newTab` (never prompt, never new window).
    public static func resolve(
        preference raw: String?,
        host: GlobalSettingsHost = GlobalSettingsCatalog.currentHost,
        windowingAvailable: Bool? = nil
    ) -> MachineStartPlacement {
        let canWindow = windowingAvailable ?? allowsWindowedStart(for: host)
        guard canWindow else { return .newTab }
        switch normalize(raw) {
        case .prompt: return .prompt
        case .newTab: return .newTab
        case .newWindow: return .newWindow
        }
    }
}
