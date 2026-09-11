import Foundation
#if canImport(Darwin)
import Darwin
#endif
import WawonaUIContracts

/// Thin Apple wrap around the rust product domain (`src/domain`).
///
/// Generated UniFFI Swift is the long-term import. Until bindgen output is
/// wired into every Apple target, this process looks up the C trampoline
/// (`wawona_profiles_v1_*`) from the linked rust staticlib. SPM tests have
/// no rust: they fall back to the frozen Swift Codable path.
///
/// Do not add schema fields here. Do not hand-edit generated UniFFI files.
public enum MachineProfileDomain {
    public static let profilesKey = "wawona.machineProfiles.v1"
    public static let activeMachineIdKey = "wawona.activeMachineId.v1"

    public static var rustAvailable: Bool {
        domainSymbol("wawona_profiles_v1_decode") != nil
    }

    public static func decodeProfilesV1(_ json: String) -> [MachineProfile]? {
        if let out = callString1("wawona_profiles_v1_decode", json),
           let data = out.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([MachineProfile].self, from: data)
        {
            return decoded
        }
        return nil
    }

    public static func encodeProfilesV1(_ profiles: [MachineProfile]) -> Data? {
        guard let data = try? JSONEncoder().encode(profiles),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        if let out = callString1("wawona_profiles_v1_decode", json) {
            return out.data(using: .utf8)
        }
        return data
    }

    public static func put(_ profile: MachineProfile, into profiles: [MachineProfile]) -> [MachineProfile]? {
        guard let listData = try? JSONEncoder().encode(profiles),
              let profileData = try? JSONEncoder().encode(profile),
              let listJSON = String(data: listData, encoding: .utf8),
              let profileJSON = String(data: profileData, encoding: .utf8),
              let out = callString2("wawona_profiles_v1_put", listJSON, profileJSON),
              let data = out.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode([MachineProfile].self, from: data)
    }

    public static func delete(id: String, from profiles: [MachineProfile]) -> [MachineProfile]? {
        guard let listData = try? JSONEncoder().encode(profiles),
              let listJSON = String(data: listData, encoding: .utf8),
              let out = callString2("wawona_profiles_v1_delete", listJSON, id),
              let data = out.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode([MachineProfile].self, from: data)
    }

    public static func sanitizeSSHHost(_ raw: String) -> String {
        if let out = callString1("wawona_editor_sanitize_ssh_host", raw) {
            return out
        }
        return MachineEditorValidation.sanitizeSSHHost(raw)
    }

    public static func normalizeSSHPort(_ raw: String, fallback: Int = 22) -> Int {
        if let sym = domainSymbol("wawona_editor_normalize_ssh_port") {
            let fn = unsafeBitCast(sym, to: PortFn.self)
            return raw.withCString { cRaw in
                Int(fn(cRaw, Int32(fallback)))
            }
        }
        return MachineEditorValidation.normalizeSSHPort(raw, fallback: fallback)
    }

    public static func validate(_ state: MachineEditorState) -> [MachineEditorValidationIssue] {
        if rustAvailable {
            guard let raw = callEditorValidate(state),
                  let data = raw.data(using: .utf8),
                  let tokens = try? JSONDecoder().decode([String].self, from: data)
            else {
                return MachineEditorValidation.validate(state)
            }
            return tokens.compactMap { MachineEditorValidationIssue(rawValue: $0) }
        }
        return MachineEditorValidation.validate(state)
    }

    /// wwn-igetty / Mode B TTY / Doorman. Never a Machines client id.
    public static func isForbiddenClientId(_ id: String) -> Bool {
        if let sym = domainSymbol("wawona_session_is_forbidden_client_id") {
            let fn = unsafeBitCast(sym, to: IntFn1.self)
            return id.withCString { fn($0) != 0 }
        }
        let token = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "modeb-tty", "modeb-ttyd", "igetty", "igettyd", "modeb-getty",
        ].contains(token)
    }
}

private typealias StrFn1 = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
private typealias StrFn2 = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?
private typealias EditorFn = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?
private typealias PortFn = @convention(c) (UnsafePointer<CChar>?, Int32) -> Int32
private typealias IntFn1 = @convention(c) (UnsafePointer<CChar>?) -> Int32
private typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

private func domainSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    name.withCString { dlsym(UnsafeMutableRawPointer(bitPattern: -2), $0) }
}

private func freeDomainString(_ raw: UnsafeMutablePointer<CChar>) {
    if let freeSym = domainSymbol("wawona_domain_string_free") {
        unsafeBitCast(freeSym, to: FreeFn.self)(raw)
    } else {
        free(raw)
    }
}

private func callString1(_ name: String, _ arg: String) -> String? {
    guard let sym = domainSymbol(name) else { return nil }
    let fn = unsafeBitCast(sym, to: StrFn1.self)
    return arg.withCString { cArg in
        guard let raw = fn(cArg) else { return nil }
        defer { freeDomainString(raw) }
        return String(cString: raw)
    }
}

private func callString2(_ name: String, _ a: String, _ b: String) -> String? {
    guard let sym = domainSymbol(name) else { return nil }
    let fn = unsafeBitCast(sym, to: StrFn2.self)
    return a.withCString { cA in
        b.withCString { cB in
            guard let raw = fn(cA, cB) else { return nil }
            defer { freeDomainString(raw) }
            return String(cString: raw)
        }
    }
}

private func callEditorValidate(_ state: MachineEditorState) -> String? {
    guard let sym = domainSymbol("wawona_editor_validate") else { return nil }
    let fn = unsafeBitCast(sym, to: EditorFn.self)
    return state.name.withCString { cName in
        state.typeRawValue.withCString { cType in
            state.sshHost.withCString { cHost in
                state.sshUser.withCString { cUser in
                    state.sshPortText.withCString { cPort in
                        guard let raw = fn(cName, cType, cHost, cUser, cPort) else { return nil }
                        defer { freeDomainString(raw) }
                        return String(cString: raw)
                    }
                }
            }
        }
    }
}
