#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
/// Not `@MainActor`: iOS/tvOS/visionOS construct this from an ObjC trampoline.
final class WWNSettingsValueModel: ObservableObject {
    static let shared = WWNSettingsValueModel()

    /// Snapshot of `WWNPreferences.sections`. Rebuilt when a change invalidates
    /// the section layout (SSH auth method, virtual cursor).
    @Published private(set) var sections: [WWNPreferencesSection] = []

    private let defaults = UserDefaults.standard
    private let globalSnapshotKey = "wawona.globalSettingsSnapshot.v1"
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
        seedGlobalSnapshotIfNeeded()
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
        if !key.isEmpty, let stored = defaults.object(forKey: key) {
            if let string = stored as? String {
                return string
            }
            if let number = stored as? NSNumber {
                return number.stringValue
            }
        }
        if let def = itemDefault(item) {
            return String(describing: def)
        }
        return ""
    }

    func boolValue(for item: WWNSettingItem) -> Bool {
        let key = itemKey(item)
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return (itemDefault(item) as? NSNumber)?.boolValue ?? false
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
        recordGlobalValue(value, forKey: key)
        commit(rebuild: false)
    }

    func integerValue(for item: WWNSettingItem) -> Int {
        let spec = numberSpec(for: item)
        let parsed = Int(stringValue(for: item)) ?? spec.defaultValue
        return min(max(parsed, spec.range.lowerBound), spec.range.upperBound)
    }

    func setInteger(_ value: Int, for item: WWNSettingItem) {
        let key = itemKey(item)
        guard !key.isEmpty else { return }
        let spec = numberSpec(for: item)
        let clamped = min(max(value, spec.range.lowerBound), spec.range.upperBound)
        if key == "SSHPort" {
            WWNPreferencesManager.shared().setSshPort(clamped)
        } else {
            defaults.set(clamped, forKey: key)
        }
        recordGlobalValue(clamped, forKey: key)
        commit(rebuild: false)
    }

    func setNumberText(_ text: String, for item: WWNSettingItem) {
        let spec = numberSpec(for: item)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && spec.allowsEmpty {
            defaults.removeObject(forKey: itemKey(item))
            recordGlobalValue("", forKey: itemKey(item))
            commit(rebuild: false)
            return
        }
        setInteger(Int(trimmed) ?? spec.defaultValue, for: item)
    }

    func setBool(_ value: Bool, for item: WWNSettingItem) {
        let key = itemKey(item)
        guard !key.isEmpty else { return }
        #if !os(tvOS)
        if key == WWNRootfsICloudSyncPreferenceKey {
            // iCloud sync is routed through the rootfs provider (it can fail).
            // ObjC `NSError **` imports as `throws` in Swift. tvOS has no Drive.
            do {
                try WWNRootfsProvider.setICloudSyncEnabled(value)
            } catch {
                #if os(macOS)
                let alert = NSAlert()
                alert.messageText = "iCloud Sync Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                #endif
            }
            commit(rebuild: false)
            return
        }
        #endif
        defaults.set(value, forKey: key)
        recordGlobalValue(value, forKey: key)
        if key == "ForceServerSideDecorations" {
            // Live compositor reaction (same notification WawonaPreferences
            // save() posts for the SwiftUI machine settings).
            NotificationCenter.default.post(
                name: Notification.Name("WWNForceSSDChangedNotification"),
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
            recordGlobalValue(index, forKey: key)
        } else {
            let vals = optionValues(item)
            let value = vals.isEmpty ? opts[index] : vals[index]
            defaults.set(value, forKey: key)
            recordGlobalValue(value, forKey: key)
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
        recordGlobalValue(password, forKey: itemKey(item))
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
        Task { @MainActor in
            WawonaPreferences.shared.load()
        }
        NotificationCenter.default.post(
            name: Notification.Name("WWNPreferencesChanged"),
            object: nil
        )
        NotificationCenter.default.post(name: .wawonaPreferencesDidSave, object: nil)
    }

    private func recordGlobalValue(_ value: Any, forKey key: String) {
        var snapshot = defaults.dictionary(forKey: globalSnapshotKey) ?? [:]
        snapshot[key] = value
        defaults.set(snapshot, forKey: globalSnapshotKey)
    }

    private func seedGlobalSnapshotIfNeeded() {
        guard defaults.dictionary(forKey: globalSnapshotKey) == nil else { return }
        var snapshot: [String: Any] = [:]
        for section in sections {
            for item in section.items {
                let key = itemKey(item)
                guard !key.isEmpty else { continue }
                if let stored = defaults.object(forKey: key) {
                    snapshot[key] = stored
                } else if let defaultValue = itemDefault(item) {
                    snapshot[key] = defaultValue
                }
            }
        }
        defaults.set(snapshot, forKey: globalSnapshotKey)
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

    struct NumberSpec {
        let range: ClosedRange<Int>
        let defaultValue: Int
        let allowsEmpty: Bool
    }

    func numberSpec(for item: WWNSettingItem) -> NumberSpec {
        switch itemKey(item) {
        case "SSHPort", "MachineVMVsockPort", "ContainerVsockPort":
            return NumberSpec(
                range: 1...65535,
                defaultValue: itemKey(item) == "SSHPort" ? 22 : 1024,
                allowsEmpty: false
            )
        case "WaylandDisplayNumber":
            return NumberSpec(range: 0...255, defaultValue: 0, allowsEmpty: false)
        case "WaypipeCompressLevel":
            return NumberSpec(range: 1...22, defaultValue: 7, allowsEmpty: false)
        case "WaypipeThreads":
            return NumberSpec(range: 0...64, defaultValue: 0, allowsEmpty: false)
        case "WaypipeVideoBpf":
            return NumberSpec(
                range: 1_000...100_000,
                defaultValue: 5_000,
                allowsEmpty: true
            )
        default:
            return NumberSpec(range: 0...65_535, defaultValue: 0, allowsEmpty: false)
        }
    }

    func actionPresentation(for item: WWNSettingItem) -> (title: String, systemImage: String) {
        switch itemKey(item) {
        case "EnvironmentManage": return ("Open", "list.bullet.rectangle")
        case "RootfsResetDotfiles": return ("Reset", "arrow.counterclockwise")
        case "RootfsReinstallSystem": return ("Reset", "arrow.counterclockwise")
        case "RootfsImportFile": return ("Import", "square.and.arrow.down")
        case "WatchCompanionSend": return ("Choose File", "applewatch.and.arrow.forward")
        case "DesktopReplacementSipHowTo": return ("Learn More", "info.circle")
        case "DesktopReplacementTakeOver": return ("Replace Now", "rectangle.inset.filled")
        case "WaypipePreview": return ("Preview", "terminal")
        case "SSHPingHost": return ("Ping", "network")
        case "SSHTestConnection": return ("Test", "checkmark.shield")
        case "SSHGenerateKey": return ("Generate", "key")
        case "SSHImportGPGKey": return ("Import", "square.and.arrow.down")
        case "CopyRecentLogs", "CopyMachineLogs": return ("Copy", "doc.on.doc")
        case "ReportGitHubIssue": return ("Report", "ladybug")
        default: return ("Run", "play")
        }
    }

    func linkPresentation(for item: WWNSettingItem) -> (title: String, systemImage: String) {
        let configured = item.value(forKey: "buttonTitle") as? String
        return (configured?.isEmpty == false ? configured! : "Open", "arrow.up.right.square")
    }

    func copyValueToPasteboard(_ item: WWNSettingItem) {
        let value = stringValue(for: item)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #elseif !os(tvOS)
        UIPasteboard.general.string = value
        #endif
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

    func integerBinding(for item: WWNSettingItem) -> Binding<Int> {
        Binding(
            get: { [weak self] in self?.integerValue(for: item) ?? 0 },
            set: { [weak self] newValue in self?.setInteger(newValue, for: item) }
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
