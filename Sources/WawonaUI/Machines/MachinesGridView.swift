import SwiftUI
import WawonaModel

struct MachinesGridView: View {
    let profiles: [MachineProfile]
    @ObservedObject var sessions: SessionOrchestrator
    let onAdd: () -> Void
    let onEdit: (MachineProfile) -> Void
    let onConnect: (MachineProfile) -> Void
    let onDelete: (MachineProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader("Machines", subtitle: gridBlurb)
                Spacer()
                Button("New Machine", action: onAdd)
            }

            if profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No Machines")
                        .font(.headline)
                }
                .frame(maxWidth: CGFloat.infinity)
                .padding(Edge.Set.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 14)], spacing: 14) {
                    ForEach(profiles) { profile in
                        MachineCardView(
                            profile: profile,
                            status: status(for: profile.id),
                            onConnect: { onConnect(profile) },
                            onEdit: { onEdit(profile) },
                            onDelete: { onDelete(profile) }
                        )
                    }
                }
            }
        }
    }

    private func status(for machineId: String) -> MachineStatus {
        sessions.sessions.first(where: { $0.machineId == machineId })?.status ?? .disconnected
    }

    private var gridBlurb: String {
        "Add a profile, pick a Wayland client or SSH target, then connect."
    }
}
