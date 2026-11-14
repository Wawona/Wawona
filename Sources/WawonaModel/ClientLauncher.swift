import Foundation

public struct ClientLauncher: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var executablePath: String
    public var arguments: [String]
    public var autoLaunch: Bool
    public var displayName: String
    /// ANGLE / Vulkan / iland GLES demos. Omitted from availablePresets when
    /// `PlatformCapabilities.allowsGpuStack` is false (watchOS blocked).
    public var requiresGpuStack: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        executablePath: String,
        arguments: [String] = [],
        autoLaunch: Bool = false,
        displayName: String,
        requiresGpuStack: Bool = false
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.autoLaunch = autoLaunch
        self.displayName = displayName
        self.requiresGpuStack = requiresGpuStack
    }

    enum CodingKeys: String, CodingKey {
        case id, name, executablePath, arguments, autoLaunch, displayName, requiresGpuStack
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        executablePath = try c.decode(String.self, forKey: .executablePath)
        arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        autoLaunch = try c.decodeIfPresent(Bool.self, forKey: .autoLaunch) ?? false
        displayName = try c.decode(String.self, forKey: .displayName)
        requiresGpuStack = try c.decodeIfPresent(Bool.self, forKey: .requiresGpuStack) ?? false
    }
}

public extension ClientLauncher {
    /// Rust `client_catalog` when linked; else the frozen Swift table below.
    static var rustCatalogPresets: [ClientLauncher]? {
        guard let json = WawonaDomainBridge.clientCatalogJSON(),
              let data = json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let display = row["display_name"] as? String,
                  let exe = row["executable"] as? String
            else {
                return nil
            }
            return ClientLauncher(
                name: id,
                executablePath: exe,
                displayName: display,
                requiresGpuStack: (row["requires_gpu"] as? Bool) ?? false
            )
        }
    }

    /// Full catalog (Rust `client_catalog` owns the list when linked).
    /// Never include modeb-tty / igetty.
    static var allPresets: [ClientLauncher] {
        if let rust = rustCatalogPresets, !rust.isEmpty { return rust }
        return fallbackPresets
    }

    /// Product keep-set only. Nested compositors and demos install later via
    /// `wpm` / apt (`InstalledOptionalSoftware`).
    static let fallbackPresets: [ClientLauncher] = [
        ClientLauncher(name: "wawona-shell", executablePath: "wawona-shell", displayName: "Native Shell"),
        ClientLauncher(name: "wawona-wasm", executablePath: "wasm", displayName: "Hello WASI GUI / Runtime (.wasm)"),
    ]

    /// Clients runnable on this platform (GPU demos dropped when the stack is
    /// blocked/forbidden. E.g. watchOS has no Metal).
    static var availablePresets: [ClientLauncher] {
        allPresets.filter { launcher in
            if launcher.name == "wawona-wasm" {
                return PlatformCapabilities.allowsWasmRuntime
            }
            if PlatformCapabilities.glesClientIds.contains(launcher.name) {
                return PlatformCapabilities.openGLDriverEnabled
            }
            if launcher.requiresGpuStack {
                return PlatformCapabilities.allowsGpuStack
            }
            return true
        }
    }

    /// Back-compat alias used throughout UI.
    static var presets: [ClientLauncher] { availablePresets }

    /// GPU demos present in the catalog but not launchable here.
    static var unavailableGpuPresets: [ClientLauncher] {
        allPresets.filter { $0.requiresGpuStack && !PlatformCapabilities.allowsGpuStack }
    }

    static func displayName(for clientID: String) -> String {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Not set" }
        return allPresets.first { $0.name == trimmed }?.displayName ?? trimmed
    }
}
