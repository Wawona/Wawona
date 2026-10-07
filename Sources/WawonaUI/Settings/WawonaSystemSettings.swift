#if os(macOS)
import AppKit
import Foundation
import os.log

/// Opens macOS System Settings → Wawona preference pane.
/// Global Settings exclusivity: PrefPane is the sole host. Never fall back to
/// an in-app duplicate catalog (`wawona-global-settings-exclusive`).
enum WawonaSystemSettings {
    private static let log = Logger(
        subsystem: "com.aspauldingcode.Wawona",
        category: "SystemSettings"
    )

    static let preferencePaneBundleID = "com.aspauldingcode.Wawona.prefPane"

    static var preferencePaneURL: URL? {
        URL(string: "x-apple.systempreferences:\(preferencePaneBundleID)")
    }

    @discardableResult
    static func openPreferencePane() -> Bool {
        guard let url = preferencePaneURL else {
            log.error("Wawona PrefPane URL missing")
            return false
        }
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            log.error(
                "Failed to open System Settings → Wawona. Install Wawona.prefPane via the product pkg."
            )
        }
        return opened
    }

    static func isPreferencePaneInstalled() -> Bool {
        let homes = [
            ("\(NSHomeDirectory())/Library/PreferencePanes/Wawona.prefPane" as NSString)
                .expandingTildeInPath,
            "/Library/PreferencePanes/Wawona.prefPane",
        ]
        return homes.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
#endif
