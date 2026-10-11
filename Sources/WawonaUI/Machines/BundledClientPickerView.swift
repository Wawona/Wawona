import SwiftUI
import WawonaModel

/// Wayland software list for native machine profiles.
/// Installed debs + wpm wasm first. In-app keep-set clients follow while unlink
/// is incomplete. Store builds never list APT. See `wawona-optional-software`.
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

    private var installed: [InstalledOptionalSoftware.Entry] {
        InstalledOptionalSoftware.allInstalled()
    }

    private var grouped: [(kind: BundledWaylandSoftwareKind, clients: [ClientLauncher])] {
        clients.waylandPickerGrouped()
    }

    var body: some View {
        List {
            Section(header: Text("Installed")) {
                if installed.isEmpty {
                    Text("Install Wayland clients with wpm (store) or apt debs (jailbreak / Termux / Linux). Default session is Native Shell.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(installed, id: \.id) { entry in
                        row(
                            id: entry.id,
                            title: entry.displayName,
                            subtitle: "\(entry.source.rawValue): \(entry.executablePath)"
                        )
                    }
                }
            }

            ForEach(grouped, id: \.kind) { group in
                Section(header: Text(group.kind.sectionTitle)) {
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
            if selection == "custom" || selection == "weston-terminal" {
                selection = "wawona-shell"
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
