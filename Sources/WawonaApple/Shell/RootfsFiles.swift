import Foundation

/// Rootfs copy / execute-bit restore. Policy stays in Rust; this only touches FileManager.
public enum RootfsFiles {
    public static func restoreExecuteBits(at root: URL, relativePaths: [String]) throws {
        let fm = FileManager.default
        for rel in relativePaths {
            let url = root.appendingPathComponent(rel)
            var attrs = try fm.attributesOfItem(atPath: url.path)
            let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
            attrs[.posixPermissions] = NSNumber(value: mode | 0o111)
            try fm.setAttributes(attrs, ofItemAtPath: url.path)
        }
    }

    public static func copyDirectory(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: dst)
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
    public static func ubiquityDocumentsURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }
    #endif
}
