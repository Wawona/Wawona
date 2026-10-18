import CryptoKit
import Foundation

/// Device-local bookkeeping for CloudKit sync. Kept in a file, not
/// UserDefaults, so writing it never re-triggers a defaults sync.
struct CloudSyncState: Codable {
    struct Entry: Codable, Equatable {
        /// Current local content hash (`deleted` for a removed HOME file).
        var hash: String
        /// When the local content last changed (file mtime for HOME).
        var modified: Date
        /// Hash last confirmed in CloudKit. `nil` = never synced here.
        var synced: String?

        var needsPush: Bool { hash != synced }
    }

    static let deletedHash = "deleted"

    var zoneReady = false
    var subscriptionReady = false
    var changeToken: Data?
    var defaults: [String: Entry] = [:]
    var home: [String: Entry] = [:]

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func defaultsRecordName(_ key: String) -> String { "pref." + key }

    static func homeRecordName(_ rel: String) -> String { "home." + digest(Data(rel.utf8)) }

    /// Forget what CloudKit has (zone deleted or reset). Everything local
    /// pushes again; nothing is deleted.
    mutating func forgetServer() {
        zoneReady = false
        subscriptionReady = false
        changeToken = nil
        for key in defaults.keys { defaults[key]?.synced = nil }
        home = home.filter { $0.value.hash != Self.deletedHash }
        for key in home.keys { home[key]?.synced = nil }
    }

    private static var fileURL: URL {
        let fm = FileManager.default
        #if os(tvOS)
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        #else
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        #endif
        let dir = (base ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Wawona", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cloudkit-sync-state.json")
    }

    static func load() -> CloudSyncState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(CloudSyncState.self, from: data)
        else {
            return CloudSyncState()
        }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

/// UserDefaults values as CloudKit payloads. Profiles travel as redacted
/// JSON; every other key is a one-entry binary plist.
enum CloudSyncDefaults {
    static func payload(for key: String) -> Data? {
        let defaults = UserDefaults.standard
        guard let value = defaults.object(forKey: key) else { return nil }
        if key == CloudSyncPolicy.profilesKey {
            guard let json = profilesJSON(value), let redacted = CloudSyncPolicy.redactProfiles(json) else {
                return nil
            }
            return Data(redacted.utf8)
        }
        return try? PropertyListSerialization.data(fromPropertyList: ["v": value], format: .binary, options: 0)
    }

    /// Writes a cloud payload into UserDefaults. Profiles merge so local
    /// passwords survive. Returns false when the payload was unusable.
    static func apply(_ payload: Data, to key: String, bootstrap: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if key == CloudSyncPolicy.profilesKey {
            guard let remote = String(data: payload, encoding: .utf8) else { return false }
            let local = defaults.object(forKey: key).flatMap(profilesJSON) ?? "[]"
            guard let merged = CloudSyncPolicy.mergeProfiles(local: local, remote: remote, bootstrap: bootstrap) else {
                return false
            }
            defaults.set(Data(merged.utf8), forKey: key)
            return true
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil),
              let dict = plist as? [String: Any],
              let value = dict["v"]
        else {
            return false
        }
        defaults.set(value, forKey: key)
        return true
    }

    private static func profilesJSON(_ value: Any) -> String? {
        if let data = value as? Data { return String(data: data, encoding: .utf8) }
        return value as? String
    }
}

/// Shell HOME walk. Skips symlinks (the watch `inbox` link) and paths the
/// rust policy excludes.
enum CloudSyncHome {
    struct Scan {
        var signatures: [String: (hash: String, modified: Date)] = [:]
        /// Present but over the size or count cap. Never treated as deleted.
        var skipped: Set<String> = []
        var limitReached = false
    }

    static func signature(size: Int, modified: Date) -> String {
        "\(size)-\(Int64(modified.timeIntervalSince1970 * 1000))"
    }

    static func scan(root: URL) -> Scan {
        var scan = Scan()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                      .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return scan
        }
        let maxBytes = CloudSyncPolicy.homeMaxFileBytes
        let maxFiles = CloudSyncPolicy.homeMaxFiles
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let url as URL in walker {
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(prefix) || url.path.hasPrefix(prefix) else { continue }
            let rel = String((path.hasPrefix(prefix) ? path : url.path).dropFirst(prefix.count))
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if CloudSyncPolicy.homePathExcluded(rel) {
                if values.isDirectory == true { walker.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0
            if UInt64(size) > maxBytes || scan.signatures.count >= maxFiles {
                scan.skipped.insert(rel)
                scan.limitReached = true
                continue
            }
            let modified = values.contentModificationDate ?? .distantPast
            scan.signatures[rel] = (signature(size: size, modified: modified), modified)
        }
        return scan
    }

    /// Lands a CKAsset at `rel` and stamps the cloud modification time so
    /// the next scan sees the synced signature.
    static func write(asset: URL, rel: String, root: URL, modified: Date) -> String? {
        guard !rel.split(separator: "/").contains("..") else { return nil }
        let fm = FileManager.default
        let dest = root.appendingPathComponent(rel)
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staging = dest.deletingLastPathComponent()
                .appendingPathComponent(".wwn-cloud-\(UUID().uuidString)")
            try fm.copyItem(at: asset, to: staging)
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: staging.path)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: dest)
            }
            let values = try dest.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return signature(size: values.fileSize ?? 0, modified: values.contentModificationDate ?? modified)
        } catch {
            return nil
        }
    }
}
