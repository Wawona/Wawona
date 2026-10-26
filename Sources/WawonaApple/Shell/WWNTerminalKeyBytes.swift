#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
enum WWNTerminalKeyBytes {
    @available(iOS 13.4, tvOS 13.4, *)
    static func special(for key: UIKey) -> [UInt8]? {
        if key.modifierFlags.contains(.command) { return nil }
        if key.modifierFlags.contains(.control) {
            if let ch = key.charactersIgnoringModifiers.uppercased().first,
                let ascii = ch.asciiValue, ascii >= 0x40, ascii <= 0x5F,
                !key.modifierFlags.contains(.shift)
            {
                let byte = ascii & 0x1F
                return key.modifierFlags.contains(.alternate) ? [0x1B, byte] : [byte]
            }
            let extra: UInt8?
            switch key.keyCode {
            case .keyboard2: extra = 0x00
            case .keyboard3, .keyboardOpenBracket: extra = 0x1B
            case .keyboard4, .keyboardBackslash: extra = 0x1C
            case .keyboard5, .keyboardCloseBracket: extra = 0x1D
            case .keyboard6: extra = 0x1E
            case .keyboard7, .keyboardHyphen: extra = 0x1F
            case .keyboard8: extra = 0x7F
            case .keyboardSlash: extra = key.modifierFlags.contains(.shift) ? 0x7F : 0x1F
            default: extra = nil
            }
            if let extra {
                if key.modifierFlags.contains(.shift), key.keyCode != .keyboardSlash, let code = key.charactersIgnoringModifiers.first?.asciiValue { return Array("\u{1B}[27;\(xtermParam(key));\(code)~".utf8) }
                return key.modifierFlags.contains(.alternate) ? [0x1B, extra] : [extra]
            }
        }
        switch key.keyCode {
        case .keyboardUpArrow: return letterCSI(0x41, [0x1B, 0x5B, 0x41], key); case .keyboardDownArrow: return letterCSI(0x42, [0x1B, 0x5B, 0x42], key)
        case .keyboardRightArrow: return letterCSI(0x43, [0x1B, 0x5B, 0x43], key)
        case .keyboardLeftArrow: return letterCSI(0x44, [0x1B, 0x5B, 0x44], key)
        case .keyboardHome: return letterCSI(0x48, [0x1B, 0x5B, 0x48], key)
        case .keyboardEnd: return letterCSI(0x46, [0x1B, 0x5B, 0x46], key)
        case .keyboardPageUp, .keyboardPrior: return tildeCSI(0x35, [0x1B, 0x5B, 0x35, 0x7E], key)
        case .keyboardPageDown: return tildeCSI(0x36, [0x1B, 0x5B, 0x36, 0x7E], key)
        case .keyboardDeleteForward: return tildeCSI(0x33, [0x1B, 0x5B, 0x33, 0x7E], key)
        case .keyboardInsert: return tildeCSI(0x32, [0x1B, 0x5B, 0x32, 0x7E], key)
        case .keyboardApplication: return tildeCode("29", [0x1B, 0x5B, 0x32, 0x39, 0x7E], key)
        case .keyboardFind: return tildeCSI(0x31, [0x1B, 0x5B, 0x31, 0x7E], key)
        case .keyboardSelect: return tildeCSI(0x34, [0x1B, 0x5B, 0x34, 0x7E], key)
        case .keyboardHelp, .keyboardF15: return tildeCode("28", [0x1B, 0x5B, 0x32, 0x38, 0x7E], key)
        case .keyboardEscape: let p = xtermParam(key); return p <= 1 ? [0x1B] : (p == 3 ? [0x1B, 0x1B] : Array("\u{1B}[27;\(p);27~".utf8))
        case .keyboardSpacebar:
            if key.modifierFlags.contains(.shift), xtermParam(key) > 2 { return Array("\u{1B}[27;\(xtermParam(key));32~".utf8) }
            if key.modifierFlags.contains(.control) { return key.modifierFlags.contains(.alternate) ? [0x1B, 0x00] : [0x00] }
            return key.modifierFlags.contains(.alternate) ? [0x1B, 0x20] : nil
        case .keyboardF1: return letterCSI(0x50, [0x1B, 0x4F, 0x50], key)
        case .keyboardF2: return letterCSI(0x51, [0x1B, 0x4F, 0x51], key)
        case .keyboardF3: return letterCSI(0x52, [0x1B, 0x4F, 0x52], key)
        case .keyboardF4: return letterCSI(0x53, [0x1B, 0x4F, 0x53], key)
        case .keyboardF5: return tildeCode("15", [0x1B, 0x5B, 0x31, 0x35, 0x7E], key)
        case .keyboardF6: return tildeCode("17", [0x1B, 0x5B, 0x31, 0x37, 0x7E], key)
        case .keyboardF7: return tildeCode("18", [0x1B, 0x5B, 0x31, 0x38, 0x7E], key)
        case .keyboardF8: return tildeCode("19", [0x1B, 0x5B, 0x31, 0x39, 0x7E], key)
        case .keyboardF9: return tildeCode("20", [0x1B, 0x5B, 0x32, 0x30, 0x7E], key)
        case .keyboardF10: return tildeCode("21", [0x1B, 0x5B, 0x32, 0x31, 0x7E], key)
        case .keyboardF11: return tildeCode("23", [0x1B, 0x5B, 0x32, 0x33, 0x7E], key)
        case .keyboardF12: return tildeCode("24", [0x1B, 0x5B, 0x32, 0x34, 0x7E], key)
        case .keyboardF13: return tildeCode("25", [0x1B, 0x5B, 0x32, 0x35, 0x7E], key)
        case .keyboardF14: return tildeCode("26", [0x1B, 0x5B, 0x32, 0x36, 0x7E], key)
        case .keyboardF16: return tildeCode("29", [0x1B, 0x5B, 0x32, 0x39, 0x7E], key)
        case .keyboardF17: return tildeCode("31", [0x1B, 0x5B, 0x33, 0x31, 0x7E], key)
        case .keyboardF18: return tildeCode("32", [0x1B, 0x5B, 0x33, 0x32, 0x7E], key)
        case .keyboardF19: return tildeCode("33", [0x1B, 0x5B, 0x33, 0x33, 0x7E], key); case .keyboardF20: return tildeCode("34", [0x1B, 0x5B, 0x33, 0x34, 0x7E], key)
        case .keyboardTab:
            let tab = xtermParam(key)
            if key.modifierFlags.contains(.shift) { return tab == 2 ? [0x1B, 0x5B, 0x5A] : Array("\u{1B}[1;\(tab)Z".utf8) }
            return tab <= 1 ? [0x09] : (tab == 3 ? [0x1B, 0x09] : Array("\u{1B}[27;\(tab);9~".utf8))
        case .keyboardReturnOrEnter, .keypadEnter, .keyboardReturn:
            if key.keyCode == .keypadEnter, xtermParam(key) == 1, let app = WWNTerminalCursorMode.keypadSequence(key.keyCode) { return app }
            let ret = xtermParam(key)
            if ret == 1 { return [0x0A] }
            return ret == 3 ? [0x1B, 0x0A] : Array("\u{1B}[27;\(ret);13~".utf8)
        case .keyboardDeleteOrBackspace:
            let byte: UInt8 = key.modifierFlags.contains(.control) ? 0x08 : 0x7F
            if key.modifierFlags.contains(.shift) { return Array("\u{1B}[27;\(xtermParam(key));\(byte)~".utf8) }
            return key.modifierFlags.contains(.alternate) ? [0x1B, byte] : [byte]
        case .keypad8, .keypad2, .keypad6, .keypad4, .keypad7, .keypad1,
            .keypad9, .keypad3, .keypad0, .keypadPeriod, .keypad5:
            if xtermParam(key) == 1, let app = WWNTerminalCursorMode.keypadSequence(key.keyCode) { return app }
            if !key.characters.isEmpty { return asciiModifier(key) }
            switch key.keyCode {
            case .keypad8: return letterCSI(0x41, [0x1B, 0x5B, 0x41], key)
            case .keypad2: return letterCSI(0x42, [0x1B, 0x5B, 0x42], key)
            case .keypad6: return letterCSI(0x43, [0x1B, 0x5B, 0x43], key)
            case .keypad4: return letterCSI(0x44, [0x1B, 0x5B, 0x44], key)
            case .keypad7: return letterCSI(0x48, [0x1B, 0x5B, 0x48], key)
            case .keypad1: return letterCSI(0x46, [0x1B, 0x5B, 0x46], key)
            case .keypad9: return tildeCSI(0x35, [0x1B, 0x5B, 0x35, 0x7E], key)
            case .keypad3: return tildeCSI(0x36, [0x1B, 0x5B, 0x36, 0x7E], key)
            case .keypad0: return tildeCSI(0x32, [0x1B, 0x5B, 0x32, 0x7E], key)
            case .keypadPeriod: return tildeCSI(0x33, [0x1B, 0x5B, 0x33, 0x7E], key)
            case .keypad5: return letterCSI(0x45, [0x1B, 0x5B, 0x45], key)
            default: return nil
            }
        case .keypadSlash, .keypadAsterisk, .keypadHyphen, .keypadPlus, .keypadEqualSign, .keypadComma:
            if xtermParam(key) == 1, let app = WWNTerminalCursorMode.keypadSequence(key.keyCode) { return app }
            if !key.characters.isEmpty { return asciiModifier(key) }
            let byte: UInt8
            switch key.keyCode {
            case .keypadSlash: byte = 0x2F
            case .keypadAsterisk: byte = 0x2A
            case .keypadHyphen: byte = 0x2D
            case .keypadPlus: byte = 0x2B
            case .keypadEqualSign: byte = 0x3D
            case .keypadComma: byte = 0x2C
            default: return nil
            }
            if key.modifierFlags.contains(.control) { return Array("\u{1B}[27;\(xtermParam(key));\(byte)~".utf8) }
            return key.modifierFlags.contains(.alternate) ? [0x1B, byte] : [byte]
        default: return asciiModifier(key)
        }
    }

