import SwiftUI
import WawonaModel

struct MachineEditorView: View {
    let profileStore: MachineProfileStore
    let existingProfile: MachineProfile?

    @Environment(\.dismiss) var dismiss

    @State var name: String
    @State var type: MachineType
    @State var sshHost: String
    @State var sshUser: String
    @State var sshPort: String
    @State var sshPassword: String
    @State var remoteCommand: String
    @State var selectedLauncherName: String

    private var isEditing: Bool { existingProfile != nil }
    private var isSSH: Bool { type == .sshWaypipe || type == .sshTerminal }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(profileStore: MachineProfileStore, profile: MachineProfile? = nil) {
        self.profileStore = profileStore
        self.existingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _type = State(initialValue: profile?.type ?? .native)
        _sshHost = State(initialValue: profile?.sshHost ?? "")
        _sshUser = State(initialValue: profile?.sshUser ?? "")
        _sshPort = State(initialValue: profile.map { "\($0.sshPort)" } ?? "22")
        _sshPassword = State(initialValue: profile?.sshPassword ?? "")
        _remoteCommand = State(initialValue: profile?.remoteCommand ?? "weston-terminal")
        _selectedLauncherName = State(initialValue: profile?.launchers.first?.name ?? "weston-terminal")
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Identity + type in one compact section
                Section("Profile") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(MachineType.allCases, id: \.self) { t in
                            Label(t.watchDisplayName, systemImage: t.watchSystemImage).tag(t)
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #else
                    .pickerStyle(.navigationLink)
                    #endif
                }

                // MARK: Native — local Wayland socket, no network
                if type == .native {
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
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(launcher.displayName)
                                            .foregroundStyle(.primary)
                                            .font(.subheadline)
                                        Text(launcher.name)
                                            .foregroundStyle(.secondary)
                                            .font(.caption2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Wayland Client")
                    } footer: {
                        Text("Local socket — no network required.")
                            .font(.caption2)
                    }
                }

                // MARK: SSH — remote machine via network
                if isSSH {
                    Section("Remote Host") {
                        TextField("Host", text: $sshHost)
                            #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        TextField("Username", text: $sshUser)
                            #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        SecureField("Password", text: $sshPassword)
                            .textContentType(.password)
                        TextField("Port", text: $sshPort)
                            .autocorrectionDisabled()
                        TextField(
                            type == .sshWaypipe ? "Waypipe command" : "SSH command",
                            text: $remoteCommand
                        )
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Machine" : "Add Machine")
            .onAppear {
                NSLog("[Wawona·Nav] MachineEditorView appeared — %@",
                      isEditing ? "editing '\(existingProfile?.name ?? "?")'" : "adding new")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        // Preserve the existing ID on update so upsert replaces the right profile.
        var profile = existingProfile ?? MachineProfile(name: "", type: type)
        profile.name    = name.trimmingCharacters(in: .whitespaces)
        profile.type    = type
        profile.sshHost = sshHost.trimmingCharacters(in: .whitespaces)
        profile.sshUser = sshUser.trimmingCharacters(in: .whitespaces)
        profile.sshPort = Int(sshPort.trimmingCharacters(in: .whitespaces)) ?? 22
        profile.sshPassword = sshPassword
        profile.remoteCommand = remoteCommand.trimmingCharacters(in: .whitespaces)

        if type == .native {
            profile.launchers = ClientLauncher.presets
                .filter { $0.name == selectedLauncherName }
        } else {
            profile.launchers = []
        }

        profileStore.upsert(profile)
        dismiss()
    }
}
