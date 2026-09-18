#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  KeyboardToolbarCustomization.swift
//  Wawona
//
//  Data models for keyboard toolbar customization:
//  KeyID (built-in key identifiers), KeySlot (layout slot type),
//  ToolbarLayoutConfig (persisted layout), CustomKey + SequenceStep (user-defined keys).
//  Ported 1:1 from rootshell.
//

import Foundation
import UIKit

// MARK: - KeyID

/// Identifies a built-in toolbar key. Raw values are stable — never rename or remove a shipped case.
public enum KeyID: String, Codable, CaseIterable, Hashable, Sendable {
    // Modifiers (5)
    case esc
    case ctrl
    case alt
    case shift
    case cmd

    // Special (1)
    case tab

    // Navigation (5)
    case arrowDrawerToggle
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight

    // Symbols (28)
    case backtick
    case tilde
    case caret
    case underscore
    case backslash
    case pipe
    case leftBracket
    case rightBracket
    case leftBrace
    case rightBrace
    case lessThan
    case greaterThan
    case slash
    case questionMark
    case dash
    case equals
    case singleQuote
    case doubleQuote
    case semicolon
    case colon
    case leftParen
    case rightParen
    case atSign
    case hash
    case dollar
    case percent
    case ampersand
    case asterisk

    // Actions (14)
    case dismiss
    case tabSwitcher
    case compose
    case writingAssistance
    case toolbarSettings
    case paste
    case voiceAgent
    case toggleFullScreen
    case toggleTabBar
    case newConnection
    case appSettings
    case toggleMouseCapture
    case aiAgent
    case brightnessBoost
    case clipboardManager

    // Toggles (1)
    case drawerToggle

    // MARK: - Display Properties

    public var displayName: String {
        switch self {
        case .esc: return String(localized: "Escape")
        case .ctrl: return String(localized: "Control")
        case .alt: return String(localized: "Option")
        case .shift: return String(localized: "Shift")
        case .cmd: return String(localized: "Command")
        case .tab: return String(localized: "Tab")
        case .arrowDrawerToggle: return String(localized: "Arrow Joystick")
        case .arrowUp: return String(localized: "Arrow Up")
        case .arrowDown: return String(localized: "Arrow Down")
        case .arrowLeft: return String(localized: "Arrow Left")
        case .arrowRight: return String(localized: "Arrow Right")
        case .backtick: return String(localized: "Backtick `")
        case .tilde: return String(localized: "Tilde ~")
        case .caret: return String(localized: "Caret ^")
        case .underscore: return String(localized: "Underscore _")
        case .backslash: return String(localized: "Backslash \\")
        case .pipe: return String(localized: "Pipe |")
        case .leftBracket: return String(localized: "Left Bracket [")
        case .rightBracket: return String(localized: "Right Bracket ]")
        case .leftBrace: return String(localized: "Left Brace {")
        case .rightBrace: return String(localized: "Right Brace }")
        case .lessThan: return String(localized: "Less Than <")
        case .greaterThan: return String(localized: "Greater Than >")
        case .slash: return String(localized: "Slash /")
        case .questionMark: return String(localized: "Question Mark ?")
        case .dash: return String(localized: "Dash -")
        case .equals: return String(localized: "Equals =")
        case .singleQuote: return String(localized: "Single Quote '")
        case .doubleQuote: return String(localized: "Double Quote \"")
        case .semicolon: return String(localized: "Semicolon ;")
        case .colon: return String(localized: "Colon :")
        case .leftParen: return String(localized: "Left Paren (")
        case .rightParen: return String(localized: "Right Paren )")
        case .atSign: return String(localized: "At Sign @")
        case .hash: return String(localized: "Hash #")
        case .dollar: return String(localized: "Dollar $")
        case .percent: return String(localized: "Percent %")
        case .ampersand: return String(localized: "Ampersand &")
        case .asterisk: return String(localized: "Asterisk *")
        case .dismiss: return String(localized: "Dismiss Keyboard")
        case .tabSwitcher: return String(localized: "Tab Switcher")
        case .compose: return String(localized: "Compose")
        case .writingAssistance: return String(localized: "Writing Assistance")
        case .toolbarSettings: return String(localized: "Toolbar Settings")
        case .paste: return String(localized: "Paste")
        case .voiceAgent: return String(localized: "Voice Agent")
        case .toggleFullScreen: return String(localized: "Toggle Full Screen")
        case .toggleTabBar: return String(localized: "Toggle Top Tab Bar")
        case .newConnection: return String(localized: "New Connection")
        case .appSettings: return String(localized: "App Settings")
        case .toggleMouseCapture: return String(localized: "Toggle Mouse Capture")
        case .aiAgent: return String(localized: "AI Agent")
        case .brightnessBoost: return String(localized: "Brightness Boost")
        case .clipboardManager: return String(localized: "Clipboard Manager")
        case .drawerToggle: return String(localized: "Drawer Toggle")
        }
    }

