#if os(macOS)
import AppKit
import Foundation

/// ObjC trampoline into in-app Global Settings (Machines sidebar catalog).
@objc(WawonaSystemSettings)
public final class WawonaSystemSettingsBridge: NSObject {
    @objc public static func openPreferencePane() {
        if let controller = NSClassFromString("WWNUnifiedWindowController") as AnyObject?,
           controller.responds(to: Selector(("showSettings"))) {
            _ = controller.perform(Selector(("showSettings")))
            return
        }
        WawonaLaunchMode.openOrActivateUI(arguments: ["--show-settings"])
    }
}
#endif
