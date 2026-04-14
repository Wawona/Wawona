import SwiftUI
import WawonaModel

struct DisplaySettingsView: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Auto Scale", isOn: $preferences.autoScale)
                TextField("Wayland Display", text: $preferences.waylandDisplay)
            }
            Section("Preview") {
                CompositorBridge()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .onDisappear { preferences.save() }
    }
}
