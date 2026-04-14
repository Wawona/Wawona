import SwiftUI
import WawonaModel

struct AdvancedSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            Section("Advanced") {
                Picker("Log Level", selection: $preferences.logLevel) {
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Warn").tag("warn")
                    Text("Error").tag("error")
                }
            }
        }
        .onDisappear { preferences.save() }
    }
}
