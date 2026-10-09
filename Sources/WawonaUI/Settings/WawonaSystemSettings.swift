#if os(macOS)
import AppKit
import Foundation

/// macOS Global Settings entry. Opens the in-app Machines sidebar catalog.
/// PrefPane / System Settings hosts are retired (`wawona-global-settings-exclusive`).
enum WawonaSystemSettings {
    @discardableResult
    static func openPreferencePane() -> Bool {
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

    static func isPreferencePaneInstalled() -> Bool {
        false
    }
}
#endif
