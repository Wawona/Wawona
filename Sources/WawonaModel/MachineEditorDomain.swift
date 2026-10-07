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

        var session = NativeShellSession.from(profile: profile)
        let uiType = profile.type.selectablePivot
        var launcher = resolvedLauncherName(for: profile)
        var remote = profile.remoteCommand
        // Legacy Wayland "custom" launcher → Terminal Custom Command.
        if launcher == "custom" {
            session = NativeShellSession(kind: .terminal, useSSH: session.useSSH)
            if remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                remote = ""
            }
            launcher = ClientLauncher.presets.first?.name ?? "weston-simple-shm"
        }
        return MachineEditorState(
            id: profile.id,
            name: profile.name,
            typeRawValue: uiType.rawValue,
            nativeShellKindRawValue: session.kind.rawValue,
            nativeShellUseSSH: session.useSSH,
            selectedLauncherName: launcher,
            sshHost: profile.sshHost,
            sshUser: profile.sshUser,
            sshPortText: String(profile.sshPort),
            sshPassword: profile.sshPassword,
            sshAuthMethod: profile.sshAuthMethod,
            sshKeyPath: profile.sshKeyPath,
            sshKeyPassphrase: profile.sshKeyPassphrase,
            remoteCommand: remote,
            inputProfile: profile.runtimeOverrides.inputProfile
                ?? WawonaPreferences.normalizedTouchInputType(nil),
            bundledAppID: profile.runtimeOverrides.bundledAppID ?? "",
            waypipeEnabled: profile.runtimeOverrides.waypipeEnabled ?? session.waypipeEnabled,
            containerRef: profile.containerSettings?.containerRef ?? "",
            entryCommand: profile.containerSettings?.entryCommand ?? "",
            desktopSession: profile.containerSettings?.desktopSession ?? (profile.type == .container),
            imageArchivePath: profile.containerSettings?.imageArchivePath ?? "",
            vmIdentifier: profile.vmSettings?.vmIdentifier ?? "",
            vmVsockPort: profile.vmSettings?.vsockPort ?? "",
            vmGuestVariant: profile.vmSettings?.guestVariant ?? "4k",
            vmMemoryMB: profile.vmSettings?.memoryMB ?? 2048,
            vmDiskGiB: profile.vmSettings?.diskGiB ?? 8,
            vmNotes: profile.vmSettings?.notes ?? "",
            wasmCommand: profile.runtimeOverrides.wasmCommand ?? "wasm hello-wasi-gui",
            wasmModulePath: profile.runtimeOverrides.wasmModulePath ?? "",
            wasmPackage: profile.runtimeOverrides.wasmPackage ?? ""
        )
    }

    public static func profile(from state: MachineEditorState) -> MachineProfile {
        let session = NativeShellSession(
            kind: NativeShellKind(rawValue: state.nativeShellKindRawValue) ?? .terminal,
            useSSH: state.nativeShellUseSSH
        )
        let uiType = MachineType(rawValue: state.typeRawValue) ?? .native
        let storageType: MachineType
        if uiType == .native {
            storageType = session.storageType
        } else {
            storageType = uiType
        }

        let bundled = uiType == .native
            ? session.resolvedBundledAppID(selectedLauncher: state.selectedLauncherName)
            : nil
        let isWasm = storageType == .wasm || session.kind == .wasm

        var profile = MachineProfile(
            id: state.id ?? UUID().uuidString,
            name: state.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            type: storageType,
            runtimeOverrides: MachineRuntimeOverrides(
                inputProfile: state.inputProfile.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                bundledAppID: bundled,
                waypipeEnabled: uiType == .native ? session.waypipeEnabled : state.waypipeEnabled,
                wasmModulePath: isWasm
                    && !state.wasmModulePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                    ? state.wasmModulePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    : nil,
                wasmLaunchMode: isWasm ? "command" : nil,
                wasmPackage: isWasm
                    && !state.wasmPackage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                    ? state.wasmPackage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    : nil,
                wasmCommand: isWasm
                    ? (state.wasmCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                        ? "wasm hello-wasi-gui"
                        : state.wasmCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
                    : nil
            )
        )

        if uiType == .native && session.kind == .wayland, let bundled {
            profile.launchers = ClientLauncher.presets.filter { $0.name == bundled }
        } else {
            profile.launchers = []
        }

        let trimmedRemote = state.remoteCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if uiType == .native && session.needsSSHFields {
            profile.sshHost = MachineProfileDomain.sanitizeSSHHost(state.sshHost)
            profile.sshUser = state.sshUser.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            profile.sshPort = MachineProfileDomain.normalizeSSHPort(state.sshPortText)
            profile.sshPassword = state.sshPassword
            profile.sshAuthMethod = state.sshAuthMethod
            profile.sshKeyPath = state.sshKeyPath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            profile.sshKeyPassphrase = state.sshKeyPassphrase
            profile.remoteCommand = trimmedRemote
        } else if uiType == .native {
            profile.sshHost = ""
            profile.sshUser = ""
            profile.sshPort = 22
            profile.sshPassword = ""
            profile.sshAuthMethod = 0
            profile.sshKeyPath = ""
            profile.sshKeyPassphrase = ""
            // Terminal Custom Command (local) and Waypipe default command share remoteCommand.
            if session.kind == .terminal {
                profile.remoteCommand = trimmedRemote
            } else if session.kind == .waypipe {
                profile.remoteCommand = trimmedRemote.isEmpty ? "weston-simple-shm" : trimmedRemote
            } else {
                profile.remoteCommand = ""
            }
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

        if state.isVirtualMachine {
            profile.vmSettings = VirtualMachineSettings(
                provider: "relay",
                vmIdentifier: state.vmIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                vsockPort: state.vmVsockPort.trimmingCharacters(in: .whitespacesAndNewlines),
                guestVariant: state.vmGuestVariant == "16k" ? "16k" : "4k",
                memoryMB: max(256, min(state.vmMemoryMB, 4096)),
                diskGiB: max(4, min(state.vmDiskGiB, 64)),
                maxDiskGiB: 64,
                notes: state.vmNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                nixFiles: profile.vmSettings?.nixFiles
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
           bundled != "wawona-shell",
           bundled != "wawona-wasm",
           ClientLauncher.presets.contains(where: { $0.name == bundled }) {
            return bundled
        }
        return ClientLauncher.presets.first?.name ?? "weston-terminal"
    }
}