    /// SF Symbol icon name, if applicable
    public var iconName: String? {
        switch self {
        case .esc: return "escape"
        case .ctrl: return "control"
        case .alt: return "option"
        case .shift: return "shift"
        case .cmd: return "command"
        case .tab: return "arrow.right.to.line"
        case .arrowDrawerToggle: return "arrow.up.and.down.and.arrow.left.and.right"
        case .arrowUp: return "arrow.up"
        case .arrowDown: return "arrow.down"
        case .arrowLeft: return "arrow.left"
        case .arrowRight: return "arrow.right"
        case .dismiss: return "chevron.down"
        case .tabSwitcher: return "rectangle.stack"
        case .compose: return "character.cursor.ibeam"
        case .writingAssistance: return TerminalWritingAssistanceMode.toolbarIcon
        case .toolbarSettings: return "gearshape"
        case .paste: return "doc.on.clipboard"
        case .voiceAgent: return "waveform.circle"
        case .toggleFullScreen: return "arrow.up.left.and.arrow.down.right"
        case .toggleTabBar: return "menubar.rectangle"
        case .newConnection: return "plus"
        case .appSettings: return "slider.horizontal.3"
        case .toggleMouseCapture: return "computermouse"
        case .aiAgent: return "sparkles"
        case .brightnessBoost: return "sun.max"
        case .clipboardManager: return "list.clipboard"
        case .drawerToggle: return "ellipsis"
        default: return nil
        }
    }

    /// The character or key value string this key sends
    public var keyValue: String {
        switch self {
        case .esc: return "Esc"
        case .ctrl: return "Ctrl"
        case .alt: return "Alt"
        case .shift: return "Shift"
        case .cmd: return "Cmd"
        case .tab: return "\t"
        case .arrowDrawerToggle: return "__arrowDrawer__"
        case .arrowUp: return "\u{1B}[A"
        case .arrowDown: return "\u{1B}[B"
        case .arrowLeft: return "\u{1B}[D"
        case .arrowRight: return "\u{1B}[C"
        case .backtick: return "`"
        case .tilde: return "~"
        case .caret: return "^"
        case .underscore: return "_"
        case .backslash: return "\\"
        case .pipe: return "|"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .leftBrace: return "{"
        case .rightBrace: return "}"
        case .lessThan: return "<"
        case .greaterThan: return ">"
        case .slash: return "/"
        case .questionMark: return "?"
        case .dash: return "-"
        case .equals: return "="
        case .singleQuote: return "'"
        case .doubleQuote: return "\""
        case .semicolon: return ";"
        case .colon: return ":"
        case .leftParen: return "("
        case .rightParen: return ")"
        case .atSign: return "@"
        case .hash: return "#"
        case .dollar: return "$"
        case .percent: return "%"
        case .ampersand: return "&"
        case .asterisk: return "*"
        case .dismiss: return "__dismiss__"
        case .tabSwitcher: return "__tabswitcher__"
        case .compose: return "__compose__"
        case .writingAssistance: return "__writingAssistance__"
        case .toolbarSettings: return "__toolbarSettings__"
        case .paste: return "__paste__"
        case .voiceAgent: return "__voiceAgent__"
        case .toggleFullScreen: return "__toggleFullScreen__"
        case .toggleTabBar: return "__toggleTabBar__"
        case .newConnection: return "__newConnection__"
        case .appSettings: return "__appSettings__"
        case .toggleMouseCapture: return "__toggleMouseCapture__"
        case .aiAgent: return "__aiAgent__"
        case .brightnessBoost: return "__brightnessBoost__"
        case .clipboardManager: return "__clipboardManager__"
        case .drawerToggle: return "__extraDrawer__"
        }
    }

