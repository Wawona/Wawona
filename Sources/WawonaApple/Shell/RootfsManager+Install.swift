#if os(iOS) || os(tvOS) || os(visionOS)
import Foundation

extension WWNRootfsManager {
    @objc public static func refreshShellDotfiles(_ error: NSErrorPointer) -> Bool {
        let bundleRoot = bundleRootfsPath()
        guard !bundleRoot.isEmpty else {
            error?.pointee = NSError(
                domain: "WWNRootfs", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled wawona-rootfs not found."]
            )
            return false
        }
        prepareFilesAppAccess()
        if !ensureShellDotfilesPresent(bundleRoot, home: activeHomePath(), force: true) {
            error?.pointee = NSError(
                domain: "WWNRootfs", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to refresh zsh dotfiles from templates."]
            )
            return false
        }
        return true
    }

    @objc public static func reinstallSystemTree(_ error: NSErrorPointer) -> Bool {
        let bundleRoot = bundleRootfsPath()
        let activeRoot = activeRootfsPath()
        let fm = FileManager.default
        guard !bundleRoot.isEmpty, fm.fileExists(atPath: bundleRoot) else {
            error?.pointee = NSError(
                domain: "WWNRootfs", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled wawona-rootfs not found in app resources."]
            )
            return false
        }
        do {
            try fm.createDirectory(atPath: activeRoot, withIntermediateDirectories: true)
        } catch let err as NSError {
            error?.pointee = err
            return false
        }
        for subdir in ["etc", "usr"] {
            let src = (bundleRoot as NSString).appendingPathComponent(subdir)
            let dst = (activeRoot as NSString).appendingPathComponent(subdir)
            guard fm.fileExists(atPath: src) else { continue }
            if fm.fileExists(atPath: dst) { try? fm.removeItem(atPath: dst) }
            if !copyTree(from: src, to: dst, error: error) { return false }
        }
        let bundleTemplateVer = bundledTemplateVersion(bundleRoot)
        let appliedVerPath = (activeRoot as NSString).appendingPathComponent(".template-version-applied")
        try? bundleTemplateVer.write(toFile: appliedVerPath, atomically: true, encoding: .utf8)
        let installed = (activeRoot as NSString).appendingPathComponent(".installed-v13")
        try? "installed".write(toFile: installed, atomically: true, encoding: .utf8)
        markInterpreterStubsExecutable(activeRoot)
        return true
    }

    @objc public static func ensureRootfsInstalled(_ error: NSErrorPointer) -> Bool {
        let bundleRoot = bundleRootfsPath()
        let activeRoot = activeRootfsPath()
        let fm = FileManager.default
        guard !bundleRoot.isEmpty, fm.fileExists(atPath: bundleRoot) else {
            error?.pointee = NSError(
                domain: "WWNRootfs", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled wawona-rootfs not found in app resources."]
            )
            return false
        }
        prepareFilesAppAccess()
        do {
            try fm.createDirectory(atPath: activeRoot, withIntermediateDirectories: true)
        } catch let err as NSError {
            error?.pointee = err
            return false
        }
        let home = activeHomePath()
        if !ensureShellDotfilesPresent(bundleRoot, home: home, force: false) {
            error?.pointee = NSError(
                domain: "WWNRootfs", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to install zsh dotfiles."]
            )
            return false
        }
        let bundleTemplateVer = bundledTemplateVersion(bundleRoot)
        let appliedVer = appliedTemplateVersion()
        let markerV13 = (activeRoot as NSString).appendingPathComponent(".installed-v13")
        let needRefresh = !fm.fileExists(atPath: markerV13) || appliedVer != bundleTemplateVer
        if !needRefresh {
            markInterpreterStubsExecutable(activeRoot)
            return true
        }
        if !appliedVer.isEmpty, appliedVer != bundleTemplateVer {
            NSLog("WWNRootfs: bundle template v%@ → v%@; refreshing etc/usr tree", appliedVer, bundleTemplateVer)
            _ = ensureShellDotfilesPresent(bundleRoot, home: home, force: true)
        }
        if !reinstallSystemTree(error) { return false }
        for old in [
            ".installed-v5", ".installed-v6", ".installed-v7", ".installed-v8",
            ".installed-v9", ".installed-v10", ".installed-v11", ".installed-v12",
        ] {
            let p = (activeRoot as NSString).appendingPathComponent(old)
            if fm.fileExists(atPath: p) { try? fm.removeItem(atPath: p) }
        }
        return true
    }

