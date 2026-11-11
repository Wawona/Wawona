#if os(visionOS) || os(tvOS)
import SwiftUI
import UIKit

/// Leaves Terminal on Escape, Cmd-W or Cmd-. (visionOS, when a pinch misses
/// Done) and on the Siri Remote Menu press (tvOS).
public struct WWNTerminalEscapeDismissHost: UIViewControllerRepresentable {
    public var onEscape: () -> Void
    public init(onEscape: @escaping () -> Void) { self.onEscape = onEscape }

    public func makeUIViewController(context: Context) -> WWNTerminalEscapeDismissController {
        let vc = WWNTerminalEscapeDismissController()
        vc.onEscape = onEscape
        return vc
    }

    public func updateUIViewController(_ vc: WWNTerminalEscapeDismissController, context: Context) {
        vc.onEscape = onEscape
    }
}

public final class WWNTerminalEscapeDismissController: UIViewController {
    public var onEscape: (() -> Void)?

    public override var canBecomeFirstResponder: Bool { true }

    // On visionOS the terminal's key field holds first responder for typing,
    // so only tvOS, which has no such field, takes it here.
    #if os(tvOS)
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = becomeFirstResponder()
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            onEscape?()
            return
        }
        super.pressesBegan(presses, with: event)
    }
    #endif

    public override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape)),
            UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(escape)),
            UIKeyCommand(input: ".", modifierFlags: .command, action: #selector(escape)),
        ]
    }

    @objc private func escape() { onEscape?() }
}

/// A UIKit button for Terminal chrome. SwiftUI `Button` actions are swallowed
/// while the soft keyboard is first responder; this resigns it on tap or
/// accessibility activation, then runs `action`.
public struct WWNTerminalDoneButton: UIViewRepresentable {
    public var title: String
    public var accessibilityId: String
    public var action: () -> Void

    public init(title: String = "Done", accessibilityId: String, action: @escaping () -> Void) {
        self.title = title
        self.accessibilityId = accessibilityId
        self.action = action
    }

    public func makeUIView(context: Context) -> WWNTerminalDoneUIButton {
        let button = WWNTerminalDoneUIButton(type: .system)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(button, action: #selector(WWNTerminalDoneUIButton.fire), for: .touchUpInside)
        updateUIView(button, context: context)
        return button
    }

    public func updateUIView(_ button: WWNTerminalDoneUIButton, context: Context) {
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = title
        button.accessibilityIdentifier = accessibilityId
        button.action = action
    }
}

public final class WWNTerminalDoneUIButton: UIButton {
    var action: (() -> Void)?

    public override var intrinsicContentSize: CGSize { CGSize(width: 96, height: 44) }

    public override func accessibilityActivate() -> Bool {
        fire()
        return true
    }

    @objc func fire() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.async { [action] in action?() }
    }
}
#endif
