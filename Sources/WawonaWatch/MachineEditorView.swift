#if os(watchOS)
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
    @State var inputProfile: String
    @State var bundledAppID: String
    @State var waypipeEnabled: Bool

    private var isEditing: Bool { existingProfile != nil }
    private var isSSH: Bool { type == .sshWaypipe || type == .sshTerminal }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var selectableTypes: [MachineType] {
        MachineType.allCases.filter { $0 != .virtualMachine && $0 != .container }
    }

    init(profileStore: MachineProfileStore, profile: MachineProfile? = nil) {
        self.profileStore = profileStore
        self.existingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _type = State(initialValue: profile?.type ?? .native)
        _sshHost = State(initialValue: profile?.sshHost ?? "")
        _sshUser = State(initialValue: profile?.sshUser ?? "")
        _sshPort = State(initialValue: profile.map { "\($0.sshPort)" } ?? "22")
        _sshPassword = State(initialValue: profile?.sshPassword ?? "")
        _remoteCommand = State(initialValue: profile?.remoteCommand ?? "weston-simple-shm")
        _selectedLauncherName = State(initialValue: profile?.launchers.first?.name ?? "weston-terminal")
        _inputProfile = State(initialValue: profile?.runtimeOverrides.inputProfile ?? "direct")
        _bundledAppID = State(initialValue: profile?.runtimeOverrides.bundledAppID ?? "")
        _waypipeEnabled = State(initialValue: profile?.runtimeOverrides.waypipeEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(selectableTypes, id: \.self) { t in
                            Label(t.userFacingName, systemImage: t.symbolName).tag(t)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                if type == .native {
                    Section("Wayland Client") {
                        ForEach(ClientLauncher.presets, id: \.name) { launcher in
                            Button {
                                selectedLauncherName = launcher.name
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedLauncherName == launcher.name ? "checkmark.circle.fill" : "circle")
                                    Text(launcher.displayName)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if isSSH {
                    Section("Remote Host") {
                        TextField("Host", text: $sshHost)
                        TextField("Username", text: $sshUser)
                        SecureField("Password", text: $sshPassword)
                        TextField("Port", text: $sshPort)
                        TextField(type == .sshWaypipe ? "Waypipe command" : "SSH command", text: $remoteCommand)
                    }
                    Section("Remote Session") {
                        Toggle("Waypipe Enabled", isOn: $waypipeEnabled)
                    }
                }
                Section("Input") {
                    TextField("Input Profile", text: $inputProfile)
                }
                Section("Native Session") {
                    TextField("Bundled App ID", text: $bundledAppID)
                }
            }
            .navigationTitle(isEditing ? "Edit Machine" : "Add Machine")
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
        var profile = existingProfile ?? MachineProfile(name: "", type: type)
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.type = type
        profile.sshHost = sshHost.trimmingCharacters(in: .whitespaces)
        profile.sshUser = sshUser.trimmingCharacters(in: .whitespaces)
        profile.sshPort = Int(sshPort.trimmingCharacters(in: .whitespaces)) ?? 22
        profile.sshPassword = sshPassword
        profile.remoteCommand = remoteCommand.trimmingCharacters(in: .whitespaces)
        profile.runtimeOverrides.inputProfile = inputProfile.trimmingCharacters(in: .whitespaces)
        profile.runtimeOverrides.bundledAppID = bundledAppID.trimmingCharacters(in: .whitespaces)
        profile.runtimeOverrides.waypipeEnabled = waypipeEnabled
        if type == .native {
            profile.launchers = ClientLauncher.presets.filter { $0.name == selectedLauncherName }
        } else {
            profile.launchers = []
        }
        profileStore.upsert(profile)
        dismiss()
    }
}
#endif
