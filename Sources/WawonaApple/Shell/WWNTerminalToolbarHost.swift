#if os(iOS)
import SwiftUI
import UIKit

/// Hidden first-responder host whose `inputAccessoryView` is Toolbar Keys.
/// Shell bytes go to PTY via `onInject`; compositor Focus path is separate.
struct WWNTerminalToolbarHost: UIViewRepresentable {
    var isShell: Bool
    var onInjectData: (Data) -> Void
    var onInjectText: (String) -> Void
    var onDismissKeyboard: () -> Void
    var autoFocus: Bool

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
        // Never steal FR while UITextView owns press-hold selection. Stealing
        // mid-gesture re-shows the soft keyboard and floods the PTY with Return.
        if autoFocus, !uiView.isFirstResponder,
          !WawonaTerminalSelectionGate.isActive
        {
            DispatchQueue.main.async {
                guard !WawonaTerminalSelectionGate.isActive else { return }
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, WWNKeyboardAccessoryDelegate {
        var parent: WWNTerminalToolbarHost
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
                if let character, !character.isEmpty {
                    parent.onInjectText(character)
                } else if keycode == WWNEvdevKeycode.esc {
                    parent.onInjectData(Data([0x1B]))
                } else if keycode == WWNEvdevKeycode.tab {
                    parent.onInjectData(Data([0x09]))
                } else if keycode == WWNEvdevKeycode.enter {
                    WawonaTerminalReturnInject.once {
                        parent.onInjectData(Data([0x0A]))
                    }
                } else if keycode == WWNEvdevKeycode.backspace {
                    parent.onInjectData(Data([0x7F]))
                } else if keycode == WWNEvdevKeycode.up {
                    parent.onInjectData(Data([0x1B, 0x5B, 0x41]))
                } else if keycode == WWNEvdevKeycode.down {
                    parent.onInjectData(Data([0x1B, 0x5B, 0x42]))
                } else if keycode == WWNEvdevKeycode.right {
                    parent.onInjectData(Data([0x1B, 0x5B, 0x43]))
                } else if keycode == WWNEvdevKeycode.left {
                    parent.onInjectData(Data([0x1B, 0x5B, 0x44]))
                } else if !name.isEmpty, name != "raw" {
                    parent.onInjectText(name)
                }
            } else if let character, !character.isEmpty {
                // Log Terminal: printable echo only; Esc/^C still useful as markers.
                parent.onInjectText(character)
            }
            field?.accessory?.clearOneShotModifiers()
        }

        func keyboardAccessoryModifierChanged(modifier: String, active: Bool, locked: Bool) {
            _ = (modifier, active, locked)
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
            if parent.isShell {
                parent.onInjectText(text)
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

/// Minimal `UITextField` so the system keyboard + Toolbar Keys accessory attach.
final class WWNTerminalToolbarField: UITextField, UITextFieldDelegate {
    weak var coordinator: WWNTerminalToolbarHost.Coordinator?
    private(set) var accessory: WWNKeyboardAccessoryView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        keyboardAppearance = .dark
        keyboardType = .asciiCapable
        textContentType = nil
        // Keep a thin hit target so SwiftUI layout does not collapse the host.
        alpha = 0.02
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configureAccessory() {
        let view = WWNKeyboardAccessoryView()
        view.wwnDelegate = coordinator
        accessory = view
        inputAccessoryView = view
    }

    override var canBecomeFirstResponder: Bool { true }

    override func insertText(_ text: String) {
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
        }
        super.pressesBegan(presses, with: event)
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
#endif

#if os(tvOS) || os(visionOS)
import SwiftUI
import UIKit

/// Live key host for tvOS and visionOS. No Toolbar Keys accessory.
struct WWNTerminalKeyHost: UIViewRepresentable {
    var onInjectData: (Data) -> Void
    var onInjectText: (String) -> Void
    var autoFocus: Bool

    func makeUIView(context: Context) -> WWNTerminalKeyField {
        let field = WWNTerminalKeyField()
        field.onInjectData = onInjectData
        field.onInjectText = onInjectText
        return field
    }

    func updateUIView(_ uiView: WWNTerminalKeyField, context: Context) {
        uiView.onInjectData = onInjectData
        uiView.onInjectText = onInjectText
        if autoFocus, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
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
        keyboardType = .asciiCapable
        alpha = 0.02
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var canBecomeFirstResponder: Bool { true }

    override func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        if text == "\n" || text == "\r" { return }
        onInjectText?(text)
    }

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
