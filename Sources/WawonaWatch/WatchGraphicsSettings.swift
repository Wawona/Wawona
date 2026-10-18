#if os(watchOS)
import SwiftUI
import WawonaModel

/// Watch present is software frames composited by SpriteKit.
struct WatchGraphicsSettingsPage: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        List {
            Section {
                Picker("Renderer", selection: $preferences.renderer) {
                    Text("Software").tag("software")
                }
                .onChange(of: preferences.renderer) { _, _ in preferences.save() }
            } footer: {
                Text("Software rendering draws each frame.")
            }
            Section {
                Toggle("SpriteKit Present Accelerator", isOn: $preferences.spritePresentAccelerator)
                    .onChange(of: preferences.spritePresentAccelerator) { _, _ in preferences.save() }
                    .accessibilityIdentifier("wwn.settings.graphics.spritePresent")
            } footer: {
                Text("SpriteKit composites the software frame onto the watch. Off uses a CPU image blit.")
            }
            Section {
            Toggle("Session Thumbnails", isOn: $preferences.machineSessionThumbnailsEnabled)
                .onChange(of: preferences.machineSessionThumbnailsEnabled) { _, _ in preferences.save() }
                .accessibilityIdentifier("wwn.settings.graphics.sessionThumbnails")
            } footer: {
                Text("Capture machine thumbnails while a session is running.")
            }
        }
        .navigationTitle("Graphics")
        .onAppear {
            if preferences.renderer != "software" {
                preferences.renderer = "software"
                preferences.save()
            }
        }
    }
}
#endif
