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
            detail: "Wiring Ready (N10). Live non-black session surface still required on tip Start."
        ),
        .init(
            title: "Interaction",
            state: "Active",
            color: .orange,
            detail: "Multi-Touch + Stop park wired. Need guest-seen touch evidence on session surface."
        ),
        .init(
            title: "OCI lifecycle",
            state: "Active",
            color: .orange,
            detail: "Host → Relay; ContainerCommand includes Kill. Prove one StaticCpu create/start/stop/kill."
        ),
        .init(
            title: "Offline AOT",
            state: "Ready",
            color: .green,
            detail: "aot-translate offline only. Not in store staticlib. Hot-kernel measure recorded."
        ),
        .init(
            title: "STARDUST / ASC",
            state: "Active",
            color: .orange,
            detail: "ASC VALID/IN_BETA_TESTING. Store IPA audit + TF Distribution still open. Completely complete 0%."
        ),
    ]

    var body: some View {
        List {
            Section {
                WawonaLabel("Wawona delivery board", systemImage: "scope")
                    .font(.headline)
                Text("Green proved. Orange in progress. Red blocker. Session pixels use Machines Focus surface, not this board.")
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
                    "Completely complete needs every acceptance gate plus a store-shaped IPA that boots NixOS on device. Work Status is a board only; guest frames present on the session surface."
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
