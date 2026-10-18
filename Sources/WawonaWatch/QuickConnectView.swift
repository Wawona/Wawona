#if os(watchOS)
import SwiftUI
import WawonaModel

struct QuickConnectView: View {
    let profile: MachineProfile
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    var onStarted: (MachineSession) -> Void

    @ObservedObject private var preferences = WawonaPreferences.shared
    @State private var showDisconnectConfirmation = false
    @State private var startFailed = false
    @State private var showingEditor = false

    private var requiresExitConfirmation: Bool {
        let resolved = preferences.resolvedSettings(for: profile)
        return resolved.shakeToCloseEnabled || resolved.swipeBackToCloseEnabled
    }

    private var runningSession: MachineSession? {
        sessions.sessions.first {
            $0.machineId == profile.id && ($0.status == .connected || $0.status == .connecting)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(profile.name).font(.headline)
            if let runningSession {
                Button {
                    onStarted(runningSession)
                } label: {
                    Label("Focus", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("wwn.watch.focus")
                .accessibilityLabel("Focus")
                Button(role: .destructive) {
                    if requiresExitConfirmation {
                        showDisconnectConfirmation = true
                    } else {
                        stopSession(runningSession)
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("wwn.watch.stop")
                .accessibilityLabel("Stop")
            } else {
                Button {
                    // Do not write profileStore here. `activeMachineId` + save()
                    // republishes Machines and destroys this destination
                    // before the compositor cover can present.
                    if WatchMachineSessionBridge.connect(profile: profile) {
                        onStarted(sessions.connect(machineId: profile.id))
                    } else {
                        startFailed = true
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("wwn.watch.start")
                .accessibilityLabel("Start")
            }
            Button(action: { showingEditor = true }) {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("wwn.watch.machineSettings")
            .accessibilityLabel("Edit")
        }
        .sheet(isPresented: $showingEditor) {
            MachineEditorView(profileStore: profileStore, profile: profile)
        }
        .alert("Could not start", isPresented: $startFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The Wayland compositor did not start. Check Watch logs for WATCH errors.")
        }
        .confirmationDialog(
            "Close current Wayland app?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                if let runningSession {
                    stopSession(runningSession)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop the current session and return to Machines.")
        }
    }

    private func stopSession(_ activeSession: MachineSession) {
        WatchMachineSessionBridge.disconnect(profile: profile)
        sessions.disconnect(sessionId: activeSession.id)
    }
}
#endif
