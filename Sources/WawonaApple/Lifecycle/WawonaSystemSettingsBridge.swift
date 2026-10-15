#if os(macOS)
import AppKit
import Foundation

/// ObjC trampoline into in-app Global Settings (replaces Machines chrome).
/// PrefPane / System Settings hosts are retired.
@objc(WawonaSystemSettings)
public final class WawonaSystemSettingsBridge: NSObject {
    @objc public static func openInAppSettings() {
        if let controller = NSClassFromString("WWNUnifiedWindowController") as AnyObject?,
           controller.responds(to: Selector(("showSettings"))) {
            _ = controller.perform(Selector(("showSettings")))
            return
        }
        WawonaLaunchMode.openOrActivateUI(arguments: ["--show-settings"])
    }

    /// Legacy selector. Always opens in-app Settings (never a PrefPane).
    @objc public static func openPreferencePane() {
        openInAppSettings()
    }
}
#endif
