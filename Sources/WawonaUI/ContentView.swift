import SwiftUI
import WawonaModel

struct ContentView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator

    init(
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore,
        sessions: SessionOrchestrator
    ) {
        self.preferences = preferences
        self.profileStore = profileStore
        self.sessions = sessions
    }

    var body: some View {
        MachinesRootView(
            preferences: preferences,
            profileStore: profileStore,
            sessions: sessions
        )
        .onAppear {
            MachineRuntimeSettingsApplicator.applyActiveMachine(
                profileStore: profileStore,
                preferences: preferences
            )
        }
    }
}
