#if os(watchOS)
import WatchKit

/// Independent watch app (`@main` WindowGroup) — not a WatchKit extension.
/// `WKExtensionDelegateAdaptor` logs "should only be used within an extension
/// based process" and is the wrong adaptor here.
final class WawonaWatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidBecomeActive() {
        WatchKitGlobalSettings.registerHost()
        // Auto-connect lives in WawonaWatch.onAppear (deferred) — do not start
        // the compositor from didBecomeActive (can race dyld / first layout).
    }
}
#endif
