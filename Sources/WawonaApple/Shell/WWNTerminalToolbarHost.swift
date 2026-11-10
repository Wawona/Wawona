#if os(iOS) || os(tvOS) || os(visionOS)
import SwiftUI
import UIKit

private func claimTerminalFocus(_ field: UITextField, tries: Int = 8) {
    DispatchQueue.main.async {
        #if os(visionOS)
        if let key = field as? WWNTerminalKeyField {
            key.allowFocus = true
        }
        #endif
        let ready = field.window != nil && field.becomeFirstResponder()
        if !ready, tries > 1 { claimTerminalFocus(field, tries: tries - 1) }
    }
}
#endif

#if os(iOS)

struct WWNTerminalToolbarHost: UIViewRepresentable {
    var isShell: Bool
    var onInjectData: (Data) -> Void
    var onInjectText: (String) -> Void
    var onPaste: ((String) -> Void)? = nil
    var onDismissKeyboard: () -> Void
    var autoFocus: Bool
    var focusTick: Int = 0
    var onKeyRepeat: (([UInt8]) -> Void)? = nil
    var onKeyUp: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WWNTerminalToolbarField {
        let field = WWNTerminalToolbarField()
        field.coordinator = context.coordinator
        context.coordinator.field = field
        field.configureAccessory()
        return field
    }

    func updateUIView(_ uiView: WWNTerminalToolbarField, context: Context) {
        context.coordinator.parent = self
        uiView.coordinator = context.coordinator
        uiView.accessory?.wwnDelegate = context.coordinator
        // Same as WWNTerminalKeyHost: only on focusTick change, never on
        // every !isFirstResponder (steals Done / toolbar taps).
        if autoFocus, context.coordinator.focusTick != focusTick {
            context.coordinator.focusTick = focusTick
            claimTerminalFocus(uiView)
        }
        if uiView.isFirstResponder, let bytes = WWNTerminalCursorMode.takePendingFocusIn() {
            context.coordinator.parent.onInjectData(bytes)
        }
    }

    final class Coordinator: NSObject, WWNKeyboardAccessoryDelegate {
        var parent: WWNTerminalToolbarHost
        var focusTick = -1
        var modControl = false
        var modAlt = false
        var modShift = false
        weak var field: WWNTerminalToolbarField?

        init(parent: WWNTerminalToolbarHost) {
            self.parent = parent
        }

        func keyboardAccessoryDidSendKey(name: String, keycode: UInt32, character: String?) {
            if parent.isShell {
                let control = field?.accessory?.lastKeyControl == true
                let alt = field?.accessory?.lastKeyAlt == true
                let shift = field?.accessory?.lastKeyShift == true
                if let character, !character.isEmpty {
                    if let bytes = WWNTerminalKeyBytes.toolbar(
                        character, control: control, alt: alt, shift: shift)
                    {
                        parent.onInjectData(Data(bytes))
                    } else {
                        parent.onInjectText(character)
                    }
                } else if keycode == WWNEvdevKeycode.esc {
                    parent.onInjectData(Data(WWNTerminalKeyBytes.toolbar("\u{1B}", control: control, alt: alt, shift: shift) ?? [0x1B]))
                } else if keycode == WWNEvdevKeycode.tab {
                    if let bytes = WWNTerminalKeyBytes.toolbar(
                        "\t", control: control, alt: alt, shift: shift)
                    {
                        parent.onInjectData(Data(bytes))
                    } else {
                        parent.onInjectData(Data([0x09]))
                    }
                } else if keycode == WWNEvdevKeycode.enter {
                    parent.onInjectData(Data(WWNTerminalKeyBytes.toolbar("\n", control: control, alt: alt, shift: shift) ?? [0x0A]))
                } else if keycode == WWNEvdevKeycode.backspace {
                    let byte: UInt8 = control ? 0x08 : 0x7F
                    parent.onInjectData(Data(shift ? Array("\u{1B}[27;\(1 + 1 + (alt ? 2 : 0) + (control ? 4 : 0));\(byte)~".utf8) : (alt ? [0x1B, byte] : [byte])))
                } else if let letter = toolbarArrowLetter(keycode) {
                    parent.onInjectData(
                        toolbarArrow(letter, control: control, alt: alt, shift: shift))
                } else if !name.isEmpty, name != "raw", !name.hasPrefix("__") {
                    parent.onInjectText(name)
                }
            } else if let character, !character.isEmpty {
                parent.onInjectText(character)
            }
            field?.accessory?.clearOneShotModifiers()
        }

