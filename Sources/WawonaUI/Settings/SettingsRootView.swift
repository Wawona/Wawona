import SwiftUI
import WawonaModel

struct SettingsRootView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @State var selection: String? = "global-display"
    @State var machineSelection: String?

    var body: some View {
        AdaptiveNavigationView {
            List {
                Section("Global Wawona Settings") {
                    Button("Display") { selection = "global-display" }
                    Button("Input") { selection = "global-input" }
                    Button("Graphics") { selection = "global-graphics" }
                    Button("Connection Defaults") { selection = "global-connection" }
                    Button("SSH / Waypipe Defaults") { selection = "global-ssh" }
                    Button("Clients") { selection = "global-clients" }
                    Button("Advanced") { selection = "global-advanced" }
                    Button("Connection Tests") { selection = "global-tests" }
                    Button("Diagnostics") { selection = "global-diagnostics" }
                    Button("About") { selection = "global-about" }
                }
                Section("Machine Settings") {
                    if profileStore.profiles.isEmpty {
                        Text("No machine profiles yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profileStore.profiles) { profile in
                            Button(profile.name) {
                                machineSelection = profile.id
                                selection = "machine-settings"
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        } detail: {
            switch selection {
            case "global-display": DisplaySettingsView(preferences: preferences)
            case "global-input": InputSettingsView(preferences: preferences)
            case "global-graphics": GraphicsSettingsView(preferences: preferences)
            case "global-connection": ConnectionSettingsView(preferences: preferences)
            case "global-ssh": SSHWaypipeSettingsView(preferences: preferences)
            case "global-clients": ClientsSettingsView(preferences: preferences)
            case "global-advanced": AdvancedSettingsView(preferences: preferences)
            case "global-tests":
                GlobalConnectionTestsView(preferences: preferences)
            case "global-diagnostics":
                SettingsDiagnosticsView(preferences: preferences)
            case "global-about": AboutView()
            case "machine-settings":
                MachineSettingsView(
                    preferences: preferences,
                    profileStore: profileStore,
                    machineID: machineSelection ?? profileStore.activeMachineId
                )
            default:
                DisplaySettingsView(preferences: preferences)
            }
        }
        .onAppear {
            if machineSelection == nil {
                machineSelection = profileStore.activeMachineId ?? profileStore.profiles.first?.id
            }
        }
    }
}
