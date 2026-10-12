import Foundation

#if !os(macOS)
@_silgen_name("ssh_keygen_main")
private func wwn_ssh_keygen_main(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32
#endif

@objc(WWNSSHKeygen)
public final class WWNSSHKeygen: NSObject {
    /// Writes OpenSSH private + `.pub` under Application Support `Wawona/ssh/`.
    /// macOS uses `/usr/bin/ssh-keygen`. Apple mobile uses linked `ssh_keygen_main`.
    @objc public static func generateKeyType(
        _ keyType: String,
        comment: String?,
        directory: String?
    ) -> String? {
        generateKeyType(keyType, passphrase: "", comment: comment, directory: directory)
    }

    /// Compatibility for editor "Generate Key".
    @objc public static func generateKeyType(_ keyType: String, passphrase: String) throws -> String {
        guard let path = generateKeyType(
            keyType,
            passphrase: passphrase,
            comment: "wawona",
            directory: nil
        ) else {
            throw NSError(domain: "WWNSSHKeygen", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "ssh-keygen failed"
            ])
        }
        return path
    }

    public static func generateKeyType(
        _ keyType: String,
        passphrase: String,
        comment: String?,
        directory: String?
    ) -> String? {
        let type = keyType.isEmpty ? "ed25519" : keyType
        let destDir: URL
        if let directory, !directory.isEmpty {
            destDir = URL(fileURLWithPath: directory, isDirectory: true)
        } else if let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            destDir = support.appendingPathComponent("Wawona/ssh", isDirectory: true)
        } else {
            destDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        do {
            try FileManager.default.createDirectory(
                at: destDir,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        let fileName = "id_\(type)"
        let path = destDir.appendingPathComponent(fileName).path
        let pubPath = path + ".pub"
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
        if FileManager.default.fileExists(atPath: pubPath) {
            try? FileManager.default.removeItem(atPath: pubPath)
        }
        let commentArg = (comment?.isEmpty == false) ? comment! : "wawona"
        #if os(macOS)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        proc.arguments = [
            "-t", type,
            "-f", path,
            "-N", passphrase,
            "-C", commentArg,
            "-q",
        ]
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: path)
            else {
                return nil
            }
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path
            )
            return path
        } catch {
            return nil
        }
        #else
        let argv = [
            "ssh-keygen",
            "-t", type,
            "-f", path,
            "-N", passphrase,
            "-C", commentArg,
            "-q",
        ]
        let rc = Self.runSSHKeygenMain(argv)
        guard rc == 0, FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
        return path
        #endif
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

    #if !os(macOS)
    private static func runSSHKeygenMain(_ args: [String]) -> Int32 {
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cStrings.append(nil)
        defer {
            for ptr in cStrings where ptr != nil {
                free(ptr)
            }
        }
        return cStrings.withUnsafeMutableBufferPointer { buf in
            wwn_ssh_keygen_main(Int32(args.count), buf.baseAddress)
        }
    }
    #endif
}
