import Foundation

#if canImport(AppKit) && os(macOS)
import AppKit
#endif
#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
import UIKit
#endif

/// Opens the SwiftUI Settings host. Section inventory comes from
/// `WWNPreferencesSectionsBuilder` (extracted from the legacy AppKit table).
@objc(WWNPreferences)
public final class WWNPreferences: NSObject {
    @objc public static let sharedPreferences = WWNPreferences()

    @objc private(set) dynamic var sections: [WWNPreferencesSection] = []

    private override init() {
        super.init()
        rebuildSections()
        NotificationCenter.default.addObserver(
            forName: .WWNMachineProfilesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildSections()
        }
    }

    @objc public func rebuildSections() {
        sections = WWNPreferencesSectionsBuilder.buildSections() as? [WWNPreferencesSection] ?? []
    }

    #if os(macOS)
    @objc(showPreferences:)
    public func showPreferences(_ sender: Any?) {
        _ = sender
        NSApp.activate(ignoringOtherApps: true)
        // PrefPane is the sole Global Settings host. No in-app catalog fallback.
        if let url = URL(string: "x-apple.systempreferences:com.aspauldingcode.Wawona.prefPane") {
            _ = NSWorkspace.shared.open(url)
        }
    }

    @objc(show:)
    public func show(_ app: NSApplication) {
        showPreferences(app)
    }

    @objc public func selectSectionWithTitle(_ title: String) {
        if let controller = NSClassFromString("WWNUnifiedWindowController") as AnyObject?,
           controller.responds(to: Selector(("selectSectionWithTitle:"))) {
            _ = controller.perform(Selector(("selectSectionWithTitle:")), with: title)
        }
    }

    @objc public func openEnvironmentVariablesManager() {
        selectSectionWithTitle("Env Vars")
    }

    @objc public func openMachinesConfiguration(_ sender: Any?) {
        _ = sender
        if let controller = NSClassFromString("WWNUnifiedWindowController") as AnyObject?,
           controller.responds(to: Selector(("showMachines"))) {
            _ = controller.perform(Selector(("showMachines")))
        }
    }

    @objc public func installMacSettingsInterfaceInView(_ hostView: NSView) {
        _ = hostView
    }
    #endif

    #if os(iOS) || os(tvOS) || os(visionOS)
    @objc(showPreferences:)
    public func showPreferences(_ sender: Any?) {
        _ = sender
        #if os(iOS)
        // Settings.bundle is the sole Global Settings host on iPhone / iPad.
        // UIApplication.openSettingsURLString opens Settings > Apps > Wawona
        // when Settings.bundle is present (inlined Root.plist). Never App-Prefs.
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        #else
        // tvOS / visionOS: in-app Global Settings only (no Settings.bundle).
        NotificationCenter.default.post(
            name: Notification.Name("wawonaOpenInAppGlobalSettingsPanel"),
            object: nil
        )
        #endif
    }

    @objc public func selectSectionWithTitle(_ title: String) {
        _ = title
    }

    @objc public func openEnvironmentVariablesManager() {}

    @objc public func openMachinesConfiguration(_ sender: Any?) {
        _ = sender
    }

    @objc public func dismissSelf() {}
    #endif
}
