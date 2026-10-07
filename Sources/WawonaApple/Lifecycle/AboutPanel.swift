import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#endif

/// Thin About host. Replaces `WWNAboutPanel.m`. SwiftUI status is `WawonaProjectStatusView`.
@objc(WWNAboutPanel)
public final class WWNAboutPanel: NSObject {
    @objc public static let sharedAboutPanel = WWNAboutPanel()

    private override init() { super.init() }

    #if os(macOS)
    @objc(showAboutPanel:)
    public func showAboutPanel(_ sender: Any?) {
        _ = sender
        if let unified = NSClassFromString("WWNUnifiedWindowController") as AnyObject?,
           unified.responds(to: NSSelectorFromString("sharedController")),
           let controller = unified.perform(NSSelectorFromString("sharedController"))?
            .takeUnretainedValue() as AnyObject?,
           controller.responds(to: NSSelectorFromString("showProjectStatus")) {
            _ = controller.perform(NSSelectorFromString("showProjectStatus"))
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif
}
