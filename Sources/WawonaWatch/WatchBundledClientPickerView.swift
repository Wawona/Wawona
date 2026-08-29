#if os(watchOS)
import SwiftUI
import WawonaModel

/// Full-screen client list for native machine profiles / global defaults.
/// Shows platform-available clients; GPU demos appear as unavailable on watchOS.
struct WatchBundledClientPickerView: View {
    @Binding var selection: String
    let clients: [ClientLauncher]
    let unavailableGpu: [ClientLauncher]

    init(
        selection: Binding<String>,
        clients: [ClientLauncher] = ClientLauncher.availablePresets,
        unavailableGpu: [ClientLauncher] = ClientLauncher.unavailableGpuPresets
    ) {
        self._selection = selection
        self.clients = clients
        self.unavailableGpu = unavailableGpu
    }

    var body: some View {
        List {
            Section {
                ForEach(clients) { launcher in
                    clientRow(launcher, enabled: true)
                }
            } footer: {
                if !unavailableGpu.isEmpty {
                    Text("GPU demos need Metal/ANGLE (blocked on watchOS). They ship on macOS, iOS, iPadOS, visionOS, and Android.")
                        .font(.caption2)
                }
            }

            if !unavailableGpu.isEmpty {
                Section("Requires GPU") {
                    ForEach(unavailableGpu) { launcher in
                        clientRow(launcher, enabled: false)
                    }
                }
            }
        }
        .navigationTitle("Wayland Client")
    }

    @ViewBuilder
    private func clientRow(_ launcher: ClientLauncher, enabled: Bool) -> some View {
        Button {
            guard enabled else { return }
            selection = launcher.name
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selection == launcher.name ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        enabled
                            ? (selection == launcher.name ? Color.accentColor : .secondary)
                            : .secondary.opacity(0.35)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(launcher.displayName)
                        .foregroundStyle(enabled ? .primary : .secondary)
                    Text(launcher.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}
#endif
