#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  WWNKeyboardAccessoryView.swift
//  Wawona
//
//  Objective-C bridge and host coordinator for KeyboardAccessoryView.
//

import UIKit

// MARK: - Keycodes Constants (evdev/XKB keycodes for Wayland injection)

public enum WWNEvdevKeycode {
    public static let esc: UInt32 = 1
    public static let tab: UInt32 = 15
    public static let enter: UInt32 = 28
    public static let backspace: UInt32 = 14
    public static let grave: UInt32 = 41
    public static let minus: UInt32 = 12
    public static let equal: UInt32 = 13
    public static let slash: UInt32 = 53
    public static let backslash: UInt32 = 43
    public static let leftBracket: UInt32 = 26
    public static let rightBracket: UInt32 = 27
    public static let semicolon: UInt32 = 39
    public static let apostrophe: UInt32 = 40
    public static let comma: UInt32 = 51
    public static let dot: UInt32 = 52

    public static let leftCtrl: UInt32 = 29
    public static let leftShift: UInt32 = 42
    public static let leftAlt: UInt32 = 56
    public static let leftMeta: UInt32 = 125

    public static let up: UInt32 = 103
    public static let down: UInt32 = 108
    public static let left: UInt32 = 105
    public static let right: UInt32 = 106

    public static let home: UInt32 = 102
    public static let end: UInt32 = 107
    public static let pageUp: UInt32 = 104
    public static let pageDown: UInt32 = 109
    public static let insert: UInt32 = 110
    public static let delete: UInt32 = 111

    public static let f1: UInt32 = 59
    public static let f2: UInt32 = 60
    public static let f3: UInt32 = 61
    public static let f4: UInt32 = 62
    public static let f5: UInt32 = 63
    public static let f6: UInt32 = 64
    public static let f7: UInt32 = 65
    public static let f8: UInt32 = 66
    public static let f9: UInt32 = 67
    public static let f10: UInt32 = 68
    public static let f11: UInt32 = 87
    public static let f12: UInt32 = 88
}

// MARK: - Delegate Protocols

@objc(WWNKeyboardAccessoryDelegate)
public protocol WWNKeyboardAccessoryDelegate: AnyObject {
    @objc(keyboardAccessoryDidSendKey:keycode:character:)
    func keyboardAccessoryDidSendKey(name: String, keycode: UInt32, character: String?)

    @objc(keyboardAccessoryModifierChanged:active:locked:)
    func keyboardAccessoryModifierChanged(modifier: String, active: Bool, locked: Bool)

    @objc(keyboardAccessoryDidRequestDismiss)
    func keyboardAccessoryDidRequestDismiss()

    @objc(keyboardAccessoryDidRequestTabOverview)
    func keyboardAccessoryDidRequestTabOverview()

    @objc(keyboardAccessoryDidRequestNewTab)
    func keyboardAccessoryDidRequestNewTab()

    @objc(keyboardAccessoryDidRequestPaste)
    func keyboardAccessoryDidRequestPaste()

    @objc(keyboardAccessoryGeometryDidChange)
    func keyboardAccessoryGeometryDidChange()

    @objc(keyboardAccessoryDidRequestToolbarSettings)
    optional func keyboardAccessoryDidRequestToolbarSettings()

    @objc(keyboardAccessorySendRawData:)
    optional func keyboardAccessorySendRawData(_ data: Data)
}

@objc(WWNKeyboardAccessoryHosting)
public protocol WWNKeyboardAccessoryHosting: AnyObject {
    func clearOneShotModifiers()
    func resetAllModifiers()
    func toggleDrawer()
    func setKeyboardUiModeAccessoryOnly(_ accessoryOnly: Bool)
}

// MARK: - WWNKeyboardAccessoryView Implementation

@objc(WWNKeyboardAccessoryView)
public final class WWNKeyboardAccessoryView: KeyboardAccessoryView, WWNKeyboardAccessoryHosting, KeyboardButtonDelegate {
    @objc public weak var wwnDelegate: WWNKeyboardAccessoryDelegate?

    public override weak var delegate: KeyboardButtonDelegate? {
        get { self }
        set { /* Internal KeyboardButtonDelegate routing */ }
    }

    public var hostingDelegate: AnyObject? {
        get { wwnDelegate }
        set { wwnDelegate = newValue as? WWNKeyboardAccessoryDelegate }
    }

    // Explicit Objective-C property accessor required by WWNKeyboardAccessoryHosting
    @objc(delegate)
    public var objcDelegate: AnyObject? {
        get { wwnDelegate }
        set { wwnDelegate = newValue as? WWNKeyboardAccessoryDelegate }
    }

