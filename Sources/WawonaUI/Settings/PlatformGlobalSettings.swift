#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Opens native global Wawona Settings. Product hosts (iOS / tvOS / visionOS /
/// macOS) now show the SwiftUI sidebar (`WawonaMainWindowView`). This helper
/// is a leftover trampoline for gear buttons on the SPM `WawonaUI` path.
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
        #if !SWIFT_PACKAGE
        #if os(iOS) || os(tvOS) || os(visionOS)
        WWNMachinesHostingBridge.showSettings()
        #elseif os(macOS)
        WWNUnifiedWindowController.sharedController().showSettings()
        #endif
        #endif
    }
}
