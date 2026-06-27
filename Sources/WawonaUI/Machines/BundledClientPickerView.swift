import SwiftUI
import WawonaModel

/// Full-screen client list for native machine profiles (keeps main editor/settings forms compact).
struct BundledClientPickerView: View {
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
                HStack(spacing: 10) {
                    Image(systemName: selection == launcher.name ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection == launcher.name ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(launcher.displayName)
                            .foregroundStyle(.primary)
                        Text(launcher.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Wayland Client")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
