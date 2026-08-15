#if os(watchOS)
import SwiftUI
import WawonaModel

struct MachineEditorView: View {
    @ObservedObject var profileStore: MachineProfileStore
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
    @State var waypipeEnabled: Bool

    private var isEditing: Bool { existingProfile != nil }
    private var isSSH: Bool { type == .sshWaypipe || type == .sshTerminal }
    /// Name is optional — empty saves as "Unnamed Machine" (macOS/iOS parity).
    /// SSH still needs host + user.
    private var canSave: Bool {
        guard isSSH else { return true }
        let host = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        return !host.isEmpty && !user.isEmpty
    }
    private var selectableTypes: [MachineType] {
        PlatformCapabilities.availableMachineTypes
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
        let launcher = profile?.runtimeOverrides.bundledAppID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = profile?.launchers.first?.name ?? "weston-simple-shm"
        _selectedLauncherName = State(initialValue: launcher.isEmpty ? fallback : launcher)
        _inputProfile = State(initialValue: profile?.runtimeOverrides.inputProfile ?? "direct")
        _waypipeEnabled = State(initialValue: profile?.runtimeOverrides.waypipeEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Unnamed Machine", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(selectableTypes, id: \.self) { t in
                            Label(t.userFacingName, systemImage: t.symbolName).tag(t)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if type == .native {
                    Section {
                        NavigationLink {
                            WatchBundledClientPickerView(selection: $selectedLauncherName)
                        } label: {
                            HStack {
                                Text("Wayland Client")
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
                        TextField("Host", text: $sshHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Username", text: $sshUser)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $sshPassword)
                        TextField("Port", text: $sshPort)
                        TextField(
                            type == .sshWaypipe ? "Waypipe command" : "SSH command",
                            text: $remoteCommand
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    Section("Remote Session") {
                        Toggle("Waypipe Enabled", isOn: $waypipeEnabled)
                    }
                }

                Section("Input") {
                    TextField("Input Profile", text: $inputProfile)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.name = trimmedName.isEmpty ? "Unnamed Machine" : trimmedName
        profile.type = type
        profile.sshHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.sshUser = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.sshPort = Int(sshPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22
        profile.sshPassword = sshPassword
        profile.remoteCommand = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.runtimeOverrides.inputProfile = inputProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.runtimeOverrides.waypipeEnabled = waypipeEnabled
        if type == .native {
            profile.runtimeOverrides.bundledAppID = selectedLauncherName
            profile.launchers = ClientLauncher.presets.filter { $0.name == selectedLauncherName }
        } else {
            profile.runtimeOverrides.bundledAppID = nil
            profile.launchers = []
        }
        profileStore.upsert(profile)
        dismiss()
    }
}
#endif
