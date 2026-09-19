import Combine
import Foundation

public extension Notification.Name {
    /// Posted after `WawonaPreferences.save()` writes to `UserDefaults`.
    static let wawonaPreferencesDidSave = Notification.Name("WawonaPreferencesDidSave")
}

public enum SettingsDiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case ssh
    case waypipe
    case dependency
}

public enum SettingsDiagnosticMode: String, Codable, CaseIterable, Sendable {
    case configLint
    case runtimeProbe
}

public struct SettingsDiagnosticEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var timestamp: Date
    public var category: SettingsDiagnosticCategory
    public var mode: SettingsDiagnosticMode
    public var target: String
    public var success: Bool
    public var message: String
    public var details: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case category
        case mode
        case target
        case success
        case message
        case details
    }

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        category: SettingsDiagnosticCategory,
        mode: SettingsDiagnosticMode = .configLint,
        target: String,
        success: Bool,
        message: String,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.mode = mode
        self.target = target
        self.success = success
        self.message = message
        self.details = details
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        category = try container.decode(SettingsDiagnosticCategory.self, forKey: .category)
        mode = try container.decodeIfPresent(SettingsDiagnosticMode.self, forKey: .mode) ?? SettingsDiagnosticMode.configLint
        target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        details = try container.decodeIfPresent([String: String].self, forKey: .details) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(category, forKey: .category)
        try container.encode(mode, forKey: .mode)
        try container.encode(target, forKey: .target)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        try container.encode(details, forKey: .details)
    }
}

public struct ResolvedMachineSettings: Codable, Hashable, Sendable {
    public var machineID: String
    public var machineName: String
    public var machineType: MachineType
    public var renderer: String
    public var vulkanDriver: String
    public var openGLDriver: String
    public var dmabufEnabled: Bool
    public var forceSSD: Bool
    public var renderMacOSPointer: Bool
    public var nestedCompositorCursor: String
    public var autoScale: Bool
    public var colorOperations: Bool
    public var waylandDisplay: String
    public var sshHost: String
    public var sshUser: String
    public var sshPort: Int
    public var sshPassword: String
    public var waypipeSSHPassword: String
    public var remoteCommand: String
    public var waypipeEnabled: Bool
    public var bundledAppID: String
    public var inputProfile: String
    public var logLevel: String
    public var shakeToCloseEnabled: Bool
    public var swipeBackToCloseEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case machineID = "machineId"
        case machineName
        case machineType
        case renderer
        case vulkanDriver
        case openGLDriver = "openGlDriver"
        case dmabufEnabled
        case forceSSD = "forceSsd"
        case renderMacOSPointer = "renderMacosPointer"
        case nestedCompositorCursor
        case autoScale
        case colorOperations
        case waylandDisplay
        case sshHost
        case sshUser
        case sshPort
        case sshPassword
        case waypipeSSHPassword = "waypipeSshPassword"
        case remoteCommand
        case waypipeEnabled
        case bundledAppID = "bundledAppId"
        case inputProfile
        case logLevel
        case shakeToCloseEnabled
        case swipeBackToCloseEnabled
    }
}

private struct RustPreferencesSnapshot: Codable {
    var renderer: String
    var vulkanDriver: String
    var openGLDriver: String
    var forceSSD: Bool
    var renderMacosPointer: Bool
    var nestedCompositorCursor: String
    var autoScale: Bool
    var colorOperations: Bool
    var waylandDisplay: String
    var sshHost: String
    var sshUser: String
    var sshPort: Int
    var sshPassword: String
    var sshAuthMethod: Int
    var sshKeyPath: String
    var sshKeyPassphrase: String
    var sshKeyType: String
    var waypipeSshPassword: String
    var logLevel: String
    var defaultInputProfile: String
    var defaultBundledAppId: String
    var defaultWaypipeEnabled: Bool
    var xwaylandSupport: Bool
    var shakeToCloseEnabled: Bool
    var swipeBackToCloseEnabled: Bool
    var hasCompletedWelcome: Bool
}

@MainActor
public final class WawonaPreferences: ObservableObject {
    public static let shared = WawonaPreferences()

