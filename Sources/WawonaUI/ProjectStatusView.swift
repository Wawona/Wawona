import SwiftUI

/// Human-readable delivery board. Data comes from project evidence, not a
/// spinner: green is proved, orange is active, red needs attention.
struct WawonaProjectStatusView: View {
    private let rows: [ProjectStatusRow] = [
        .init(
            title: "Relay StaticCpu",
            state: "Ready",
            color: .green,
            detail: "Multi-User NixOS on E4A1C0DE (4 KiB and 16 KiB). auth51."
        ),
        .init(
            title: "NixOS readiness",
            state: "Ready",
            color: .green,
            detail: "WAWONA_RELAY_AUTH_OK=1 on vsock plus WAWONA_RELAY_READY=1."
        ),
        .init(
            title: "nixpkgs over NAT",
            state: "Ready",
            color: .green,
            detail: "nix run nixpkgs#fastfetch substitutes then wawona-fastfetch: end."
        ),
        .init(
            title: "Wayland SHM import",
            state: "Ready",
            color: .green,
            detail: "Relay imported SHM frame 800x600 sha256=5b6add91… (auth18/51)."
        ),
        .init(
            title: "iland present in UI",
            state: "Active",
            color: .orange,
            detail: "Mode A pumps shm importer into IlandPresentEngine. Host waypipe client_fd still stub."
        ),
        .init(
            title: "Interaction",
            state: "Blocked",
            color: .red,
            detail: "Need one Multi-Touch the guest sees, then Stop back to Machines."
        ),
        .init(
            title: "OCI lifecycle",
            state: "Blocked",
            color: .red,
            detail: "Thin create/start/stop/kill on StaticCpu still open."
        ),
        .init(
            title: "STARDUST / ASC",
            state: "Blocked",
            color: .red,
            detail: "Signed device run + store IPA audit last. Completely complete stays 0%."
        ),
    ]

    var body: some View {
        List {
            Section {
                WawonaLabel("Wawona delivery board", systemImage: "scope")
                    .font(.headline)
                Text("Green proved. Orange in progress. Red blocker. Scorecard ~59% of twelve gates.")
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
                Text(
                    "Completely complete needs every acceptance gate plus a store-shaped IPA that boots NixOS on device. Simulator E4A1C0DE is not STARDUST."
                )
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
