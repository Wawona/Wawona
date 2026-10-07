#if os(macOS)
import AppKit

/// Replaces wawona-shell WWNAppScanner.m / WWNLauncherClient.m.
@objc(WWNAppScanner)
public final class WWNAppScanner: NSObject {
    @objc public static func installedApplications() -> [[String: String]] {
        let urls = FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        var out: [[String: String]] = []
        for dir in urls {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for url in items where url.pathExtension == "app" {
                out.append([
                    "name": url.deletingPathExtension().lastPathComponent,
                    "path": url.path,
                ])
            }
        }
        return out
    }
}

@objc(WWNLauncherClient)
public final class WWNLauncherClient: NSObject {
    @objc(launchApplicationAtPath:)
    public static func launchApplication(atPath path: String) -> Bool {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
#endif
