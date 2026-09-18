#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  KeyboardToolbarManager.swift
//  Wawona
//
//  Manages keyboard toolbar layout customization and custom keys.
//  Persists configuration to UserDefaults and notifies observers on changes.
//  Ported 1:1 from rootshell.
//

import Foundation
import SwiftUI
import Observation
import os

@MainActor
@Observable
public class KeyboardToolbarManager {
    public static let shared = KeyboardToolbarManager()

    private nonisolated static let logger = Logger(subsystem: "io.wawona.Wawona", category: "KeyboardToolbarManager")

    public static let layoutDidChangeNotification = Notification.Name("KeyboardToolbarLayoutDidChange")

    // MARK: - Storage Keys

    private static let configStorageKey = "keyboardToolbarConfig"
    private static let customKeysStorageKey = "keyboardToolbarCustomKeys"
    private static let drawerOpenByDefaultKey = "keyboardToolbarDrawerOpenByDefault"
    private static let drawerToggleModeKey = "keyboardToolbarDrawerToggleMode"
    private static let deviceIdiomKey = "keyboardToolbarDeviceIdiom"

    @ObservationIgnored private var isReloading = false

    // MARK: - Observable Properties

    public private(set) var config: ToolbarLayoutConfig {
        didSet {
            guard !isReloading else { return }
            saveConfig()
        }
    }

    public private(set) var customKeys: [CustomKey] {
        didSet {
            guard !isReloading else { return }
            saveCustomKeys()
        }
    }

    public var drawerOpenByDefault: Bool {
        didSet {
            guard !isReloading else { return }
            UserDefaults.standard.set(drawerOpenByDefault, forKey: Self.drawerOpenByDefaultKey)
        }
    }

    /// How the "…" button steps through multiple drawer rows (stack vs cycle).
    public var drawerToggleMode: DrawerToggleMode {
        didSet {
            guard !isReloading else { return }
            UserDefaults.standard.set(drawerToggleMode.rawValue, forKey: Self.drawerToggleModeKey)
        }
    }

    // MARK: - Computed Properties

    public var isCustomized: Bool {
        let defaults = ToolbarLayoutConfig.defaultConfig(for: currentIdiom)
        return config != defaults || !customKeys.isEmpty
    }

    private var currentIdiom: UIUserInterfaceIdiom {
        UIDevice.current.userInterfaceIdiom
    }

    // MARK: - Initialization

    private init() {
        let idiom = UIDevice.current.userInterfaceIdiom
        config = Self.loadConfig(idiom: idiom)
        customKeys = Self.loadCustomKeys()
        drawerOpenByDefault = UserDefaults.standard.bool(forKey: Self.drawerOpenByDefaultKey)

        if let savedMode = UserDefaults.standard.string(forKey: Self.drawerToggleModeKey),
           let mode = DrawerToggleMode(rawValue: savedMode) {
            drawerToggleMode = mode
        } else {
            drawerToggleMode = .stack
        }

        let savedIdiom = UserDefaults.standard.string(forKey: Self.deviceIdiomKey)
        let currentIdiomString = idiom == .pad ? "pad" : "phone"
        if let savedIdiom, savedIdiom != currentIdiomString {
            config = ToolbarLayoutConfig.defaultConfig(for: idiom)
        }
        UserDefaults.standard.set(currentIdiomString, forKey: Self.deviceIdiomKey)
    }

    // MARK: - Layout Mutations

    public enum ToolbarSection: Equatable, Sendable {
        case mainRow
        case drawer(Int)
    }

    /// Maximum number of configurable drawer rows.
    public static let maxDrawerRows = 5

    /// Number of configured drawer rows (1...maxDrawerRows).
    public var drawerRowCount: Int { config.drawerRows.count }

