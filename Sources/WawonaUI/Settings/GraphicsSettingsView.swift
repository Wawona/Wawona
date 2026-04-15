import SwiftUI
import WawonaModel

struct GraphicsSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences
    @State var rendererOptions = ["metal", "vulkan", "software"]

    var body: some View {
        Form {
            Section("Graphics") {
                Picker("Renderer", selection: $preferences.renderer) {
                    ForEach(rendererOptions, id: \.self) { option in
                        Text(option.capitalized).tag(option)
                    }
                }
                Toggle("Force Server-Side Decorations", isOn: $preferences.forceSSD)
                Toggle("HDR / Color Operations", isOn: $preferences.colorOperations)
            }
        }
        .onDisappear { preferences.save() }
    }
}
