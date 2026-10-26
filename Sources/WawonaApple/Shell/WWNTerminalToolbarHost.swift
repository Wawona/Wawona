#if os(iOS) || os(tvOS) || os(visionOS)
import SwiftUI
import UIKit

private func claimTerminalFocus(_ field: UITextField, tries: Int = 8) {
    DispatchQueue.main.async {
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
        context.coordinator.ensureRestoreObserver()
        if autoFocus, !uiView.isFirstResponder,
          !WawonaTerminalSelectionGate.isActive
        {
            if context.coordinator.focusTick != focusTick {
                context.coordinator.focusTick = focusTick
                claimTerminalFocus(uiView)
            } else {
                DispatchQueue.main.async {
                    guard !WawonaTerminalSelectionGate.isActive else { return }
                    _ = uiView.becomeFirstResponder()
                }
            }
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
        private var restoreObserver: NSObjectProtocol?

        init(parent: WWNTerminalToolbarHost) {
            self.parent = parent
        }

        deinit {
            if let restoreObserver {
                NotificationCenter.default.removeObserver(restoreObserver)
            }
        }

        func ensureRestoreObserver() {
            guard restoreObserver == nil else { return }
            restoreObserver = NotificationCenter.default.addObserver(
                forName: WawonaTerminalSelectionGate.restoreKeyboard,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let field = self?.field, self?.parent.autoFocus == true else { return }
                // Steal FR even if gate briefly lags resign. UITextView keeping
                // FR after select was why typing stayed dead until rotate.
                DispatchQueue.main.async {
                    guard !WawonaTerminalSelectionGate.isActive else { return }
                    if !field.isFirstResponder {
                        _ = field.becomeFirstResponder()
                    }
                }
            }
        }

        func keyboardAccessoryDidSendKey(name: String, keycode: UInt32, character: String?) {
            guard !WawonaTerminalSelectionGate.isActive else { return }
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
<<<<<<< ours
                    WawonaTerminalReturnInject.once {
                        parent.onInjectData(Data([0x0A]))
                    }
=======
                    parent.onInjectData(Data(WWNTerminalKeyBytes.toolbar("\n", control: control, alt: alt, shift: shift) ?? [0x0A]))
>>>>>>> theirs
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

<<<<<<< ours
/// Minimal `UITextField` so the system keyboard + Toolbar Keys accessory attach.
final class WWNTerminalToolbarField: UITextField, UITextFieldDelegate {
=======
final class WWNTerminalToolbarField: UITextField {
>>>>>>> theirs
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
<<<<<<< ours
        keyboardType = .asciiCapable
        textContentType = nil
        // Keep a thin hit target so SwiftUI layout does not collapse the host.
=======
>>>>>>> theirs
        alpha = 0.02
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configureAccessory() {
        let view = WWNKeyboardAccessoryView(); view.wwnDelegate = coordinator; accessory = view;         inputAccessoryView = view
    }

    override var canBecomeFirstResponder: Bool { true }
    override var hasText: Bool { true }

    override func insertText(_ text: String) {
<<<<<<< ours
        guard !text.isEmpty else { return }
        guard !WawonaTerminalSelectionGate.isActive else { return }
        if text == "\n" || text == "\r" {
            WawonaTerminalReturnInject.once {
                coordinator?.parent.onInjectData(Data([0x0A]))
            }
            return
        }
        coordinator?.parent.onInjectText(text)
    }

    override func deleteBackward() {
        guard !WawonaTerminalSelectionGate.isActive else { return }
        coordinator?.parent.onInjectData(Data([0x7F]))
=======
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
>>>>>>> theirs
    }

    /// Soft keyboard on recent iOS often routes through the delegate instead of
    /// `insertText(_:)`. Never mutate the field; every key goes to the PTY.
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        guard !WawonaTerminalSelectionGate.isActive else { return false }
        if string.isEmpty, range.length > 0 {
            coordinator?.parent.onInjectData(Data([0x7F]))
        } else if string == "\n" || string == "\r" {
            WawonaTerminalReturnInject.once {
                coordinator?.parent.onInjectData(Data([0x0A]))
            }
        } else if !string.isEmpty {
            coordinator?.parent.onInjectText(string)
        }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard !WawonaTerminalSelectionGate.isActive else { return false }
        WawonaTerminalReturnInject.once {
            coordinator?.parent.onInjectData(Data([0x0A]))
        }
        return false
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
<<<<<<< ours
        if WawonaTerminalSelectionGate.isActive {
            super.pressesBegan(presses, with: event)
            return
        }
        if #available(iOS 13.4, *), coordinator?.parent.isShell == true {
            var rest = Set<UIPress>()
            for press in presses {
                if let key = press.key, let bytes = WWNTerminalKeyBytes.special(for: key) {
                    if key.keyCode == .keyboardReturnOrEnter {
                        WawonaTerminalReturnInject.once {
                            coordinator?.parent.onInjectData(Data([0x0A]))
                        }
                    } else {
                        coordinator?.parent.onInjectData(Data(bytes))
                    }
                } else {
                    rest.insert(press)
                }
            }
            if !rest.isEmpty {
                super.pressesBegan(rest, with: event)
            }
            return
=======
        guard #available(iOS 13.4, *), coordinator?.parent.isShell == true else {
            super.pressesBegan(presses, with: event); return
>>>>>>> theirs
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
        guard !WawonaTerminalSelectionGate.isActive else { return }
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
        if autoFocus, context.coordinator.focusTick != focusTick || !uiView.isFirstResponder {
            context.coordinator.focusTick = focusTick
            claimTerminalFocus(uiView)
        }
        if uiView.isFirstResponder, let bytes = WWNTerminalCursorMode.takePendingFocusIn() {
            onInjectData(bytes)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var focusTick = -1
    }
}

final class WWNTerminalKeyField: UITextField, UITextFieldDelegate {
    var onInjectData: ((Data) -> Void)?
    var onInjectText: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
<<<<<<< ours
        keyboardType = .asciiCapable
=======
        smartQuotesType = .no; smartDashesType = .no; smartInsertDeleteType = .no
>>>>>>> theirs
        alpha = 0.02
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var canBecomeFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let was = isFirstResponder
        let ok = super.becomeFirstResponder(); if ok { WWNTerminalCursorMode.noteResponder(true) }
        if ok, !was, let bytes = WWNTerminalCursorMode.focusReport(true) {
            onInjectData?(bytes)
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let was = isFirstResponder
        let ok = super.resignFirstResponder()
        if was, ok, let bytes = WWNTerminalCursorMode.focusReport(false) { onInjectData?(bytes) }
        if was, ok { WWNTerminalCursorMode.noteResponder(false) }
        return ok
    }

    override func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        if text == "\n" || text == "\r" { return }
        onInjectText?(text)
    }

    override var hasText: Bool { true }

    override func deleteBackward() {
        onInjectData?(Data([0x7F]))
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        if string.isEmpty, range.length > 0 {
            onInjectData?(Data([0x7F]))
        } else if string == "\n" || string == "\r" {
            // Sole Return inject is textFieldShouldReturn.
        } else if !string.isEmpty {
            onInjectText?(string)
        }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onInjectData?(Data([0x0A]))
        return false
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
#endif
