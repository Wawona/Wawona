import SwiftUI
import WawonaModel

struct MachineDetailView: View {
    let profile: MachineProfile
    @ObservedObject var sessions: SessionOrchestrator
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(profile.name, subtitle: profile.type.rawValue)
            if let onOpenSettings {
                Button("Open Machine Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
            }
            ForEach(sessions.sessions.filter { $0.machineId == profile.id }) { session in
                GlassCard {
                    VStack(alignment: .leading) {
                        StatusBadge(status: session.status)
                        Text("Sent: \(session.bytesSent) bytes")
                        Text("Received: \(session.bytesReceived) bytes")
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}
