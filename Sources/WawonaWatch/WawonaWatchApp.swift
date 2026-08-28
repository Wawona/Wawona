#if os(watchOS)
import SwiftUI
import WawonaModel

public struct WawonaWatchRootView: View {
    @StateObject private var profileStore = MachineProfileStore()
    @StateObject private var sessions = SessionOrchestrator()
    @State private var runningCover: WatchMachineCover?

    public init() {}

    public var body: some View {
        NavigationStack {
            MachineStatusView(
                profileStore: profileStore,
                sessions: sessions,
                runningCover: $runningCover
            )
        }
        .onAppear {
            WatchCompanionController.shared.activate()
            startAutoClientIfRequested(sessions: sessions)
        }
    }

    /// Matrix / simctl parity with iOS `WWNSceneDelegate` and macOS `main.m`.
    /// Only runs when `WAWONA_AUTO_CLIENT` is set (e.g. `SIMCTL_CHILD_…` on launch).
    private func startAutoClientIfRequested(sessions: SessionOrchestrator) {
        guard let raw = ProcessInfo.processInfo.environment["WAWONA_AUTO_CLIENT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return }

        WawonaPreferences.shared.hasCompletedWelcome = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            var overrides = MachineRuntimeOverrides()
            overrides.bundledAppID = raw
            let profile = MachineProfile(
                id: "wawona-auto-client",
                name: "Auto Client",
                type: .native,
                runtimeOverrides: overrides
            )
            guard WatchMachineSessionBridge.connect(profile: profile) else { return }
            let session = sessions.connect(machineId: profile.id)
            runningCover = WatchMachineCover(profile: profile, session: session)
        }
    }
}
#endif