    static func bundledTemplateVersion(_ bundleRoot: String) -> String {
        let path = (bundleRoot as NSString).appendingPathComponent("etc/zsh/.template-version")
        guard FileManager.default.fileExists(atPath: path),
              let ver = try? String(contentsOfFile: path, encoding: .utf8), !ver.isEmpty
        else { return "0" }
        return ver.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appliedTemplateVersion() -> String {
        let path = (activeRootfsPath() as NSString).appendingPathComponent(".template-version-applied")
        guard let ver = try? String(contentsOfFile: path, encoding: .utf8), !ver.isEmpty else { return "" }
        return ver.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func copyTree(from src: String, to dst: String, error: NSErrorPointer) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: src) else { return true }
        for case let rel as String in enumerator {
            let srcPath = (src as NSString).appendingPathComponent(rel)
            let dstPath = (dst as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: srcPath, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                do {
                    try fm.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
                } catch let err as NSError {
                    error?.pointee = err
                    return false
                }
                continue
            }
            try? fm.createDirectory(
                atPath: (dstPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            if fm.fileExists(atPath: dstPath) { try? fm.removeItem(atPath: dstPath) }
            do {
                try fm.copyItem(atPath: srcPath, toPath: dstPath)
            } catch let err as NSError {
                error?.pointee = err
                return false
            }
        }
        return true
    }

    @discardableResult
    static func ensureShellDotfilesPresent(_ bundleRoot: String, home: String, force: Bool) -> Bool {
        let fm = FileManager.default
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
            do {
                try fm.copyItem(atPath: src, toPath: dst)
            } catch {
                return false
            }
        }
        return true
    }

    @discardableResult
    static func migrateLegacyHomeIfNeeded(_ newHome: String, error: NSErrorPointer) -> Bool {
        let fm = FileManager.default
        let legacyHome = (activeRootfsPath() as NSString).appendingPathComponent("home")
        if legacyHome == newHome { return true }
        guard fm.fileExists(atPath: legacyHome) else { return true }
        if let newEntries = try? fm.contentsOfDirectory(atPath: newHome), !newEntries.isEmpty {
            let backup = (activeRootfsPath() as NSString).appendingPathComponent("home.legacy-backup")
            if !fm.fileExists(atPath: backup) {
                try? fm.moveItem(atPath: legacyHome, toPath: backup)
                NSLog("WWNRootfs: legacy home moved to %@", backup)
            }
            return true
        }
        do {
            try fm.moveItem(atPath: legacyHome, toPath: newHome)
        } catch let moveError {
            var copyErr: NSError?
            if !copyTree(from: legacyHome, to: newHome, error: &copyErr) {
                error?.pointee = copyErr ?? (moveError as NSError)
                return false
            }
            try? fm.removeItem(atPath: legacyHome)
        }
        NSLog("WWNRootfs: migrated shell HOME → %@", newHome)
        return true
    }

    static func ensureXDGDirectoriesUnderHome(_ home: String) {
        let fm = FileManager.default
        for rel in [".config", ".cache", ".local/share", ".local/state"] {
            try? fm.createDirectory(
                atPath: (home as NSString).appendingPathComponent(rel),
                withIntermediateDirectories: true
            )
        }
    }

    static func markInterpreterStubsExecutable(_ activeRoot: String) {
        let fm = FileManager.default
        let names = ["sh", "zsh", "bash", "dash", "chmod"]
        for dir in ["usr/bin", "bin"] {
            for name in names {
                let path = ((activeRoot as NSString).appendingPathComponent(dir) as NSString).appendingPathComponent(name)
                guard fm.fileExists(atPath: path),
                      let attrs = try? fm.attributesOfItem(atPath: path),
                      let mode = attrs[.posixPermissions] as? NSNumber
                else { continue }
                if mode.uintValue & 0o111 == 0o111 { continue }
                var next = attrs
                next[.posixPermissions] = NSNumber(value: mode.uintValue | 0o111)
                try? fm.setAttributes(next, ofItemAtPath: path)
            }
        }
    }

    static func migrateFastfetchConfigFromBundle(_ bundleRoot: String, configHome: String) {
        let fm = FileManager.default
        let bundleVerPath = (bundleRoot as NSString).appendingPathComponent("etc/fastfetch/.template-version")
        guard fm.fileExists(atPath: bundleVerPath) else { return }
        var bundleVer = (try? String(contentsOfFile: bundleVerPath, encoding: .utf8)) ?? "0"
        bundleVer = bundleVer.trimmingCharacters(in: .whitespacesAndNewlines)
        let destDir = (configHome as NSString).appendingPathComponent("fastfetch")
        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        let appliedVerPath = (destDir as NSString).appendingPathComponent(".template-version-applied")
        var appliedVer = (try? String(contentsOfFile: appliedVerPath, encoding: .utf8)) ?? ""
        appliedVer = appliedVer.trimmingCharacters(in: .whitespacesAndNewlines)
        if appliedVer == bundleVer { return }
        let configPath = (destDir as NSString).appendingPathComponent("config.jsonc")
        if fm.fileExists(atPath: configPath) {
            try? fm.removeItem(atPath: configPath)
            NSLog(
                "WWNRootfs: removed fastfetch config.jsonc (template v%@ → v%@)",
                appliedVer.isEmpty ? "0" : appliedVer, bundleVer
            )
        }
        try? bundleVer.write(toFile: appliedVerPath, atomically: true, encoding: .utf8)
    }
}

#endif
