#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

/// Scene entry. Replaces WWNSceneDelegate.m. Host chrome stays SwiftUI.
@objc(WWNSceneDelegate)
public final class WWNSceneDelegate: UIResponder, UIWindowSceneDelegate {
    @objc public var window: UIWindow?
    @objc public var compositorContainer: UIView?

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        let container = UIView(frame: window.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.backgroundColor = .black
        compositorContainer = container
        // SwiftUI root lives in WawonaUI (WawonaRootView). Scene owns the window shell.
        let root = UIViewController()
        root.view.backgroundColor = .black
        container.frame = root.view.bounds
        root.view.addSubview(container)
        window.rootViewController = root
        window.makeKeyAndVisible()
        applyRespectSafeAreaPreference()
        _ = WWNCompositorBridge.sharedBridge.start(withSocketName: "wayland-0")
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
