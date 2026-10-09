#if os(macOS)
import AppKit
import Foundation

/// Accessory menu-bar applet (`Wawona --menubar`).
/// Never opens a second Regular UI via `open -n` / NSTask of this Mach-O.
@MainActor
final class WawonaMenuBarController: NSObject, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var statusLabel: NSTextField?
    var desktopStatusLabel: NSTextField?
    var desktopTakeOverButton: NSButton?
    var desktopRestoreButton: NSButton?
    var desktopRestartButton: NSButton?
    var compositorRow: NSView?
    var desktopRow: NSView?
    var startButton: NSButton?
    var stopButton: NSButton?
    var restartButton: NSButton?
    var pollTimer: Timer?
    var loginSwitch: NSSwitch?
    var loginRow: NSView?

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
        label.frame = NSRect(x: 14, y: 6, width: 150, height: 20)
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        compositorRow.addSubview(label)
        statusLabel = label
        self.compositorRow = compositorRow
        updateCompositorStatus(running: false)

        let startBtn = symbolButton("play.fill", "Start Compositor", #selector(startCompositor))
        let stopBtn = symbolButton("stop.fill", "Stop Compositor", #selector(stopCompositor))
        let restartBtn = symbolButton("arrow.clockwise", "Restart Compositor", #selector(restartCompositor))
        startButton = startBtn
        stopButton = stopBtn
        restartButton = restartBtn
        for (idx, btn) in [restartBtn, stopBtn, startBtn].enumerated() {
            btn.frame.origin = CGPoint(x: 268 - 26 - CGFloat(idx) * 26, y: 5)
            compositorRow.addSubview(btn)
        }

        let compositorItem = NSMenuItem()
        compositorItem.view = compositorRow
        menu.addItem(compositorItem)
        menu.addItem(.separator())

        // Desktop Replacement row (Mode B). Policy via DesktopReplacementController.
        let desktopRow = NSView(frame: NSRect(x: 0, y: 0, width: 268, height: 32))
        let deskLabel = NSTextField(labelWithString: "")
        deskLabel.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        deskLabel.frame = NSRect(x: 14, y: 6, width: 150, height: 20)
        deskLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        desktopRow.addSubview(deskLabel)
        desktopStatusLabel = deskLabel
        self.desktopRow = desktopRow

        let deskRestart = symbolButton(
            "arrow.clockwise", "Restart Mac (Path B reboot)", #selector(restartMacForDesktop)
        )
        let deskRestore = symbolButton("stop.fill", "Restore Aqua", #selector(restoreDesktop))
        let deskTakeOver = symbolButton("play.fill", "Replace now", #selector(takeOverDesktop))
        desktopRestartButton = deskRestart
        desktopRestoreButton = deskRestore
        desktopTakeOverButton = deskTakeOver
        for (idx, btn) in [deskRestart, deskRestore, deskTakeOver].enumerated() {
            btn.frame.origin = CGPoint(x: 268 - 26 - CGFloat(idx) * 26, y: 5)
            desktopRow.addSubview(btn)
        }
        let desktopItem = NSMenuItem()
        desktopItem.view = desktopRow
        menu.addItem(desktopItem)
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

        let about = NSMenuItem(
            title: "About Wawona",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)
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
        self.loginRow = loginRow
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
            Task { @MainActor in self?.refreshStatus(fromTimer: true) }
        }
        refreshStatus(fromTimer: false)
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
        syncCustomMenuItemWidths(menu)
        refreshStatus(fromTimer: false)
        loginSwitch?.state =
            WWNLaunchAgentManager.sharedManager.isAppLaunchAgentLoaded() ? .on : .off
    }

    private func syncCustomMenuItemWidths(_ menu: NSMenu) {
        var width: CGFloat = 268
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: NSFont.systemFontSize)
        ]
        for item in menu.items where item.view == nil && !item.isSeparatorItem && !item.title.isEmpty {
            width = max(width, (item.title as NSString).size(withAttributes: attrs).width + 48)
        }
        let trailing: CGFloat = 12
        let btn: CGFloat = 22
        let gap: CGFloat = 4
        if let row = compositorRow {
            var frame = row.frame
            frame.size.width = width
            row.frame = frame
            var x = width - trailing
            startButton?.frame = NSRect(x: x - btn, y: 5, width: btn, height: btn)
            x -= btn + gap
            stopButton?.frame = NSRect(x: x - btn, y: 5, width: btn, height: btn)
            x -= btn + gap
            restartButton?.frame = NSRect(x: x - btn, y: 5, width: btn, height: btn)
            if var status = statusLabel?.frame {
                status.size.width = max(80, x - btn - 8 - 14)
                statusLabel?.frame = status
            }
        }
        if let row = desktopRow {
            var frame = row.frame
            frame.size.width = width
            row.frame = frame
            var x = width - trailing
            desktopTakeOverButton?.frame = NSRect(x: x - btn, y: 5, width: btn, height: btn)
            x -= btn + gap
            desktopRestoreButton?.frame = NSRect(x: x - btn, y: 5, width: btn, height: btn)
            x -= btn + gap
            desktopRestartButton?.frame = NSRect(x: x - btn, y: 5, width: btn, height: btn)
            if var status = desktopStatusLabel?.frame {
                status.size.width = max(80, x - btn - 8 - 14)
                desktopStatusLabel?.frame = status
            }
        }
        if let row = loginRow, let sw = loginSwitch {
            var frame = row.frame
            frame.size.width = width
            row.frame = frame
            sw.sizeToFit()
            let swSize = sw.frame.size
            let y = (frame.size.height - swSize.height) / 2
            sw.frame = NSRect(
                x: width - trailing - swSize.width, y: y,
                width: swSize.width, height: swSize.height
            )
        }
    }

    func refreshStatus(fromTimer: Bool) {
        let running = WWNLaunchAgentManager.sharedManager.isCompositorAgentLoaded()
            && Self.compositorSocketReady()
        updateCompositorStatus(running: running)

        let refreshGate = !fromTimer
        let desk = WWNDesktopReplacementController.sharedController
            .menuBarDesktopStatus(refreshingGate: refreshGate)
        updateDesktopStatus(desk)
    }

    func updateCompositorStatus(running: Bool) {
        statusLabel?.attributedStringValue = statusAttributed(
            prefix: "Compositor",
            state: running ? "running" : "stopped",
            color: running ? .systemGreen : .systemRed
        )
        startButton?.isEnabled = !running
        stopButton?.isEnabled = running
        restartButton?.isEnabled = running
    }

    func updateDesktopStatus(_ desk: WWNModeBMenuBarStatus) {
        let state = desk.state
        let color: NSColor
        if state == "ready" || state == "takeover" || state == "Armed" {
            color = .systemGreen
        } else if state == "reboot" {
            color = .systemPurple
        } else {
            color = .systemRed
        }
        desktopStatusLabel?.attributedStringValue = statusAttributed(
            prefix: "Desktop",
            state: state,
            color: color
        )
        desktopStatusLabel?.toolTip = desk.tooltip.isEmpty ? "Desktop: \(state)" : desk.tooltip
        desktopTakeOverButton?.isEnabled = desk.canTakeOver || desk.canPrepare
        desktopRestoreButton?.isEnabled = desk.canRestore
        desktopRestartButton?.isEnabled = desk.canRestartMac
        desktopTakeOverButton?.toolTip = "Replace now"
    }

    func statusAttributed(prefix: String, state: String, color: NSColor) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        let text = NSMutableAttributedString(
            string: "\(prefix): ",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: state,
            attributes: [.font: font, .foregroundColor: color]
        ))
        return text
    }

    @objc private func startCompositor() {
        _ = WWNLaunchAgentManager.sharedManager.startCompositorAgent()
        refreshStatus(fromTimer: false)
    }

    @objc private func stopCompositor() {
        _ = WWNLaunchAgentManager.sharedManager.stopCompositorAgent()
        refreshStatus(fromTimer: false)
    }

    @objc private func restartCompositor() {
        _ = WWNLaunchAgentManager.sharedManager.restartCompositorAgent()
        refreshStatus(fromTimer: false)
    }
}

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