    /// Converts this KeyID to a KeyDefinition for the toolbar view
    public var keyDefinition: KeyDefinition {
        switch self {
        case .esc: return .esc
        case .ctrl: return .ctrl
        case .alt: return .alt
        case .shift: return .shift
        case .cmd: return .cmd
        case .tab: return .tab
        case .arrowDrawerToggle: return .arrowDrawerToggle
        case .arrowUp: return .text("\u{1B}[A")
        case .arrowDown: return .text("\u{1B}[B")
        case .arrowLeft: return .text("\u{1B}[D")
        case .arrowRight: return .text("\u{1B}[C")
        case .dismiss: return .dismiss
        case .tabSwitcher: return .tabSwitcher
        case .compose: return .compose
        case .writingAssistance: return .text(keyValue)
        case .toolbarSettings: return .toolbarSettings
        case .paste: return .paste
        case .voiceAgent: return .voiceAgent
        case .toggleFullScreen: return .toggleFullScreen
        case .toggleTabBar: return .toggleTabBar
        case .newConnection: return .newConnection
        case .appSettings: return .appSettings
        case .toggleMouseCapture: return .toggleMouseCapture
        case .aiAgent: return .aiAgent
        case .brightnessBoost: return .brightnessBoost
        case .clipboardManager: return .clipboardManager
        case .drawerToggle: return .extraKeysDrawerToggle
        default:
            return .text(keyValue)
        }
    }

    /// Whether this key is a modifier (esc/ctrl/alt/shift/cmd)
    public var isModifier: Bool {
        switch self {
        case .esc, .ctrl, .alt, .shift, .cmd: return true
        default: return false
        }
    }

    /// Category for grouping in settings UI
    public var category: KeyCategory {
        switch self {
        case .esc, .ctrl, .alt, .shift, .cmd: return .modifier
        case .tab: return .special
        case .arrowDrawerToggle, .arrowUp, .arrowDown, .arrowLeft, .arrowRight: return .navigation
        case .dismiss, .tabSwitcher, .compose, .writingAssistance, .toolbarSettings, .paste, .voiceAgent,
             .toggleFullScreen, .toggleTabBar, .newConnection, .appSettings,
             .toggleMouseCapture, .aiAgent, .brightnessBoost, .clipboardManager: return .action
        case .drawerToggle: return .toggle
        default: return .symbol
        }
    }

    public enum KeyCategory: String, Sendable {
        case modifier, special, navigation, symbol, action, toggle
    }
}

// MARK: - KeySlot

/// A slot in the toolbar layout — either a built-in key or a reference to a custom key.
public enum KeySlot: Codable, Hashable, Sendable {
    case builtIn(KeyID)
    case custom(UUID)

    public var keyID: KeyID? {
        if case .builtIn(let id) = self { return id }
        return nil
    }

    public var customID: UUID? {
        if case .custom(let id) = self { return id }
        return nil
    }
}

// MARK: - DrawerToggleMode

/// How the "…" button behaves when more than one drawer row is configured.
public enum DrawerToggleMode: String, Codable, CaseIterable, Sendable {
    /// Each press reveals one more drawer row; when all are open, the next press collapses them.
    case stack
    /// Each press swaps the single drawer row's contents to the next drawer.
    case cycle

