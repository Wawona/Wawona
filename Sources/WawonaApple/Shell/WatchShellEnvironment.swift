#if os(watchOS)
import Foundation

@objc(WWNWatchShellEnvironment)
public final class WWNWatchShellEnvironment: NSObject {
    @objc public static func apply() {
        setenv("WAWONA_ZSH_IN_PROCESS", "1", 1)
        setenv("WAWONA_SHELL", "/usr/bin/zsh", 1)
        setenv("SHELL", "/usr/bin/zsh", 1)
        setenv("TERM", "xterm-256color", 1)
        setenv("USER", "mobile", 1)
        setenv("PATH", "/usr/bin:/bin", 1)

        let bundleRoot = bundleRootfsPath()
        let home = activeHomePath()
        let active = canonicalFilesystemPath(activeRootfsPath())

        if !bundleRoot.isEmpty {
            let refreshDots = ensureRootfsInstalledFromBundle(bundleRoot)
            ensureDotfilesFromBundle(bundleRoot, home: home, force: refreshDots)
            bundleRoot.withCString { setenv("WAWONA_BUNDLE_ROOTFS", $0, 1) }
            active.withCString { setenv("WAWONA_ROOTFS", $0, 1) }
        }

        let fm = FileManager.default
        try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        home.withCString { setenv("HOME", $0, 1) }
        home.withCString { setenv("ZDOTDIR", $0, 1) }

        for rel in [".config", ".cache", ".local/share", ".local/state"] {
            try? fm.createDirectory(
                atPath: (home as NSString).appendingPathComponent(rel),
                withIntermediateDirectories: true
            )
        }
        setenv("XDG_CONFIG_HOME", (home as NSString).appendingPathComponent(".config"), 1)
        setenv("XDG_CACHE_HOME", (home as NSString).appendingPathComponent(".cache"), 1)
        setenv("XDG_DATA_HOME", (home as NSString).appendingPathComponent(".local/share"), 1)
        setenv("XDG_STATE_HOME", (home as NSString).appendingPathComponent(".local/state"), 1)

        applyBundleShareEnv()
        linkInboxIntoHome(home)
        publishWaylandSession(display: "wayland-0")
        shellLog("in-process zsh; HOME=\(home) WAWONA_ROOTFS=\(active)")
    }

