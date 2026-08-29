import WawonaModel

/// Push resolved per-machine settings into the ObjC runtime prefs + compositor.
@MainActor
public enum MachineRuntimeSettingsApplicator {
    public static func applyActiveMachine(
        profileStore: MachineProfileStore,
        preferences: WawonaPreferences
    ) {
        #if !SWIFT_PACKAGE
        WWNMachineProfileStore.applyActiveMachineToRuntimePrefs()
        #endif
        applyEnvironment(profileStore: profileStore, preferences: preferences)
    }

    public static func apply(profile: MachineProfile, preferences: WawonaPreferences) {
        #if !SWIFT_PACKAGE
        WWNMachineProfileStore.setActiveMachineId(profile.id)
        WWNMachineProfileStore.applyActiveMachineToRuntimePrefs()
        #endif
        applyEnvironment(profile: profile, preferences: preferences)
    }

    private static func applyEnvironment(
        profileStore: MachineProfileStore,
        preferences: WawonaPreferences
    ) {
        let profile = profileStore.profile(for: profileStore.activeMachineId)
        applyEnvironment(profile: profile, preferences: preferences)
    }

    private static func applyEnvironment(
        profile: MachineProfile?,
        preferences: WawonaPreferences
    ) {
        let rows = preferences.resolvedEnvironment(for: profile)
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let strip = true
        #else
        let strip = false
        #endif
        EnvironmentProcessApplicator.applyOverridesToProcess(
            global: preferences.environmentOverrides,
            machine: profile?.runtimeOverrides.environment ?? [:],
            stripBannedLocalShellKeys: strip
        )
        _ = rows
    }
}
