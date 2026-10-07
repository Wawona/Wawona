import Foundation
import WawonaModel

/// Routes machine connect/disconnect to the native session bridge on Apple platforms.
@MainActor
public enum MachineSessionBridge {
    public enum ConnectError: LocalizedError {
        case missingProfile
        case backendFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingProfile:
                return "Missing machine profile."
            case .backendFailed(let message):
                return message
            }
        }
    }

    #if os(watchOS)
    public static func connect(
        profile: MachineProfile,
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore
    ) throws {
        profileStore.activeMachineId = profile.id
        profileStore.save()
        guard WatchMachineSessionBridge.connect(profile: profile) else {
            throw ConnectError.backendFailed("Connect failed for \(profile.type.userFacingName) on watchOS.")
        }
        MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
    }

    public static func disconnect(profile: MachineProfile) {
        WatchMachineSessionBridge.disconnect(profile: profile)
    }
    #elseif os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
    public static func connect(
        profile: MachineProfile,
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore
    ) throws {
        profileStore.activeMachineId = profile.id
        profileStore.save()
        #if !SWIFT_PACKAGE
        let objc = WWNMachineProfileBridge.makeObjC(from: profile)
        _ = WWNMachineProfileStore.upsertProfile(objc)
        do {
            try WWNMachineSessionBridge.connect(objc)
        } catch {
            throw ConnectError.backendFailed(error.localizedDescription)
        }
        #endif
        MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
    }

    public static func disconnect(profile: MachineProfile) {
        #if !SWIFT_PACKAGE
        let objc = WWNMachineProfileBridge.makeObjC(from: profile)
        WWNMachineSessionBridge.disconnectProfile(objc)
        #else
        _ = profile
        #endif
    }
    #else
    public static func connect(
        profile: MachineProfile,
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore
    ) throws {
        _ = profile
        _ = preferences
        _ = profileStore
        throw ConnectError.backendFailed("No native session bridge on this platform.")
    }

    public static func disconnect(profile: MachineProfile) {
        _ = profile
    }
    #endif
}

#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
/// Convert domain `MachineProfile` into the Apple glue `WWNMachineProfile`.
enum WWNMachineProfileBridge {
    static func makeObjC(from profile: MachineProfile) -> WWNMachineProfile {
        let p = WWNMachineProfile()
        p.machineId = profile.id
        p.name = profile.name
        p.type = profile.type.rawValue
        p.sshHost = profile.sshHost
        p.sshUser = profile.sshUser
        p.sshPort = profile.sshPort
        p.sshPassword = profile.sshPassword
        p.sshAuthMethod = profile.sshAuthMethod
        p.sshKeyPath = profile.sshKeyPath
        p.sshKeyPassphrase = profile.sshKeyPassphrase
        p.remoteCommand = profile.remoteCommand
        p.favorite = profile.favorite
        var runtime: [String: Any] = [:]
        if let bundled = profile.runtimeOverrides.bundledAppID, !bundled.isEmpty {
            runtime["bundledAppID"] = bundled
        }
        if let wasmPath = profile.runtimeOverrides.wasmModulePath, !wasmPath.isEmpty {
            runtime["wasmModulePath"] = wasmPath
        }
        if let pkg = profile.runtimeOverrides.wasmPackage, !pkg.isEmpty {
            runtime["wasmPackage"] = pkg
        }
        if let cmd = profile.runtimeOverrides.wasmCommand, !cmd.isEmpty {
            runtime["wasmCommand"] = cmd
        }
        if let env = profile.runtimeOverrides.environment, !env.isEmpty {
            var flat: [String: String] = [:]
            for (key, override) in env {
                if override.action == .set, let value = override.value, !value.isEmpty {
                    flat[key] = value
                }
            }
            if !flat.isEmpty {
                runtime["environment"] = flat
            }
        }
        p.runtimeOverrides = runtime
        var settings: [String: Any] = [:]
        let session = NativeShellSession.from(profile: profile)
        if profile.type.selectablePivot == .native
            || profile.type == .wasm
            || profile.type.isSSH {
            settings["NativeShellKind"] = session.kind.rawValue
            settings["NativeShellUseSSH"] = session.useSSH
        }
        let native = profile.resolvedNativeClientId
        if !native.isEmpty {
            settings["NativeClientId"] = native
        }
        p.settingsOverrides = settings
        return p
    }
}
#endif
