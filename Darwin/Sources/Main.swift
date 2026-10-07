import SwiftUI
#if canImport(AppKit)
    import AppKit
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
                if showSettings {
                    openSystemSettingsPane(section: settingsSection)
                }
                return
            }
            if showSettings {
                // Defer until after AppKit is up; still only one UI instance.
                DispatchQueue.main.async {
                    openSystemSettingsPane(section: settingsSection)
                }
            }
            AppMain.main()
        }
        #else
        AppMain.main()
        #endif
    }

    #if os(macOS)
    private static func openSystemSettingsPane(section: String?) {
        _ = section
        if let url = URL(string: "x-apple.systempreferences:com.aspauldingcode.Wawona.prefPane") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
}

struct AppMain: App {
    @AppDelegateAdaptor(AppMainDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhase(newPhase)
                }
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.aspauldingcode.Wawona.prefPane"
                    ) {
                        _ = NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
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

#if canImport(UIKit)
    typealias AppDelegateAdaptor = UIApplicationDelegateAdaptor
    typealias AppMainDelegateBase = UIApplicationDelegate
    typealias AppType = UIApplication
#elseif canImport(AppKit)
    typealias AppDelegateAdaptor = NSApplicationDelegateAdaptor
    typealias AppMainDelegateBase = NSApplicationDelegate
    typealias AppType = NSApplication
#endif

@MainActor
final class AppMainDelegate: NSObject, AppMainDelegateBase {
    #if canImport(UIKit)
        func application(
            _ application: UIApplication,
            willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
        ) -> Bool {
            _ = application
            _ = launchOptions
            SharedAppDelegate.shared.onInit()
            return true
        }

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
        ) -> Bool {
            _ = application
            _ = launchOptions
            SharedAppDelegate.shared.onLaunch()
            return true
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
                if let url = URL(
                    string: "x-apple.systempreferences:com.aspauldingcode.Wawona.prefPane"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            for window in NSApp.windows where window.isVisible == false {
                window.makeKeyAndOrderFront(nil)
            }
        }
    #endif
}
