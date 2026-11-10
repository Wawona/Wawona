import SwiftUI
import WawonaModel

struct MachinesGridView: View {
    let profiles: [MachineProfile]
    @ObservedObject var sessions: SessionOrchestrator
    let onSelect: (MachineProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No Machines")
                        .font(.headline)
                }
                .frame(maxWidth: CGFloat.infinity)
                .padding(Edge.Set.top, 40)
            } else {
                if #available(iOS 14, tvOS 14, watchOS 7, *) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 14)],
                        alignment: .leading,
                        spacing: 14
                    ) {
                        cards
                    }
                } else {
                    VStack(spacing: 14) { cards }
                }
            }
        }
    }

    private var cards: some View {
        ForEach(profiles) { profile in
            MachineCardView(
                profile: profile,
                status: status(for: profile.id),
                onSelect: { onSelect(profile) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(profile.id)
        }
    }

    private func status(for machineId: String) -> MachineStatus {
        sessions.sessions.first(where: { $0.machineId == machineId })?.status ?? .disconnected
    }
}
