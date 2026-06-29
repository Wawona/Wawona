#if os(watchOS)
import SwiftUI
import WawonaModel

/// Watch-local machine overrides editor.
/// Keeps watch target independent from the app-only `WawonaUI` module.
struct MachineSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    var machineID: String?

    @State private var selectedID: String?
    @State private var draft: MachineProfile?

    var body: some View {
        Form {
            Section {
                Button("Open Wawona Settings…") {
                    WatchKitGlobalSettings.open()
                }
                Text("Global defaults live in WatchKit settings. Values below override them for this machine only.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Machine") {
                if profileStore.profiles.isEmpty {
                    Text("No machine profiles available.")
                        .foregroundStyle(.secondary)
                } else if let machineID,
                          let profile = profileStore.profiles.first(where: { $0.id == machineID }) {
                    Text(profile.name)
                        .font(.headline)
                } else {
                    Picker("Profile", selection: Binding(
                        get: { selectedID ?? profileStore.profiles.first?.id ?? "" },
                        set: { value in
                            selectedID = value
                            loadDraft()
                        }
                    )) {
                        ForEach(profileStore.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                }
            }

            if draft != nil {
                Section("Connection") {
                    TextField("Host", text: sshHostBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("User", text: sshUserBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: sshPortBinding)
                    SecureField("Password", text: sshPasswordBinding)
                    TextField("Remote Command", text: remoteCommandBinding)
                }

                Section("Runtime Overrides") {
                    TextField("Input Profile", text: inputProfileBinding)
                    if draft?.type == .native {
                        NavigationLink {
                            WatchBundledClientPickerView(selection: bundledAppIDSelectionBinding)
                        } label: {
                            HStack {
                                Text("Wayland Client")
                                Spacer()
                                Text(ClientLauncher.displayName(for: resolvedBundledAppID))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Toggle("Waypipe Enabled", isOn: waypipeEnabledBinding)
                        .disabled(draft?.type == .native)
                }

                Section {
                    Button("Save Machine Settings") {
                        guard let draft else { return }
                        profileStore.upsert(draft)
                        profileStore.activeMachineId = draft.id
                        profileStore.save()
                    }
                }
            }
        }
        .navigationTitle("Machine Settings")
        .onAppear {
            selectedID = machineID ?? profileStore.activeMachineId ?? profileStore.profiles.first?.id
            loadDraft()
        }
    }

    private func loadDraft() {
        guard let selectedID,
              let profile = profileStore.profiles.first(where: { $0.id == selectedID }) else {
            draft = nil
            return
        }
        draft = profile
    }

    private func updateDraft(_ mutate: (inout MachineProfile) -> Void) {
        guard var copy = draft else { return }
        mutate(&copy)
        draft = copy
    }

    private var sshHostBinding: Binding<String> {
        Binding(
            get: { draft?.sshHost ?? "" },
            set: { value in updateDraft { $0.sshHost = value } }
        )
    }

    private var sshUserBinding: Binding<String> {
        Binding(
            get: { draft?.sshUser ?? "" },
            set: { value in updateDraft { $0.sshUser = value } }
        )
    }

    private var sshPortBinding: Binding<String> {
        Binding(
            get: { String(draft?.sshPort ?? 22) },
            set: { value in
                updateDraft { profile in
                    profile.sshPort = Int(value) ?? profile.sshPort
                }
            }
        )
    }

    private var sshPasswordBinding: Binding<String> {
        Binding(
            get: { draft?.sshPassword ?? "" },
            set: { value in updateDraft { $0.sshPassword = value } }
        )
    }

    private var remoteCommandBinding: Binding<String> {
        Binding(
            get: { draft?.remoteCommand ?? "" },
            set: { value in updateDraft { $0.remoteCommand = value } }
        )
    }

    private var inputProfileBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.inputProfile ?? preferences.defaultInputProfile },
            set: { value in updateDraft { $0.runtimeOverrides.inputProfile = value } }
        )
    }

    private var resolvedBundledAppID: String {
        let raw = draft?.runtimeOverrides.bundledAppID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? preferences.defaultBundledAppID : raw
    }

    private var bundledAppIDSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedBundledAppID },
            set: { value in updateDraft { $0.runtimeOverrides.bundledAppID = value } }
        )
    }

    private var waypipeEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft?.runtimeOverrides.waypipeEnabled ?? preferences.defaultWaypipeEnabled },
            set: { value in updateDraft { $0.runtimeOverrides.waypipeEnabled = value } }
        )
    }
}

private struct WatchBundledClientPickerView: View {
    @Binding var selection: String

    var body: some View {
        List(ClientLauncher.presets) { launcher in
            Button {
                selection = launcher.name
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selection == launcher.name ? "checkmark.circle.fill" : "circle")
                    VStack(alignment: .leading) {
                        Text(launcher.displayName)
                        Text(launcher.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Wayland Client")
    }
}
#endif
