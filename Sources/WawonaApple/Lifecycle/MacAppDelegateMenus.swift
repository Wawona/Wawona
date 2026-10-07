#if os(macOS)
import AppKit

/// Menu actions formerly in main.m. Darwin @main owns process entry.
@objc(WWNMacAppMenuActions)
public final class WWNMacAppMenuActions: NSObject {
    @objc public static let shared = WWNMacAppMenuActions()

    @objc public func installDefaultMenus() {
        let app = NSApplication.shared
        let mainMenu = app.mainMenu ?? NSMenu()
        if app.mainMenu == nil { app.mainMenu = mainMenu }
    }

    @objc public func spawnCLIHelp() {
        print("Wawona CLI: use Machines UI or `Wawona --help`.")
    }
}
#endif
