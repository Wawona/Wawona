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
            if let activeSession, activeSession.status == .connected {
                Button(role: .destructive) {
                    if requiresExitConfirmation {
                        showDisconnectConfirmation = true
                    } else {
                        disconnectActiveSession(activeSession)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                        Text(stopLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(isNative ? "wwn.watch.stop" : "wwn.watch.disconnect")
                .accessibilityLabel(stopLabel)
            } else {
                Button {
                    // Do not write profileStore here. `activeMachineId` + save()
                    // republishes Machines and destroys this NavigationLink
                    // destination before the compositor cover can present.
                    if WatchMachineSessionBridge.connect(profile: profile) {
                        onStarted(sessions.connect(machineId: profile.id))
                    } else {
                        startFailed = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(startLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(isNative ? "wwn.watch.start" : "wwn.watch.connect")
                .accessibilityLabel(startLabel)
            }
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
