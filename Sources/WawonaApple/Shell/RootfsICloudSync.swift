import Foundation

public let WWNRootfsICloudSyncPreferenceKey = "wawona.pref.localShellICloudSyncEnabled"

@objc(WWNRootfsICloudSync)
public final class WWNRootfsICloudSync: NSObject {

    private static let iCloudContainerID = "iCloud.com.aspauldingcode.Wawona"

    #if (os(iOS) || os(macOS)) && !os(tvOS) && !os(watchOS)

    @objc public static func isSupported() -> Bool { true }

    @objc public static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: WWNRootfsICloudSyncPreferenceKey)
    }

    @objc public static func containerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerID)
    }

    @objc public static func isContainerAvailable() -> Bool {
        containerURL() != nil
    }

    @objc public static func localHomePath() -> String {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return ""
        }
        return docs.appendingPathComponent("Wawona/home", isDirectory: true).path
    }

    @objc public static func icloudHomePath() -> String? {
        guard let container = containerURL() else { return nil }
        return container.appendingPathComponent("Documents/Wawona/home", isDirectory: true).path
    }

    @objc public static func statusSummary() -> String {
        if !isEnabled() {
            return "Off. Shell HOME stays on this device only."
        }
        if !isContainerAvailable() {
            return "On. Waiting for iCloud sign-in (using local HOME until available)."
        }
        return "On. Shell HOME syncs via iCloud Drive (Settings → Apple ID → iCloud)."
    }

    @objc public static func prepareICloudLayout() {
        guard let home = icloudHomePath(), !home.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    @objc(copyTreeFrom:to:error:)
    public static func copyTree(from src: String, to dst: String, error: NSErrorPointer) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src) else { return true }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: src, isDirectory: &isDir)
        if !isDir.boolValue {
            try? fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dst) {
                try? fm.removeItem(atPath: dst)
            }
            do {
                try fm.copyItem(atPath: src, toPath: dst)
                return true
            } catch let err as NSError {
                error?.pointee = err
                return false
            }
        }
        do {
            try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        } catch let err as NSError {
            error?.pointee = err
            return false
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: src) else { return false }
        for name in entries {
            if name.hasPrefix("."), name == ".DS_Store" { continue }
            let srcPath = (src as NSString).appendingPathComponent(name)
            let dstPath = (dst as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: dstPath) { continue }
            if !copyTree(from: srcPath, to: dstPath, error: error) { return false }
        }
        return true
    }

    @objc(migrateFrom:to:error:)
    public static func migrate(from src: String, to dst: String, error: NSErrorPointer) -> Bool {
        guard !src.isEmpty, !dst.isEmpty else { return true }
        do {
            try FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
        } catch let err as NSError {
            error?.pointee = err
            return false
        }
        return copyTree(from: src, to: dst, error: error)
    }

    @objc(setEnabled:error:)
    public static func setEnabled(_ enabled: Bool, error: NSErrorPointer) -> Bool {
        let wasEnabled = isEnabled()
        if enabled == wasEnabled {
            prepareICloudLayout()
            return true
        }
        let local = localHomePath()
        if enabled {
            prepareICloudLayout()
            guard let cloud = icloudHomePath(), !cloud.isEmpty else {
                UserDefaults.standard.set(true, forKey: WWNRootfsICloudSyncPreferenceKey)
                return true
            }
            if !migrate(from: local, to: cloud, error: error) { return false }
            UserDefaults.standard.set(true, forKey: WWNRootfsICloudSyncPreferenceKey)
            return true
        }
        if let cloud = icloudHomePath(), !cloud.isEmpty {
            if !migrate(from: cloud, to: local, error: error) { return false }
        }
        UserDefaults.standard.set(false, forKey: WWNRootfsICloudSyncPreferenceKey)
        return true
    }

    #else

    @objc public static func isSupported() -> Bool { false }
    @objc public static func isEnabled() -> Bool { false }
    @objc public static func isContainerAvailable() -> Bool { false }
    @objc public static func icloudHomePath() -> String? { nil }
    @objc public static func statusSummary() -> String { "Not available on this platform." }
    @objc public static func prepareICloudLayout() {}
    @objc(setEnabled:error:)
    public static func setEnabled(_ enabled: Bool, error: NSErrorPointer) -> Bool {
        _ = enabled
        error?.pointee = NSError(
            domain: "WWNRootfs",
            code: 200,
            userInfo: [NSLocalizedDescriptionKey: "iCloud sync is not available on this platform."]
        )
        return false
    }

    #endif
}
