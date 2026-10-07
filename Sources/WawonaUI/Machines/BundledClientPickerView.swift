import SwiftUI
import WawonaModel

/// Full-screen Wayland software list for native machine profiles.
/// Compositors first, then client types. Custom commands belong under Terminal.
struct BundledClientPickerView: View {
    @Binding var selection: String
    let clients: [ClientLauncher]

    init(
        selection: Binding<String>,
        clients: [ClientLauncher] = ClientLauncher.presets
    ) {
        self._selection = selection
        self.clients = clients
    }

    private var grouped: [(kind: BundledWaylandSoftwareKind, clients: [ClientLauncher])] {
        clients.waylandPickerGrouped()
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.kind) { group in
                Section(group.kind.sectionTitle) {
                    ForEach(group.clients) { launcher in
                        row(
                            id: launcher.name,
                            title: launcher.displayName,
                            subtitle: launcher.name
                        )
                    }
                }
            }
        }
        .backport.navigationTitle("Wayland Software", inline: true)
        .onAppear {
            if selection == "custom" {
                selection = "weston-simple-shm"
            }
        }
    }

    @ViewBuilder
    private func row(id: String, title: String, subtitle: String) -> some View {
        WawonaButton {
            selection = id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == id ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selection == id ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
