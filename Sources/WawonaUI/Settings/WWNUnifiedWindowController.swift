#if os(macOS)
import AppKit
import SwiftUI
import WawonaModel

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
    private let router = WWNMainWindowRouter.shared
    private let valueModel = WWNSettingsValueModel.shared
    private let preferences = WawonaPreferences.shared
    private let profileStore = MachineProfileStore()
    private let sessions = SessionOrchestrator()

    // MARK: - ObjC entry points

    /// Launch path, ⌘⇧M menu, Settings → Machines: open the unified window on
    /// the Machine Configuration destination.
    @objc func showMachines() {
        router.showMachines()
        present()
    }

    /// ⌘, / toolbar Settings: in-app Global Settings sidebar catalog.
    @objc func showSettings() {
        router.showSettings()
        present()
    }

    /// Bring the unified window forward without changing selection.
    @objc func presentIfNeeded() {
        present()
    }

    /// About menu / `--show-about`: unified window on Project Status (SwiftUI).
    @objc func showProjectStatus() {
        router.selection = .projectStatus
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
        let root = WawonaMainWindowView(
            model: valueModel,
            router: router,
            preferences: preferences,
            profileStore: profileStore,
            sessions: sessions,
            onConnect: nil
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 1024, height: 720)
        // Native unified titlebar/toolbar. Do not force a transparent
        // titlebar or custom toolbar material (that broke Machine Configuration).
        window.toolbarStyle = .unified
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
