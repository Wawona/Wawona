import Foundation

@objc(WWNMachineProfile)
public final class WWNMachineProfile: NSObject {
    @objc public var machineId: String = UUID().uuidString
    @objc public var name: String = "New Machine"
    @objc public var type: String = "native"
    @objc public var sshEnabled = false
    @objc public var sshHost: String = ""
    @objc public var sshUser: String = ""
    @objc public var sshPort: Int = 22
    @objc public var sshPassword: String = ""
    @objc public var sshBinary: String = "ssh"
    @objc public var sshAuthMethod: Int = 0
    @objc public var sshKeyPath: String = ""
    @objc public var sshKeyPassphrase: String = ""
    @objc public var remoteCommand: String = ""
    @objc public var customScript: String = ""
    @objc public var waypipeCompress: String = ""
    @objc public var waypipeThreads: String = ""
    @objc public var waypipeVideo: String = ""
    @objc public var waypipeDebug = false
    @objc public var waypipeOneshot = false
    @objc public var waypipeDisableGpu = false
    @objc public var waypipeLoginShell = false
    @objc public var waypipeTitlePrefix: String = ""
    @objc public var waypipeSecCtx: String = ""
    @objc public var settingsOverrides: [String: Any] = [:]
    @objc public var runtimeOverrides: [String: Any] = [:]
    @objc public var containerSettings: [String: Any] = [:]
    @objc public var vmSettings: [String: Any] = [:]
    @objc public var favorite = false
    @objc public var createdAtMs: Int64 = 0
    @objc public var updatedAtMs: Int64 = 0

    @objc public static func defaultProfile() -> WWNMachineProfile {
        WWNMachineProfile().initDefaultProfile()
    }

    @objc public func initDefaultProfile() -> WWNMachineProfile {
        createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        updatedAtMs = createdAtMs
        return self
    }

    @objc public func serialize() -> [AnyHashable: Any] {
        [
            "machineId": machineId,
            "name": name,
            "type": type,
            "favorite": favorite,
            "sshHost": sshHost,
            "sshUser": sshUser,
            "sshPort": sshPort,
            "remoteCommand": remoteCommand,
            "settingsOverrides": settingsOverrides,
            "runtimeOverrides": runtimeOverrides,
        ]
    }
}

@objc(WWNMachineProfileStore)
public final class WWNMachineProfileStore: NSObject {
    private static let defaultsKey = "WWNMachineProfiles"
    private static let activeKey = "WWNActiveMachineId"

