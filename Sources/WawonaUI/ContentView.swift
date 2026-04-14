import SwiftUI
import WawonaModel

struct ContentView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    @ObservedObject var sessions: SessionOrchestrator
    /// Android (Skip): `@StateObject` is not observable at the root, so the parent must hold overlay
    /// state and set it from here when the user connects a native machine.
    var onPresentNativeCompositor: ((MachineSession) -> Void)?

    init(
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore,
        sessions: SessionOrchestrator,
        onPresentNativeCompositor: ((MachineSession) -> Void)? = nil
    ) {
        self.preferences = preferences
        self.profileStore = profileStore
        self.sessions = sessions
        self.onPresentNativeCompositor = onPresentNativeCompositor
    }

    var body: some View {
        TabView {
            MachinesRootView(
                preferences: preferences,
                profileStore: profileStore,
                sessions: sessions,
                onPresentNativeCompositor: onPresentNativeCompositor
            )
            .tabItem { Label("Machines", systemImage: "square.grid.2x2") }

            SettingsRootView(
                preferences: preferences,
                profileStore: profileStore
            )
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
