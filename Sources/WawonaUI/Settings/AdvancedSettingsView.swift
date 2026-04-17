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
                #if os(iOS)
                Toggle("Shake to Exit Machine", isOn: $preferences.shakeToCloseEnabled)
                Text("If disabled, use the iOS swipe-back gesture to close the active machine session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .onDisappear { preferences.save() }
    }
}
