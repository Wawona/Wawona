import SwiftUI
import WawonaModel
import WawonaUIContracts

#if os(visionOS)
public struct WawonaVisionShell: Scene {
    @StateObject private var preferences: WawonaPreferences
    @StateObject private var profileStore: MachineProfileStore
    @StateObject private var sessions: SessionOrchestrator

    public init() {
        _preferences = StateObject(wrappedValue: WawonaPreferences.shared)
        _profileStore = StateObject(wrappedValue: MachineProfileStore())
        _sessions = StateObject(wrappedValue: SessionOrchestrator())
    }

    public var body: some Scene {
        WindowGroup("Wawona") {
            ContentView(
                preferences: preferences,
                profileStore: profileStore,
                sessions: sessions
            )
        }
        .defaultSize(width: 1100, height: 800)
    }
}
#endif
