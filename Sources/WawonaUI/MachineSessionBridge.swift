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
        guard let objc = WWNMachineProfileStore.profile(byId: profile.id) else {
            throw ConnectError.missingProfile
        }
        do {
            // ObjC `+ (BOOL)connectProfile:error:` bridges to Swift as the
            // throwing method `connect(_:)` (error-peeling + trailing-noun drop).
            try WWNMachineSessionBridge.connect(objc)
        } catch {
            throw ConnectError.backendFailed(error.localizedDescription)
        }
        MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
    }

    public static func disconnect(profile: MachineProfile) {
        guard let objc = WWNMachineProfileStore.profile(byId: profile.id) else { return }
        WWNMachineSessionBridge.disconnectProfile(objc)
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