    @Published public var renderer: String = "metal"
    @Published public var vulkanDriver: String = ""
    @Published public var openGLDriver: String = "angle"
    @Published public var forceSSD: Bool = false
    @Published public var renderMacOSPointer: Bool = false
    /// "virtual" or "host"
    @Published public var nestedCompositorCursor: String = "virtual"
    @Published public var autoScale: Bool = true
    @Published public var colorOperations: Bool = false
    @Published public var waylandDisplay: String = "wayland-0"
    @Published public var sshHost: String = ""
    @Published public var sshUser: String = ""
    @Published public var sshPort: Int = 22
    @Published public var sshPassword: String = ""
    /// 0 = password, 1 = public key (synced to SSHAuthMethod / WaypipeSSHAuthMethod).
    @Published public var sshAuthMethod: Int = 0
    @Published public var sshKeyPath: String = ""
    @Published public var sshKeyPassphrase: String = ""
    @Published public var sshKeyType: String = "ed25519"
    @Published public var waypipeSSHPassword: String = ""
    @Published public var logLevel: String = "info"
    /// Canonical values: "Multi-Touch" or "Touchpad" (matches ObjC TouchInputType).
    @Published public var defaultInputProfile: String = "Multi-Touch"

    /// Map legacy labels ("direct", "multitouch", …) onto TouchInputType.
    public static func normalizedTouchInputType(_ raw: String?) -> String {
        RustDomainTransport.normalizeTouchInput(raw)
    }
    @Published public var defaultBundledAppID: String = ""
    @Published public var defaultWaypipeEnabled: Bool = true
    /// When true, Waypipe is launched with `--xwls` (XWayland integration) for supported sessions.
    @Published public var xwaylandSupport: Bool = false
    @Published public var shakeToCloseEnabled: Bool = true
    @Published public var swipeBackToCloseEnabled: Bool = true
    @Published public var hasCompletedWelcome: Bool = false
    @Published public var globalClientLaunchers: [ClientLauncher] = ClientLauncher.presets
    @Published public var diagnostics: [SettingsDiagnosticEntry] = []

    private let defaults = UserDefaults.standard
    private let keyPrefix = "wawona.pref."

    public init() {
        load()
    }

    public func load() {
        RustDomainClient.bootstrapIfNeeded()
        guard let snapshot = RustDomainClient.snapshot(),
              let raw = snapshot["preferences"],
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let value = try? JSONDecoder().decode(RustPreferencesSnapshot.self, from: data)
        else {
            return
        }
        renderer = value.renderer
        vulkanDriver = value.vulkanDriver
        openGLDriver = value.openGLDriver
        forceSSD = value.forceSSD
        renderMacOSPointer = value.renderMacosPointer
        nestedCompositorCursor = value.nestedCompositorCursor
        autoScale = value.autoScale
        colorOperations = value.colorOperations
        waylandDisplay = value.waylandDisplay
        sshHost = value.sshHost
        sshUser = value.sshUser
        sshPort = value.sshPort
        sshPassword = value.sshPassword
        sshAuthMethod = value.sshAuthMethod
        sshKeyPath = value.sshKeyPath
        sshKeyPassphrase = value.sshKeyPassphrase
        sshKeyType = value.sshKeyType
        waypipeSSHPassword = value.waypipeSshPassword
        logLevel = value.logLevel
        defaultInputProfile = value.defaultInputProfile
        defaultBundledAppID = value.defaultBundledAppId
        defaultWaypipeEnabled = value.defaultWaypipeEnabled
        xwaylandSupport = value.xwaylandSupport
        shakeToCloseEnabled = value.shakeToCloseEnabled
        swipeBackToCloseEnabled = value.swipeBackToCloseEnabled
        hasCompletedWelcome = value.hasCompletedWelcome
    }