        func keyboardAccessoryModifierChanged(modifier: String, active: Bool, locked: Bool) {
            _ = locked
            if modifier == "ctrl" { modControl = active }
            else if modifier == "alt" { modAlt = active }
            else if modifier == "shift" { modShift = active }
        }

        func keyboardAccessoryDidRequestDismiss() {
            field?.resignFirstResponder()
            parent.onDismissKeyboard()
        }

        func keyboardAccessoryDidRequestTabOverview() {
            WWNClientTabChromeController.active?.openTabExpose()
        }

        func keyboardAccessoryDidRequestNewTab() {
            WWNClientTabChromeController.active?.createNewTab()
        }

        func keyboardAccessoryDidRequestPaste() {
            guard let text = Pasteboard.paste(), !text.isEmpty else { return }
            if let onPaste = parent.onPaste {
                onPaste(text)
            } else {
                parent.onInjectText(text)
            }
        }

        func keyboardAccessoryGeometryDidChange() {}

        func keyboardAccessorySendRawData(_ data: Data) {
            if parent.isShell {
                parent.onInjectData(data)
            } else if let text = String(data: data, encoding: .utf8) {
                parent.onInjectText(text)
            }
        }
    }
}

final class WWNTerminalToolbarField: UITextField {
    weak var coordinator: WWNTerminalToolbarHost.Coordinator?
    private(set) var accessory: WWNKeyboardAccessoryView?
    private var specialDown = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no; smartDashesType = .no; smartInsertDeleteType = .no
        if #available(iOS 17.0, *) { inlinePredictionType = .no }
        if #available(iOS 18.0, *) { writingToolsBehavior = .none }
        keyboardAppearance = .dark
        alpha = 0.02
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configureAccessory() {
        let view = WWNKeyboardAccessoryView(); view.wwnDelegate = coordinator; accessory = view;         inputAccessoryView = view
    }

    override var canBecomeFirstResponder: Bool { true }
    override var hasText: Bool { true }

    override func insertText(_ text: String) {
        if !specialDown { coordinator?.parent.onKeyUp?() }
        guard let mods = coordinator, mods.parent.isShell,
            mods.modControl || mods.modAlt || mods.modShift,
            let bytes = WWNTerminalKeyBytes.toolbar(
                text, control: mods.modControl, alt: mods.modAlt, shift: mods.modShift)
        else {
            let shift = coordinator?.modShift == true, byte = text.utf8.first ?? 0
            coordinator?.parent.onInjectText((shift && text.utf8.count == 1 && (0x61...0x7A).contains(byte)) ? String(UnicodeScalar(byte &- 0x20)) : text)
            if shift { accessory?.clearOneShotModifiers() }
            return
        }
        mods.parent.onInjectData(Data(bytes))
        accessory?.clearOneShotModifiers()
    }

    override func paste(_ sender: Any?) {
        if let text = Pasteboard.paste(), !text.isEmpty {
            if let onPaste = coordinator?.parent.onPaste {
                onPaste(text)
            } else {
                coordinator?.parent.onInjectText(text)
            }
            return
        }
        super.paste(sender)
    }

