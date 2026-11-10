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
        setenv("WAWONA_ZSH_IN_PROCESS", "1", 1)
        setenv("WAWONA_SHELL", "/usr/bin/zsh", 1)
        setenv("SHELL", "/usr/bin/zsh", 1)
        setenv("TERM", "xterm-256color", 1)
        // Real POSIX PTY on Simulator: zsh clears ONLCR; wwn_write needs this
        // so LF expands to CRLF (else fastfetch / multiline output stair-steps).
        setenv("WAWONA_PTY_FAKE_TTY", "1", 1)
        let path = "/usr/bin:/bin:/usr/sbin:/sbin:" + activeRootfsPath() + "/usr/bin"
        setenv("PATH", path, 1)
        setenv("XDG_CONFIG_HOME", (home as NSString).appendingPathComponent(".config"), 1)
        setenv("XDG_CACHE_HOME", (home as NSString).appendingPathComponent(".cache"), 1)
        setenv("XDG_DATA_HOME", (home as NSString).appendingPathComponent(".local/share"), 1)
        setenv("XDG_STATE_HOME", (home as NSString).appendingPathComponent(".local/state"), 1)
        // In-process hist locks use host getpid(); drop a stuck LOCK and heal
        // SHARE_HISTORY in writable HOME (tvOS Done hang, 2026-11-04).
        let histLock = (home as NSString).appendingPathComponent(".zsh_history.LOCK")
        try? fm.removeItem(atPath: histLock)
        healShareHistoryInZshrc(home: home)
        WWNBundleShareEnvironment.apply()
    }

    /// Older rootfs templates enabled SHARE_HISTORY. Rewrite to APPEND_HISTORY
    /// so lockhistfile cannot hang Done on a host-pid LOCK.
    /// HIST_FCNTL_LOCK replaces the symlink LOCK with a per-process fcntl
    /// lock, which in-process zsh always acquires.
    private static func healShareHistoryInZshrc(home: String) {
        let zshrc = (home as NSString).appendingPathComponent(".zshrc")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: zshrc)),
              var text = String(data: data, encoding: .utf8)
        else { return }
        let original = text
        text = text.replacingOccurrences(
            of: "setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE",
            with: """
            setopt APPEND_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE
            unsetopt SHARE_HISTORY
            """
        )
        let setsShare = text.components(separatedBy: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("setopt")
                && $0.contains("SHARE_HISTORY")
        }
        if setsShare && !text.contains("unsetopt SHARE_HISTORY") {
            text += "\n# Wawona: in-process zsh must not SHARE_HISTORY (host-pid LOCK hang).\nunsetopt SHARE_HISTORY 2>/dev/null\n"
        }
        if !text.contains("HIST_FCNTL_LOCK") {
            text += "\n# Wawona: in-process zsh shares the host pid; use fcntl hist locks.\nsetopt HIST_FCNTL_LOCK\n"
        }
        guard text != original else { return }
        try? text.write(toFile: zshrc, atomically: true, encoding: .utf8)
    }
}
