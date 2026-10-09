#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Opens Global Wawona Settings via the sole in-app host
/// (`wawona-global-settings-exclusive`). Never System Settings, Settings.app,
/// or App Info Preferences as a second catalog.
enum PlatformGlobalSettings {
    static var isAvailable: Bool {
        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
        true
        #else
        false
        #endif
    }

    @MainActor
    static func open() {
        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
        WWNMainWindowRouter.shared.showSettings()
        #endif
    }
}
