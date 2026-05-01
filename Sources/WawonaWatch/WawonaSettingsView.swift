import SwiftUI
import WawonaModel

struct WawonaWatchSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = WawonaPreferences.shared
    @ObservedObject var profileStore: MachineProfileStore

    init(profileStore: MachineProfileStore) {
        _profileStore = ObservedObject(wrappedValue: profileStore)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Globals below; per-machine values in “Overrides” replace them for that machine only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("Display") {
                    Toggle("Auto Scale", isOn: boolBinding(\.autoScale))
                    Toggle("Force SSD", isOn: boolBinding(\.forceSSD))
                    Toggle("Color Operations (HDR)", isOn: boolBinding(\.colorOperations))
                }
                Section("Graphics") {
                    Picker("Renderer", selection: stringBinding(\.renderer)) {
                        Text("Metal").tag("metal")
                        Text("Software").tag("software")
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("Connection") {
                    TextField("Wayland Display", text: stringBinding(\.waylandDisplay))
                    TextField("Input Profile", text: stringBinding(\.defaultInputProfile))
                    TextField("Bundled App ID", text: stringBinding(\.defaultBundledAppID))
                    Toggle("Waypipe by Default", isOn: boolBinding(\.defaultWaypipeEnabled))
                }
                Section("SSH Defaults") {
                    TextField("Host", text: stringBinding(\.sshHost))
                        .textInputAutocapitalization(.never)
                    TextField("User", text: stringBinding(\.sshUser))
                    TextField("Port", value: intBinding(\.sshPort), format: .number)
                }
                Section("Advanced") {
                    Picker("Log Level", selection: stringBinding(\.logLevel)) {
                        Text("Debug").tag("debug")
                        Text("Info").tag("info")
                        Text("Warn").tag("warn")
                    }
                    .pickerStyle(.navigationLink)
                    Toggle("XWayland Support", isOn: boolBinding(\.xwaylandSupport))
                    Toggle("Shake to Close", isOn: boolBinding(\.shakeToCloseEnabled))
                }
                Section("Per-Machine Overrides") {
                    if profileStore.profiles.isEmpty {
                        Text("No machines yet. Add one from the list.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profileStore.profiles) { profile in
                            NavigationLink {
                                MachineSettingsView(
                                    preferences: WawonaPreferences.shared,
                                    profileStore: profileStore,
                                    machineID: profile.id
                                )
                            } label: {
                                Text(profile.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wawona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        preferences.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<WawonaPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0; preferences.save() }
        )
    }

    private func stringBinding(_ keyPath: ReferenceWritableKeyPath<WawonaPreferences, String>) -> Binding<String> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0; preferences.save() }
        )
    }

    private func intBinding(_ keyPath: ReferenceWritableKeyPath<WawonaPreferences, Int>) -> Binding<Int> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0; preferences.save() }
        )
    }
}
