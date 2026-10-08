#if os(iOS) || os(tvOS) || os(visionOS)
import SwiftUI
import UIKit

/// Scene entry. Hosts Machines / Welcome SwiftUI chrome. Replaces
/// `WWNSceneDelegate.m`. Process entry is `Darwin/Sources/Main.swift`
/// (`UIApplicationMain`); Info.plist names this class.
@objc(WWNSceneDelegate)
public final class WWNSceneDelegate: UIResponder, UIWindowSceneDelegate {
    @objc public var window: UIWindow?
    @objc public var compositorContainer: UIView?

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        _ = session
        _ = connectionOptions
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        // Host chrome is SwiftUI. Do not insert UIKit subviews under
        // UIHostingController.view (SwiftUI runtime warning / broken hierarchy).
        let hosting = UIHostingController(rootView: WawonaRootView())
        window.rootViewController = hosting
        compositorContainer = hosting.view
        window.makeKeyAndVisible()
        applyRespectSafeAreaPreference()
        // Ensure host Wayland is up before any lab auto-start (AppDelegate may
        // race scene connection on cold launch).
        let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
        try? FileManager.default.createDirectory(
            atPath: runtime,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        setenv("XDG_RUNTIME_DIR", runtime, 1)
        let bridge = WWNCompositorBridge.sharedBridge
        if bridge.start(withSocketName: "wayland-0") {
            setenv("WAYLAND_DISPLAY", bridge.socketName(), 1)
        }
        Self.autoStartMachineIfRequested()
    }

    /// Lab / simctl: `SIMCTL_CHILD_WWN_AUTO_START_MACHINE=<id> xcrun simctl launch …`.
    /// Starts the named profile without XCUITest (Xcode 26 agent-device runner gap).
    private static func autoStartMachineIfRequested() {
        let mid = ProcessInfo.processInfo.environment["WWN_AUTO_START_MACHINE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !mid.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let bridge = WWNCompositorBridge.sharedBridge
            if !bridge.isRunning() {
                if bridge.start(withSocketName: "wayland-0") {
                    setenv("WAYLAND_DISPLAY", bridge.socketName(), 1)
                } else {
                    NSLog("WWN_AUTO_START_MACHINE: host compositor still down")
                }
            }
            guard let profile = WWNMachineProfileStore.profile(byId: mid) else {
                NSLog("WWN_AUTO_START_MACHINE: no profile %@", mid)
                return
            }
            do {
                try WWNMachineSessionBridge.connect(profile)
                NSLog("WWN_AUTO_START_MACHINE: started %@", mid)
            } catch {
                NSLog(
                    "WWN_AUTO_START_MACHINE: failed %@: %@",
                    mid,
                    error.localizedDescription
                )
            }
        }
    }

    @objc public func applyRespectSafeAreaPreference() {
        guard let window, let container = compositorContainer else { return }
        container.frame = window.bounds
    }

    public func sceneDidBecomeActive(_ scene: UIScene) {
        _ = scene
        WWNCompositorBridge.sharedBridge.pollAndHandleWindowEvents()
    }
}
#endif
