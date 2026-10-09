#if os(macOS)
import AppKit
import Foundation

extension WawonaMenuBarController {
    @objc func takeOverDesktop() {
        WWNDesktopReplacementController.sharedController.presentReplaceNowFlow()
        refreshStatus(fromTimer: false)
    }

    @objc func restoreDesktop() {
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Restore Aqua?"
        confirm.informativeText =
            "Ends this Desktop Replacement session and restores WindowServer. "
            + "Path B stays installed. Enable Desktop Replacement stays on."
        confirm.addButton(withTitle: "Restore Aqua")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        if !WWNDesktopReplacementController.sharedController.endClassicSession() {
            let fail = NSAlert()
            fail.alertStyle = .critical
            fail.messageText = "Could not restore Aqua"
            fail.informativeText =
                "Approve the administrator prompt so Wawona can restore WindowServer."
            fail.addButton(withTitle: "OK")
            fail.runModal()
        }
        refreshStatus(fromTimer: false)
    }

    @objc func restartMacForDesktop() {
        let desk = WWNDesktopReplacementController.sharedController
        let ready = desk.evaluateClassicReadiness()
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Restart required before Take Over"
        confirm.informativeText =
            "\(ready.userSummary)\n\nWawona will open the native macOS Restart sheet "
            + "(loginwindow kAERestart, 60-second countdown). After you log "
            + "back in, use Replace now. Login does not take over."
        confirm.addButton(withTitle: "Restart")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        var err: NSError?
        if !desk.requestNativeMacOSRestart(&err) {
            let fail = NSAlert()
            fail.alertStyle = .critical
            fail.messageText = "Could not open Restart"
            fail.informativeText = err?.localizedDescription ?? "Use the Apple menu, then Restart."
            fail.addButton(withTitle: "OK")
            fail.runModal()
        }
        refreshStatus(fromTimer: false)
    }

    @objc func openSettings() {
        WawonaLaunchMode.openOrActivateUI(arguments: ["--show-settings"])
    }

    @objc func openMachines() {
        WawonaLaunchMode.openOrActivateUI(arguments: [])
    }

    @objc func openAbout() {
        WawonaLaunchMode.openOrActivateUI(arguments: ["--show-about"])
    }

    @objc func toggleLaunchAtLogin(_ sender: NSSwitch) {
        if sender.state == .on {
            _ = WWNLaunchAgentManager.sharedManager.enableAppLaunchAtLogin()
        } else {
            _ = WWNLaunchAgentManager.sharedManager.disableAppLaunchAtLogin()
        }
    }

    @objc func quitMenuBar() {
        _ = WWNLaunchAgentManager.sharedManager.stopMenuBarAgent()
        NSApp.terminate(nil)
    }

    func symbolButton(_ symbol: String, _ label: String, _ sel: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        let btn = NSButton(image: image ?? NSImage(), target: self, action: sel)
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        btn.toolTip = label
        btn.setFrameSize(NSSize(width: 22, height: 22))
        return btn
    }

    static func templateIcon() -> NSImage? {
        let names = [
            "Wawona-menubar-silhouette",
            "Wawona-iOS-Dark-1024x1024@1x",
            "Wawona",
        ]
        let bundle = Bundle.main
        for name in names {
            if let img = bundle.image(forResource: name) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                return img
            }
            if let path = bundle.path(forResource: name, ofType: "png"),
               let img = NSImage(contentsOfFile: path) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                return img
            }
        }
        return nil
    }

    static func compositorSocketReady() -> Bool {
        let dir = WawonaProcessLock.runtimeDirectory()
        let statePath = (dir as NSString).appendingPathComponent("wawona-runtime-state.plist")
        guard let state = NSDictionary(contentsOfFile: statePath) as? [String: Any],
              (state["healthy"] as? Bool) == true else {
            return false
        }
        let socketPath = (state["socketPath"] as? String)
            ?? (dir as NSString).appendingPathComponent("wayland-0")
        return FileManager.default.fileExists(atPath: socketPath)
    }
}

/// Runs the menubar agent event loop (no SwiftUI WindowGroup).
}
#endif
