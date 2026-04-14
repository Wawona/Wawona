import SwiftUI
import WawonaModel

struct ClientsSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            Section("Default Launchers") {
                ForEach(preferences.globalClientLaunchers) { launcher in
                    VStack(alignment: .leading) {
                        Text(launcher.displayName).font(.headline)
                        Text("\(launcher.executablePath) \(launcher.arguments.joined(separator: " "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Add Weston Terminal") {
                    preferences.globalClientLaunchers.append(
                        ClientLauncher(
                            name: "weston-terminal",
                            executablePath: "weston-terminal",
                            displayName: "Weston Terminal"
                        )
                    )
                }
            }
        }
        .onDisappear { preferences.save() }
    }
}
