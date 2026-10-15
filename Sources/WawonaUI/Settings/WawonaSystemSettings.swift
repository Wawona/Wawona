#if os(macOS)
import AppKit
import Foundation

/// macOS Global Settings entry. Opens the in-app host that replaces Machines
/// chrome in the main window (`wawona-global-settings-exclusive`).
enum WawonaSystemSettings {
    /// Present in-app Global Settings (same window as Machines).
    @discardableResult
    static func openInAppSettings() -> Bool {
        #if !SWIFT_PACKAGE
        let openOnMain = {
            MainActor.assumeIsolated {
                WWNUnifiedWindowController.sharedController().showSettings()
            }
        }
        if Thread.isMainThread {
            openOnMain()
        } else {
            DispatchQueue.main.sync(execute: openOnMain)
        }
        #else
        WWNMainWindowRouter.shared.showSettings()
        #endif
        return true
    }

    /// Legacy name. PrefPane host is gone; always opens in-app Settings.
    @discardableResult
    static func openPreferencePane() -> Bool {
        openInAppSettings()
    }

    static func isPreferencePaneInstalled() -> Bool {
        false
    }
}
#endif
