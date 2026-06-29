import SwiftUI
import WawonaModel

struct CompositorActiveView: View {
    let profile: MachineProfile
    let session: MachineSession
    let sessions: SessionOrchestrator
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Text(profile.name).font(.headline)
            Text("Session Active").font(.caption)
            SessionGlanceView(session: session)
            Button(role: .destructive) {
                WatchMachineSessionBridge.disconnect(profile: profile)
                sessions.disconnect(sessionId: session.id)
                dismiss()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
