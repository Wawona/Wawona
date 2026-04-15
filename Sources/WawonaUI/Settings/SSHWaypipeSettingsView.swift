import SwiftUI
import WawonaModel

struct SSHWaypipeSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences
    @State var defaultBundledAppID = ""
    @State var defaultWaypipeEnabled = true
    private var sshPortText: Binding<String> {
        Binding(
            get: { String(preferences.sshPort) },
            set: { preferences.sshPort = Int($0) ?? preferences.sshPort }
        )
    }

    var body: some View {
        Form {
            Section("SSH") {
                TextField("Host", text: $preferences.sshHost)
                TextField("User", text: $preferences.sshUser)
                SecureField("Password", text: $preferences.sshPassword)
                    .textContentType(.password)
                TextField("Port", text: sshPortText)
                    .autocorrectionDisabled()
            }
            Section("Waypipe") {
                SecureField("Waypipe Password (optional override)", text: $preferences.waypipeSSHPassword)
                    .textContentType(.password)
                Toggle("Default Waypipe Enabled", isOn: $defaultWaypipeEnabled)
            }
            Section("Native Bundled App Default") {
                TextField("Bundled App ID", text: $defaultBundledAppID)
                    .autocorrectionDisabled()
            }
        }
        .onAppear {
            defaultBundledAppID = preferences.defaultBundledAppID
            defaultWaypipeEnabled = preferences.defaultWaypipeEnabled
        }
        .onDisappear {
            preferences.defaultBundledAppID = defaultBundledAppID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            preferences.defaultWaypipeEnabled = defaultWaypipeEnabled
            preferences.save()
        }
    }
}
