import SwiftUI
import Foundation
#if canImport(Darwin)
    import Darwin
#endif
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(CarPlay)
    import CarPlay
#endif
#if canImport(WawonaUI)
    import WawonaUI
#endif
#if canImport(WawonaModel)
    import WawonaModel
#endif
private typealias AppRootView = WawonaRootView
private typealias SharedAppDelegate = WawonaAppDelegate

/// Process entry. Branches LaunchAgent roles before SwiftUI App.main so
/// `--compositor-host` / `--menubar` never open a Regular Machines UI.
///
/// Apple mobile compiles with an iOS 13.0 floor: SwiftUI `App` / `Scene` /
/// `UIApplicationDelegateAdaptor` are iOS 14+. Those targets use
/// `UIApplicationMain` + `WWNSceneDelegate` (Info.plist) instead.
@main
enum WawonaProcessEntry {
    static func main() {
        #if os(macOS)
        switch WawonaLaunchMode.parse() {
        case .help:
            WawonaLaunchMode.printHelp()
            return
        case .version:
            WawonaLaunchMode.printVersion()
            return
        case .compositorHost:
            WawonaCompositorHostApp.run()
            return
        case .menuBar:
            WawonaMenuBarApp.run()
            return
        case .ui(let showSettings, let settingsSection):
            if !WawonaLaunchLockState.acquireUIInstance() {
                let panel = showSettings ? "settings" : "machines"
                WawonaLaunchMode.activateExistingUI(panel: panel)
                return
            }
            if showSettings {
                // Defer until after AppKit is up; still only one UI instance.
                DispatchQueue.main.async {
                    openInAppSettings(section: settingsSection)
                }
            }
            AppMain.main()
        }
        #elseif os(iOS) || os(tvOS) || os(visionOS)
        // Ignore SIGPIPE so broken waypipe/SSH pipes do not kill the process.
        signal(SIGPIPE, SIG_IGN)
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        UIApplicationMain(
            CommandLine.argc,
            CommandLine.unsafeArgv,
            nil,
            NSStringFromClass(AppMainDelegate.self)
        )
        #else
        AppMain.main()
        #endif
    }

    #if os(macOS)
    static func openInAppSettings(section: String?) {
        if let section, !section.isEmpty,
           let controller = NSClassFromString("WWNUnifiedWindowController") as AnyObject?,
           controller.responds(to: Selector(("selectSectionWithTitle:"))) {
            _ = controller.perform(Selector(("selectSectionWithTitle:")), with: section)
            return
        }
        if let controller = NSClassFromString("WWNUnifiedWindowController") as AnyObject?,
           controller.responds(to: Selector(("showSettings"))) {
            _ = controller.perform(Selector(("showSettings")))
        }
    }
    #endif
}

#if os(macOS)
struct AppMain: App {
    @NSApplicationDelegateAdaptor(AppMainDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhase(newPhase)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    WawonaProcessEntry.openInAppSettings(section: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func handleScenePhase(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            SharedAppDelegate.shared.onResume()
        case .inactive:
            SharedAppDelegate.shared.onPause()
        case .background:
            SharedAppDelegate.shared.onStop()
        @unknown default:
            break
        }
    }
}
#endif

#if canImport(UIKit)
    typealias AppMainDelegateBase = UIApplicationDelegate
#elseif canImport(AppKit)
    typealias AppMainDelegateBase = NSApplicationDelegate
#endif

@MainActor
final class AppMainDelegate: NSObject, AppMainDelegateBase {
    #if canImport(UIKit)
        func application(
            _ application: UIApplication,
            willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            _ = application
            _ = launchOptions
            SharedAppDelegate.shared.onInit()
            return true
        }

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            _ = application
            _ = launchOptions
            SharedAppDelegate.shared.onLaunch()
            return true
        }

        func application(
            _ application: UIApplication,
            configurationForConnecting connectingSceneSession: UISceneSession,
            options: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            _ = application
            _ = options
            #if canImport(CarPlay) && !os(tvOS) && !os(visionOS)
            if connectingSceneSession.role == .carTemplateApplication {
                let carPlay = UISceneConfiguration(
                    name: "CarPlay Configuration",
                    sessionRole: connectingSceneSession.role
                )
                carPlay.delegateClass = CarPlaySceneDelegate.self
                return carPlay
            }
            #endif
            #if !os(tvOS) && !os(visionOS)
            if #available(iOS 16.0, *),
               connectingSceneSession.role == .windowExternalDisplayNonInteractive
            {
                let external = UISceneConfiguration(
                    name: "External Display",
                    sessionRole: connectingSceneSession.role
                )
                external.delegateClass = ExternalSceneDelegate.self
                return external
            }
            #endif
            let config = UISceneConfiguration(
                name: "Default Configuration",
                sessionRole: connectingSceneSession.role
            )
            config.delegateClass = WWNSceneDelegate.self
            return config
        }

        func applicationDidBecomeActive(_ application: UIApplication) {
            _ = application
            SharedAppDelegate.shared.onResume()
        }

        func applicationDidEnterBackground(_ application: UIApplication) {
            _ = application
            SharedAppDelegate.shared.onStop()
        }

        func applicationWillTerminate(_ application: UIApplication) {
            _ = application
            SharedAppDelegate.shared.onDestroy()
        }

        func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
            _ = application
            SharedAppDelegate.shared.onLowMemory()
        }

    #elseif canImport(AppKit)
        func applicationWillFinishLaunching(_ notification: Notification) {
            _ = notification
            SharedAppDelegate.shared.onInit()
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            _ = notification
            SharedAppDelegate.shared.onLaunch()
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(handleReopen(_:)),
                name: WawonaLaunchMode.reopenNotification,
                object: nil
            )
        }

        func applicationShouldHandleReopen(
            _ sender: NSApplication,
            hasVisibleWindows flag: Bool
        ) -> Bool {
            _ = sender
            if !flag {
                NSApp.activate(ignoringOtherApps: true)
            }
            return true
        }

        func applicationWillTerminate(_ notification: Notification) {
            _ = notification
            DistributedNotificationCenter.default().removeObserver(self)
            SharedAppDelegate.shared.onDestroy()
            WawonaLaunchLockState.releaseAll()
        }

        @objc private func handleReopen(_ note: Notification) {
            let panel = (note.userInfo?["panel"] as? String) ?? "machines"
            NSApp.activate(ignoringOtherApps: true)
            if panel == "settings" {
                WawonaProcessEntry.openInAppSettings(section: nil)
            }
            for window in NSApp.windows where window.isVisible == false {
                window.makeKeyAndOrderFront(nil)
            }
        }
    #endif
}