    @available(iOS 13.4, tvOS 13.4, *)
    private static func asciiModifier(_ key: UIKey) -> [UInt8]? {
        guard let ch = key.charactersIgnoringModifiers.first?.asciiValue else { return nil }
        let byte = (key.modifierFlags.contains(.shift) && (0x61...0x7A).contains(ch)) ? ch &- 0x20 : ch
        if key.modifierFlags.contains(.control) {
            let c0 = ([0x32: 0x00, 0x33: 0x1B, 0x34: 0x1C, 0x35: 0x1D, 0x36: 0x1E, 0x37: 0x1F, 0x38: 0x7F] as [UInt8: UInt8])[byte]
            if let c0, !key.modifierFlags.contains(.shift) { return key.modifierFlags.contains(.alternate) ? [0x1B, c0] : [c0] }
            return Array("\u{1B}[27;\(xtermParam(key));\(byte)~".utf8)
        }
        let altByte = key.modifierFlags.contains(.shift) ? (Array("1234567890-=[]\\;',./`".utf8).firstIndex(of: byte).map { Array("!@#$%^&*()_+{}|:\"<>?~".utf8)[$0] } ?? byte) : byte
        return key.modifierFlags.contains(.alternate) ? [0x1B, altByte] : nil
    }

    @available(iOS 13.4, tvOS 13.4, *)
    private static func xtermParam(_ key: UIKey) -> Int {
        let f = key.modifierFlags
        return 1 + (f.contains(.shift) ? 1 : 0) + (f.contains(.alternate) ? 2 : 0) + (f.contains(.control) ? 4 : 0)
    }