    public var displayName: String {
        switch self {
        case .stack: return String(localized: "Stack")
        case .cycle: return String(localized: "Cycle")
        }
    }
}

// MARK: - ToolbarLayoutConfig

/// Persisted toolbar layout configuration.
public struct ToolbarLayoutConfig: Equatable, Sendable {
    public var version: Int
    public var mainRow: [KeySlot]
    /// One or more drawer rows. Invariant: never empty — always at least one row (possibly `[]`).
    public var drawerRows: [[KeySlot]]
    public var hiddenKeys: Set<KeyID>

    // MARK: - Defaults

    public static let currentVersion = 14

    public static func defaultConfig(for idiom: UIUserInterfaceIdiom) -> ToolbarLayoutConfig {
        switch idiom {
        case .pad:
            return iPadDefault
        default:
            return iPhoneDefault
        }
    }

    public static let iPhoneDefault = ToolbarLayoutConfig(
        version: currentVersion,
        mainRow: [
            .builtIn(.dismiss),
            .builtIn(.tabSwitcher),
            .builtIn(.esc),
            .builtIn(.ctrl),
            .builtIn(.writingAssistance),
            .builtIn(.shift),
            .builtIn(.tab),
            .builtIn(.arrowDrawerToggle),
            .builtIn(.drawerToggle),
            .builtIn(.toolbarSettings),
        ],
        drawerRows: [[
            .builtIn(.alt),
            .builtIn(.cmd),
            .builtIn(.backtick),
            .builtIn(.tilde),
            .builtIn(.caret),
            .builtIn(.underscore),
            .builtIn(.backslash),
            .builtIn(.pipe),
            .builtIn(.leftBracket),
            .builtIn(.rightBracket),
            .builtIn(.leftBrace),
            .builtIn(.rightBrace),
            .builtIn(.slash),
            .builtIn(.questionMark),
            .builtIn(.dash),
            .builtIn(.equals),
            .builtIn(.singleQuote),
            .builtIn(.doubleQuote),
            .builtIn(.leftParen),
            .builtIn(.rightParen),
            .builtIn(.atSign),
            .builtIn(.hash),
            .builtIn(.dollar),
            .builtIn(.percent),
            .builtIn(.semicolon),
            .builtIn(.colon),
            .builtIn(.lessThan),
            .builtIn(.greaterThan),
            .builtIn(.ampersand),
            .builtIn(.asterisk),
            .builtIn(.paste),
            .builtIn(.compose),
            .builtIn(.voiceAgent),
            .builtIn(.toggleFullScreen),
            .builtIn(.toggleTabBar),
            .builtIn(.newConnection),
            .builtIn(.toggleMouseCapture),
            .builtIn(.aiAgent),
            .builtIn(.brightnessBoost),
            .builtIn(.clipboardManager),
            .builtIn(.appSettings),
        ]],
        hiddenKeys: []
    )

    public static let iPadDefault = ToolbarLayoutConfig(
        version: currentVersion,
        mainRow: iPhoneDefault.mainRow + [
            .builtIn(.alt),
            .builtIn(.cmd),
            .builtIn(.backtick),
            .builtIn(.dash),
            .builtIn(.slash),
            .builtIn(.singleQuote),
            .builtIn(.semicolon),
            .builtIn(.leftBracket),
            .builtIn(.rightBracket),
        ],
        drawerRows: [[
            .builtIn(.tilde),
            .builtIn(.caret),
            .builtIn(.underscore),
            .builtIn(.backslash),
            .builtIn(.pipe),
            .builtIn(.leftBrace),
            .builtIn(.rightBrace),
            .builtIn(.lessThan),
            .builtIn(.greaterThan),
            .builtIn(.questionMark),
            .builtIn(.equals),
            .builtIn(.doubleQuote),
            .builtIn(.colon),
            .builtIn(.leftParen),
            .builtIn(.rightParen),
            .builtIn(.atSign),
            .builtIn(.hash),
            .builtIn(.dollar),
            .builtIn(.percent),
            .builtIn(.ampersand),
            .builtIn(.asterisk),
            .builtIn(.paste),
            .builtIn(.compose),
            .builtIn(.voiceAgent),
            .builtIn(.toggleFullScreen),
            .builtIn(.toggleTabBar),
            .builtIn(.newConnection),
            .builtIn(.toggleMouseCapture),
            .builtIn(.aiAgent),
            .builtIn(.brightnessBoost),
            .builtIn(.clipboardManager),
            .builtIn(.appSettings),
        ]],
        hiddenKeys: []
    )