    override func deleteBackward() {
        let ctrl = coordinator?.modControl == true, alt = coordinator?.modAlt == true, shift = coordinator?.modShift == true
        let byte: UInt8 = ctrl ? 0x08 : 0x7F
        let seq = shift ? Array("\u{1B}[27;\(1 + 1 + (alt ? 2 : 0) + (ctrl ? 4 : 0));\(byte)~".utf8) : (alt ? [0x1B, byte] : [byte])
        coordinator?.parent.onInjectData(Data(seq))
        if coordinator?.parent.isShell == true, ctrl || alt || shift {
            accessory?.clearOneShotModifiers()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let was = isFirstResponder
        let ok = super.becomeFirstResponder(); if ok { WWNTerminalCursorMode.noteResponder(true) }
        if ok, !was, let bytes = WWNTerminalCursorMode.focusReport(true) {
            coordinator?.parent.onInjectData(bytes)
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let was = isFirstResponder
        let ok = super.resignFirstResponder()
        if was, ok, let bytes = WWNTerminalCursorMode.focusReport(false) { coordinator?.parent.onInjectData(bytes) }
        if was, ok { WWNTerminalCursorMode.noteResponder(false); specialDown = false; coordinator?.parent.onKeyUp?() }
        return ok
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard #available(iOS 13.4, *), coordinator?.parent.isShell == true else {
            super.pressesBegan(presses, with: event); return
        }
        var rest = presses
        for press in presses {
            guard let key = press.key, let raw = WWNTerminalKeyBytes.special(for: key) else { continue }
            let bytes = WWNTerminalKeyBytes.latched(key, raw, control: coordinator?.modControl == true, alt: coordinator?.modAlt == true, shift: coordinator?.modShift == true)
            coordinator?.parent.onInjectData(Data(bytes))
            coordinator?.parent.onKeyRepeat?(bytes); specialDown = true
            if bytes != raw { accessory?.clearOneShotModifiers() }
            rest.remove(press)
        }
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseRepeat(event); super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseRepeat(event); super.pressesCancelled(presses, with: event)
    }

    private func releaseRepeat(_ event: UIPressesEvent?) {
        guard #available(iOS 13.4, *), let event, let press = event.allPresses.first(where: { ($0.phase == .began || $0.phase == .stationary || $0.phase == .changed) && $0.key.flatMap { WWNTerminalKeyBytes.special(for: $0) } != nil }),
            let key = press.key, let raw = WWNTerminalKeyBytes.special(for: key) else { specialDown = false; coordinator?.parent.onKeyUp?(); return }
        coordinator?.parent.onKeyRepeat?(WWNTerminalKeyBytes.latched(key, raw, control: coordinator?.modControl == true, alt: coordinator?.modAlt == true, shift: coordinator?.modShift == true)); specialDown = true
    }

    override var keyCommands: [UIKeyCommand]? {
        if #available(iOS 13.4, *) { return super.keyCommands }
        guard coordinator?.parent.isShell == true else { return super.keyCommands }
        return WWNTerminalKeyBytes.legacyCommands(action: #selector(legacyTermKey(_:)))
    }

    @objc private func legacyTermKey(_ command: UIKeyCommand) {
        guard coordinator?.parent.isShell == true else { return }
        coordinator?.parent.onInjectData(Data(WWNTerminalKeyBytes.legacyBytes(command)))
    }
}

private func toolbarArrowLetter(_ keycode: UInt32) -> UInt8? {
    switch keycode {
    case WWNEvdevKeycode.up: return 0x41
    case WWNEvdevKeycode.down: return 0x42
    case WWNEvdevKeycode.right: return 0x43
    case WWNEvdevKeycode.left: return 0x44
    default: return nil
    }
}

private func toolbarArrow(_ letter: UInt8, control: Bool, alt: Bool, shift: Bool) -> Data {
    let plain = Data([0x1B, 0x5B, letter])
    let text = String(data: plain, encoding: .utf8) ?? ""
    if let bytes = WWNTerminalKeyBytes.toolbar(text, control: control, alt: alt, shift: shift) {
        return Data(bytes)
    }
    return WWNTerminalCursorMode.mapArrow(plain)
}
#endif

#if os(tvOS) || os(visionOS)
/// Live key host for tvOS and visionOS. No Toolbar Keys accessory.
struct WWNTerminalKeyHost: UIViewRepresentable {
    var onInjectData: (Data) -> Void
    var onInjectText: (String) -> Void
    var autoFocus: Bool
    var focusTick: Int = 0

    func makeUIView(context: Context) -> WWNTerminalKeyField {
        let field = WWNTerminalKeyField()
        field.onInjectData = onInjectData
        field.onInjectText = onInjectText
        return field
    }

    func updateUIView(_ uiView: WWNTerminalKeyField, context: Context) {
        uiView.onInjectData = onInjectData
        uiView.onInjectText = onInjectText
        // Claim only when focusTick changes. Seed coordinator at 0 so the
        // first update with focusTick=0 does not open visionOS IME over Done.
        // autoFocus=false (visionOS Terminal): claim only after grid tap
        // bumps the tick. Never re-steal on !isFirstResponder (cancels Done).
        if context.coordinator.focusTick != focusTick {
            let previous = context.coordinator.focusTick
            context.coordinator.focusTick = focusTick
            if autoFocus {
                claimTerminalFocus(uiView)
            } else if focusTick > previous {
                claimTerminalFocus(uiView)
            }
        }
        if uiView.isFirstResponder, let bytes = WWNTerminalCursorMode.takePendingFocusIn() {
            onInjectData(bytes)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var focusTick = 0
    }
}

final class WWNTerminalKeyField: UITextField, UITextFieldDelegate {
    var onInjectData: ((Data) -> Void)?
    var onInjectText: ((String) -> Void)?
    /// visionOS: soft IME must not open until the grid bumps focusTick.
    /// Ungated canBecomeFirstResponder lets AX/system steal focus and cover Done.
    var allowFocus = false
    /// Soft-IME is open for this field (Escape host must not steal focus).
    static weak var focusedInstance: WWNTerminalKeyField?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no; smartDashesType = .no; smartInsertDeleteType = .no
        alpha = 0.02
        // Never absorb pointer/gaze hits. Stay first-responder for IME /
        // hardware keys only. Keep out of AX tree so the Terminal sheet is
        // not classified as one giant text-field (steals Done activate).
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "wwn.guestConsole.send"
        delegate = self
        addTarget(self, action: #selector(flushEditingText), for: .editingChanged)
        returnKeyType = .default
    }

    /// Pass all hit tests through so Done / Clear / ^C stay tappable.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    #if os(tvOS)
    // Refuse first responder: tvOS UISystemInputViewController.setupKeyboard
    // layout-loops the main thread even with an empty inputView.
    override var canBecomeFirstResponder: Bool { false }
    #elseif os(visionOS)
    override var canBecomeFirstResponder: Bool { allowFocus }
    #else
    override var canBecomeFirstResponder: Bool { true }
    #endif

    override func becomeFirstResponder() -> Bool {
        #if os(tvOS)
        return false
        #else
        #if os(visionOS)
        guard allowFocus else { return false }
        #endif
        let was = isFirstResponder
        let ok = super.becomeFirstResponder(); if ok { WWNTerminalCursorMode.noteResponder(true) }
        if ok {
            Self.focusedInstance = self
        }
        if ok, !was, let bytes = WWNTerminalCursorMode.focusReport(true) {
            onInjectData?(bytes)
        }
        return ok
        #endif
    }

    override func resignFirstResponder() -> Bool {
        flushEditingText()
        let was = isFirstResponder
        let ok = super.resignFirstResponder()
        if was, ok, let bytes = WWNTerminalCursorMode.focusReport(false) { onInjectData?(bytes) }
        if was, ok {
            if Self.focusedInstance === self { Self.focusedInstance = nil }
            WWNTerminalCursorMode.noteResponder(false)
        }
        return ok
    }

    override func insertText(_ incoming: String) {
        // Soft IME path. Clear any AX-buffered `.text` so we do not double-send.
        self.text = nil
        onInjectText?(incoming)
    }

    /// agent-device / AX `type` sets `UITextField.text` and never calls
    /// `insertText`. Flush that buffer into the PTY.
    @objc private func flushEditingText() {
        guard let pending = text, !pending.isEmpty else { return }
        text = nil
        onInjectText?(pending)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        flushEditingText()
        onInjectData?(Data([0x0D]))
        return false
    }

    override var hasText: Bool { true }

    override func deleteBackward() {
        if let pending = text, !pending.isEmpty {
            text = String(pending.dropLast())
            return
        }
        onInjectData?(Data([0x7F]))
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if #available(tvOS 13.4, iOS 13.4, *) {
            var rest = Set<UIPress>()
            for press in presses {
                if let key = press.key, let bytes = WWNTerminalKeyBytes.special(for: key) {
                    onInjectData?(Data(bytes))
                } else {
                    rest.insert(press)
                }
            }
            if !rest.isEmpty {
                super.pressesBegan(rest, with: event)
            }
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override var keyCommands: [UIKeyCommand]? {
        if #available(tvOS 13.4, iOS 13.4, *) { return super.keyCommands }
        return WWNTerminalKeyBytes.legacyCommands(action: #selector(legacyTermKey(_:)))
    }

    @objc private func legacyTermKey(_ command: UIKeyCommand) {
        onInjectData?(Data(WWNTerminalKeyBytes.legacyBytes(command)))
    }
}

/// UIKit Done for visionOS / tvOS Terminal. SwiftUI `Button` actions are
/// often swallowed while the soft IME owns first responder; this control
/// resigns focus on tap / AX activate then runs `onDone`.
struct WWNTerminalDoneButton: UIViewRepresentable {
    var title: String = "Done"
    var accessibilityId: String
    var onDone: () -> Void

    func makeUIView(context: Context) -> WWNTerminalDoneUIButton {
        let button = WWNTerminalDoneUIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = accessibilityId
        button.accessibilityLabel = title
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.tapped),
            for: .touchUpInside
        )
        context.coordinator.onDone = onDone
        button.onActivate = { [weak coordinator = context.coordinator] in
            coordinator?.tapped()
        }
        return button
    }

    func updateUIView(_ uiView: WWNTerminalDoneUIButton, context: Context) {
        context.coordinator.onDone = onDone
        uiView.onActivate = { [weak coordinator = context.coordinator] in
            coordinator?.tapped()
        }
        uiView.setTitle(title, for: .normal)
        uiView.accessibilityIdentifier = accessibilityId
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    final class Coordinator: NSObject {
        var onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        @objc func tapped() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            DispatchQueue.main.async { [onDone] in onDone() }
        }
    }
}

final class WWNTerminalDoneUIButton: UIButton {
    var onActivate: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        #if os(visionOS)
        CGSize(width: 96, height: 44)
        #else
        CGSize(width: 72, height: 36)
        #endif
    }

    override func accessibilityActivate() -> Bool {
        NSLog("WWNTerminalDoneUIButton: accessibilityActivate title=%@", title(for: .normal) ?? "")
        onActivate?()
        return true
    }
}

#if os(visionOS) || os(tvOS)
/// visionOS: Escape / Cmd-W / Cmd-. when pinch coords miss Done.
/// tvOS: Siri Remote Menu press (and Escape on paired keyboard) leave Terminal.
public struct WWNTerminalEscapeDismissHost: UIViewControllerRepresentable {
    public var onEscape: () -> Void
    public init(onEscape: @escaping () -> Void) { self.onEscape = onEscape }

    public func makeUIViewController(context: Context) -> WWNTerminalEscapeDismissController {
        let vc = WWNTerminalEscapeDismissController()
        vc.onEscape = onEscape
        return vc
    }

    public func updateUIViewController(
        _ uiViewController: WWNTerminalEscapeDismissController,
        context: Context
    ) {
        uiViewController.onEscape = onEscape
    }
}

public final class WWNTerminalEscapeDismissController: UIViewController {
    public var onEscape: (() -> Void)?

    public override var canBecomeFirstResponder: Bool { true }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if os(visionOS)
        if WWNTerminalKeyField.focusedInstance == nil {
            _ = becomeFirstResponder()
        }
        #else
        _ = becomeFirstResponder()
        #endif
    }

    public override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape)),
            UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(escape)),
            UIKeyCommand(input: ".", modifierFlags: .command, action: #selector(escape)),
        ]
    }

    #if os(tvOS)
    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            NSLog("WWNIosGuestConsole: Menu press dismiss")
            onEscape?()
            return
        }
        super.pressesBegan(presses, with: event)
    }
    #endif

    @objc private func escape() {
        NSLog("WWNIosGuestConsole: Escape dismiss")
        onEscape?()
    }
}
#endif
#endif
