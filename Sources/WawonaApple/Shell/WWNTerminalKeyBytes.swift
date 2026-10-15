#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

/// Hardware-key bytes for Wawona Terminal. Printable text stays on `insertText`.
enum WWNTerminalKeyBytes {
    @available(iOS 13.4, tvOS 13.4, *)
    static func special(for key: UIKey) -> [UInt8]? {
        if key.modifierFlags.contains(.command) { return nil }
        if key.modifierFlags.contains(.control),
            let ch = key.charactersIgnoringModifiers.lowercased().first,
            ch.isLetter,
            let ascii = ch.asciiValue
        {
            return [ascii &- UInt8(ascii: "a") &+ 1]
        }
        switch key.keyCode {
        case .keyboardUpArrow: return [0x1B, 0x5B, 0x41]
        case .keyboardDownArrow: return [0x1B, 0x5B, 0x42]
        case .keyboardRightArrow: return [0x1B, 0x5B, 0x43]
        case .keyboardLeftArrow: return [0x1B, 0x5B, 0x44]
        case .keyboardHome: return [0x1B, 0x5B, 0x48]
        case .keyboardEnd: return [0x1B, 0x5B, 0x46]
        case .keyboardPageUp: return [0x1B, 0x5B, 0x35, 0x7E]
        case .keyboardPageDown: return [0x1B, 0x5B, 0x36, 0x7E]
        case .keyboardDeleteForward: return [0x1B, 0x5B, 0x33, 0x7E]
        case .keyboardEscape: return [0x1B]
        case .keyboardF1: return [0x1B, 0x4F, 0x50]
        case .keyboardF2: return [0x1B, 0x4F, 0x51]
        case .keyboardF3: return [0x1B, 0x4F, 0x52]
        case .keyboardF4: return [0x1B, 0x4F, 0x53]
        case .keyboardF5: return [0x1B, 0x5B, 0x31, 0x35, 0x7E]
        case .keyboardF6: return [0x1B, 0x5B, 0x31, 0x37, 0x7E]
        case .keyboardF7: return [0x1B, 0x5B, 0x31, 0x38, 0x7E]
        case .keyboardF8: return [0x1B, 0x5B, 0x31, 0x39, 0x7E]
        case .keyboardF9: return [0x1B, 0x5B, 0x32, 0x30, 0x7E]
        case .keyboardF10: return [0x1B, 0x5B, 0x32, 0x31, 0x7E]
        case .keyboardF11: return [0x1B, 0x5B, 0x32, 0x33, 0x7E]
        case .keyboardF12: return [0x1B, 0x5B, 0x32, 0x34, 0x7E]
        case .keyboardTab: return [0x09]
        case .keyboardReturnOrEnter: return [0x0A]
        case .keyboardDeleteOrBackspace: return [0x7F]
        default: return nil
        }
    }

    static func legacyCommands(action: Selector) -> [UIKeyCommand] {
        let inputs = [
            UIKeyCommand.inputUpArrow,
            UIKeyCommand.inputDownArrow,
            UIKeyCommand.inputLeftArrow,
            UIKeyCommand.inputRightArrow,
            UIKeyCommand.inputEscape,
            UIKeyCommand.inputPageUp,
            UIKeyCommand.inputPageDown,
            "\t",
        ]
        var commands = inputs.map { input in
            UIKeyCommand(input: input, modifierFlags: [], action: action)
        }
        for ch in "abcdefghijklmnopqrstuvwxyz" {
            commands.append(
                UIKeyCommand(input: String(ch), modifierFlags: .control, action: action))
        }
        return commands
    }

    static func legacyBytes(_ command: UIKeyCommand) -> [UInt8] {
        if command.modifierFlags.contains(.control),
            let input = command.input,
            let ch = input.lowercased().first,
            ch.isLetter,
            let ascii = ch.asciiValue
        {
            return [ascii &- UInt8(ascii: "a") &+ 1]
        }
        switch command.input {
        case UIKeyCommand.inputUpArrow: return [0x1B, 0x5B, 0x41]
        case UIKeyCommand.inputDownArrow: return [0x1B, 0x5B, 0x42]
        case UIKeyCommand.inputRightArrow: return [0x1B, 0x5B, 0x43]
        case UIKeyCommand.inputLeftArrow: return [0x1B, 0x5B, 0x44]
        case UIKeyCommand.inputEscape: return [0x1B]
        case UIKeyCommand.inputPageUp: return [0x1B, 0x5B, 0x35, 0x7E]
        case UIKeyCommand.inputPageDown: return [0x1B, 0x5B, 0x36, 0x7E]
        case "\t": return [0x09]
        default: return []
        }
    }
}
#endif