    /// Grow or shrink the number of drawer rows.
    public func setDrawerRowCount(_ count: Int) {
        let target = max(1, min(Self.maxDrawerRows, count))
        guard target != config.drawerRows.count else { return }
        var rows = config.drawerRows
        if target > rows.count {
            rows.append(contentsOf: Array(repeating: [], count: target - rows.count))
        } else {
            let overflow = rows[target...].flatMap { $0 }
            rows = Array(rows.prefix(target))
            rows[target - 1].append(contentsOf: overflow)
        }
        config.drawerRows = rows
        notifyChange()
    }

    public func setLayout(mainRow newMain: [KeySlot], drawerRows newDrawers: [[KeySlot]]) {
        let drawers = newDrawers.isEmpty ? [[]] : newDrawers
        guard config.mainRow != newMain || config.drawerRows != drawers else { return }
        config.mainRow = newMain
        config.drawerRows = drawers
        notifyChange()
    }

    public func moveKeyToSection(_ slot: KeySlot, from: ToolbarSection, to: ToolbarSection) {
        guard from != to else { return }

        switch from {
        case .mainRow:
            config.mainRow.removeAll { $0 == slot }
        case .drawer:
            for i in config.drawerRows.indices {
                config.drawerRows[i].removeAll { $0 == slot }
            }
        }

        switch to {
        case .mainRow:
            config.mainRow.append(slot)
        case .drawer(let index):
            let clamped = max(0, min(config.drawerRows.count - 1, index))
            config.drawerRows[clamped].insert(slot, at: 0)
        }
        notifyChange()
    }

    public func hideKey(_ keyID: KeyID) {
        config.mainRow.removeAll { $0 == .builtIn(keyID) }
        for i in config.drawerRows.indices {
            config.drawerRows[i].removeAll { $0 == .builtIn(keyID) }
        }
        config.hiddenKeys.insert(keyID)
        notifyChange()
    }

    public func unhideKey(_ keyID: KeyID) {
        config.hiddenKeys.remove(keyID)
        config.drawerRows[0].append(.builtIn(keyID))
        notifyChange()
    }

    public func resetToDefaults() {
        config = ToolbarLayoutConfig.defaultConfig(for: currentIdiom)
        customKeys = []
        notifyChange()
    }

    // MARK: - Custom Key CRUD

    public func createCustomKey(_ key: CustomKey) {
        customKeys.append(key)
        config.drawerRows[0].append(.custom(key.id))
        notifyChange()
    }

    public func updateCustomKey(_ key: CustomKey) {
        if let index = customKeys.firstIndex(where: { $0.id == key.id }) {
            customKeys[index] = key
        }
        notifyChange()
    }

    public func deleteCustomKey(id: UUID) {
        customKeys.removeAll { $0.id == id }
        config.mainRow.removeAll { $0 == .custom(id) }
        for i in config.drawerRows.indices {
            config.drawerRows[i].removeAll { $0 == .custom(id) }
        }
        notifyChange()
    }

    public func customKey(for id: UUID) -> CustomKey? {
        customKeys.first { $0.id == id }
    }

    public var unplacedCustomKeys: [CustomKey] {
        let placedIDs = Set(
            (config.mainRow + config.drawerRows.flatMap { $0 }).compactMap { slot -> UUID? in
                if case .custom(let uuid) = slot { return uuid }
                return nil
            }
        )
        return customKeys.filter { !placedIDs.contains($0.id) }
    }

    public func removeCustomKeyFromLayout(id: UUID) {
        let slot = KeySlot.custom(id)
        config.mainRow.removeAll { $0 == slot }
        for i in config.drawerRows.indices {
            config.drawerRows[i].removeAll { $0 == slot }
        }
        notifyChange()
    }

    public func addCustomKeyToLayout(id: UUID, section: ToolbarSection) {
        guard customKey(for: id) != nil else { return }
        let slot = KeySlot.custom(id)
        guard !config.mainRow.contains(slot),
              !config.drawerRows.contains(where: { $0.contains(slot) }) else { return }
        switch section {
        case .mainRow:
            config.mainRow.append(slot)
        case .drawer(let index):
            let clamped = max(0, min(config.drawerRows.count - 1, index))
            config.drawerRows[clamped].append(slot)
        }
        notifyChange()
    }