    // MARK: - Migration

    public static func migrate(_ saved: ToolbarLayoutConfig, idiom: UIUserInterfaceIdiom) -> ToolbarLayoutConfig {
        guard saved.version < currentVersion else { return saved }

        let defaults = defaultConfig(for: idiom)
        var migrated = saved
        if migrated.drawerRows.isEmpty { migrated.drawerRows = [[]] }

        var previousDefaults = defaults
        previousDefaults.version = saved.version
        if idiom == .pad {
            previousDefaults.mainRow.removeAll { $0 == .builtIn(.alt) || $0 == .builtIn(.cmd) }
            previousDefaults.mainRow.insert(.builtIn(.alt), at: 4)
            previousDefaults.mainRow.removeAll { $0 == .builtIn(.writingAssistance) }
            previousDefaults.mainRow.insert(contentsOf: [.builtIn(.cmd), .builtIn(.writingAssistance)], at: 6)
        }
        if saved.version < 13 {
            previousDefaults.mainRow = previousDefaults.mainRow.map {
                $0 == .builtIn(.writingAssistance) ? .builtIn(.compose) : $0
            }
            for row in previousDefaults.drawerRows.indices {
                previousDefaults.drawerRows[row].removeAll { $0 == .builtIn(.compose) }
            }
            if saved.version == 12,
               let composeIndex = previousDefaults.mainRow.firstIndex(of: .builtIn(.compose)) {
                previousDefaults.mainRow.insert(.builtIn(.writingAssistance), at: composeIndex + 1)
            }
        }
        if (11...13).contains(saved.version), saved == previousDefaults {
            return defaults
        }

        if saved.version < 3 && !saved.hiddenKeys.contains(.toolbarSettings) {
            migrated.mainRow.removeAll { $0 == .builtIn(.toolbarSettings) }
            for i in migrated.drawerRows.indices {
                migrated.drawerRows[i].removeAll { $0 == .builtIn(.toolbarSettings) }
            }

            if let toggleIndex = migrated.mainRow.firstIndex(of: .builtIn(.drawerToggle)) {
                migrated.mainRow.insert(.builtIn(.toolbarSettings), at: toggleIndex + 1)
            } else {
                migrated.mainRow.append(.builtIn(.toolbarSettings))
            }
        }

        let savedKeyIDs = Set(
            (migrated.mainRow + migrated.drawerRows.flatMap { $0 }).compactMap(\.keyID)
        )

        let defaultMainKeyIDs = defaults.mainRow.compactMap(\.keyID)
        let defaultDrawerKeyIDs = defaults.drawerRows.flatMap { $0 }.compactMap(\.keyID)

        for keyID in defaultMainKeyIDs where !savedKeyIDs.contains(keyID) && !saved.hiddenKeys.contains(keyID) {
            migrated.mainRow.append(.builtIn(keyID))
        }
        for keyID in defaultDrawerKeyIDs where !savedKeyIDs.contains(keyID) && !saved.hiddenKeys.contains(keyID) {
            migrated.drawerRows[0].append(.builtIn(keyID))
        }

        let validKeyIDs = Set(KeyID.allCases)
        migrated.mainRow.removeAll { slot in
            if let keyID = slot.keyID { return !validKeyIDs.contains(keyID) }
            return false
        }
        for i in migrated.drawerRows.indices {
            migrated.drawerRows[i].removeAll { slot in
                if let keyID = slot.keyID { return !validKeyIDs.contains(keyID) }
                return false
            }
        }
        migrated.hiddenKeys = migrated.hiddenKeys.filter { validKeyIDs.contains($0) }

        if migrated.drawerRows.isEmpty {
            migrated.drawerRows = [[]]
        }

        migrated.version = currentVersion
        return migrated
    }
}

