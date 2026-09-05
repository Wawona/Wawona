#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import WawonaModel

/// SwiftUI bridge over the shared ObjC settings inventory (`WWNPreferences`
/// `buildSections`). Reads and writes the exact `NSUserDefaults` keys the
/// AppKit settings window used, so the unified SwiftUI window and the iOS
/// settings UI stay in sync on one source of truth.
///
/// Write semantics mirror `WWNPreferencesContent act:` (switch/popup commit,
/// auth-method integer storage, section rebuilds, iCloud routing).
@MainActor
final class WWNSettingsValueModel: ObservableObject {
    static let shared = WWNSettingsValueModel()

    /// Snapshot of `WWNPreferences.sections`. Rebuilt when a change invalidates
    /// the section layout (SSH auth method, virtual cursor).
    @Published private(set) var sections: [WWNPreferencesSection] = []

    private let defaults = UserDefaults.standard
    private var observers: [NSObjectProtocol] = []

    /// Keys whose change rebuilds `WWNPreferences.sections` (matching the
    /// AppKit `act:` behavior).
    private let sectionRebuildKeys: Set<String> = [
        "SSHAuthMethod",
        "WaypipeSSHAuthMethod",
        kWWNPrefsRenderMacOSPointer,
    ]

    init() {
        reloadSections()
        observers = [
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.objectWillChange.send()
            },
            NotificationCenter.default.addObserver(
                forName: .wawonaPreferencesDidSave,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.objectWillChange.send()
            },
        ]
    }

    func reloadSections() {
        sections = WWNPreferences.shared().sections
    }

    // MARK: - Item accessors (KVC: ObjC items are declared nonnull but some
    // rows are built with nil key/desc, which would trap on direct access).

    func itemTitle(_ item: WWNSettingItem) -> String {
        item.value(forKey: "title") as? String ?? ""
    }

    func itemDescription(_ item: WWNSettingItem) -> String {
        item.value(forKey: "desc") as? String ?? ""
    }

    func itemKey(_ item: WWNSettingItem) -> String {
        item.value(forKey: "key") as? String ?? ""
    }

    private func options(_ item: WWNSettingItem) -> [String] {
        item.value(forKey: "options") as? [String] ?? []
    }

    private func optionValues(_ item: WWNSettingItem) -> [String] {
        item.value(forKey: "optionValues") as? [String] ?? []
    }

    private func itemDefault(_ item: WWNSettingItem) -> Any? {
        item.value(forKey: "defaultValue")
    }

    private func isAuthMethodKey(_ key: String) -> Bool {
        key == "SSHAuthMethod" || key == "WaypipeSSHAuthMethod"
    }

    // MARK: - Value reads

    func stringValue(for item: WWNSettingItem) -> String {
        let key = itemKey(item)
        if !key.isEmpty, let stored = defaults.string(forKey: key) {
            return stored
        }
        if let def = itemDefault(item) {
            return String(describing: def)
        }
        return ""
    }

    func boolValue(for item: WWNSettingItem) -> Bool {
        defaults.bool(forKey: itemKey(item))
    }

    func popupOptions(for item: WWNSettingItem) -> [String] {
        options(item)
    }

    /// Selected index for a popup row: stored integer for auth-method keys,
    /// otherwise the stored optionValue / option title.
    func popupIndex(for item: WWNSettingItem) -> Int {
        let opts = options(item)
        guard !opts.isEmpty else { return 0 }
        let key = itemKey(item)
        if isAuthMethodKey(key) {
            let idx = defaults.integer(forKey: key)
            return idx >= 0 && idx < opts.count ? idx : 0
        }
        let stored = stringValue(for: item)
        let vals = optionValues(item)
        if !vals.isEmpty {
            if let i = vals.firstIndex(of: stored) { return i }
            if let i = opts.firstIndex(of: stored) { return i }
        } else if let i = opts.firstIndex(of: stored) {
            return i
        }
        if let def = itemDefault(item) as? String, let i = opts.firstIndex(of: def) {
            return i
        }
        return 0
    }

    /// True when a password row has a stored value (button shows "Change…").
    func hasPassword(for item: WWNSettingItem) -> Bool {
        let prefs = WWNPreferencesManager.shared()
        switch itemKey(item) {
        case "WaypipeSSHPassword", "SSHPassword":
            let waypipe = prefs.value(forKey: "waypipeSSHPassword") as? String
            let ssh = prefs.value(forKey: "sshPassword") as? String
            return !((waypipe?.isEmpty == false) ? waypipe! : (ssh ?? "")).isEmpty
        case "WaypipeSSHKeyPassphrase", "SSHKeyPassphrase":
            let waypipe = prefs.value(forKey: "waypipeSSHKeyPassphrase") as? String
            let ssh = prefs.value(forKey: "sshKeyPassphrase") as? String
            return !((waypipe?.isEmpty == false) ? waypipe! : (ssh ?? "")).isEmpty
        default:
            return false
        }
    }

    // MARK: - Value writes (mirror `act:`)

    func setString(_ value: String, for item: WWNSettingItem) {
        let key = itemKey(item)
        guard !key.isEmpty else { return }
        defaults.set(value, forKey: key)
        commit(rebuild: false)
    }

    func setBool(_ value: Bool, for item: WWNSettingItem) {
        let key = itemKey(item)
        guard !key.isEmpty else { return }
        if key == WWNRootfsICloudSyncPreferenceKey {
            // iCloud sync is routed through the rootfs provider (it can fail).
            // ObjC `NSError **` imports as `throws` in Swift.
            do {
                try WWNRootfsProvider.setICloudSyncEnabled(value)
            } catch {
                let alert = NSAlert()
                alert.messageText = "iCloud Sync Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
            commit(rebuild: false)
            return
        }
        defaults.set(value, forKey: key)
        if key == "ForceServerSideDecorations" {
            // Live compositor reaction (same notification WawonaPreferences
            // save() posts for the SwiftUI machine settings).
            NotificationCenter.default.post(
                name: NSNotification.Name.wwnForceSSDChanged,
                object: nil
            )
        }
        commit(rebuild: sectionRebuildKeys.contains(key))
    }

    func setPopupIndex(_ index: Int, for item: WWNSettingItem) {
        let key = itemKey(item)
        guard !key.isEmpty else { return }
        let opts = options(item)
        guard index >= 0 && index < opts.count else { return }
        if isAuthMethodKey(key) {
            defaults.set(index, forKey: key)
        } else {
            let vals = optionValues(item)
            let value = vals.isEmpty ? opts[index] : vals[index]
            defaults.set(value, forKey: key)
        }
        commit(rebuild: sectionRebuildKeys.contains(key))
    }

    func setPassword(_ password: String, for item: WWNSettingItem) {
        // Same WWNPreferencesManager setters the AppKit password dialog used.
        // (The manager exposes getter/setter method pairs, not @properties.)
        let prefs = WWNPreferencesManager.shared()
        switch itemKey(item) {
        case "WaypipeSSHPassword":
            prefs.setWaypipeSSHPassword(password)
        case "WaypipeSSHKeyPassphrase":
            prefs.setWaypipeSSHKeyPassphrase(password)
        case "SSHPassword":
            prefs.setSshPassword(password)
        case "SSHKeyPassphrase":
            prefs.setSshKeyPassphrase(password)
        default:
            break
        }
        commit(rebuild: false)
    }

    /// Keep every reader in sync after a defaults write: refresh the Swift
    /// `WawonaPreferences` in-memory model (per-machine editors read it) and
    /// post the same notifications the AppKit window posted.
    private func commit(rebuild: Bool) {
        if rebuild {
            WWNPreferences.shared().rebuildSections()
            reloadSections()
        }
        WawonaPreferences.shared.load()
        NotificationCenter.default.post(
            name: Notification.Name("WWNPreferencesChanged"),
            object: nil
        )
        NotificationCenter.default.post(name: .wawonaPreferencesDidSave, object: nil)
    }

    // MARK: - Row helpers

    func placeholder(for item: WWNSettingItem) -> String? {
        let key = itemKey(item)
        if key == "WaypipeRemoteCommand" { return "e.g. weston-simple-shm" }
        if key.contains("Host") { return "Remote host address" }
        if key.contains("User") { return "SSH username" }
        if key.contains("Path") { return "Enter path..." }
        return nil
    }

    func copyValueToPasteboard(_ item: WWNSettingItem) {
        let value = stringValue(for: item)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    // MARK: - Bindings

    func boolBinding(for item: WWNSettingItem) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.boolValue(for: item) ?? false },
            set: { [weak self] newValue in self?.setBool(newValue, for: item) }
        )
    }

    func stringBinding(for item: WWNSettingItem) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.stringValue(for: item) ?? "" },
            set: { [weak self] newValue in self?.setString(newValue, for: item) }
        )
    }

    func popupBinding(for item: WWNSettingItem) -> Binding<Int> {
        Binding(
            get: { [weak self] in self?.popupIndex(for: item) ?? 0 },
            set: { [weak self] newIndex in self?.setPopupIndex(newIndex, for: item) }
        )
    }
}
#endif
