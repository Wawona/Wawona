import Foundation
import ObjectiveC
#if os(iOS) || targetEnvironment(simulator)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@objc(WWNMachinesCoordinator)
public final class WWNMachinesCoordinator: NSObject {

    @objc public static let sharedCoordinator: WWNMachinesCoordinator = {
        WWNMachinesCoordinator()
    }()

    #if os(macOS)
    private var macMachinesController: NSWindowController?
    #endif

    private static func findMachinesHostingBridgeClass() -> AnyClass? {
        var candidateNames: [String] = [
            "WWNMachinesHostingBridge",
            "Wawona.WWNMachinesHostingBridge",
            "Wawona_iOS.WWNMachinesHostingBridge",
            "Wawona_macOS.WWNMachinesHostingBridge",
        ]
        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
            candidateNames.append("\(bundleName).WWNMachinesHostingBridge")
            candidateNames.append("\(bundleName.replacingOccurrences(of: "-", with: "_")).WWNMachinesHostingBridge")
        }
        if let execName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, !execName.isEmpty {
            candidateNames.append("\(execName).WWNMachinesHostingBridge")
            candidateNames.append("\(execName.replacingOccurrences(of: "-", with: "_")).WWNMachinesHostingBridge")
        }
        for name in candidateNames {
            if let cls = NSClassFromString(name) {
                return cls
            }
        }
        let count = objc_getClassList(nil, 0)
        guard count > 0 else { return nil }
        let buffer = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(count))
        defer { buffer.deallocate() }
        let listed = objc_getClassList(AutoreleasingUnsafeMutablePointer(buffer), Int32(count))
        for i in 0..<Int(listed) {
            let className = NSStringFromClass(buffer[i])
            if className == "WWNMachinesHostingBridge" || className.hasSuffix(".WWNMachinesHostingBridge") {
                return buffer[i]
            }
        }
        return nil
    }

    #if os(iOS) || targetEnvironment(simulator)
    @objc(buildMachinesViewControllerWithOnConnect:)
    public func buildMachinesViewController(onConnect: (() -> Void)?) -> UIViewController? {
        buildSwiftUIMachinesController(onConnect: onConnect)
    }

    @objc(buildSwiftUIMachinesController:)
    public func buildSwiftUIMachinesController(onConnect: (() -> Void)?) -> UIViewController? {
        guard let bridgeClass = Self.findMachinesHostingBridgeClass() else { return nil }
        let selector = NSSelectorFromString("buildIOSMachinesControllerWithOnConnect:")
        guard (bridgeClass as AnyObject).responds(to: selector) else { return nil }
        typealias BuildFn = @convention(c) (AnyObject, Selector, (@convention(block) () -> Void)?) -> UIViewController?
        let imp = unsafeBitCast(
            (bridgeClass as AnyObject).method(for: selector),
            to: BuildFn.self
        )
        return imp(bridgeClass as AnyObject, selector, onConnect)
    }

    @objc(presentMachinesFromViewController:onConnect:)
    public func presentMachines(from presenter: UIViewController, onConnect: (() -> Void)?) {
        var top = presenter
        while let presented = top.presentedViewController {
            top = presented
        }
        guard let machinesVC = buildMachinesViewController(onConnect: onConnect) else {
            let alert = UIAlertController(
                title: "Machines UI Unavailable",
                message: "SwiftUI machines view failed to load. Regenerate the Xcode project and rebuild.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            top.present(alert, animated: true)
            return
        }
        top.present(machinesVC, animated: true)
    }
    #elseif os(macOS)
    @objc(buildSwiftUIMachinesWindowController:)
    public func buildSwiftUIMachinesWindowController(onConnect: (() -> Void)?) -> NSWindowController? {
        guard let bridgeClass = Self.findMachinesHostingBridgeClass() else { return nil }
        let selector = NSSelectorFromString("buildMacMachinesWindowControllerWithOnConnect:")
        guard (bridgeClass as AnyObject).responds(to: selector) else { return nil }
        typealias BuildFn = @convention(c) (AnyObject, Selector, (@convention(block) () -> Void)?) -> NSWindowController?
        let imp = unsafeBitCast((bridgeClass as AnyObject).method(for: selector), to: BuildFn.self)
        return imp(bridgeClass as AnyObject, selector, onConnect)
    }

    @objc(showMachinesWindowAndActivate:)
    public func showMachinesWindowAndActivate(_ activate: Bool) {
        if let unifiedClass = NSClassFromString("WWNUnifiedWindowController") {
            let sharedSel = NSSelectorFromString("sharedController")
            let showSel = NSSelectorFromString("showMachines")
            if (unifiedClass as AnyObject).responds(to: sharedSel) {
                typealias SharedFn = @convention(c) (AnyObject, Selector) -> AnyObject?
                let sharedImp = unsafeBitCast((unifiedClass as AnyObject).method(for: sharedSel), to: SharedFn.self)
                if let controller = sharedImp(unifiedClass as AnyObject, sharedSel),
                   controller.responds(to: showSel) {
                    typealias ShowFn = @convention(c) (AnyObject, Selector) -> Void
                    let showImp = unsafeBitCast(controller.method(for: showSel), to: ShowFn.self)
                    showImp(controller, showSel)
                    if activate {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    return
                }
            }
        }

        if macMachinesController == nil || macMachinesController?.window == nil
            || macMachinesController?.window?.isVisible == false {
            if let controller = buildSwiftUIMachinesWindowController(onConnect: nil) {
                if let existing = macMachinesController?.window,
                   existing != controller.window {
                    macMachinesController?.window?.close()
                }
                macMachinesController = controller
            }
        }

        guard let macMachinesController else {
            let alert = NSAlert()
            alert.messageText = "Machines UI Unavailable"
            alert.informativeText =
                "SwiftUI machines view failed to load. Regenerate the Xcode project and rebuild."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let keep = macMachinesController.window
        for window in NSApp.windows {
            if window === keep { continue }
            let title = window.title
            let ident = window.identifier?.rawValue ?? ""
            if ident == "wwn.machines.control-panel"
                || title == "Wawona Machine Control Panel"
                || title == "Machines" {
                window.close()
            }
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        macMachinesController.showWindow(nil)
        keep?.makeKeyAndOrderFront(nil)
    }

    @objc(showMachinesWindowFromMenu:)
    public func showMachinesWindowFromMenu(_ sender: Any?) {
        _ = sender
        showMachinesWindowAndActivate(true)
    }
    #endif
}
