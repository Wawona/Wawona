import SwiftUI
import WawonaModel
import WawonaUIContracts

struct MachineEditorView: View {
    @Environment(\.dismiss) var dismiss

    @State var name = ""
    @State var type: MachineType = .native
    @State var selectedLauncherName = ClientLauncher.presets.first?.name ?? "weston-simple-shm"

    // SSH-only fields — not shown for native type
    @State var sshHost = ""
    @State var sshUser = ""
    @State var sshPort = 22
    @State var sshPassword = ""
    @State var remoteCommand = ""

    let onSave: (MachineProfile) -> Void

    private var isNative: Bool { type == .native }
    private var isSSH:    Bool { type == .sshWaypipe || type == .sshTerminal }
    private var contractState: MachineEditorState {
        MachineEditorState(
            name: name,
            typeRawValue: type.rawValue,
            selectedLauncherName: selectedLauncherName,
            sshHost: sshHost,
            sshUser: sshUser,
            sshPortText: String(sshPort),
            sshPassword: sshPassword,
            remoteCommand: remoteCommand
        )
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
                            Text(t.rawValue).tag(t)
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
            .navigationTitle(name.isEmpty ? "New Machine" : name)
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
        let state = MachineEditorState(
            name: name,
            typeRawValue: type.rawValue,
            selectedLauncherName: selectedLauncherName,
            sshHost: sshHost,
            sshUser: sshUser,
            sshPortText: String(sshPort),
            sshPassword: sshPassword,
            remoteCommand: remoteCommand
        )
        if !MachineEditorValidation.validate(state).isEmpty {
            return
        }
        var profile = WawonaUIContractAdapters.profile(from: state)
        if profile.name.isEmpty {
            profile.name = "Unnamed"
        }
        onSave(profile)
        dismiss()
    }
}
