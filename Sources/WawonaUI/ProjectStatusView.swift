import SwiftUI

/// Human-readable delivery board. Data comes from project evidence, not a
/// spinner: green is proved, orange is active, red needs attention.
struct WawonaProjectStatusView: View {
    private let rows: [ProjectStatusRow] = [
        .init(title: "Relay static CPU", state: "Active", color: .orange, detail: "Real 4 KiB NixOS guest executes. Boot proof pending."),
        .init(title: "Guest console", state: "Active", color: .orange, detail: "PL011 early path plus virtio-console to wwn-igetty."),
        .init(title: "NixOS readiness", state: "Blocked", color: .red, detail: "Awaiting real guest output: WAWONA_RELAY_READY=1."),
        .init(title: "iOS / iPadOS Mode A", state: "Ready", color: .green, detail: "Static CPU route. No JIT or Hypervisor.framework."),
        .init(title: "visionOS VM / container", state: "Ready", color: .green, detail: "Same static CPU route as iOS and iPadOS."),
        .init(title: "Wayland to iland", state: "Planned", color: .orange, detail: "vsock + waypipe proof follows guest readiness.")
    ]

    var body: some View {
        List {
            Section {
                WawonaLabel("Wawona delivery board", systemImage: "scope")
                    .font(.headline)
                Text("Green proved. Orange in progress. Red blocker.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Section(header: Text("Current work")) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.title).font(.headline)
                            Spacer()
                            WawonaLabel(row.state, systemImage: row.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(row.color)
                        }
                        Text(row.detail).font(.subheadline).foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibility(identifier: "wwn.projectStatus.\(row.id)")
                }
            }
            Section(header: Text("Completion gate")) {
                Text("Real NixOS console must print WAWONA_RELAY_READY=1. Then verify Wayland over vsock/waypipe into iland.")
            }
        }
    }
}

private struct ProjectStatusRow: Identifiable {
    let title: String
    let state: String
    let color: Color
    let detail: String
    var id: String { title.lowercased().replacingOccurrences(of: " ", with: "-") }
    var icon: String {
        switch state {
        case "Ready": "checkmark.circle.fill"
        case "Blocked": "xmark.octagon.fill"
        default: "exclamationmark.triangle.fill"
        }
    }
}
