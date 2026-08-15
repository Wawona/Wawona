#if os(watchOS)
import SwiftUI
import WawonaModel

struct QuickConnectView: View {
    let profile: MachineProfile
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator

    @State var runningSession: MachineSession?
    @ObservedObject private var preferences = WawonaPreferences.shared
    @State private var showDisconnectConfirmation = false

    private var requiresExitConfirmation: Bool {
        let resolved = preferences.resolvedSettings(for: profile)
        return resolved.shakeToCloseEnabled || resolved.swipeBackToCloseEnabled
    }

    var activeSession: MachineSession? {
        sessions.sessions.first(where: { $0.machineId == profile.id })
    }

    private var isNative: Bool { profile.type == .native }
    private var startLabel: String { isNative ? "Start" : "Connect" }
    private var stopLabel: String { isNative ? "Stop" : "Disconnect" }

    var body: some View {
        VStack(spacing: 12) {
            Text(profile.name).font(.headline)
            NavigationLink {
                MachineSettingsView(
                    preferences: WawonaPreferences.shared,
                    profileStore: profileStore,
                    machineID: profile.id
                )
            } label: {
                Label("Machine Settings", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("wwn.watch.machineSettings")
            .accessibilityLabel("Machine Settings")
            if let activeSession, activeSession.status == .connected {
                Button(role: .destructive) {
                    if requiresExitConfirmation {
                        showDisconnectConfirmation = true
                    } else {
                        disconnectActiveSession(activeSession)
                    }
                } label: {
                    Label(stopLabel, systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(isNative ? "wwn.watch.stop" : "wwn.watch.disconnect")
                .accessibilityLabel(stopLabel)
            } else {
                Button {
                    profileStore.activeMachineId = profile.id
                    profileStore.save()
                    if WatchMachineSessionBridge.connect(profile: profile) {
                        runningSession = sessions.connect(machineId: profile.id)
                    }
                } label: {
                    Label(startLabel, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(isNative ? "wwn.watch.start" : "wwn.watch.connect")
                .accessibilityLabel(startLabel)
            }
        }
        .navigationDestination(item: $runningSession) { session in
            CompositorActiveView(profile: profile, session: session, sessions: sessions)
        }
        .confirmationDialog(
            "Close current Wayland app?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                if let activeSession {
                    disconnectActiveSession(activeSession)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop the current session and return to Machines.")
        }
    }

    private func disconnectActiveSession(_ activeSession: MachineSession) {
        WatchMachineSessionBridge.disconnect(profile: profile)
        sessions.disconnect(sessionId: activeSession.id)
    }
}
#endif
