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
        if autoFocus, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, WWNKeyboardAccessoryDelegate {
        var parent: WWNTerminalToolbarHost
        weak var field: WWNTerminalToolbarField?

        init(parent: WWNTerminalToolbarHost) {
            self.parent = parent
        }

        func keyboardAccessoryDidSendKey(name: String, keycode: UInt32, character: String?) {
            if parent.isShell {
                if let character, !character.isEmpty {
                    parent.onInjectText(character)
                } else if keycode == WWNEvdevKeycode.esc {
                    parent.onInjectData(Data([0x1B]))
                } else if keycode == WWNEvdevKeycode.tab {
                    parent.onInjectData(Data([0x09]))
                } else if keycode == WWNEvdevKeycode.enter {
                    parent.onInjectData(Data([0x0A]))
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
final class WWNTerminalToolbarField: UITextField {
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
        // Keep a 1pt hit target so SwiftUI layout does not collapse the host.
        alpha = 0.02
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
        coordinator?.parent.onInjectText(text)
    }

    override func deleteBackward() {
        coordinator?.parent.onInjectData(Data([0x7F]))
    }
}
#endif
