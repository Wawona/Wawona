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
        let hosting = UIHostingController(rootView: WawonaRootView())
        window.rootViewController = hosting
        // Keep a full-bleed container for DRM present / nested clients that
        // attach under the root (Machines Focus path).
        let container = UIView(frame: window.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.isUserInteractionEnabled = false
        container.backgroundColor = .clear
        hosting.view.insertSubview(container, at: 0)
        compositorContainer = container
        window.makeKeyAndVisible()
        applyRespectSafeAreaPreference()
        Self.autoStartMachineIfRequested()
    }

    /// Lab / simctl: `xcrun simctl launch … -e WWN_AUTO_START_MACHINE=<id>`.
    /// Starts the named profile without XCUITest (Xcode 26 agent-device runner gap).
    private static func autoStartMachineIfRequested() {
        let mid = ProcessInfo.processInfo.environment["WWN_AUTO_START_MACHINE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !mid.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