    @available(iOS 13.4, tvOS 13.4, *)
    private static func letterCSI(_ letter: UInt8, _ plain: [UInt8], _ key: UIKey) -> [UInt8] {
        let param = xtermParam(key)
        if param == 1 { return plain }
        return Array("\u{1B}[1;\(param)\(Character(UnicodeScalar(letter)))".utf8)
    }

    @available(iOS 13.4, tvOS 13.4, *)
    private static func tildeCode(_ code: String, _ plain: [UInt8], _ key: UIKey) -> [UInt8] {
        let param = xtermParam(key)
        if param == 1 { return plain }
        return Array("\u{1B}[\(code);\(param)~".utf8)
    }

    @available(iOS 13.4, tvOS 13.4, *)
    private static func tildeCSI(_ code: UInt8, _ plain: [UInt8], _ key: UIKey) -> [UInt8] {
        let param = xtermParam(key)
        if param == 1 { return plain }
        return Array("\u{1B}[\(Character(UnicodeScalar(code)));\(param)~".utf8)
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
        commands.append(UIKeyCommand(input: "\t", modifierFlags: .shift, action: action))
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
        case "\t":
            if command.modifierFlags.contains(.shift) { return [0x1B, 0x5B, 0x5A] }
            return [0x09]
        default: return []
        }
    }

    static func toolbar(_ text: String, control: Bool, alt: Bool, shift: Bool) -> [UInt8]? {
        guard control || alt || shift else { return nil }
        let param = 1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (control ? 4 : 0)
        if text == "\t" {
            if shift { return param == 2 ? [0x1B, 0x5B, 0x5A] : Array("\u{1B}[1;\(param)Z".utf8) }
            return param == 3 ? [0x1B, 0x09] : Array("\u{1B}[27;\(param);9~".utf8)
        }
        if text == "\n" || text == "\r" {
            return param == 3 ? [0x1B, 0x0A] : (param > 1 ? Array("\u{1B}[27;\(param);13~".utf8) : nil)
        }
        if let last = text.last, (text.hasPrefix("\u{1B}[") && "ABCDHF".contains(last))
            || (text.utf8.count == 3 && text.hasPrefix("\u{1B}O") && "PQRS".contains(last)) {
            return Array("\u{1B}[1;\(param)\(last)".utf8)
        }
        if text.hasPrefix("\u{1B}["), text.hasSuffix("~"), !text.contains(";") {
            let code = text.dropFirst(2).dropLast()
            if !code.isEmpty { return Array("\u{1B}[\(code);\(param)~".utf8) }
        }
        if text == " " {
            if shift, param > 2 { return Array("\u{1B}[27;\(param);32~".utf8) }
            if control { return alt ? [0x1B, 0x00] : [0x00] }
        }
        if control, text.utf8.count == 1, let raw = text.utf8.first {
            if !shift, let ch = text.uppercased().first?.asciiValue, (0x40...0x5F).contains(ch) {
                let byte = ch & 0x1F; return alt ? [0x1B, byte] : [byte]
            }
            let byte = (shift && (0x61...0x7A).contains(raw)) ? raw &- 0x20 : raw
            return Array("\u{1B}[27;\(param);\(byte)~".utf8)
        }
        if text == "\u{1B}", shift { return Array("\u{1B}[27;\(param);27~".utf8) }
        if text.utf8.count == 1, let raw = text.utf8.first {
            let from = Array("1234567890-=[]\\;',./`".utf8), to = Array("!@#$%^&*()_+{}|:\"<>?~".utf8)
            let byte: UInt8 = shift && (0x61...0x7A).contains(raw) ? raw &- 0x20 : (shift ? (from.firstIndex(of: raw).map { to[$0] } ?? raw) : raw)
            if alt || byte != raw { return alt ? [0x1B, byte] : [byte] }
        }
        return nil
    }

    @available(iOS 13.4, tvOS 13.4, *)
    static func latched(_ key: UIKey, _ raw: [UInt8], control: Bool, alt: Bool, shift: Bool) -> [UInt8] {
        let flags = key.modifierFlags
        guard !flags.contains(.control), !flags.contains(.alternate), !flags.contains(.shift),
            control || alt || shift else { return raw }
        if raw == [0x7F] || raw == [0x08] {
            let b: UInt8 = control ? 0x08 : raw[0]; if shift { return Array("\u{1B}[27;\(1 + 1 + (alt ? 2 : 0) + (control ? 4 : 0));\(b)~".utf8) }; return alt ? [0x1B, b] : [b]
        }
        let text = String(bytes: raw, encoding: .utf8) ?? ""
        return toolbar(text, control: control, alt: alt, shift: shift) ?? raw
    }
}

