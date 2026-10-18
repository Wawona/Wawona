#if os(watchOS)
import WatchKit
import WawonaModel

/// Independent watch app (`@main` WindowGroup). Not a WatchKit extension.
/// `WKExtensionDelegateAdaptor` logs "should only be used within an extension
/// based process" and is the wrong adaptor here.
final class WawonaWatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            WWNCloudSync.shared.start()
            WKApplication.shared().registerForRemoteNotifications()
        }
    }

    func applicationDidBecomeActive() {
        // Auto-connect lives in WawonaWatch.onAppear (deferred). Do not start
        // the compositor from didBecomeActive (can race dyld / first layout).
    }

    /// CKDatabaseSubscription silent push.
    func didReceiveRemoteNotification(
        _ userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (WKBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            await WWNCloudSync.shared.syncNow()
            completionHandler(.newData)
        }
    }
}
#endif
