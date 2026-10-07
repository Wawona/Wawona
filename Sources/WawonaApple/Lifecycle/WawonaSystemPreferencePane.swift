#if WWN_PREFPANE && os(macOS)
import AppKit
import PreferencePanes
import SwiftUI

/// macOS System Settings pane: Network-style NavigationStack over the global
/// Settings catalog (`com.aspauldingcode.Wawona`).
///
/// Width: `NSPrefPaneSupportsAutoLayout` in Info.plist + a flexible
/// `mainView` so System Settings sizes us like Network / Dock. Do not ship a
/// fixed 700×720 island.
///
/// Navigation: System Settings toolbar back/forward is sidebar history only.
/// In-pane Back lives in `WawonaPrefPaneRootView`.
@objc(WWNPreferencePane)
final class WWNPreferencePane: NSPreferencePane {
    override func mainViewDidLoad() {
        super.mainViewDidLoad()
    }

    override func loadMainView() -> NSView {
        // Zero frame: Auto Layout (NSPrefPaneSupportsAutoLayout) stretches
        // mainView to the System Settings content column.
        let host = WawonaPrefPaneHostingView(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        mainView = host
        return host
    }
}

@objc(WawonaAppHandoff)
@objcMembers
final class WawonaAppHandoff: NSObject {
    /// Prefer staying inside System Settings. Never spawn a second Regular
    /// Wawona.app via `openApplication` + argv (that was a multi-instance bug).
    static func openSettings(sectionTitle: String?) {
        _ = sectionTitle
        if let url = URL(string: "x-apple.systempreferences:com.aspauldingcode.Wawona.prefPane"),
           NSWorkspace.shared.open(url) {
            return
        }
        // Last resort: activate existing UI (createsNewApplicationInstance=false).
        let appURL = URL(fileURLWithPath: "/Applications/Wawona.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
#endif