enum WWNTerminalCursorMode {
    private static let lock = NSLock()
    private static var application = false
    private static var keypadApplication = false
    private static var focusReports = false
    private static var focusInPending = false
    private static var reportedFocus = false, fieldFirst = false, mouseReports = false
    private static var pending = [UInt8]()

    static func noteResponder(_ on: Bool) { lock.lock(); fieldFirst = on; lock.unlock() }
    static var pointerDrags: Bool { lock.lock(); defer { lock.unlock() }; return mouseReports }

    static var arrowsAreSS3: Bool {
        lock.lock()
        defer { lock.unlock() }
        return application
    }

    static func observe(_ bytes: Data) {
        lock.lock()
        defer { lock.unlock() }
        pending.append(contentsOf: bytes)
        var i = 0
        while i < pending.count {
            if pending[i] == 0x1B {
                if i + 1 >= pending.count { break }
                if pending[i + 1] == 0x63 {
                    application = false
                    keypadApplication = false
                    focusReports = false; focusInPending = false; reportedFocus = false; mouseReports = false
                    i += 2
                    continue
                }
                if pending[i + 1] == 0x3D {
                    keypadApplication = true
                    i += 2
                    continue
                }
                if pending[i + 1] == 0x3E {
                    keypadApplication = false
                    i += 2
                    continue
                }
                if pending[i + 1] == 0x5B {
                    if let next = finishCSI(from: i + 2) {
                        i = next
                        continue
                    }
                    break
                }
            }
            i += 1
        }
        if i > 0 { pending.removeFirst(i) }
        if pending.count > 32 { pending.removeFirst(pending.count - 32) }
    }

