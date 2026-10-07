#if os(macOS)
import Foundation
import Darwin

/// Exclusive flock helpers for macOS LaunchAgent / UI single-instance gates.
/// Lock files live under `/tmp/wawona-$UID/` (same as XDG_RUNTIME_DIR default).
enum WawonaProcessLock {
    static func runtimeDirectory() -> String {
        if let env = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"], !env.isEmpty {
            return env
        }
        return "/tmp/wawona-\(getuid())"
    }

    @discardableResult
    static func ensureRuntimeDirectory() -> String {
        let dir = runtimeDirectory()
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }

    /// Acquire `name` under the runtime dir. Caller must keep the returned fd open.
    static func acquire(_ name: String) -> Int32? {
        let dir = ensureRuntimeDirectory()
        let path = (dir as NSString).appendingPathComponent(name)
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        return fd
    }

    static func release(_ fd: inout Int32) {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    /// True when another process already holds `name`.
    static func isHeld(_ name: String) -> Bool {
        let dir = ensureRuntimeDirectory()
        let path = (dir as NSString).appendingPathComponent(name)
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return false }
        let held = flock(fd, LOCK_EX | LOCK_NB) != 0
        if !held {
            flock(fd, LOCK_UN)
        }
        close(fd)
        return held
    }
}
#endif
