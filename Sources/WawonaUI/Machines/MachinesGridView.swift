import SwiftUI
import WawonaModel

struct MachinesGridView: View {
    let profiles: [MachineProfile]
    @ObservedObject var sessions: SessionOrchestrator
    let onAdd: () -> Void
    let onConnect: (MachineProfile) -> Void
    let onDelete: (MachineProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader("Machine Grid", subtitle: "Adaptive layout across iPhone, iPad, and Mac")
                Spacer()
                Button("New Machine", action: onAdd)
            }

            if profiles.isEmpty {
                #if SKIP
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No Machines")
                        .font(.headline)
                }
                .frame(maxWidth: CGFloat.infinity)
                .padding(Edge.Set.top, 40)
                #else
                ContentUnavailableView("No Machines", systemImage: "server.rack")
                    .frame(maxWidth: CGFloat.infinity)
                    .padding(Edge.Set.top, 40)
                #endif
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 14)], spacing: 14) {
                    ForEach(profiles) { profile in
                        MachineCardView(
                            profile: profile,
                            status: status(for: profile.id),
                            onConnect: { onConnect(profile) },
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
}
