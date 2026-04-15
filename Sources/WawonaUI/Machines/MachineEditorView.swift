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
        _type = State(initialValue: MachineType(rawValue: state.typeRawValue) ?? .native)
        _selectedLauncherName = State(initialValue: state.selectedLauncherName)
        _sshHost = State(initialValue: state.sshHost)
        _sshUser = State(initialValue: state.sshUser)
        _sshPort = State(initialValue: MachineEditorValidation.normalizedPort(from: state))
        _sshPassword = State(initialValue: state.sshPassword)
        _remoteCommand = State(initialValue: state.remoteCommand)
    }

    private var isNative: Bool { type == .native }
    private var isSSH:    Bool { type == .sshWaypipe || type == .sshTerminal }
    private var contractState: MachineEditorState {
        persistableEditorState()
    }

    private func persistableEditorState() -> MachineEditorState {
        let base = WawonaUIContractAdapters.machineEditorState(from: editingBaseline)
        return MachineEditorState(
            id: existingProfileId ?? base.id,
            name: name,
            typeRawValue: type.rawValue,
            selectedLauncherName: selectedLauncherName,
            sshHost: sshHost,
            sshUser: sshUser,
            sshPortText: String(sshPort),
            sshPassword: sshPassword,
            remoteCommand: remoteCommand,
            vmSubtype: base.vmSubtype,
            containerSubtype: base.containerSubtype,
            inputProfile: base.inputProfile,
            bundledAppID: base.bundledAppID,
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
            set: { sshPort = Int($0) ?? sshPort }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Identity + type in one compact section
                Section("Profile") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(MachineType.allCases, id: \.self) { t in
                            Text(t.userFacingName).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // MARK: Native — local Wayland socket, no network
                if isNative {
                    Section {
                        ForEach(ClientLauncher.presets, id: \.name) { launcher in
                            Button {
                                selectedLauncherName = launcher.name
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedLauncherName == launcher.name
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedLauncherName == launcher.name
                                                         ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(launcher.displayName)
                                            .foregroundStyle(.primary)
                                        Text(launcher.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Wayland Client")
                    } footer: {
                        Text("Connects to the compositor via local Wayland socket. No network or SSH required.")
                    }
                }

                // MARK: SSH — remote machine via network
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
                    }

                    Section {
                        TextField(
                            type == .sshWaypipe ? "e.g. weston-terminal" : "e.g. bash -l",
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
