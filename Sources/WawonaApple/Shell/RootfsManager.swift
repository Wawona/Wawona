import Foundation

@objc(WWNRootfsManager)
public final class WWNRootfsManager: NSObject {
    @objc public static func bundleRootfsPath() -> String {
        Bundle.main.resourcePath.map { $0 + "/wawona-rootfs" } ?? ""
    }

    @objc public static func bundledShellPath() -> String { "/usr/bin/zsh" }

    @objc public static func bundledZshSharePath() -> String {
        bundleRootfsPath() + "/usr/share/zsh"
    }

    @objc public static func activeRootfsPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (base?.appendingPathComponent("wawona-rootfs").path) ?? ""
    }

    @objc public static func filesAppRootPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (docs?.appendingPathComponent("Wawona").path) ?? ""
    }

    @objc public static func localHomePath() -> String {
        filesAppRootPath() + "/home"
    }

    @objc public static func activeHomePath() -> String {
        if WWNRootfsICloudSync.isEnabled(),
           let cloud = WWNRootfsICloudSync.icloudHomePath(), !cloud.isEmpty {
            return cloud
        }
        return localHomePath()
    }

    @objc public static func prepareFilesAppAccess() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: filesAppRootPath())
        try? fm.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
    }

    #if !(os(iOS) || os(tvOS) || os(visionOS))
    @objc public static func ensureRootfsInstalled(_ error: NSErrorPointer) -> Bool {
        prepareFilesAppAccess()
        let src = URL(fileURLWithPath: bundleRootfsPath())
        let dst = URL(fileURLWithPath: activeRootfsPath())
        guard FileManager.default.fileExists(atPath: src.path) else { return true }
        do {
            try RootfsFiles.copyDirectory(from: src, to: dst)
            return true
        } catch let err as NSError {
            error?.pointee = err
            return false
        }
    }

    @objc public static func refreshShellDotfiles(_ error: NSErrorPointer) -> Bool {
        _ = error
        return true
    }

    @objc public static func reinstallSystemTree(_ error: NSErrorPointer) -> Bool {
        ensureRootfsInstalled(error)
    }
    #endif

    @objc public static func rootfsStatusSnapshot() -> [String: String] {
        [
            "bundle": bundleRootfsPath(),
            "active": activeRootfsPath(),
            "home": activeHomePath(),
        ]
    }

    @objc public static func applyShellEnvironment() {
        let home = activeHomePath()
        let fm = FileManager.default
        try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        for rel in [".config", ".cache", ".local/share", ".local/state"] {
            try? fm.createDirectory(
                atPath: (home as NSString).appendingPathComponent(rel),
                withIntermediateDirectories: true
            )
        }
        setenv("HOME", home, 1)
        setenv("ZDOTDIR", home, 1)
        setenv("WAWONA_ROOTFS", activeRootfsPath(), 1)
        let path = "/usr/bin:/bin:/usr/sbin:/sbin:" + activeRootfsPath() + "/usr/bin"
        setenv("PATH", path, 1)
        setenv("XDG_CONFIG_HOME", (home as NSString).appendingPathComponent(".config"), 1)
        setenv("XDG_CACHE_HOME", (home as NSString).appendingPathComponent(".cache"), 1)
        setenv("XDG_DATA_HOME", (home as NSString).appendingPathComponent(".local/share"), 1)
        setenv("XDG_STATE_HOME", (home as NSString).appendingPathComponent(".local/state"), 1)
        WWNBundleShareEnvironment.apply()
    }
}
