#if os(watchOS)
import WatchKit

final class WawonaWatchExtensionDelegate: NSObject, WKExtensionDelegate {
    func applicationDidBecomeActive() {
        WatchKitGlobalSettings.registerHost()
        // Auto-connect lives in WawonaWatch.onAppear (deferred) — do not start
        // the compositor from didBecomeActive (can race dyld / first layout).
    }
}
#endif
