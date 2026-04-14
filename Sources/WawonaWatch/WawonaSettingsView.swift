import SwiftUI
import WawonaModel
import WawonaUI

struct WawonaSettingsView: View {
    @ObservedObject private var prefs: WawonaPreferences

    private let logLevels = ["debug", "info", "warn", "error"]

    init() {
        _prefs = ObservedObject(wrappedValue: WawonaPreferences.shared)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Auto Scale", isOn: $prefs.autoScale)
                    Toggle("Force Server Decorations", isOn: $prefs.forceSSD)
                }

                Section("Wayland") {
                    LabeledContent("Socket") {
                        TextField("wayland-0", text: $prefs.waylandDisplay)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("SSH Defaults") {
                    LabeledContent("Host") {
                        TextField("host.example.com", text: $prefs.sshHost)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("User") {
                        TextField("username", text: $prefs.sshUser)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Logging") {
                    Picker("Log Level", selection: $prefs.logLevel) {
                        ForEach(logLevels, id: \.self) { level in
                            Text(level.capitalized).tag(level)
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #else
                    .pickerStyle(.navigationLink)
                    #endif
                }

                Section("Renderer") {
                    Picker("Renderer", selection: $prefs.renderer) {
                        Text("Metal").tag("metal")
                        Text("Software").tag("software")
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #else
                    .pickerStyle(.navigationLink)
                    #endif
                }
            }
            .navigationTitle("Settings")
            .onAppear { NSLog("[Wawona·Nav] WawonaSettingsView appeared") }
            .onDisappear { prefs.save() }
        }
    }
}