    static func mapArrow(_ data: Data) -> Data {
        guard arrowsAreSS3, data.count == 3, data[0] == 0x1B, data[1] == 0x5B,
              (0x41...0x44).contains(data[2]) else { return data }
        return Data([0x1B, 0x4F, data[2]])
    }

    @available(iOS 13.4, tvOS 13.4, *)
    static func keypadSequence(_ code: UIKeyboardHIDUsage) -> [UInt8]? {
        lock.lock(); let on = keypadApplication; lock.unlock()
        guard on else { return nil }
        let letter: UInt8
        switch code {
        case .keypad0: letter = 0x70; case .keypad1: letter = 0x71
        case .keypad2: letter = 0x72; case .keypad3: letter = 0x73
        case .keypad4: letter = 0x74; case .keypad5: letter = 0x75
        case .keypad6: letter = 0x76; case .keypad7: letter = 0x77
        case .keypad8: letter = 0x78; case .keypad9: letter = 0x79
        case .keypadPeriod: letter = 0x6E; case .keypadHyphen: letter = 0x6D
        case .keypadPlus: letter = 0x6B; case .keypadAsterisk: letter = 0x6A
        case .keypadSlash: letter = 0x6F; case .keypadEnter: letter = 0x4D
        case .keypadComma: letter = 0x6C; case .keypadEqualSign: letter = 0x58
        default: return nil
        }
        return [0x1B, 0x4F, letter]
    }

    static func focusReport(_ focused: Bool) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard focusReports, fieldFirst, reportedFocus != focused else { return nil }
        reportedFocus = focused; if focused { focusInPending = false }
        return Data([0x1B, 0x5B, focused ? 0x49 : 0x4F])
    }

    static func takePendingFocusIn() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard focusReports, focusInPending else { return nil }
        focusInPending = false; reportedFocus = true
        return Data([0x1B, 0x5B, 0x49])
    }

    private static func finishCSI(from start: Int) -> Int? {
        var j = start
        var privateMode = false
        if j < pending.count, pending[j] == 0x3F {
            privateMode = true
            j += 1
        }
        var params = [Int]()
        var cur = 0
        var any = false
        while j < pending.count {
            let c = pending[j]
            if c >= 0x30, c <= 0x39 {
                cur = min(cur * 10 + Int(c - 0x30), 9999)
                any = true
                j += 1
                continue
            }
            if c == 0x3B {
                params.append(any ? cur : 0)
                cur = 0
                any = false
                j += 1
                continue
            }
            if c >= 0x40, c <= 0x7E {
                params.append(any ? cur : 0)
                if privateMode, c == 0x68 || c == 0x6C {
                    if params.contains(1) { application = c == 0x68 }
                    if params.contains(66) { keypadApplication = c == 0x6C }
                    if params.contains(1004) {
                        let enable = c == 0x68
                        if enable, !focusReports { focusInPending = true }
                        if !enable { focusInPending = false; reportedFocus = false }
                        focusReports = enable
                    }
                    if params.contains(1000) || params.contains(1002) || params.contains(1003) || params.contains(1006) { mouseReports = c == 0x68 }
                }
                return j + 1
            }
            return j + 1
        }
        return nil
    }
}
#endif
