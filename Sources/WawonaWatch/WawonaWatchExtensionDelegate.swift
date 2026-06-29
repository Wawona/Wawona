import WatchKit

final class WawonaWatchExtensionDelegate: NSObject, WKExtensionDelegate {
    func applicationDidBecomeActive() {
        WatchKitGlobalSettings.registerHost()
    }
}
