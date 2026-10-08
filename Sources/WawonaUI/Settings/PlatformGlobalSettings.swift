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

    #if os(iOS)
    /// Opens Settings.app on this app's Settings.bundle page (not Settings root).
    /// Requires `Settings.bundle` in the product. Public API only (`app-settings:`).
    /// Nonisolated: callers include `WWNMainWindowRouter.showSettings()` (not MainActor).
    static func openAppSettingsBundle() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        // Settings.bundle must ship in the product; without it iOS opens Settings root.
        _ = Bundle.main.url(forResource: "Settings", withExtension: "bundle")
        guard UIApplication.shared.canOpenURL(url) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    #endif
}
