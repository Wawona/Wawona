import Foundation
import SwiftUI
import WawonaUIContracts

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

/// Opens a dedicated host window/scene for Machines Start → New Window.
/// Tabbed Start stays in the primary Machines window (`showSessionSurface`).
@MainActor
public enum WWNSessionWindowPresenter {
    /// Activity type for an iPad / visionOS session scene.
    public static let sessionActivityType = "com.aspauldingcode.wawona.session"

    #if os(macOS)
    private static var sessionController: NSWindowController?
    #endif

    public static func presentSessionWindow(title: String) {
        #if os(macOS)
        presentMacSessionWindow(title: title)
        #elseif os(iOS) || os(visionOS)
        presentUIKitSessionScene()
        #endif
    }

    #if os(macOS)
    private static func presentMacSessionWindow(title: String) {
        if let existing = sessionController?.window, existing.isVisible {
            existing.title = title
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: WWNSessionSurfaceRootView())
        let window = NSWindow(contentViewController: hosting)
        window.title = title.isEmpty ? "Session" : title
        window.setContentSize(NSSize(width: 1024, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        let controller = NSWindowController(window: window)
        sessionController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif

    #if os(iOS) || os(visionOS)
    private static func presentUIKitSessionScene() {
        let activity = NSUserActivity(activityType: sessionActivityType)
        activity.title = "Wawona Session"
        activity.userInfo = ["wwn.session": true]
        activity.becomeCurrent()
        let options: UIScene.ActivationRequestOptions?
        #if os(iOS)
        if #available(iOS 15.0, *) {
            let windowOptions = UIWindowScene.ActivationRequestOptions()
            windowOptions.preferredPresentationStyle = .prominent
            options = windowOptions
        } else {
            options = nil
        }
        #else
        options = nil
        #endif
        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: options,
            errorHandler: { error in
                NSLog(
                    "WWNSessionWindowPresenter: scene activation failed: %@",
                    error.localizedDescription
                )
            }
        )
    }

    /// True when this scene connection should host session surface only.
    public static func isSessionScene(options: UIScene.ConnectionOptions) -> Bool {
        options.userActivities.contains {
            $0.activityType == sessionActivityType
                || ($0.userInfo?["wwn.session"] as? Bool) == true
        }
    }
    #endif
}

/// Full-bleed compositor host for a dedicated session window/scene.
public struct WWNSessionSurfaceRootView: View {
    public init() {}

    var body: some View {
        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(visionOS))
        CompositorBridge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        #else
        Color.black
        #endif
    }
}
