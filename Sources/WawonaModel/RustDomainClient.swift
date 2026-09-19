import Foundation

/// Mechanical adapter for the Rust-owned application domain.
///
/// This type contains no product policy. It moves JSON snapshots/intents across
/// the hand-written C ABI and stores the opaque durable blob in UserDefaults.
enum RustDomainClient {
    static let durableStateKey = "wawona.rustDomain.v1"
    private static var bootstrapped = false

    static func bootstrapIfNeeded() {
        guard !bootstrapped else { return }
        bootstrapped = true

        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: durableStateKey),
           let state = try? JSONSerialization.jsonObject(with: data) {
            _ = dispatch(["type": "import_durable_state", "state": state])
            return
        }

        // One-time import of the pre-Rust profile store. Rust applies schema
        // defaults, validation, and normalization after receiving this raw blob.
        let profiles: Any
        if let data = defaults.data(forKey: MachineProfileStore.profilesKey),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            profiles = decoded
        } else if let text = defaults.string(forKey: MachineProfileStore.profilesKey),
                  let data = text.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) {
            profiles = decoded
        } else {
            profiles = []
        }
        var state: [String: Any] = [
            "schemaVersion": 1,
            "profiles": profiles,
            "preferences": [String: Any](),
        ]
        if let active = defaults.string(forKey: MachineProfileStore.activeMachineIdKey) {
            state["activeMachineId"] = active
        }
        guard dispatch(
            ["type": "import_durable_state", "state": state],
            persistDurable: false
        ) else {
            return
        }

        var legacyValues: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            if value is String || value is NSNumber {
                legacyValues[key] = value
            }
        }
        if dispatch([
            "type": "import_legacy_preferences",
            "values": legacyValues,
        ], persistDurable: false) {
            persist()
        }
    }

    static func snapshot() -> [String: Any]? {
        guard let json = RustDomainTransport.snapshotJSON(),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return nil
        }
        return object
    }

    @discardableResult
    static func dispatch(_ intent: [String: Any], persistDurable: Bool = true) -> Bool {
        guard JSONSerialization.isValidJSONObject(intent),
              let data = try? JSONSerialization.data(withJSONObject: intent),
              let json = String(data: data, encoding: .utf8),
              RustDomainTransport.dispatch(json) else {
            return false
        }
        if persistDurable {
            persist()
        }
        return true
    }

    static func resolvedSettingsData(machineID: String) -> Data? {
        RustDomainTransport.resolvedMachineJSON(machineID)?
            .data(using: .utf8)
    }

    static func resolvedSettingsData(profile: MachineProfile) -> Data? {
        guard let data = try? JSONEncoder().encode(profile),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return RustDomainTransport.resolvedProfileJSON(json)?.data(using: .utf8)
    }

    static func persist() {
        guard let json = RustDomainTransport.durableJSON(),
              let data = json.data(using: .utf8) else {
            return
        }
        UserDefaults.standard.set(data, forKey: durableStateKey)
    }
}
