#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Opens Global Wawona Settings via the sole host for this platform
/// (`wawona-global-settings-exclusive`).
/// macOS: System Settings PrefPane. iOS/iPadOS: Settings.app (Settings.bundle).
/// tvOS / visionOS: in-app sheet. Never dual OS + in-app catalog.
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
