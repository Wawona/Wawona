#if os(watchOS)
import Foundation
import SwiftUI
import WawonaModel
import WawonaUIContracts

/// Add / Edit Machine — same `MachineEditorValidation.visibleFields` catalog as iOS/macOS.
/// Input (Touch Input Type) is Machine Settings only; do not show it here.
struct MachineEditorView: View {
    @ObservedObject var profileStore: MachineProfileStore
    let existingProfile: MachineProfile?

    @Environment(\.dismiss) var dismiss

    @State var name: String
    @State var type: MachineType
    @State var selectedLauncherName: String
    @State var sshHost: String
    @State var sshUser: String
    @State var sshPort: Int
    @State var sshPassword: String
    @State var sshAuthMethod: Int
    @State var sshKeyPath: String
    @State var sshKeyPassphrase: String
    @State var remoteCommand: String
    @State var waypipeEnabled: Bool
    @State private var keygenMessage: String?

    private var isEditing: Bool { existingProfile != nil }
    private var isNative: Bool { type == .native }
    private var isSSH: Bool { type == .sshWaypipe || type == .sshTerminal }

    private var contractState: MachineEditorState {
        persistableEditorState()
    }

    private var visibleFields: [MachineEditorFieldID] {
        MachineEditorValidation.visibleFields(for: contractState)
    }

    private func shows(_ field: MachineEditorFieldID) -> Bool {
        visibleFields.contains(field)
    }