extension ToolbarLayoutConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case version
        case mainRow
        case drawerRows
        case drawerRow
        case hiddenKeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        mainRow = try container.decode([KeySlot].self, forKey: .mainRow)
        hiddenKeys = try container.decode(Set<KeyID>.self, forKey: .hiddenKeys)
        if let rows = try container.decodeIfPresent([[KeySlot]].self, forKey: .drawerRows) {
            drawerRows = rows.isEmpty ? [[]] : rows
        } else {
            drawerRows = [try container.decodeIfPresent([KeySlot].self, forKey: .drawerRow) ?? []]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(mainRow, forKey: .mainRow)
        try container.encode(drawerRows, forKey: .drawerRows)
        try container.encode(drawerRows[0], forKey: .drawerRow)
        try container.encode(hiddenKeys, forKey: .hiddenKeys)
    }
}

// MARK: - CustomKey

/// A user-defined key that sends an arbitrary sequence of key combos and text.
public struct CustomKey: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var label: String
    public var iconName: String?
    public var sequence: [SequenceStep]

    public init(id: UUID = UUID(), label: String, iconName: String? = nil, sequence: [SequenceStep] = []) {
        self.id = id
        self.label = label
        self.iconName = iconName
        self.sequence = sequence
    }

    /// Concatenate all steps into a single Data payload for writing to the terminal.
    public func terminalData() -> Data {
        var result = Data()
        for step in sequence {
            result.append(step.terminalData())
        }
        return result
    }

    /// Human-readable summary of the sequence (e.g. "Ctrl+B -> Return")
    public var sequenceSummary: String {
        sequence.map(\.displayText).joined(separator: " \u{2192} ")
    }

    /// If this key is a single plain character with no baked-in modifiers, return it.
    public var plainCharacter: Character? {
        guard sequence.count == 1 else { return nil }
        switch sequence[0] {
        case .text(let s):
            return s.count == 1 ? s.first : nil
        case .keyCombo(let combo):
            guard combo.modifiers.isEmpty else { return nil }
            switch combo.key {
            case .letter(let c), .digit(let c), .symbol(let c):
                return c
            case .special:
                return nil
            }
        }
    }
}

// MARK: - SequenceStep

/// One step in a custom key's sequence — either a key combination or raw text.
public enum SequenceStep: Codable, Hashable, Sendable {
    case keyCombo(KeyCombo)
    case text(String)

    public struct KeyCombo: Codable, Hashable, Sendable {
        public var modifiers: Set<KeyModifier>
        public var key: ComboKey

        public init(modifiers: Set<KeyModifier>, key: ComboKey) {
            self.modifiers = modifiers
            self.key = key
        }

        public var displayText: String {
            let modGlyphs = KeyModifier.allCases
                .filter { modifiers.contains($0) }
                .map(\.displayGlyph)
            return (modGlyphs + [key.displayText]).joined(separator: "")
        }

        public func terminalData() -> Data {
            let hasCtrl = modifiers.contains(.ctrl)
            let hasAlt = modifiers.contains(.alt)
            let hasShift = modifiers.contains(.shift)

            switch key {
            case .letter(let c):
                return letterData(c, ctrl: hasCtrl, alt: hasAlt, shift: hasShift)
            case .digit(let c):
                return characterData(c, ctrl: hasCtrl, alt: hasAlt, shift: hasShift)
            case .symbol(let c):
                return characterData(c, ctrl: hasCtrl, alt: hasAlt, shift: hasShift)
            case .special(let specialKey):
                return specialKeyData(specialKey, ctrl: hasCtrl, alt: hasAlt, shift: hasShift)
            }
        }

