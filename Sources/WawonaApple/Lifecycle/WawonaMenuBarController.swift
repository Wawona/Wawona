#if os(macOS)
import AppKit
import Foundation

/// Accessory menu-bar applet (`Wawona --menubar`).
/// Never opens a second Regular UI via `open -n` / NSTask of this Mach-O.
@MainActor
final class WawonaMenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusLabel: NSTextField?
    private var pollTimer: Timer?
    private var loginSwitch: NSSwitch?

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Wawona"
        if let icon = Self.templateIcon() {
            item.button?.image = icon
            item.button?.imagePosition = .imageOnly
            item.button?.title = ""
        } else {
            item.button?.title = "Wawona"
        }

        let menu = NSMenu(title: "Wawona")
        menu.autoenablesItems = false
        menu.delegate = self

        let compositorRow = NSView(frame: NSRect(x: 0, y: 0, width: 268, height: 32))
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        label.frame = NSRect(x: 14, y: 6, width: 180, height: 20)
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        compositorRow.addSubview(label)
        statusLabel = label
        updateCompositorStatus(running: false)

        let startBtn = symbolButton("play.fill", "Start Compositor", #selector(startCompositor))
        let stopBtn = symbolButton("stop.fill", "Stop Compositor", #selector(stopCompositor))
        let restartBtn = symbolButton("arrow.clockwise", "Restart Compositor", #selector(restartCompositor))
        for (idx, btn) in [restartBtn, stopBtn, startBtn].enumerated() {
            btn.frame.origin = CGPoint(x: 268 - 26 - CGFloat(idx) * 26, y: 5)
            compositorRow.addSubview(btn)
        }

        let compositorItem = NSMenuItem()
        compositorItem.view = compositorRow
        menu.addItem(compositorItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Wawona Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let machines = NSMenuItem(
            title: "Machine Configuration",
            action: #selector(openMachines),
            keyEquivalent: "m"
        )
        machines.target = self
        menu.addItem(machines)
        menu.addItem(.separator())

        let loginRow = NSView(frame: NSRect(x: 0, y: 0, width: 268, height: 32))
        let loginLabel = NSTextField(labelWithString: "Launch at Login")
        loginLabel.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        loginLabel.frame = NSRect(x: 14, y: 6, width: 180, height: 20)
        loginRow.addSubview(loginLabel)
        let sw = NSSwitch()
        sw.controlSize = .mini
        sw.target = self
        sw.action = #selector(toggleLaunchAtLogin(_:))
        sw.frame = NSRect(x: 220, y: 6, width: 40, height: 20)
        sw.state = WWNLaunchAgentManager.sharedManager.isAppLaunchAgentLoaded() ? .on : .off
        loginRow.addSubview(sw)
        loginSwitch = sw
        let loginItem = NSMenuItem()
        loginItem.view = loginRow
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Menu Bar",
            action: #selector(quitMenuBar),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        refreshStatus()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        _ = menu
        refreshStatus()
        loginSwitch?.state =
            WWNLaunchAgentManager.sharedManager.isAppLaunchAgentLoaded() ? .on : .off
    }

    private func refreshStatus() {
        let running = WWNLaunchAgentManager.sharedManager.isCompositorAgentLoaded()
            && Self.compositorSocketReady()
        updateCompositorStatus(running: running)
    }

    private func updateCompositorStatus(running: Bool) {
        let font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        let prefix = NSAttributedString(
            string: "Compositor: ",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        let state = NSAttributedString(
            string: running ? "running" : "stopped",
            attributes: [
                .font: font,
                .foregroundColor: running ? NSColor.systemGreen : NSColor.systemRed,
            ]
        )
        let text = NSMutableAttributedString(attributedString: prefix)
        text.append(state)
        statusLabel?.attributedStringValue = text
    }

    @objc private func startCompositor() {
        _ = WWNLaunchAgentManager.sharedManager.startCompositorAgent()
        refreshStatus()
    }

    @objc private func stopCompositor() {
        _ = WWNLaunchAgentManager.sharedManager.stopCompositorAgent()
        refreshStatus()
    }

    @objc private func restartCompositor() {
        _ = WWNLaunchAgentManager.sharedManager.restartCompositorAgent()
        refreshStatus()
    }

    @objc private func openSettings() {
        // Activate Regular UI on the in-app Global Settings catalog.
        WawonaLaunchMode.openOrActivateUI(arguments: ["--show-settings"])
    }

    @objc private func openMachines() {
        WawonaLaunchMode.openOrActivateUI(arguments: [])
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSSwitch) {
        if sender.state == .on {
            _ = WWNLaunchAgentManager.sharedManager.enableAppLaunchAtLogin()
        } else {
            _ = WWNLaunchAgentManager.sharedManager.disableAppLaunchAtLogin()
        }
    }

    @objc private func quitMenuBar() {
        // Boot out this agent only. Compositor-host stays up.
        _ = WWNLaunchAgentManager.sharedManager.stopMenuBarAgent()
        NSApp.terminate(nil)
    }

    private func symbolButton(_ symbol: String, _ label: String, _ sel: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        let btn = NSButton(image: image ?? NSImage(), target: self, action: sel)
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        btn.toolTip = label
        btn.setFrameSize(NSSize(width: 22, height: 22))
        return btn
    }

    private static func templateIcon() -> NSImage? {
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

    private static func compositorSocketReady() -> Bool {
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
enum WawonaMenuBarApp {
    static func run() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { run() }
            return
        }
        MainActor.assumeIsolated { runOnMain() }
    }

    @MainActor
    private static func runOnMain() {
        if !WawonaLaunchLockState.acquireMenuBar() {
            // Another menubar agent already holds the lock.
            return
        }
        atexit {
            WawonaLaunchLockState.releaseAll()
        }

        ProcessInfo.processInfo.processName = "WawonaMenuBar"
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var agentError: NSError?
        _ = WWNLaunchAgentManager.sharedManager.ensureCompositorAgent(&agentError)

        let controller = WawonaMenuBarController()
        controller.start()
        // Keep controller alive for the run loop.
        objc_setAssociatedObject(
            app,
            "wawona.menubar.controller",
            controller,
            .OBJC_ASSOCIATION_RETAIN
        )
        app.run()
        controller.stop()
        WawonaLaunchLockState.releaseAll()
    }
}
#endif
