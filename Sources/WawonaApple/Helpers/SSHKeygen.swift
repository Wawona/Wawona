import Foundation

@objc(WWNSSHKeygen)
public final class WWNSSHKeygen: NSObject {
    @objc public static func generateKeyType(_ keyType: String, comment: String?, directory: String?) -> String? {
        let dir = directory ?? NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("wawona_\(keyType)")
        #if os(macOS)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        var args = ["-t", keyType, "-f", path, "-N", ""]
        if let comment, !comment.isEmpty { args += ["-C", comment] }
        proc.arguments = args
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? path : nil
        } catch {
            return nil
        }
        #else
        _ = keyType; _ = comment; _ = path
        return nil
        #endif
    }

    /// Compatibility for editor "Generate Key" (passphrase ignored until ssh-keygen -N wired).
    @objc public static func generateKeyType(_ keyType: String, passphrase: String) throws -> String {
        _ = passphrase
        guard let path = generateKeyType(keyType, comment: nil, directory: nil) else {
            throw NSError(domain: "WWNSSHKeygen", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "ssh-keygen failed"
            ])
        }
        return path
    }

    @objc public static func installOpenSSHPrivateKey(at url: URL, error: NSErrorPointer) -> String? {
        let destDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Wawona/ssh", isDirectory: true)
        guard let destDir else {
            error?.pointee = NSError(domain: "WWNSSHKeygen", code: 1)
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let dest = destDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
            return dest.path
        } catch let err {
            error?.pointee = err as NSError
            return nil
        }
    }
}