        private func letterData(_ char: Character, ctrl: Bool, alt: Bool, shift: Bool) -> Data {
            let lower = char.lowercased().first ?? char
            var byte = lower.asciiValue ?? 0

            if ctrl {
                byte = byte - 0x60
            } else if shift {
                byte = (char.uppercased().first ?? char).asciiValue ?? byte
            }

            if alt {
                return Data([0x1B, byte])
            }
            return Data([byte])
        }

        private func characterData(_ char: Character, ctrl: Bool, alt: Bool, shift: Bool) -> Data {
            guard let byte = char.asciiValue else {
                return Data(String(char).utf8)
            }
            var result = byte
            if ctrl {
                if byte >= 0x40 && byte <= 0x7F {
                    result = byte & 0x1F
                }
            }
            if alt {
                return Data([0x1B, result])
            }
            return Data([result])
        }

        private func specialKeyData(_ key: SpecialKey, ctrl: Bool, alt: Bool, shift: Bool) -> Data {
            let hasModifiers = ctrl || alt || shift
            guard hasModifiers else {
                return key.baseData
            }

            var modParam = 1
            if shift { modParam += 1 }
            if alt { modParam += 2 }
            if ctrl { modParam += 4 }

            if let code = key.csiCode {
                return Data("\u{1B}[1;\(modParam)\(code)".utf8)
            }
            if let tildeCode = key.csiTildeCode {
                return Data("\u{1B}[\(tildeCode);\(modParam)~".utf8)
            }

            switch key {
            case .returnKey:
                if alt { return Data([0x1B, 0x0D]) }
                return Data([0x0D])
            case .tab:
                if shift { return Data([0x1B, 0x5B, 0x5A]) }
                if alt { return Data([0x1B, 0x09]) }
                return Data([0x09])
            case .escape:
                if alt { return Data([0x1B, 0x1B]) }
                return Data([0x1B])
            case .space:
                if ctrl { return Data(alt ? [0x1B, 0x00] : [0x00]) }
                if alt { return Data([0x1B, 0x20]) }
                return Data([0x20])
            case .backspace:
                if alt { return Data([0x1B, 0x7F]) }
                if ctrl { return Data([0x08]) }
                return Data([0x7F])
            default:
                return key.baseData
            }
        }
    }

    public enum KeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
        case ctrl
        case alt
        case shift
        case cmd

        public var displayGlyph: String {
            switch self {
            case .ctrl: return "\u{2303}"   // ⌃
            case .alt: return "\u{2325}"    // ⌥
            case .shift: return "\u{21E7}"  // ⇧
            case .cmd: return "\u{2318}"    // ⌘
            }
        }

