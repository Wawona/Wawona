import SwiftUI
#if canImport(WawonaUI)
import WawonaUI
#endif
#if canImport(WawonaModel)
import WawonaModel
#endif

private typealias AppRootView = WawonaRootView
private typealias SharedAppDelegate = WawonaAppDelegate

@main
struct AppMain: App {
    @AppDelegateAdaptor(AppMainDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        if #available(iOS 17, macOS 14, *) {
            WindowGroup("Session", id: "session", for: MachineSession.ID.self) { _ in
                CompositorBridge()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        SharedAppDelegate.shared.onDestroy()
    }
    #endif
}
