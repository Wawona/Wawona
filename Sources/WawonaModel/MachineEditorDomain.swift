import Foundation
import WawonaUIContracts

/// Profile editor mapping. One copy for WawonaUI and WawonaWatch.
/// Schema stays rust `src/domain`. Do not fork this on Watch.
@MainActor
public enum MachineEditorDomain {
    public static func machineEditorState(from profile: MachineProfile?) -> MachineEditorState {
        guard let profile else {
            return MachineEditorState(
                selectedLauncherName: ClientLauncher.presets.first?.name ?? "weston-terminal",
                sshPortText: "22",
                inputProfile: WawonaPreferences.normalizedTouchInputType(nil),
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
            sshAuthMethod: profile.sshAuthMethod,
            sshKeyPath: profile.sshKeyPath,
            sshKeyPassphrase: profile.sshKeyPassphrase,
            remoteCommand: profile.remoteCommand,
            inputProfile: profile.runtimeOverrides.inputProfile
                ?? WawonaPreferences.normalizedTouchInputType(nil),
            bundledAppID: profile.runtimeOverrides.bundledAppID ?? "",
            waypipeEnabled: profile.runtimeOverrides.waypipeEnabled ?? true,
            containerRef: profile.containerSettings?.containerRef ?? "",
            entryCommand: profile.containerSettings?.entryCommand ?? "",
            desktopSession: profile.containerSettings?.desktopSession ?? (profile.type == .container),
            imageArchivePath: profile.containerSettings?.imageArchivePath ?? "",
            wasmCommand: profile.runtimeOverrides.wasmCommand ?? "wasm hello-wasi-gui",
            wasmModulePath: profile.runtimeOverrides.wasmModulePath ?? "",
            wasmPackage: profile.runtimeOverrides.wasmPackage ?? ""
        )
    }

    public static func profile(from state: MachineEditorState) -> MachineProfile {
        let type = MachineType(rawValue: state.typeRawValue) ?? .native
        var profile = MachineProfile(
            id: state.id ?? UUID().uuidString,
            name: state.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            type: type,
            runtimeOverrides: MachineRuntimeOverrides(
                inputProfile: state.inputProfile.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                bundledAppID: state.isWasm
                    ? "wawona-wasm"
                    : (state.isNative
                        ? state.bundledAppID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        : nil),
                waypipeEnabled: state.waypipeEnabled,
                wasmModulePath: state.wasmModulePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                    ? nil : state.wasmModulePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                wasmLaunchMode: state.isWasm ? "command" : nil,
                wasmPackage: state.wasmPackage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                    ? nil : state.wasmPackage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                wasmCommand: state.wasmCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                    ? nil : state.wasmCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            )
        )

        if state.isNative {
            profile.launchers = ClientLauncher.presets.filter { $0.name == state.selectedLauncherName }
        } else {
            profile.launchers = []
            profile.sshHost = MachineProfileDomain.sanitizeSSHHost(state.sshHost)
            profile.sshUser = state.sshUser.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            profile.sshPort = MachineProfileDomain.normalizeSSHPort(state.sshPortText)
            profile.sshPassword = state.sshPassword
            profile.sshAuthMethod = state.sshAuthMethod
            profile.sshKeyPath = state.sshKeyPath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            profile.sshKeyPassphrase = state.sshKeyPassphrase
            profile.remoteCommand = state.remoteCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }

        if state.isContainer {
            profile.containerSettings = ContainerMachineSettings(
                containerRef: state.containerRef.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                entryCommand: state.entryCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                desktopSession: state.desktopSession,
                imageArchivePath: state.imageArchivePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                    ? nil
                    : state.imageArchivePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            )
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
        return ClientLauncher.presets.first?.name ?? "weston-terminal"
    }
}
