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
    /// Full catalog (keep in sync with macOS `kAllBundledClients` /
    /// Android `BundledClients.all`).
    static let allPresets: [ClientLauncher] = [
        ClientLauncher(name: "weston-terminal", executablePath: "weston-terminal", displayName: "Weston Terminal"),
        ClientLauncher(name: "foot", executablePath: "foot", displayName: "Foot Terminal"),
        ClientLauncher(name: "weston-simple-shm", executablePath: "weston-simple-shm", displayName: "Weston Simple SHM"),
        ClientLauncher(name: "wawona-wasm", executablePath: "wasm", displayName: "Wawona Runtime (.wasm)"),
        ClientLauncher(name: "weston", executablePath: "weston", displayName: "Weston"),
        ClientLauncher(name: "niri", executablePath: "niri", displayName: "Niri"),
        ClientLauncher(name: "weston-flower", executablePath: "weston-flower", displayName: "Weston Flower"),
        ClientLauncher(name: "kmscube", executablePath: "kmscube", displayName: "KMS Cube", requiresGpuStack: true),
        ClientLauncher(name: "gbm-es2-demo", executablePath: "gbm-es2-demo", displayName: "GBM ES2 Demo", requiresGpuStack: true),
        ClientLauncher(name: "opengl-cube", executablePath: "opengl-cube", displayName: "OpenGL Cube", requiresGpuStack: true),
        ClientLauncher(name: "vkcube", executablePath: "vkcube", displayName: "Vulkan Cube", requiresGpuStack: true),
        ClientLauncher(name: "weston-simple-egl", executablePath: "weston-simple-egl", displayName: "Weston Simple EGL", requiresGpuStack: true),
        ClientLauncher(name: "weston-smoke", executablePath: "weston-smoke", displayName: "Weston Smoke"),
        ClientLauncher(name: "weston-clickdot", executablePath: "weston-clickdot", displayName: "Weston Clickdot"),
        ClientLauncher(name: "weston-eventdemo", executablePath: "weston-eventdemo", displayName: "Weston Event Demo"),
        ClientLauncher(name: "weston-resizor", executablePath: "weston-resizor", displayName: "Weston Resizor"),
        ClientLauncher(name: "weston-cliptest", executablePath: "weston-cliptest", displayName: "Weston Cliptest"),
        ClientLauncher(name: "weston-transformed", executablePath: "weston-transformed", displayName: "Weston Transformed"),
        ClientLauncher(name: "weston-stacking", executablePath: "weston-stacking", displayName: "Weston Stacking"),
        ClientLauncher(name: "weston-dnd", executablePath: "weston-dnd", displayName: "Weston DnD"),
        ClientLauncher(name: "weston-image", executablePath: "weston-image", displayName: "Weston Image"),
        ClientLauncher(name: "weston-scaler", executablePath: "weston-scaler", displayName: "Weston Scaler"),
        ClientLauncher(name: "weston-editor", executablePath: "weston-editor", displayName: "Weston Editor"),
        ClientLauncher(name: "weston-constraints", executablePath: "weston-constraints", displayName: "Weston Constraints"),
    ]

    /// Clients runnable on this platform (GPU demos dropped when the stack is
    /// blocked/forbidden. E.g. watchOS has no Metal).
    static var availablePresets: [ClientLauncher] {
        allPresets.filter { launcher in
            if launcher.name == "wawona-wasm" {
                #if os(watchOS)
                return false
                #else
                return true
                #endif
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
