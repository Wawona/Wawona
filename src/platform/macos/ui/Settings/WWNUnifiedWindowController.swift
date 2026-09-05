#if os(macOS)
import AppKit
import SwiftUI

/// Owns the single SwiftUI window hosting Machine Configuration + every
/// settings section (`WawonaMainWindowView`). Replaces the standalone Machines
/// window and the AppKit settings window on macOS; discovered by ObjC through
/// `NSClassFromString` (same pattern as `WWNMachinesHostingBridge`).
@MainActor
@objc(WWNUnifiedWindowController)
final class WWNUnifiedWindowController: NSObject {
    @objc static func sharedController() -> WWNUnifiedWindowController {
        shared
    }

    static let shared = WWNUnifiedWindowController()

    private var windowController: NSWindowController?
    private let router = WWNMainWindowRouter()
    private let valueModel = WWNSettingsValueModel.shared

    // MARK: - ObjC entry points

    /// Launch path, ⌘⇧M menu, Settings → Machines: open the unified window on
    /// the Machine Configuration destination.
    @objc func showMachines() {
        router.showMachines()
        present()
    }

    /// ⌘, menu, gear button, `PlatformGlobalSettings.open()`: open the unified
    /// window on the first settings section.
    @objc func showSettings() {
        router.showSettings()
        present()
    }

    /// Deep-link to a settings section by title (e.g. "Display", "OpenSSH").
    @objc func selectSection(withTitle title: String) {
        router.selectSettings(title: title)
        present()
    }

    // MARK: - Window lifecycle

    private func makeWindowIfNeeded() {
        guard windowController == nil else { return }
        let root = WawonaMainWindowView(model: valueModel, router: router)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 1024, height: 720)
        if #available(macOS 26.0, *) {
            // Tahoe-style sidebar/titlebar integration (matches the old
            // machines window).
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
        }
        window.center()
        window.contentViewController = hosting
        window.title = "Wawona"
        window.isRestorable = false
        windowController = NSWindowController(window: window)
    }

    private func present() {
        makeWindowIfNeeded()
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
