import Foundation

/// Optional Wayland clients installed outside the App Store keep-set.
/// Deb prefixes (jailbreak / Termux / Linux) plus `wpm` wasm modules.
/// Store builds never probe APT. See `wawona-optional-software`.
public enum InstalledOptionalSoftware {
    public struct Entry: Hashable, Sendable {
        public let id: String
        public let displayName: String
        public let executablePath: String
        public let source: Source

        public enum Source: String, Hashable, Sendable {
            case deb
            case wasm
        }
    }

    /// Search prefixes for process debs. Empty / unused on store Mode A.
    public static var debBinPrefixes: [String] {
        #if os(Linux)
        return ["/usr/bin", "/usr/local/bin"]
        #else
        // Jailbreak rootless, rootful, Termux (when reachable from the process).
        return [
            "/var/jb/usr/bin",
            "/usr/bin",
            "/data/data/com.termux/files/usr/bin",
        ]
        #endif
    }

    /// Known optional client basenames (move-set). Not zsh / uutils / fastfetch.
    public static let optionalClientIds: [String] = [
        "weston",
        "niri",
        "foot",
        "weston-terminal",
        "weston-simple-shm",
        "weston-flower",
        "weston-smoke",
        "weston-clickdot",
        "weston-eventdemo",
        "weston-resizor",
        "weston-cliptest",
        "weston-transformed",
        "weston-stacking",
        "weston-dnd",
        "weston-image",
        "weston-scaler",
        "weston-editor",
        "weston-constraints",
        "weston-simple-egl",
        "kmscube",
        "gbm-es2-demo",
        "opengl-cube",
        "vkcube",
    ]

    public static func scanDebClients(fileManager: FileManager = .default) -> [Entry] {
        var found: [Entry] = []
        var seen = Set<String>()
        for prefix in debBinPrefixes {
            for id in optionalClientIds {
                let path = (prefix as NSString).appendingPathComponent(id)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                    continue
                }
                guard seen.insert(id).inserted else { continue }
                found.append(Entry(
                    id: id,
                    displayName: id,
                    executablePath: path,
                    source: .deb
                ))
            }
        }
        return found.sorted { $0.id < $1.id }
    }

    /// Wasm modules already installed for `wpm` / Native Shell wasm sessions.
    public static func scanWasmModules(fileManager: FileManager = .default) -> [Entry] {
        let roots: [URL] = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Wawona/wasm", isDirectory: true),
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("wasm", isDirectory: true),
        ].compactMap { $0 }

        var found: [Entry] = []
        var seen = Set<String>()
        for root in roots {
            guard let kids = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else { continue }
            for url in kids where url.pathExtension == "wasm" {
                let id = url.deletingPathExtension().lastPathComponent
                guard seen.insert(id).inserted else { continue }
                found.append(Entry(
                    id: id,
                    displayName: id,
                    executablePath: url.path,
                    source: .wasm
                ))
            }
        }
        return found.sorted { $0.id < $1.id }
    }

    public static func allInstalled(fileManager: FileManager = .default) -> [Entry] {
        scanDebClients(fileManager: fileManager) + scanWasmModules(fileManager: fileManager)
    }
}
