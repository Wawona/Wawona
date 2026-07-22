#if os(watchOS)
import SwiftUI
import WawonaModel

/// Full-screen client list for native machine profiles / global defaults.
/// Keeps machine editor and settings forms compact (same pattern as iOS/macOS).
struct WatchBundledClientPickerView: View {
    @Binding var selection: String
    let clients: [ClientLauncher]

    init(selection: Binding<String>, clients: [ClientLauncher] = ClientLauncher.presets) {
        self._selection = selection
        self.clients = clients
    }

    var body: some View {
        List(clients) { launcher in
            Button {
                selection = launcher.name
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selection == launcher.name ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection == launcher.name ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(launcher.displayName)
                            .foregroundStyle(.primary)
                        Text(launcher.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Wayland Client")
    }
}
#endif
