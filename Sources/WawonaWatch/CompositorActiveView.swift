#if os(watchOS)
import SwiftUI
import WawonaModel

struct CompositorActiveView: View {
    let profile: MachineProfile
    let session: MachineSession
    let sessions: SessionOrchestrator
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var preferences = WawonaPreferences.shared
    @State private var showStopConfirmation = false

    private var requiresExitConfirmation: Bool {
        let resolved = preferences.resolvedSettings(for: profile)
        return resolved.shakeToCloseEnabled || resolved.swipeBackToCloseEnabled
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(profile.name).font(.headline)
            Text("Session Active").font(.caption)
            SessionGlanceView(session: session)
            Button(role: .destructive) {
                if requiresExitConfirmation {
                    showStopConfirmation = true
                } else {
                    disconnectActiveSession()
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("wwn.watch.stop")
            .accessibilityLabel("Stop")
        }
        .confirmationDialog(
            "Close current Wayland app?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                disconnectActiveSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop the current session and return to Machines.")
        }
    }

    private func disconnectActiveSession() {
        WatchMachineSessionBridge.disconnect(profile: profile)
        sessions.disconnect(sessionId: session.id)
        dismiss()
    }
}
#endif
