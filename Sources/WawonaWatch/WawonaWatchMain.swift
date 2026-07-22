#if os(watchOS)
import SwiftUI
import WawonaModel

@main
struct WawonaWatch: App {
    @WKExtensionDelegateAdaptor(WawonaWatchExtensionDelegate.self) private var extensionDelegate
    @State private var didAutoConnect = false

    var body: some Scene {
        WindowGroup {
            WawonaWatchRootView()
                .onAppear {
                    // Defer past first frame — never block SwiftUI init / dyld settle.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        maybeAutoConnectNestedClient()
                    }
                }
        }
    }

    /// Automation: `SIMCTL_CHILD_WAWONA_WATCH_AUTO_CLIENT=weston-simple-shm`
    private func maybeAutoConnectNestedClient() {
        guard !didAutoConnect,
              let client = ProcessInfo.processInfo.environment["WAWONA_WATCH_AUTO_CLIENT"],
              !client.isEmpty
        else {
            return
        }
        didAutoConnect = true
        var overrides = MachineRuntimeOverrides()
        overrides.bundledAppID = client
        let profile = MachineProfile(
            id: "auto-\(client)",
            name: "Auto \(client)",
            type: .native,
            runtimeOverrides: overrides
        )
        _ = WatchMachineSessionBridge.connect(profile: profile)
    }
}
#endif
