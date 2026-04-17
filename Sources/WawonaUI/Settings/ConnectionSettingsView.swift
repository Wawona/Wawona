import SwiftUI
import WawonaModel
import WawonaUIContracts

struct ConnectionSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences
    @State var waylandDisplayDraft = ""
    @State var diagnosticsSummary = ""

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Wayland Display", text: $waylandDisplayDraft)
            }
            if !diagnosticsSummary.isEmpty {
                Section("Latest Diagnostic") {
                    Text(diagnosticsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            let state = WawonaUIContractAdapters.connectionSettingsState(from: preferences)
            waylandDisplayDraft = state.waylandDisplay
            diagnosticsSummary = state.latestDiagnosticsSummary
        }
        .onDisappear {
            let state = ConnectionSettingsState(
                waylandDisplay: waylandDisplayDraft,
                sshHost: preferences.sshHost,
                sshUser: preferences.sshUser,
                sshPortText: String(preferences.sshPort),
                sshPassword: preferences.sshPassword,
                waypipeCommand: "weston-simple-shm",
                latestDiagnosticsSummary: diagnosticsSummary
            )
            WawonaUIContractAdapters.applyConnectionSettings(state, to: preferences)
        }
    }
}
