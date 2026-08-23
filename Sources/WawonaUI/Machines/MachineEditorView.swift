import SwiftUI
import WawonaModel
import WawonaUIContracts

struct MachineEditorView: View {
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

    let existingProfileId: String?
    /// Snapshot for fields this form does not edit (VM/container metadata, favorites, renderer, etc.).
    let editingBaseline: MachineProfile?
    let onSave: (MachineProfile) -> Void

    init(profile: MachineProfile? = nil, onSave: @escaping (MachineProfile) -> Void) {
        self.existingProfileId = profile?.id
        self.editingBaseline = profile
        self.onSave = onSave
        let state = WawonaUIContractAdapters.machineEditorState(from: profile)
        _name = State(initialValue: state.name)
        #if os(iOS)
        let parsed = MachineType(rawValue: state.typeRawValue) ?? .native
        _type = State(initialValue: parsed == .container ? .native : parsed)
        #else
        _type = State(initialValue: MachineType(rawValue: state.typeRawValue) ?? .native)
        #endif
        _selectedLauncherName = State(initialValue: state.selectedLauncherName)
        _sshHost = State(initialValue: state.sshHost)
        _sshUser = State(initialValue: state.sshUser)
        _sshPort = State(initialValue: MachineEditorValidation.normalizedPort(from: state))
        _sshPassword = State(initialValue: state.sshPassword)
        _sshAuthMethod = State(initialValue: state.sshAuthMethod)
        _sshKeyPath = State(initialValue: state.sshKeyPath)
        _sshKeyPassphrase = State(initialValue: state.sshKeyPassphrase)
        _remoteCommand = State(initialValue: state.remoteCommand)
    }

    private var isNative: Bool { type == .native }
    private var isSSH:    Bool { type == .sshWaypipe || type == .sshTerminal }
    private var contractState: MachineEditorState {
        persistableEditorState()
    }

    private func persistableEditorState() -> MachineEditorState {
        let base = WawonaUIContractAdapters.machineEditorState(from: editingBaseline)
        let sanitizedHost = MachineEditorValidation.sanitizeSSHHost(sshHost)
        let normalizedPort = MachineEditorValidation.normalizeSSHPort(String(sshPort))
        return MachineEditorState(
            id: existingProfileId ?? base.id,
            name: name,
            typeRawValue: type.rawValue,
            selectedLauncherName: selectedLauncherName,
            sshHost: sanitizedHost,
            sshUser: sshUser,
            sshPortText: String(normalizedPort),
            sshPassword: sshPassword,
            sshAuthMethod: sshAuthMethod,
            sshKeyPath: sshKeyPath,
            sshKeyPassphrase: sshKeyPassphrase,
            remoteCommand: remoteCommand,
            inputProfile: base.inputProfile,
            bundledAppID: isNative ? selectedLauncherName : base.bundledAppID,
            waypipeEnabled: base.waypipeEnabled
        )
    }

    private var editorNavigationTitle: String {
        if existingProfileId != nil {
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Edit Machine" : name
        }
        return name.isEmpty ? "New Machine" : name
    }
    private var hasValidationIssues: Bool {
        !MachineEditorValidation.validate(contractState).isEmpty
    }
    private var sshPortText: Binding<String> {
        Binding(
            get: { String(sshPort) },
            set: { sshPort = MachineEditorValidation.normalizeSSHPort($0, fallback: sshPort) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Identity + type in one compact section
                Section("Profile") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(PlatformCapabilities.availableMachineTypes, id: \.self) { t in
                            Text(t.userFacingName).tag(t)
                        }
                    }
                    .wwnMachineChoicePicker()
                }

                // MARK: Native. Local Wayland socket, no network
                if isNative {
                    Section {
                        #if os(macOS)
                        Picker("Wayland Client", selection: $selectedLauncherName) {
                            ForEach(ClientLauncher.presets) { launcher in
                                Text(launcher.displayName).tag(launcher.name)
                            }
                        }
                        .wwnMachineChoicePicker()
                        #else
                        NavigationLink {
                            BundledClientPickerView(selection: $selectedLauncherName)
                        } label: {
                            HStack {
                                Text("Wayland Client")
                                Spacer()
                                Text(ClientLauncher.displayName(for: selectedLauncherName))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        #endif
                    } footer: {
                        Text("Connects to the compositor via local Wayland socket. No network or SSH required.")
                    }
                }

                // MARK: SSH. Remote machine via network
                if isSSH {
                    Section("Remote Host") {
                        TextField("Host", text: $sshHost)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        TextField("Username", text: $sshUser)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        SecureField("Password", text: $sshPassword)
                            .textContentType(.password)
                        TextField("Port", text: sshPortText)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        Picker("Auth", selection: $sshAuthMethod) {
                            Text("Password").tag(0)
                            Text("Public Key").tag(1)
                        }
                        .wwnMachineChoicePicker()
                        TextField("Key Path", text: $sshKeyPath)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        SecureField("Key Passphrase", text: $sshKeyPassphrase)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                    }

                    Section {
                        TextField(
                            type == .sshWaypipe ? "e.g. weston-simple-shm" : "e.g. bash -l",
                            text: $remoteCommand
                        )
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                    } header: {
                        Text(type == .sshWaypipe ? "Waypipe Remote Command" : "SSH Command")
                    } footer: {
                        Text(type == .sshWaypipe
                             ? "Command to run on the remote host via waypipe."
                             : "Command to run in the remote SSH session.")
                    }
                }
            }
            .navigationTitle(editorNavigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(hasValidationIssues)
                }
            }
        }
    }

    private func save() {
        let state = persistableEditorState()
        if !MachineEditorValidation.validate(state).isEmpty {
            return
        }
        var profile = WawonaUIContractAdapters.profile(from: state)
        if profile.name.isEmpty {
            profile.name = "Unnamed"
        }
        if let baseline = editingBaseline {
            profile.favorite = baseline.favorite
            profile.runtimeOverrides.renderer = baseline.runtimeOverrides.renderer
        }
        onSave(profile)
        dismiss()
    }
}

private extension View {
    @ViewBuilder
    func wwnMachineChoicePicker() -> some View {
        #if os(macOS)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.navigationLink)
        #endif
    }
}
