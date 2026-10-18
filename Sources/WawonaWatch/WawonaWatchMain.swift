#if os(watchOS)
import SwiftUI
import WawonaModel

@main
struct WawonaWatch: App {
    @WKApplicationDelegateAdaptor(WawonaWatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WawonaWatchRootView()
        }
        .backgroundTask(.appRefresh("wawona.cloudsync")) {
            await WWNCloudSync.shared.syncNow()
        }
    }
}
#endif
