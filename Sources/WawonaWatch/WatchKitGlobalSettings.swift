import WatchKit

/// Presents global Wawona Settings via WatchKit (not SwiftUI).
enum WatchKitGlobalSettings {
    static func registerHost() {
        if let controller = WKExtension.shared().visibleInterfaceController {
            WWNWatchPreferencesCoordinator.setHostInterfaceController(controller)
        }
    }

    static func open() {
        registerHost()
        WWNWatchPreferencesCoordinator.sharedCoordinator().showSettings()
    }
}
