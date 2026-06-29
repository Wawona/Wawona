import Foundation
import WawonaModel
import WawonaUIContracts

@MainActor
enum WawonaUIContractAdapters {
    static func machineEditorState(from profile: MachineProfile?) -> MachineEditorState {
        guard let profile else {
            return MachineEditorState(
                selectedLauncherName: ClientLauncher.presets.first?.name ?? "weston-simple-shm",
                sshPortText: "22",
                inputProfile: "direct",
                waypipeEnabled: true
            )
        }

        return MachineEditorState(
            id: profile.id,
            name: profile.name,
            typeRawValue: profile.type.rawValue,
            selectedLauncherName: resolvedLauncherName(for: profile),
            sshHost: profile.sshHost,
            sshUser: profile.sshUser,
            sshPortText: String(profile.sshPort),
            sshPassword: profile.sshPassword,
            remoteCommand: profile.remoteCommand,
            vmSubtype: profile.vmSubtype,
            containerSubtype: profile.containerSubtype,
            inputProfile: profile.runtimeOverrides.inputProfile ?? "direct",
            bundledAppID: profile.runtimeOverrides.bundledAppID ?? "",
            waypipeEnabled: profile.runtimeOverrides.waypipeEnabled ?? true
        )
    }

    static func profile(from state: MachineEditorState) -> MachineProfile {
        let type = MachineType(rawValue: state.typeRawValue) ?? .native
        var profile = MachineProfile(
            id: state.id ?? UUID().uuidString,
            name: state.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            type: type,
            vmSubtype: state.vmSubtype.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            containerSubtype: state.containerSubtype.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            runtimeOverrides: MachineRuntimeOverrides(
                inputProfile: state.inputProfile.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                bundledAppID: state.bundledAppID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                waypipeEnabled: state.waypipeEnabled
            )
        )

        if state.isNative {
            profile.launchers = ClientLauncher.presets.filter { $0.name == state.selectedLauncherName }
        } else {
            profile.launchers = []
            profile.sshHost = state.sshHost.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            profile.sshUser = state.sshUser.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            profile.sshPort = MachineEditorValidation.normalizedPort(from: state)
            profile.sshPassword = state.sshPassword
            profile.remoteCommand = state.remoteCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }

        return profile
    }

    private static func resolvedLauncherName(for profile: MachineProfile) -> String {
        if let launcher = profile.launchers.first?.name, !launcher.isEmpty {
            return launcher
        }
        let bundled = profile.runtimeOverrides.bundledAppID?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        if !bundled.isEmpty,
           ClientLauncher.presets.contains(where: { $0.name == bundled }) {
            return bundled
        }
        return ClientLauncher.presets.first?.name ?? "weston-simple-shm"
    }
}
