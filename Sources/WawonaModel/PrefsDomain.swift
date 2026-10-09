import Foundation

/// Pref key schema from Rust `prefs_keys`. Swift UserDefaults is I/O only.
public enum PrefsDomain {
    /// Apply Rust defaults for keys that are missing from `defaults`.
    /// Does not overwrite user values.
    @discardableResult
    public static func registerRustDefaults(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard let json = WawonaDomainBridge.prefsDefaultsJSON(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        defaults.register(defaults: obj)
        return true
    }

    public static var knownKeys: [String] {
        guard let csv = WawonaDomainBridge.prefsKeysCSV(), !csv.isEmpty else {
            return []
        }
        return csv.split(separator: ",").map(String.init)
    }
}