        public var displayName: String {
            switch self {
            case .ctrl: return "Ctrl"
            case .alt: return "Alt"
            case .shift: return "Shift"
            case .cmd: return "Cmd"
            }
        }
    }

    public enum ComboKey: Codable, Hashable, Sendable {
        case letter(Character)
        case digit(Character)
        case symbol(Character)
        case special(SpecialKey)

        public var displayText: String {
            switch self {
            case .letter(let c): return String(c).uppercased()
            case .digit(let c): return String(c)
            case .symbol(let c): return String(c)
            case .special(let key): return key.displayName
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, value
        }

        private enum CodableType: String, Codable {
            case letter, digit, symbol, special
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .letter(let c):
                try container.encode(CodableType.letter, forKey: .type)
                try container.encode(String(c), forKey: .value)
            case .digit(let c):
                try container.encode(CodableType.digit, forKey: .type)
                try container.encode(String(c), forKey: .value)
            case .symbol(let c):
                try container.encode(CodableType.symbol, forKey: .type)
                try container.encode(String(c), forKey: .value)
            case .special(let key):
                try container.encode(CodableType.special, forKey: .type)
                try container.encode(key, forKey: .value)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(CodableType.self, forKey: .type)
            switch type {
            case .letter:
                let s = try container.decode(String.self, forKey: .value)
                self = .letter(s.first ?? "a")
            case .digit:
                let s = try container.decode(String.self, forKey: .value)
                self = .digit(s.first ?? "0")
            case .symbol:
                let s = try container.decode(String.self, forKey: .value)
                self = .symbol(s.first ?? "-")
            case .special:
                let key = try container.decode(SpecialKey.self, forKey: .value)
                self = .special(key)
            }
        }
    }

    public enum SpecialKey: String, Codable, CaseIterable, Hashable, Sendable {
        case returnKey
        case tab
        case escape
        case space
        case backspace
        case delete
        case arrowUp
        case arrowDown
        case arrowLeft
        case arrowRight
        case home
        case end
        case pageUp
        case pageDown

        public var displayName: String {
            switch self {
            case .returnKey: return "Return"
            case .tab: return "Tab"
            case .escape: return "Escape"
            case .space: return "Space"
            case .backspace: return "Backspace"
            case .delete: return "Delete"
            case .arrowUp: return "Arrow Up"
            case .arrowDown: return "Arrow Down"
            case .arrowLeft: return "Arrow Left"
            case .arrowRight: return "Arrow Right"
            case .home: return "Home"
            case .end: return "End"
            case .pageUp: return "Page Up"
            case .pageDown: return "Page Down"
            }
        }

        public var displayGlyph: String {
            switch self {
            case .returnKey: return "\u{23CE}"  // ⏎
            case .tab: return "\u{21E5}"        // ⇥
            case .escape: return "\u{238B}"     // ⎋
            case .space: return "\u{2423}"      // ␣
            case .backspace: return "\u{232B}"  // ⌫
            case .delete: return "\u{2326}"     // ⌦
            case .arrowUp: return "\u{2191}"    // ↑
            case .arrowDown: return "\u{2193}"  // ↓
            case .arrowLeft: return "\u{2190}"  // ←
            case .arrowRight: return "\u{2192}" // →
            case .home: return "Home"
            case .end: return "End"
            case .pageUp: return "PgUp"
            case .pageDown: return "PgDn"
            }
        }

        public var baseData: Data {
            switch self {
            case .returnKey: return Data([0x0D])
            case .tab: return Data([0x09])
            case .escape: return Data([0x1B])
            case .space: return Data([0x20])
            case .backspace: return Data([0x7F])
            case .delete: return Data([0x1B, 0x5B, 0x33, 0x7E])     // ESC[3~
            case .arrowUp: return Data([0x1B, 0x5B, 0x41])          // ESC[A
            case .arrowDown: return Data([0x1B, 0x5B, 0x42])        // ESC[B
            case .arrowLeft: return Data([0x1B, 0x5B, 0x44])        // ESC[D
            case .arrowRight: return Data([0x1B, 0x5B, 0x43])       // ESC[C
            case .home: return Data([0x1B, 0x5B, 0x48])             // ESC[H
            case .end: return Data([0x1B, 0x5B, 0x46])              // ESC[F
            case .pageUp: return Data([0x1B, 0x5B, 0x35, 0x7E])     // ESC[5~
            case .pageDown: return Data([0x1B, 0x5B, 0x36, 0x7E])   // ESC[6~
            }
        }

        public var csiCode: String? {
            switch self {
            case .arrowUp: return "A"
            case .arrowDown: return "B"
            case .arrowRight: return "C"
            case .arrowLeft: return "D"
            case .home: return "H"
            case .end: return "F"
            default: return nil
            }
        }

        public var csiTildeCode: String? {
            switch self {
            case .delete: return "3"
            case .pageUp: return "5"
            case .pageDown: return "6"
            default: return nil
            }
        }
    }

    public func terminalData() -> Data {
        switch self {
        case .text(let string):
            return Data(string.utf8)
        case .keyCombo(let combo):
            return combo.terminalData()
        }
    }

    public var displayText: String {
        switch self {
        case .text(let string):
            return "\"\(string)\""
        case .keyCombo(let combo):
            return combo.displayText
        }
    }
}
#endif
