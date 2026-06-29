#if os(watchOS)
import SwiftUI
import WawonaModel

struct QuickConnectView: View {
    let profile: MachineProfile
    let profileStore: MachineProfileStore
    let sessions: SessionOrchestrator

    @State var runningSession: MachineSession?

    var activeSession: MachineSession? {
        sessions.sessions.first(where: { $0.machineId == profile.id })
    }

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
                Label("Overrides", systemImage: "slider.horizontal.3")
            }
            if let activeSession, activeSession.status == .connected {
                Button(role: .destructive) {
                    WatchMachineSessionBridge.disconnect(profile: profile)
                    sessions.disconnect(sessionId: activeSession.id)
                } label: {
                    Label("Disconnect", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    profileStore.activeMachineId = profile.id
                    profileStore.save()
                    if WatchMachineSessionBridge.connect(profile: profile) {
                        runningSession = sessions.connect(machineId: profile.id)
                    }
                } label: {
                    Label("Connect", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationDestination(item: $runningSession) { session in
            CompositorActiveView(profile: profile, session: session, sessions: sessions)
        }
    }
}
#endif