    @objc public static func loadProfiles() -> [WWNMachineProfile] {
        guard let data = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]] else {
            return []
        }
        return data.map { dict in
            let p = WWNMachineProfile()
            p.machineId = dict["machineId"] as? String ?? UUID().uuidString
            p.name = dict["name"] as? String ?? "Machine"
            p.type = dict["type"] as? String ?? "native"
            p.favorite = dict["favorite"] as? Bool ?? false
            p.sshHost = dict["sshHost"] as? String ?? ""
            p.sshUser = dict["sshUser"] as? String ?? ""
            p.sshPort = dict["sshPort"] as? Int ?? 22
            p.remoteCommand = dict["remoteCommand"] as? String ?? ""
            p.settingsOverrides = dict["settingsOverrides"] as? [String: Any] ?? [:]
            p.runtimeOverrides = dict["runtimeOverrides"] as? [String: Any] ?? [:]
            return p
        }
    }

    private static func save(_ profiles: [WWNMachineProfile]) {
        UserDefaults.standard.set(profiles.map { $0.serialize() }, forKey: defaultsKey)
        NotificationCenter.default.post(name: .WWNMachineProfilesChanged, object: nil)
    }

    @objc(upsertProfile:)
    public static func upsertProfile(_ profile: WWNMachineProfile) -> [WWNMachineProfile] {
        var all = loadProfiles().filter { $0.machineId != profile.machineId }
        profile.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        all.append(profile)
        save(all)
        return all
    }

    @objc(deleteProfileById:)
    public static func deleteProfile(byId machineId: String) -> [WWNMachineProfile] {
        let all = loadProfiles().filter { $0.machineId != machineId }
        save(all)
        return all
    }

    @objc public static func deleteAllProfiles() -> [WWNMachineProfile] {
        save([])
        return []
    }

    @objc public static func activeMachineId() -> String? {
        UserDefaults.standard.string(forKey: activeKey)
    }

    @objc(setActiveMachineId:)
    public static func setActiveMachineId(_ machineId: String?) {
        UserDefaults.standard.set(machineId, forKey: activeKey)
    }

    @objc(profileById:)
    public static func profile(byId machineId: String) -> WWNMachineProfile? {
        loadProfiles().first { $0.machineId == machineId }
    }

    @objc(applyMachineToRuntimePrefs:)
    public static func applyMachineToRuntimePrefs(_ profile: WWNMachineProfile) {
        _ = profile
    }

    @objc public static func applyActiveMachineToRuntimePrefs() {
        if let id = activeMachineId(), let p = profile(byId: id) {
            applyMachineToRuntimePrefs(p)
        }
    }

    @objc public static func persistActiveMachineSettings() {}

    @objc(resolvedRuntimeSettingsForProfile:)
    public static func resolvedRuntimeSettings(for profile: WWNMachineProfile) -> [String: Any] {
        profile.runtimeOverrides
    }

    @objc(isMachineThumbnailEnabledForProfile:)
    public static func isMachineThumbnailEnabled(for profile: WWNMachineProfile) -> Bool {
        _ = profile
        return true
    }

    @objc(resolvedShakeToCloseForProfile:)
    public static func resolvedShakeToClose(for profile: WWNMachineProfile?) -> Bool {
        _ = profile
        return false
    }

    @objc(resolvedSwipeBackToCloseForProfile:)
    public static func resolvedSwipeBackToClose(for profile: WWNMachineProfile?) -> Bool {
        _ = profile
        return true
    }

    @objc(resolvedResizeDisplayForVirtualKeyboardForProfile:)
    public static func resolvedResizeDisplayForVirtualKeyboard(for profile: WWNMachineProfile?) -> Bool {
        _ = profile
        return true
    }

    @objc public static func resolvedResizeDisplayForVirtualKeyboardActive() -> Bool { true }

    @objc(resolvedRenderMacOSPointerForProfile:)
    public static func resolvedRenderMacOSPointer(for profile: WWNMachineProfile?) -> Bool {
        _ = profile
        return false
    }

    @objc public static func resolvedRenderMacOSPointerActive() -> Bool { false }

    @objc(resolvedWaypipeDisableGpuForProfile:)
    public static func resolvedWaypipeDisableGpu(for profile: WWNMachineProfile?) -> Bool {
        profile?.waypipeDisableGpu ?? false
    }

    @objc(resolvedNestedCompositorCursorForProfile:)
    public static func resolvedNestedCompositorCursor(for profile: WWNMachineProfile?) -> String {
        _ = profile
        return "auto"
    }

    @objc public static func resolvedNestedCompositorCursorActive() -> String { "auto" }

    @objc public static func resolvedShowHostCursorActive() -> Bool { true }
    @objc public static func resolvedShowVirtualPointerActive() -> Bool { false }

    @objc(resolvedAlwaysOnTopForProfile:)
    public static func resolvedAlwaysOnTop(for profile: WWNMachineProfile?) -> Bool {
        _ = profile
        return false
    }

    @objc(profileIndicatesNestedWithNativeClientId:bundledAppID:)
    public static func profileIndicatesNested(withNativeClientId clientId: String, bundledAppID: String?) -> Bool {
        let id = clientId.lowercased()
        if id.contains("weston") || id.contains("niri") || id.contains("sway") || id.contains("labwc") {
            return true
        }
        if let bundledAppID, !bundledAppID.isEmpty {
            let b = bundledAppID.lowercased()
            return b.contains("weston") || b.contains("niri")
        }
        return false
    }

    /// Call-site alias used by Machines editor drafts.
    @objc(profileIndicatesNestedWithNativeClientId:customCommand:)
    public static func profileIndicatesNested(nativeClientId clientId: String, customCommand: String) -> Bool {
        profileIndicatesNested(withNativeClientId: clientId, bundledAppID: customCommand.isEmpty ? nil : customCommand)
    }

    @objc(profileIndicatesNestedCompositor:)
    public static func profileIndicatesNestedCompositor(_ profile: WWNMachineProfile) -> Bool {
        let client = WWNNativeShellConfiguration.bundledClientId(in: profile) ?? ""
        let custom = profile.remoteCommand
        return profileIndicatesNested(withNativeClientId: client, bundledAppID: custom)
    }

    /// Desktop Replacement session machine: local Native Shell Wayland
    /// compositor only (weston / niri / custom nested compositor). Not
    /// Terminal, Wasm, Waypipe, SSH, terminal clients, or igetty.
    @objc(profileEligibleForDesktopReplacement:)
    public static func profileEligibleForDesktopReplacement(_ profile: WWNMachineProfile) -> Bool {
        if profileIsIgettyConsoleNotAMachine(profile) { return false }
        guard WWNNativeShellConfiguration.isNativeShellFamily(profile.type) else {
            return false
        }
        // Folded native family must surface as Native Shell Wayland, not
        // Terminal / Wasm / Waypipe.
        let kind = WWNNativeShellConfiguration.kind(for: profile)
        guard kind == kWWNNativeShellKindWayland else { return false }
        if WWNNativeShellConfiguration.usesSSH(for: profile) { return false }
        return profileIndicatesNestedCompositor(profile)
    }

    /// Titles + machineIds for Settings → Desktop → Desktop Machine picker.
    public static func desktopReplacementMachinePickerOptions() -> (titles: [String], values: [String]) {
        var titles = ["None"]
        var values = [""]
        let eligible = loadProfiles()
            .filter { profileEligibleForDesktopReplacement($0) }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        for profile in eligible {
            let client = WWNNativeShellConfiguration.bundledClientId(in: profile) ?? "compositor"
            let clientLabel: String
            let lower = client.lowercased()
            if lower == "weston" || lower.hasSuffix("/weston") {
                clientLabel = "Weston"
            } else if lower == "niri" || lower.hasSuffix("/niri") {
                clientLabel = "Niri"
            } else {
                clientLabel = client
            }
            titles.append("\(profile.name) (\(clientLabel))")
            values.append(profile.machineId)
        }
        return (titles, values)
    }

    @objc(nativeClientIdIndicatesModeBOwnDisplay:bundledAppID:)
    public static func nativeClientIdIndicatesModeBOwnDisplay(_ clientId: String, bundledAppID: String?) -> Bool {
        _ = (clientId, bundledAppID)
        return false
    }

    @objc(profileIndicatesModeBOwnDisplay:)
    public static func profileIndicatesModeBOwnDisplay(_ profile: WWNMachineProfile) -> Bool {
        _ = profile
        return false
    }

    @objc(nativeClientIdIsIgettyConsole:)
    public static func nativeClientIdIsIgettyConsole(_ clientId: String?) -> Bool {
        (clientId ?? "").lowercased().contains("igetty")
    }

    @objc(profileIsIgettyConsoleNotAMachine:)
    public static func profileIsIgettyConsoleNotAMachine(_ profile: WWNMachineProfile) -> Bool {
        let client = profile.runtimeOverrides["nativeClientId"] as? String
        return nativeClientIdIsIgettyConsole(client)
    }

    @objc(profileEligibleForAppBridge:)
    public static func profileEligibleForAppBridge(_ profile: WWNMachineProfile) -> Bool {
        profile.type == "native"
    }

    @objc public static func migrateTvosGpuOpenGLDriverSnapshotsIfNeeded() {}
}