    public override init(sizes: KeyboardSizes = .current()) {
        super.init(sizes: sizes)
        super.delegate = self
        setupActionCallbacks()
    }

    public override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        super.delegate = self
        setupActionCallbacks()
    }

    @objc public convenience init() {
        self.init(sizes: .current())
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupActionCallbacks() {
        onDismissRequested = { [weak self] in
            self?.wwnDelegate?.keyboardAccessoryDidRequestDismiss()
        }
        onTabSwitcherRequested = { [weak self] in
            self?.wwnDelegate?.keyboardAccessoryDidRequestTabOverview()
        }
        onNewConnectionRequested = { [weak self] in
            self?.wwnDelegate?.keyboardAccessoryDidRequestNewTab()
        }
        onPasteRequested = { [weak self] in
            self?.wwnDelegate?.keyboardAccessoryDidRequestPaste()
        }
        onToolbarSettingsRequested = { [weak self] in
            self?.wwnDelegate?.keyboardAccessoryDidRequestToolbarSettings?()
        }
        onModifiersChanged = { [weak self] mods in
            guard let self = self, let del = self.wwnDelegate else { return }
            del.keyboardAccessoryModifierChanged(modifier: "ctrl", active: mods.contains(.control), locked: false)
            del.keyboardAccessoryModifierChanged(modifier: "alt", active: mods.contains(.alt), locked: false)
            del.keyboardAccessoryModifierChanged(modifier: "shift", active: mods.contains(.shift), locked: false)
            del.keyboardAccessoryModifierChanged(modifier: "cmd", active: mods.contains(.command), locked: false)
        }
        onLayoutInvalidated = { [weak self] in
            self?.wwnDelegate?.keyboardAccessoryGeometryDidChange()
        }
    }

    // MARK: - WWNKeyboardAccessoryHosting

    @objc public func clearOneShotModifiers() {
        toolbarView.clearOneShotModifiers()
    }

    @objc public func resetAllModifiers() {
        toolbarView.clearModifiers()
    }

    @objc public func toggleDrawer() {
        // Toggle the drawer through the toolbar's extra keys handler
        toolbarView.rebuildForCurrentWidth()
    }

    @objc public func setKeyboardUiModeAccessoryOnly(_ accessoryOnly: Bool) {
        setBottomEdgeHomeGestureProtectionEnabled(accessoryOnly)
        if accessoryOnly {
            setReservedBottomSafeArea(0)
        }
    }

    // MARK: - KeyboardButtonDelegate

    public func keyPressed(_ key: String, modifiers: KeyModifiers) {
        var keycode: UInt32 = 0
        var character: String? = key

        switch key {
        case "Esc":
            keycode = WWNEvdevKeycode.esc
            character = "\u{1B}"
        case "\t", "Tab":
            keycode = WWNEvdevKeycode.tab
            character = "\t"
        case "\u{1B}[A":
            keycode = WWNEvdevKeycode.up
        case "\u{1B}[B":
            keycode = WWNEvdevKeycode.down
        case "\u{1B}[D":
            keycode = WWNEvdevKeycode.left
        case "\u{1B}[C":
            keycode = WWNEvdevKeycode.right
        case "`":
            keycode = WWNEvdevKeycode.grave
        case "-":
            keycode = WWNEvdevKeycode.minus
        case "=":
            keycode = WWNEvdevKeycode.equal
        case "/":
            keycode = WWNEvdevKeycode.slash
        case "\\":
            keycode = WWNEvdevKeycode.backslash
        case "[":
            keycode = WWNEvdevKeycode.leftBracket
        case "]":
            keycode = WWNEvdevKeycode.rightBracket
        case ";":
            keycode = WWNEvdevKeycode.semicolon
        case "'":
            keycode = WWNEvdevKeycode.apostrophe
        default:
            break
        }

        wwnDelegate?.keyboardAccessoryDidSendKey(name: key, keycode: keycode, character: character)
    }

    public func cancelScrollTouches() {
        toolbarView.cancelScrollTouches()
    }

    public func sendRawData(_ data: Data) {
        if let optionalSend = wwnDelegate?.keyboardAccessorySendRawData {
            optionalSend(data)
        } else if let string = String(data: data, encoding: .utf8) {
            wwnDelegate?.keyboardAccessoryDidSendKey(name: "raw", keycode: 0, character: string)
        }
    }
}
#endif
