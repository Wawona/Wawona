import WawonaModel

/// Push resolved per-machine settings into the ObjC runtime prefs + compositor.
@MainActor
public enum MachineRuntimeSettingsApplicator {
    public static func applyActiveMachine(
        profileStore: MachineProfileStore,
        preferences: WawonaPreferences
    ) {
        _ = preferences
        WWNMachineProfileStore.applyActiveMachineToRuntimePrefs()
    }

    public static func apply(profile: MachineProfile, preferences: WawonaPreferences) {
        _ = preferences
        WWNMachineProfileStore.setActiveMachineId(profile.id)
        WWNMachineProfileStore.applyActiveMachineToRuntimePrefs()
    }
}
