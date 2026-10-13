#if os(iOS) || os(tvOS) || os(visionOS)
import SwiftUI
import UIKit

#if os(iOS) || os(visionOS)
/// Key window that surfaces shake to SwiftUI (first-responder probes miss Metal).
private final class WWNShakeWindow: UIWindow {
    private var lastShakeAt: TimeInterval = 0

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastShakeAt > 0.8 else { return }
        lastShakeAt = now
        NotificationCenter.default.post(
            name: Notification.Name("WWNDeviceDidShakeNotification"),
            object: nil
        )
    }
}
#endif

/// Scene entry. Hosts Machines SwiftUI chrome (first-launch welcome is a
/// native SwiftUI alert, not a page). Replaces `WWNSceneDelegate.m`.
/// Process entry is `Darwin/Sources/Main.swift` (`UIApplicationMain`);
/// Info.plist names this class.
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
        guard let windowScene = scene as? UIWindowScene else { return }
        #if os(iOS) || os(visionOS)
        let window: UIWindow = WWNShakeWindow(windowScene: windowScene)
        #else
        let window = UIWindow(windowScene: windowScene)
        #endif
        self.window = window
        // Host chrome is SwiftUI. Do not insert UIKit subviews under
        // UIHostingController.view (SwiftUI runtime warning / broken hierarchy).
        // New Window Start opens a session-only scene (no Machines chrome).
        // tvOS has no multi-window session scenes; isSessionScene is iOS/vision only.
        #if os(iOS) || os(visionOS)
        let sessionOnly = WWNSessionWindowPresenter.isSessionScene(options: connectionOptions)
        #else
        let sessionOnly = false
        #endif
        let hosting: UIHostingController<AnyView>
        if sessionOnly {
            hosting = UIHostingController(rootView: AnyView(WWNSessionSurfaceRootView()))
        } else {
            hosting = UIHostingController(rootView: AnyView(WawonaRootView()))
        }
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
        WWNRootfsProvider.applyShellEnvironment()
        let bridge = WWNCompositorBridge.sharedBridge
        if bridge.ensureRunning(withSocketName: "wayland-0") {
            setenv("WAYLAND_DISPLAY", bridge.socketName(), 1)
        }
        if !sessionOnly {
            Self.autoStartMachineIfRequested()
        }
    }

    /// Lab / simctl: `SIMCTL_CHILD_WWN_AUTO_START_MACHINE=<id> xcrun simctl launch …`.
    /// Starts the named profile without XCUITest (Xcode 26 agent-device runner gap).
    ///
    /// Must mount the session Metal surface before `connect`: Mode A StaticCpu
    /// present pumps `relay_copy_frame` into `IlandPresenterObjC`, which only
    /// exists while `CompositorHostView` is in the tree. Calling
    /// `WWNMachineSessionBridge.connect` alone leaves Machines UI up and
    /// `activePresenterForDrain()` nil forever (no `Mode A SHM present` log).
    private static func autoStartMachineIfRequested() {
        let mid = ProcessInfo.processInfo.environment["WWN_AUTO_START_MACHINE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !mid.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let bridge = WWNCompositorBridge.sharedBridge
            if !bridge.ensureRunning(withSocketName: "wayland-0") {
                NSLog("WWN_AUTO_START_MACHINE: host compositor still down")
            } else {
                setenv("WAYLAND_DISPLAY", bridge.socketName(), 1)
            }
            guard let profile =
                WWNMachineProfileStore.profile(byId: mid)
                ?? WWNMachineProfileStore.labSynthesizeStaticCpuProfileIfGuestStaged(
                    machineId: mid
                )
            else {
                NSLog("WWN_AUTO_START_MACHINE: no profile %@", mid)
                return
            }
            // Same path as Machines Start: reveal Metal host, then session.
            NotificationCenter.default.post(
                name: Notification.Name("WWNShowSessionSurfaceNotification"),
                object: nil
            )
            // `relay_start` SHA256-verifies grown rootfs on the calling thread
            // (multi-GB). Never block main: CompositorHostView / IlandPresenter
            // need runloop turns while artifacts hash, or Mode A SHM stays nil.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.8) {
                do {
                    try WWNMachineSessionBridge.connect(profile)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("WWNShowSessionSurfaceNotification"),
                            object: nil,
                            userInfo: [
                                "machineId": mid,
                                "source": "auto-start",
                            ]
                        )
                        NSLog("WWN_AUTO_START_MACHINE: started %@", mid)
                    }
                } catch {
                    let msg = error.localizedDescription
                    DispatchQueue.main.async {
                        NSLog(
                            "WWN_AUTO_START_MACHINE: failed %@: %@",
                            mid,
                            msg
                        )
                    }
                }
            }
        }
    }

    @objc public func applyRespectSafeAreaPreference() {
        // Compositor safe-area is owned by SwiftUI `WWNSessionSafeAreaModifier`
        // (Respect Safe Area pref). Keep the hosting root full-window.
        guard let window, let container = compositorContainer else { return }
        container.frame = window.bounds
        NotificationCenter.default.post(
            name: Notification.Name("WWNRespectSafeAreaChangedNotification"),
            object: nil
        )
    }

    public func sceneDidBecomeActive(_ scene: UIScene) {
        _ = scene
        WWNCompositorBridge.sharedBridge.pollAndHandleWindowEvents()
    }
}
#endif