    /// Same pair iOS sets before the shell. The compositor binds
    /// `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`. In-process `wasm` reads those.
    static func publishWaylandSession(display: String) {
        let runtime = watchRuntimeDir()
        try? FileManager.default.createDirectory(
            atPath: runtime,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        setenv("XDG_RUNTIME_DIR", runtime, 1)
        let name = display.isEmpty ? "wayland-0" : display
        setenv("WAYLAND_DISPLAY", name, 1)
    }

    /// Matches iOS `preferredSharedRuntimeDir` without pulling phone Settings
    /// into the watch target. Simulator path is per-UDID so two watches do
    /// not share one `wayland-0`.
    static func watchRuntimeDir() -> String {
        #if targetEnvironment(simulator)
        let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? ""
        let suffix: String
        if udid.count >= 8 {
            suffix = "_" + String(udid.prefix(8)).lowercased()
        } else if !udid.isEmpty {
            suffix = "_" + udid.lowercased()
        } else {
            suffix = ""
        }
        return "/tmp/wawona_sim_\(getuid())\(suffix)"
        #else
        return "/tmp/wawona-\(getuid())"
        #endif
    }

    /// Phone transfers already land in the Watch app container
    /// (`Documents/Wawona/inbox`). Link that directory at `$HOME/inbox` so
    /// `ls` and `cd` see it. No separate "From iPhone" screen.
    @objc public static func publishInboxIntoHome() {
        apply()
    }

    private static func linkInboxIntoHome(_ home: String) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let inbox = docs.appendingPathComponent("Wawona/inbox", isDirectory: true)
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let link = (home as NSString).appendingPathComponent("inbox")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: link, isDirectory: &isDir) {
            return
        }
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: inbox.path)
    }

    private static func shellLog(_ message: String) {
        message.withCString { wwn_log_ring_append("SHELL", $0) }
    }

    private static func bundleRootfsPath() -> String {
        let fm = FileManager.default
        let bundle = Bundle.main.bundlePath
        let atRoot = (bundle as NSString).appendingPathComponent("wawona-rootfs")
        if fm.fileExists(atPath: atRoot) { return atRoot }
        if let resource = Bundle.main.resourcePath, !resource.isEmpty {
            let atResources = (resource as NSString).appendingPathComponent("wawona-rootfs")
            if fm.fileExists(atPath: atResources) { return atResources }
        }
        return ""
    }

    private static func activeRootfsPath() -> String {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return (NSTemporaryDirectory() as NSString).appendingPathComponent("wawona-rootfs")
        }
        return base.appendingPathComponent("Wawona/wawona-rootfs", isDirectory: true).path
    }

    private static func canonicalFilesystemPath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        let resolved = (path as NSString).resolvingSymlinksInPath
        return resolved.isEmpty ? path : resolved
    }

    private static func activeHomePath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let home: String
        if let docs {
            home = docs.appendingPathComponent("Wawona/home", isDirectory: true).path
        } else {
            home = (NSHomeDirectory() as NSString).appendingPathComponent("Wawona/home")
        }
        return canonicalFilesystemPath(home)
    }

    @discardableResult
    private static func copyTree(from src: String, to dst: String) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: src) else { return false }
        for case let rel as String in enumerator {
            let srcPath = (src as NSString).appendingPathComponent(rel)
            let dstPath = (dst as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: srcPath, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                try? fm.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
                continue
            }
            try? fm.createDirectory(
                atPath: (dstPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            if fm.fileExists(atPath: dstPath) { try? fm.removeItem(atPath: dstPath) }
            try? fm.copyItem(atPath: srcPath, toPath: dstPath)
        }
        return true
    }

    private static func ensureRootfsInstalledFromBundle(_ bundleRoot: String) -> Bool {
        let fm = FileManager.default
        let active = activeRootfsPath()
        let bundleVerPath = (bundleRoot as NSString).appendingPathComponent("etc/zsh/.template-version")
        let appliedPath = (active as NSString).appendingPathComponent(".template-version-applied")
        var bundleVer = (try? String(contentsOfFile: bundleVerPath, encoding: .utf8)) ?? "0"
        bundleVer = bundleVer.trimmingCharacters(in: .whitespacesAndNewlines)
        var applied = (try? String(contentsOfFile: appliedPath, encoding: .utf8)) ?? ""
        applied = applied.trimmingCharacters(in: .whitespacesAndNewlines)
        if applied == bundleVer,
           fm.fileExists(atPath: (active as NSString).appendingPathComponent("etc"))
        {
            return false
        }
        try? fm.createDirectory(atPath: active, withIntermediateDirectories: true)
        for sub in ["etc", "usr"] {
            let src = (bundleRoot as NSString).appendingPathComponent(sub)
            let dst = (active as NSString).appendingPathComponent(sub)
            guard fm.fileExists(atPath: src) else { continue }
            if fm.fileExists(atPath: dst) { try? fm.removeItem(atPath: dst) }
            _ = copyTree(from: src, to: dst)
        }
        try? bundleVer.write(toFile: appliedPath, atomically: true, encoding: .utf8)
        shellLog("installed rootfs template v\(bundleVer)")
        return true
    }

    private static func ensureDotfilesFromBundle(_ bundleRoot: String, home: String, force: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        let dotfiles: [(String, String)] = [
            ("etc/zsh/zshenv.template", ".zshenv"),
            ("etc/zsh/zshrc.template", ".zshrc"),
            ("etc/zsh/zlogin.template", ".zlogin"),
        ]
        for (srcRel, dstName) in dotfiles {
            let src = (bundleRoot as NSString).appendingPathComponent(srcRel)
            let dst = (home as NSString).appendingPathComponent(dstName)
            guard fm.fileExists(atPath: src) else { continue }
            if !force, fm.fileExists(atPath: dst) { continue }
            if fm.fileExists(atPath: dst) { try? fm.removeItem(atPath: dst) }
            try? fm.copyItem(atPath: src, toPath: dst)
        }
    }
}

@_silgen_name("wwn_log_ring_append")
private func wwn_log_ring_append(_ module: UnsafePointer<CChar>, _ msg: UnsafePointer<CChar>)

@_cdecl("wwn_ios_refresh_bundle_env")
public func wwn_ios_refresh_bundle_env() {
    WWNWatchShellEnvironment.apply()
}

#endif
