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
    private static var retainedInventory: WWNEnvironmentInventoryHostingController?

    /// View controller hosting the full Environment Variables table (same catalog as macOS).
    @objc(iOSHostingController)
    public static func iOSHostingController() -> UIViewController {
        if Thread.isMainThread {
            return inventoryController()
        }
        return DispatchQueue.main.sync { inventoryController() }
    }

    private static func inventoryController() -> WWNEnvironmentInventoryHostingController {
        if let existing = retainedInventory {
            return existing
        }
        let hosting = WWNEnvironmentInventoryHostingController()
        retainedInventory = hosting
        return hosting
    }

    private static func presentIOS(from host: UIViewController?) {
        // Env Vars is the Settings detail pane (`WWNPreferences.wwnSyncEnvironmentInventory`).
        // Do not `showDetailViewController` this host in place of the secondary nav:
        // that left the one-row stub on the back stack / as the fallback page.
        let hosting = inventoryController()
        if host?.splitViewController != nil {
            return
        }
        if let nav = host as? UINavigationController {
            nav.pushViewController(hosting, animated: true)
            return
        }
        if let nav = host?.navigationController {
            nav.pushViewController(hosting, animated: true)
            return
        }
        let wrap = UINavigationController(rootViewController: hosting)
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

#if os(iOS) || os(tvOS) || os(visionOS)
/// Full catalog table for iOS Settings → Env Vars. Same `EnvironmentVariablesView` as macOS.
private final class WWNEnvironmentInventoryHostingController:
    UIHostingController<EnvironmentVariablesView>
{
    convenience init() {
        WawonaPreferences.shared.load()
        self.init(
            rootView: EnvironmentVariablesView(
                preferences: WawonaPreferences.shared,
                perMachine: false
            )
        )
        title = "Environment Variables"
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "wwn.settings.environment"
        #if os(tvOS)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .plain,
            target: self,
            action: #selector(dismissSettingsRoot)
        )
        #else
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSettingsRoot)
        )
        #endif
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "wwn.settings.done"
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Done"
    }

    @objc private func dismissSettingsRoot() {
        if let split = splitViewController {
            split.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}
#endif
