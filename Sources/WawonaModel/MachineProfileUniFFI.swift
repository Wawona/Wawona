import Foundation

#if canImport(wawona)
import wawona
#endif

/// UniFFI `MachineProfile` is the in-memory product type when the module is
/// linked (Exact / `cargo xtask backend`). Codable
/// ``MachineProfile`` stays a quarantine / SPM adapter only.
///
/// Gate markers for `cargo xtask verify profile-schema-lift`:
/// `MachineProfileUniFFI`, `fromUniFFI`, `toUniFFI`, `canImport(wawona)`.
public enum MachineProfileUniFFI {
    /// True when generated UniFFI Swift (`import wawona`) is on the link line.
    public static var isLinked: Bool {
        #if canImport(wawona)
        true
        #else
        false
        #endif
    }

    #if canImport(wawona)
    /// Canonical in-memory type when UniFFI is linked.
    public typealias Record = wawona.MachineProfile

    /// Decode v1 JSON through rust UniFFI, then adapt to Codable DTOs for
    /// quarantine SwiftUI that still expects ``MachineProfile``.
    public static func decodeProfilesV1(_ json: String) -> [MachineProfile]? {
        guard let records = try? machineProfilesDecodeV1(json: json),
              let encoded = try? machineProfilesEncodeV1(profiles: records),
              let data = encoded.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode([MachineProfile].self, from: data)
    }

    /// Encode Codable adapters through UniFFI so rust owns validation of the
    /// wire shape before persistence.
    public static func encodeProfilesV1(_ profiles: [MachineProfile]) -> String? {
        guard let data = try? JSONEncoder().encode(profiles),
              let json = String(data: data, encoding: .utf8),
              let records = try? machineProfilesDecodeV1(json: json),
              let out = try? machineProfilesEncodeV1(profiles: records)
        else {
            return nil
        }
        return out
    }

    public static func fromUniFFI(_ record: Record) -> MachineProfile? {
        guard let encoded = try? machineProfilesEncodeV1(profiles: [record]),
              let data = encoded.data(using: .utf8),
              let list = try? JSONDecoder().decode([MachineProfile].self, from: data)
        else {
            return nil
        }
        return list.first
    }

    public static func toUniFFI(_ profile: MachineProfile) -> Record? {
        guard let data = try? JSONEncoder().encode([profile]),
              let json = String(data: data, encoding: .utf8),
              let records = try? machineProfilesDecodeV1(json: json)
        else {
            return nil
        }
        return records.first
    }

    public static func put(_ profile: MachineProfile, into profiles: [MachineProfile]) -> [MachineProfile]? {
        guard let listJSON = encodeProfilesV1(profiles),
              let record = toUniFFI(profile)
        else {
            return nil
        }
        let store = MachineProfileStoreApi()
        do {
            try store.loadJson(json: listJSON)
            try store.putProfile(profile: record)
            return decodeProfilesV1(try store.saveJson())
        } catch {
            guard var records = try? machineProfilesDecodeV1(json: listJSON) else {
                return nil
            }
            records = records.filter { $0.id != record.id }
            records.append(record)
            guard let encoded = try? machineProfilesEncodeV1(profiles: records) else {
                return nil
            }
            return decodeProfilesV1(encoded)
        }
    }
    #endif
}