    private var hasValidationIssues: Bool {
        var state = persistableEditorState()
        if state.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            state.name = "Unnamed Machine"
        }
        return !MachineEditorValidation.validate(state).isEmpty
    }

    init(profileStore: MachineProfileStore, profile: MachineProfile? = nil) {
        self.profileStore = profileStore
        self.existingProfile = profile
        let state = WatchUIContractAdapters.machineEditorState(from: profile)
        _name = State(initialValue: state.name)
        let parsed = MachineType(rawValue: state.typeRawValue) ?? .native
        if parsed == .container || parsed == .virtualMachine {
            _type = State(initialValue: .native)
        } else {
            _type = State(initialValue: parsed)
        }
        _selectedLauncherName = State(initialValue: state.selectedLauncherName)
        _sshHost = State(initialValue: state.sshHost)
        _sshUser = State(initialValue: state.sshUser)
        _sshPort = State(initialValue: MachineEditorValidation.normalizedPort(from: state))
        _sshPassword = State(initialValue: state.sshPassword)
        _sshAuthMethod = State(initialValue: state.sshAuthMethod)
        _sshKeyPath = State(initialValue: state.sshKeyPath)
        _sshKeyPassphrase = State(initialValue: state.sshKeyPassphrase)
        _remoteCommand = State(initialValue: state.remoteCommand)
        _waypipeEnabled = State(initialValue: state.waypipeEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                if shows(.name) || shows(.type) {
                    Section("Profile") {
                        if shows(.name) {
                            TextField("Unnamed Machine", text: $name)
                        }
                        if shows(.type) {
                            Picker("Type", selection: $type) {
                                ForEach(PlatformCapabilities.availableMachineTypes, id: \.self) { t in
                                    Label(t.userFacingName, systemImage: t.symbolName).tag(t)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }
                    }
                }

                if isNative && shows(.launcher) {
                    Section {
                        NavigationLink {
                            WatchBundledClientPickerView(selection: $selectedLauncherName)
                        } label: {
                            HStack {
                                Text(MachineEditorValidation.metadata(for: .launcher).label)
                                Spacer()
                                Text(ClientLauncher.displayName(for: selectedLauncherName))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } footer: {
                        Text("Connects via local Wayland socket. No network or SSH required.")
                    }
                }

                if isSSH {
                    Section("Remote Host") {
                        if shows(.sshHost) {
                            TextField(MachineEditorValidation.metadata(for: .sshHost).label, text: $sshHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        if shows(.sshUser) {
                            TextField(MachineEditorValidation.metadata(for: .sshUser).label, text: $sshUser)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        if shows(.sshPort) {
                            TextField(MachineEditorValidation.metadata(for: .sshPort).label, text: sshPortText)
                        }
                        if shows(.sshAuthMethod) {
                            Picker(MachineEditorValidation.metadata(for: .sshAuthMethod).label, selection: $sshAuthMethod) {
                                Text("Password").tag(0)
                                Text("Public Key").tag(1)
                            }
                        }
                        if shows(.sshPassword), sshAuthMethod == 0 {
                            SecureField(MachineEditorValidation.metadata(for: .sshPassword).label, text: $sshPassword)
                        }
                        if sshAuthMethod == 1 {
                            if shows(.sshKeyPath) {
                                TextField(MachineEditorValidation.metadata(for: .sshKeyPath).label, text: $sshKeyPath)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            if shows(.sshKeyPassphrase) {
                                SecureField(
                                    MachineEditorValidation.metadata(for: .sshKeyPassphrase).label,
                                    text: $sshKeyPassphrase
                                )
                            }
                            Button("Generate Key") {
                                do {
                                    let path = try WWNSSHKeygen.generateKeyType(
                                        "ed25519",
                                        passphrase: sshKeyPassphrase
                                    )
                                    sshKeyPath = path
                                    sshAuthMethod = 1
                                    keygenMessage = "Created \(path)"
                                } catch {
                                    keygenMessage = error.localizedDescription
                                }
                            }
                            if let keygenMessage {
                                Text(keygenMessage).font(.caption2)
                            }
                        }
                    }

                    if shows(.remoteCommand) {
                        Section {
                            TextField(
                                type == .sshWaypipe ? "e.g. weston-simple-shm" : "e.g. bash -l",
                                text: $remoteCommand
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        } header: {
                            Text(type == .sshWaypipe ? "Waypipe Remote Command" : "SSH Command")
                        }
                    }

                    if shows(.waypipeEnabled) {
                        Section("Remote Session") {
                            Toggle(
                                MachineEditorValidation.metadata(for: .waypipeEnabled).label,
                                isOn: $waypipeEnabled
                            )
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Machine" : "Add Machine")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(hasValidationIssues)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var sshPortText: Binding<String> {
        Binding(
            get: { String(sshPort) },
            set: { sshPort = MachineEditorValidation.normalizeSSHPort($0, fallback: sshPort) }
        )
    }

    private func persistableEditorState() -> MachineEditorState {
        let base = WatchUIContractAdapters.machineEditorState(from: existingProfile)
        return MachineEditorState(
            id: existingProfile?.id ?? base.id,
            name: name,
            typeRawValue: type.rawValue,
            selectedLauncherName: selectedLauncherName,
            sshHost: MachineEditorValidation.sanitizeSSHHost(sshHost),
            sshUser: sshUser,
            sshPortText: String(MachineEditorValidation.normalizeSSHPort(String(sshPort))),
            sshPassword: sshPassword,
            sshAuthMethod: sshAuthMethod,
            sshKeyPath: sshKeyPath,
            sshKeyPassphrase: sshKeyPassphrase,
            remoteCommand: remoteCommand,
            inputProfile: base.inputProfile,
            bundledAppID: isNative ? selectedLauncherName : base.bundledAppID,
            waypipeEnabled: waypipeEnabled
        )
    }

    private func save() {
        let state = persistableEditorState()
        if isSSH && !MachineEditorValidation.validate(state).isEmpty {
            return
        }
        var profile = WatchUIContractAdapters.profile(from: state)
        if profile.name.isEmpty {
            profile.name = "Unnamed Machine"
        }
        if let baseline = existingProfile {
            profile.favorite = baseline.favorite
            profile.runtimeOverrides.renderer = baseline.runtimeOverrides.renderer
            profile.runtimeOverrides.inputProfile = baseline.runtimeOverrides.inputProfile
            profile.runtimeOverrides.autoScale = baseline.runtimeOverrides.autoScale
            profile.runtimeOverrides.forceSSD = baseline.runtimeOverrides.forceSSD
            profile.runtimeOverrides.renderMacOSPointer = baseline.runtimeOverrides.renderMacOSPointer
            profile.runtimeOverrides.nestedCompositorCursor = baseline.runtimeOverrides.nestedCompositorCursor
            profile.runtimeOverrides.colorOperations = baseline.runtimeOverrides.colorOperations
            profile.runtimeOverrides.waylandDisplay = baseline.runtimeOverrides.waylandDisplay
            profile.runtimeOverrides.logLevel = baseline.runtimeOverrides.logLevel
            profile.runtimeOverrides.shakeToCloseEnabled = baseline.runtimeOverrides.shakeToCloseEnabled
            profile.runtimeOverrides.swipeBackToCloseEnabled = baseline.runtimeOverrides.swipeBackToCloseEnabled
            profile.runtimeOverrides.waypipeSSHPassword = baseline.runtimeOverrides.waypipeSSHPassword
        }
        profileStore.upsert(profile)
        dismiss()
    }
}
#endif
