#if os(watchOS)
import SwiftUI
import WawonaModel

public struct WawonaWatchRootView: View {
    @StateObject private var profileStore = MachineProfileStore()
    @StateObject private var sessions = SessionOrchestrator()
    @State private var didAutoConnect = false
    @State private var autoProfile: MachineProfile?
    @State private var autoSession: MachineSession?

    public init() {}

    public var body: some View {
        NavigationStack {
            MachineStatusView(profileStore: profileStore, sessions: sessions)
        }
        .fullScreenCover(item: $autoSession) { session in
            if let autoProfile {
                NavigationStack {
                    CompositorActiveView(
                        profile: autoProfile,
                        session: session,
                        sessions: sessions
                    )
                }
            }
        }
        .onAppear {
            WatchCompanionController.shared.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                maybeAutoConnectNestedClient()
            }
        }
    }

    /// Automation: `SIMCTL_CHILD_WAWONA_WATCH_AUTO_CLIENT=weston-simple-shm`
    /// or `simctl launch … --auto-client=weston-simple-shm`.
    private func maybeAutoConnectNestedClient() {
        guard !didAutoConnect else { return }
        let client = watchAutoClientId()
        guard !client.isEmpty else { return }
        didAutoConnect = true
        var overrides = MachineRuntimeOverrides()
        overrides.bundledAppID = client
        let profile = MachineProfile(
            id: "auto-\(client)",
            name: "Auto \(client)",
            type: .native,
            runtimeOverrides: overrides
        )
        guard WatchMachineSessionBridge.connect(profile: profile) else { return }
        autoProfile = profile
        autoSession = sessions.connect(machineId: profile.id)
    }

    private func watchAutoClientId() -> String {
        if let env = ProcessInfo.processInfo.environment["WAWONA_WATCH_AUTO_CLIENT"],
           !env.isEmpty {
            return env
        }
        for arg in ProcessInfo.processInfo.arguments {
            if arg.hasPrefix("--auto-client="), arg.count > 14 {
                return String(arg.dropFirst(14))
            }
        }
        return ""
    }
}
#endif
