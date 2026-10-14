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
    /// Activity type for an iPad / visionOS Wawona Terminal window.
    public static let terminalActivityType = "com.aspauldingcode.wawona.terminal"

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

    /// New Window for Wawona Terminal. macOS uses `WWNMacGuestConsole`.
    /// iPad and visionOS get a terminal-only scene. iPhone stays tabbed.
    public static func presentTerminalWindow() {
        #if os(iOS) || os(visionOS)
        presentUIKitTerminalScene()
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
    private static weak var terminalScene: UIWindowScene?
    private static var closingTerminal = false

    private static func presentUIKitTerminalScene() {
        if let existing = terminalScene {
            existing.windows.first?.makeKeyAndVisible()
            return
        }
        requestScene(activityType: terminalActivityType, title: "Wawona Terminal")
    }

    private static func presentUIKitSessionScene() {
        requestScene(activityType: sessionActivityType, title: "Wawona Session")
    }

    private static func requestScene(activityType: String, title: String) {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = title
        let session = activityType == sessionActivityType
        activity.userInfo = session ? ["wwn.session": true] : ["wwn.terminal": true]
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
                if !session {
                    Task { @MainActor in
                        WWNIosGuestConsole.shared.fallBackToTab()
                    }
                }
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

    public static func isTerminalScene(options: UIScene.ConnectionOptions) -> Bool {
        options.userActivities.contains {
            $0.activityType == terminalActivityType
                || ($0.userInfo?["wwn.terminal"] as? Bool) == true
        }
    }

    public static func noteTerminalScene(_ scene: UIWindowScene) {
        terminalScene = scene
    }

    public static func closeTerminalWindow() {
        guard let scene = terminalScene else { return }
        closingTerminal = true
        let options = UIWindowSceneDestructionRequestOptions()
        options.windowDismissalAnimation = .standard
        UIApplication.shared.requestSceneSessionDestruction(
            scene.session,
            options: options,
            errorHandler: { error in
                closingTerminal = false
                NSLog(
                    "WWNSessionWindowPresenter: terminal close failed: %@",
                    error.localizedDescription
                )
            }
        )
    }

    /// OS closed the terminal window. Returns true when the console should dismiss.
    public static func terminalSceneDidDisconnect(_ scene: UIScene) -> Bool {
        guard let windowScene = scene as? UIWindowScene, windowScene === terminalScene else {
            return false
        }
        terminalScene = nil
        if closingTerminal {
            closingTerminal = false
            return false
        }
        return true
    }
    #endif
}

#if os(iOS) || os(visionOS)
/// Full-screen Wawona Terminal for a dedicated iPad / visionOS window.
public struct WWNTerminalWindowRoot: View {
    @ObservedObject private var console = WWNIosGuestConsole.shared

    public init() {}

    public var body: some View {
        WWNIosGuestConsoleSheet(console: console)
    }
}
#endif

/// Compositor host for a dedicated session window/scene.
public struct WWNSessionSurfaceRootView: View {
    public init() {}

    public var body: some View {
        #if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(visionOS))
        // macOS titled session window: layout below the titlebar
        // (contentLayoutRect). Do not ignore top safe area or Metal draws
        // under the chrome. iOS / visionOS session scenes stay full-bleed.
        CompositorBridge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS) || os(visionOS)
            // edgesIgnoringSafeArea stays valid on iOS 13; avoids ViewBuilder
            // buildEither (iOS 16+) around ignoresSafeArea().
            .edgesIgnoringSafeArea(.all)
            #endif
        #else
        Color.black
        #endif
    }
}