    public func save() {
        let previousForceSSD = (RustDomainClient.snapshot()?["preferences"]
            as? [String: Any])?["forceSSD"] as? Bool
        let value = RustPreferencesSnapshot(
            renderer: renderer,
            vulkanDriver: vulkanDriver,
            openGLDriver: openGLDriver,
            forceSSD: forceSSD,
            renderMacosPointer: renderMacOSPointer,
            nestedCompositorCursor: nestedCompositorCursor,
            autoScale: autoScale,
            colorOperations: colorOperations,
            waylandDisplay: waylandDisplay,
            sshHost: sshHost,
            sshUser: sshUser,
            sshPort: sshPort,
            sshPassword: sshPassword,
            sshAuthMethod: sshAuthMethod,
            sshKeyPath: sshKeyPath,
            sshKeyPassphrase: sshKeyPassphrase,
            sshKeyType: sshKeyType,
            waypipeSshPassword: waypipeSSHPassword,
            logLevel: logLevel,
            defaultInputProfile: defaultInputProfile,
            defaultBundledAppId: defaultBundledAppID,
            defaultWaypipeEnabled: defaultWaypipeEnabled,
            xwaylandSupport: xwaylandSupport,
            shakeToCloseEnabled: shakeToCloseEnabled,
            swipeBackToCloseEnabled: swipeBackToCloseEnabled,
            hasCompletedWelcome: hasCompletedWelcome
        )
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data),
              RustDomainClient.dispatch([
                "type": "update_preferences",
                "preferences": object,
              ]) else {
            return
        }
        load()

