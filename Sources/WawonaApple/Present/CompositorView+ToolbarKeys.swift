#if os(iOS)
import UIKit
import QuartzCore
import ObjectiveC

// MARK: - Toolbar Keys accessory storage + delegate

extension WWNCompositorView_ios {
    private static var accessoryAssocKey: UInt8 = 0
    private static var accessoryOnlyAssocKey: UInt8 = 0

    var toolbarAccessoryStorage: WWNKeyboardAccessoryView? {
        get {
            objc_getAssociatedObject(self, &Self.accessoryAssocKey) as? WWNKeyboardAccessoryView
        }
        set {
            objc_setAssociatedObject(
                self, &Self.accessoryAssocKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var toolbarAccessoryOnlyMode: Bool {
        get {
            (objc_getAssociatedObject(self, &Self.accessoryOnlyAssocKey) as? NSNumber)?.boolValue
                ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &Self.accessoryOnlyAssocKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    /// Lazy Toolbar Keys bar for soft-keyboard / accessory-only focus.
    @objc public func ensureToolbarAccessory() -> WWNKeyboardAccessoryView {
        if let existing = toolbarAccessoryStorage {
            return existing
        }
        let view = WWNKeyboardAccessoryView()
        view.wwnDelegate = self
        toolbarAccessoryStorage = view
        return view
    }

    @objc public func applyToolbarAccessoryOnlyMode(_ accessoryOnly: Bool) {
        toolbarAccessoryOnlyMode = accessoryOnly
        ensureToolbarAccessory().setKeyboardUiModeAccessoryOnly(accessoryOnly)
        if keyboardActive {
            resignFirstResponder()
            _ = becomeFirstResponder()
        }
    }
}

extension WWNCompositorView_ios: WWNKeyboardAccessoryDelegate {
    public func keyboardAccessoryDidSendKey(name: String, keycode: UInt32, character: String?) {
        let core = WWNCompositorBridge.sharedBridge.core
        let timeMs = UInt32(CACurrentMediaTime() * 1000.0)
        if keycode != 0 {
            SeatForwarder.injectKey(core: core, timeMs: timeMs, keycode: keycode, pressed: true)
            SeatForwarder.injectKey(core: core, timeMs: timeMs &+ 1, keycode: keycode, pressed: false)
        } else if let character, !character.isEmpty {
            SeatForwarder.insertText(core: core, text: character)
        } else if !name.isEmpty, name != "raw" {
            SeatForwarder.insertText(core: core, text: name)
        }
        ensureToolbarAccessory().clearOneShotModifiers()
    }

    public func keyboardAccessoryModifierChanged(modifier: String, active: Bool, locked: Bool) {
        _ = (modifier, active, locked)
    }

    public func keyboardAccessoryDidRequestDismiss() {
        deactivateKeyboard()
    }

    public func keyboardAccessoryDidRequestTabOverview() {
        WWNClientTabChromeController.active?.openTabExpose()
    }

    public func keyboardAccessoryDidRequestNewTab() {
        WWNClientTabChromeController.active?.createNewTab()
    }

    public func keyboardAccessoryDidRequestPaste() {
        guard let text = Pasteboard.paste(), !text.isEmpty else { return }
        SeatForwarder.insertText(
            core: WWNCompositorBridge.sharedBridge.core,
            text: text
        )
    }

    public func keyboardAccessoryGeometryDidChange() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        SeatForwarder.injectWindowResize(
            core: WWNCompositorBridge.sharedBridge.core,
            windowId: wwnWindowId,
            width: UInt32(size.width.rounded()),
            height: UInt32(size.height.rounded())
        )
    }

    public func keyboardAccessorySendRawData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        SeatForwarder.insertText(
            core: WWNCompositorBridge.sharedBridge.core,
            text: text
        )
    }
}
#endif
