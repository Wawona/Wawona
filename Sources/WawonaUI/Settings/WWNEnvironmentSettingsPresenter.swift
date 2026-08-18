import SwiftUI
import WawonaModel

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Present / embed the Environment Variables GUI from ObjC Settings (`WWNPreferences`).
@MainActor
@objc(WWNEnvironmentSettingsPresenter)
public final class WWNEnvironmentSettingsPresenter: NSObject {
    @objc public static func presentFromHost(_ host: AnyObject?) {
        if Thread.isMainThread {
            presentFromHostOnMain(host)
        } else {
            DispatchQueue.main.async { presentFromHostOnMain(host) }
        }
    }

    private static func presentFromHostOnMain(_ host: AnyObject?) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        presentIOS(from: host as? UIViewController)
        #elseif os(macOS)
        presentMac(from: host)
        #endif
    }

    #if os(macOS)
    /// NSView hosting the full Environment Variables table (embed in Settings detail).
    @objc(macOSHostingView)
    public static func macOSHostingView() -> NSView {
        if Thread.isMainThread {
            return makeMacOSHostingView()
        }
        return DispatchQueue.main.sync { makeMacOSHostingView() }
    }

    private static func makeMacOSHostingView() -> NSView {
        let root = EnvironmentVariablesView(
            preferences: WawonaPreferences.shared,
            perMachine: false
        )
        .frame(minWidth: 280, minHeight: 200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Use autoresizing (not Auto Layout flags alone) so ObjC can size the
        // host with frame + autoresizingMask. Setting
        // translatesAutoresizingMaskIntoConstraints = false without constraints
        // leaves a zero-size blank pane in Settings.
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.setAccessibilityIdentifier("wwn.settings.environment")
        return hosting
    }

    private static var retainedWindow: NSWindow?

    private static func presentMac(from host: AnyObject?) {
        _ = host
        let hosting = NSHostingController(
            rootView: EnvironmentVariablesView(
                preferences: WawonaPreferences.shared,
                perMachine: false
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Environment Variables"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 680))
        window.center()
        window.makeKeyAndOrderFront(nil)
        retainedWindow = window
    }
    #endif

    #if os(iOS) || os(tvOS) || os(visionOS)
    /// View controller hosting the full Environment Variables table.
    @objc(iOSHostingController)
    public static func iOSHostingController() -> UIViewController {
        if Thread.isMainThread {
            return makeIOSHostingController()
        }
        return DispatchQueue.main.sync { makeIOSHostingController() }
    }

    private static func makeIOSHostingController() -> UIViewController {
        let root = NavigationStack {
            EnvironmentVariablesView(
                preferences: WawonaPreferences.shared,
                perMachine: false
            )
        }
        let hosting = UIHostingController(rootView: root)
        hosting.title = "Environment Variables"
        hosting.view.accessibilityIdentifier = "wwn.settings.environment"
        return hosting
    }

    private static func presentIOS(from host: UIViewController?) {
        let hosting = makeIOSHostingController()
        if let nav = host as? UINavigationController {
            nav.pushViewController(hosting, animated: true)
            return
        }
        let wrap = UINavigationController(rootViewController: hosting)
        #if os(tvOS)
        hosting.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .plain,
            target: hosting,
            action: #selector(UIViewController.dismiss(animated:completion:))
        )
        #else
        hosting.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: hosting,
            action: #selector(UIViewController.dismiss(animated:completion:))
        )
        #endif
        var presenter = host
        if presenter == nil {
            presenter = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }?
                .rootViewController
        }
        while let shown = presenter?.presentedViewController {
            presenter = shown
        }
        presenter?.present(wrap, animated: true)
    }
    #endif
}