        // Mechanical compatibility mirrors for ObjC platform adapters that
        // have not yet moved to snapshot polling.
        defaults.set(forceSSD, forKey: "ForceServerSideDecorations")
        defaults.set(vulkanDriver, forKey: "VulkanDriver")
        defaults.set(openGLDriver, forKey: "OpenGLDriver")
        defaults.set(renderMacOSPointer, forKey: "RenderMacOSPointer")
        defaults.set(nestedCompositorCursor, forKey: "NestedCompositorCursor")
        defaults.set(sshAuthMethod, forKey: "SSHAuthMethod")
        defaults.set(sshKeyPath, forKey: "SSHKeyPath")
        defaults.set(sshKeyPassphrase, forKey: "SSHKeyPassphrase")
        defaults.set(sshKeyType, forKey: "SSHKeyType")
        defaults.set(sshAuthMethod, forKey: "WaypipeSSHAuthMethod")
        defaults.set(sshKeyPath, forKey: "WaypipeSSHKeyPath")
        defaults.set(sshKeyPassphrase, forKey: "WaypipeSSHKeyPassphrase")
        if let data = try? JSONEncoder().encode(globalClientLaunchers) {
            defaults.set(data, forKey: keyPrefix + "globalClientLaunchers")
        }
        if let diagnosticsData = try? JSONEncoder().encode(diagnostics) {
            defaults.set(diagnosticsData, forKey: keyPrefix + "diagnostics")
        }
        if previousForceSSD != forceSSD {
            NotificationCenter.default.post(
                name: Notification.Name("WWNForceSSDChangedNotification"),
                object: nil
            )
        }
        NotificationCenter.default.post(name: .wawonaPreferencesDidSave, object: self)
    }

    public func resolvedSettings(for profile: MachineProfile) -> ResolvedMachineSettings {
        guard let data = RustDomainClient.resolvedSettingsData(profile: profile),
              let resolved = try? JSONDecoder().decode(
                ResolvedMachineSettings.self,
                from: data
              ) else {
            preconditionFailure("Rust rejected a Swift profile DTO")
        }
        return resolved
    }

    public func recordDiagnostic(
        category: SettingsDiagnosticCategory,
        mode: SettingsDiagnosticMode = SettingsDiagnosticMode.configLint,
        target: String,
        success: Bool,
        message: String,
        details: [String: String] = [:]
    ) -> SettingsDiagnosticEntry {
        let entry = SettingsDiagnosticEntry(
            category: category,
            mode: mode,
            target: target,
            success: success,
            message: message,
            details: details
        )
        var next = diagnostics
        next.insert(entry, at: 0)
        if next.count > 100 {
            next = Array(next.prefix(100))
        }
        diagnostics = next
        save()
        return entry
    }

    public func testSSHConnection(
        host: String,
        user: String,
        password: String,
        port: Int,
        runtimeProbe: Bool = false
    ) -> SettingsDiagnosticEntry {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let normalizedUser = user.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let validPort = (1...65535).contains(port)
        let configOK = !normalizedHost.isEmpty && !normalizedUser.isEmpty && validPort

        var runtimeOK = configOK
        var runtimeMessage = "SSH settings are valid for connection attempt."
        if runtimeProbe {
            let transport = Self.runtimeSSHTransport()
            switch transport {
            case .externalBinary:
                let hasSSH = Self.probeCommandAvailable("ssh")
                runtimeOK = configOK && hasSSH
                runtimeMessage = runtimeOK
                    ? "Runtime probe: ssh binary is available and settings are valid."
                    : "Runtime probe failed: ssh binary is unavailable or host/user/port are invalid."
            case .inProcessLibssh2:
                runtimeOK = configOK
                runtimeMessage = runtimeOK
                    ? "Runtime probe: in-process libssh2 transport is active and settings are valid."
                    : "Runtime probe failed: host/user/port are invalid for libssh2 transport."
            }
        }
        return recordDiagnostic(
            category: .ssh,
            mode: runtimeProbe ? .runtimeProbe : .configLint,
            target: "\(normalizedUser)@\(normalizedHost):\(port)",
            success: runtimeOK,
            message: runtimeMessage,
            details: [
                "runtimeProbe": runtimeProbe ? "true" : "false",
                "host": normalizedHost,
                "user": normalizedUser,
                "port": String(port),
                "passwordProvided": password.isEmpty ? "false" : "true",
            ]
        )
    }

    public func testWaypipeCommand(_ command: String, runtimeProbe: Bool = false) -> SettingsDiagnosticEntry {
        let normalized = command.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let configOK = !normalized.isEmpty
        let binary = normalized.split(separator: " ").first.map { String($0) } ?? ""

        var success = configOK
        var message = configOK ? "Waypipe command is configured." : "Waypipe command is empty."
        if runtimeProbe {
            let hasBinary = !binary.isEmpty && Self.probeCommandAvailable(binary)
            success = configOK && hasBinary
            message = success
                ? "Runtime probe: command binary is available."
                : "Runtime probe failed: command is empty or binary was not found."
        }
        return recordDiagnostic(
            category: .waypipe,
            mode: runtimeProbe ? .runtimeProbe : .configLint,
            target: normalized.isEmpty ? "waypipe" : normalized,
            success: success,
            message: message,
            details: [
                "runtimeProbe": runtimeProbe ? "true" : "false",
                "binary": binary,
            ]
        )
    }

    public func runDependencyDiagnostics(runtimeProbe: Bool = false) -> SettingsDiagnosticEntry {
        let deps = Self.runtimeDependencyTargets()
        var status = true
        var details: [String: String] = [:]
        if runtimeProbe {
            for dep in deps {
                let available = Self.probeDependencyAvailable(dep)
                details[dep] = available ? "present" : "missing"
                if !available {
                    status = false
                }
            }
        }
        return recordDiagnostic(
            category: .dependency,
            mode: runtimeProbe ? .runtimeProbe : .configLint,
            target: "global-dependencies",
            success: status,
            message: runtimeProbe
                ? "Runtime dependency probe completed for: \(deps.joined(separator: ", "))"
                : "Configured dependencies: \(deps.joined(separator: ", "))",
            details: details
        )
    }

    private enum RuntimeSSHTransport {
        case externalBinary
        case inProcessLibssh2
    }

    private static func runtimeSSHTransport() -> RuntimeSSHTransport {
        #if os(macOS)
        return .externalBinary
        #else
        // iOS/iPadOS/tvOS/watchOS/visionOS use in-process libssh2 transport.
        return .inProcessLibssh2
        #endif
    }

    private static func runtimeDependencyTargets() -> [String] {
        switch runtimeSSHTransport() {
        case .externalBinary:
            return ["waypipe", "ssh", "weston", "foot", "xkbcommon"]
        case .inProcessLibssh2:
            return ["waypipe", "libssh2 (in-process)", "xkbcommon"]
        }
    }

    private static func probeDependencyAvailable(_ dependency: String) -> Bool {
        switch dependency {
        case "libssh2 (in-process)":
            // This transport is statically linked for Apple mobile targets.
            return true
        default:
            return probeCommandAvailable(dependency)
        }
    }

    private static func probeCommandAvailable(_ command: String) -> Bool {
        if command.contains("/") {
            return FileManager.default.isExecutableFile(atPath: command)
        }
        let searchPaths = [
            "/usr/bin",
            "/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/nix/var/nix/profiles/default/bin",
        ]
        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }
}