    // MARK: - Capacity & Effective Layout

    private func minButtonWidth(for sizes: KeyboardSizes) -> CGFloat {
        sizes.button.normalWidth
    }

    public func mainRowCapacity(availableWidth: CGFloat) -> Int {
        let sizes = KeyboardSizes.current()
        let buttonWidth = minButtonWidth(for: sizes)
        guard buttonWidth > 0 else { return 0 }
        return max(1, Int(availableWidth / buttonWidth))
    }

    public func effectiveMainRowSlots(availableWidth: CGFloat) -> [KeySlot] {
        let capacity = mainRowCapacity(availableWidth: availableWidth)
        let allMainSlots = validSlots(config.mainRow)

        var visible = Array(allMainSlots.prefix(capacity))
        let overflow = Array(allMainSlots.dropFirst(capacity))
        var firstDrawer = overflow + validSlots(config.drawerRows[0])
        let anyDrawerContent = !firstDrawer.isEmpty
            || config.drawerRows.dropFirst().contains { !validSlots($0).isEmpty }

        if anyDrawerContent && !visible.contains(.builtIn(.drawerToggle)) && !config.hiddenKeys.contains(.drawerToggle) {
            if !visible.isEmpty {
                let lastSlot = visible[visible.count - 1]
                visible[visible.count - 1] = .builtIn(.drawerToggle)
                firstDrawer.insert(lastSlot, at: 0)
            } else {
                visible = [.builtIn(.drawerToggle)]
            }
        }

        return visible
    }

    public func effectiveDrawerRowSlots(availableWidth: CGFloat) -> [[KeySlot]] {
        let capacity = mainRowCapacity(availableWidth: availableWidth)
        let allMainSlots = validSlots(config.mainRow)

        var overflow = Array(allMainSlots.dropFirst(capacity))
        overflow.removeAll { $0 == .builtIn(.drawerToggle) }

        var rows = config.drawerRows.map { validSlots($0) }
        rows[0] = overflow + rows[0]
        return rows
    }

    private func validSlots(_ slots: [KeySlot]) -> [KeySlot] {
        let customIDs = Set(customKeys.map(\.id))
        return slots.filter { slot in
            switch slot {
            case .builtIn(let keyID):
                return !config.hiddenKeys.contains(keyID)
            case .custom(let uuid):
                return customIDs.contains(uuid)
            }
        }
    }

    // MARK: - Persistence

    private func saveConfig() {
        do {
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: Self.configStorageKey)
        } catch {
            Self.logger.error("Failed to save toolbar config: \(error.localizedDescription)")
        }
    }

    private func saveCustomKeys() {
        do {
            let data = try JSONEncoder().encode(customKeys)
            UserDefaults.standard.set(data, forKey: Self.customKeysStorageKey)
        } catch {
            Self.logger.error("Failed to save custom keys: \(error.localizedDescription)")
        }
    }

    private static func loadConfig(idiom: UIUserInterfaceIdiom) -> ToolbarLayoutConfig {
        guard let data = UserDefaults.standard.data(forKey: Self.configStorageKey) else {
            return ToolbarLayoutConfig.defaultConfig(for: idiom)
        }
        do {
            var config = try JSONDecoder().decode(ToolbarLayoutConfig.self, from: data)
            if config.version < ToolbarLayoutConfig.currentVersion {
                config = ToolbarLayoutConfig.migrate(config, idiom: idiom)
            }
            return config
        } catch {
            logger.error("Failed to load toolbar config: \(error.localizedDescription)")
            return ToolbarLayoutConfig.defaultConfig(for: idiom)
        }
    }

    private static func loadCustomKeys() -> [CustomKey] {
        guard let data = UserDefaults.standard.data(forKey: Self.customKeysStorageKey) else { return [] }
        do {
            return try JSONDecoder().decode([CustomKey].self, from: data)
        } catch {
            logger.error("Failed to load custom keys: \(error.localizedDescription)")
            return []
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.layoutDidChangeNotification, object: nil)
    }
}
#endif
