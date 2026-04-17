import SwiftUI
import WawonaModel

struct GlobalConnectionTestsView: View {
    @ObservedObject var preferences: WawonaPreferences
    @State var sshHost = ""
    @State var sshUser = ""
    @State var sshPassword = ""
    @State var sshPort = "22"
    @State var waypipeCommand = "weston-simple-shm"
    @State var latestMessage = ""
    @State var runtimeProbeEnabled = true

    var body: some View {
        Form {
            Section("Diagnostic Mode") {
                Toggle("Run Runtime Probes", isOn: $runtimeProbeEnabled)
                Text(runtimeProbeEnabled
                     ? "Runs executable availability checks in addition to config linting."
                     : "Runs config-only lint checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("SSH Connection Test") {
                TextField("Host", text: $sshHost)
                TextField("User", text: $sshUser)
                SecureField("Password", text: $sshPassword)
                    .textContentType(.password)
                TextField("Port", text: $sshPort)
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                Button("Test SSH") {
                    let entry = preferences.testSSHConnection(
                        host: sshHost,
                        user: sshUser,
                        password: sshPassword,
                        port: Int(sshPort) ?? 22,
                        runtimeProbe: runtimeProbeEnabled
                    )
                    latestMessage = entry.message
                }
            }

            Section("Waypipe Command Test") {
                TextField("Command", text: $waypipeCommand)
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                Button("Test Waypipe Command") {
                    let entry = preferences.testWaypipeCommand(
                        waypipeCommand,
                        runtimeProbe: runtimeProbeEnabled
                    )
                    latestMessage = entry.message
                }
            }

            Section("Dependencies") {
                Button("Run Dependency Diagnostics") {
                    let entry = preferences.runDependencyDiagnostics(runtimeProbe: runtimeProbeEnabled)
                    latestMessage = entry.message
                }
            }

            if !latestMessage.isEmpty {
                Section("Latest Result") {
                    Text(latestMessage)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Connection Tests")
        .onAppear {
            sshHost = preferences.sshHost
            sshUser = preferences.sshUser
            sshPassword = preferences.sshPassword
            sshPort = String(preferences.sshPort)
        }
    }
}
