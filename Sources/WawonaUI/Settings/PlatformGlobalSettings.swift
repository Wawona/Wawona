#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Opens native global Wawona Settings (ObjC + AppKit/UIKit). Not SwiftUI.
enum PlatformGlobalSettings {
    static var isAvailable: Bool {
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
        true
        #else
        false
        #endif
    }

    static func open() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        WWNPreferences.shared().show(nil)
        #elseif os(macOS)
        WWNPreferences.shared().show(NSApp)
        #endif
    }
}
