import Combine
import Foundation

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

public struct ResolvedMachineSettings: Hashable, Sendable {
    public var machineID: String
    public var machineName: String
    public var machineType: MachineType
    public var renderer: String
    public var vulkanDriver: String
    public var openGLDriver: String
    public var dmabufEnabled: Bool
    public var forceSSD: Bool
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
}

@MainActor
public final class WawonaPreferences: ObservableObject {
    public static let shared = WawonaPreferences()

    @Published public var renderer: String = "metal"
    @Published public var forceSSD: Bool = false
    @Published public var autoScale: Bool = true
    @Published public var colorOperations: Bool = false
    @Published public var waylandDisplay: String = "wayland-0"
    @Published public var sshHost: String = ""
    @Published public var sshUser: String = ""
    @Published public var sshPort: Int = 22
    @Published public var sshPassword: String = ""
    @Published public var waypipeSSHPassword: String = ""
    @Published public var logLevel: String = "info"
    @Published public var defaultInputProfile: String = "direct"
    @Published public var defaultBundledAppID: String = ""
    @Published public var defaultWaypipeEnabled: Bool = true
    @Published public var shakeToCloseEnabled: Bool = true
    @Published public var hasCompletedWelcome: Bool = false
    @Published public var globalClientLaunchers: [ClientLauncher] = ClientLauncher.presets
    @Published public var diagnostics: [SettingsDiagnosticEntry] = []

    private let defaults = UserDefaults.standard
    private let keyPrefix = "wawona.pref."

    public init() {
        load()
    }

    public func load() {
        renderer = defaults.string(forKey: keyPrefix + "renderer") ?? "metal"
        forceSSD = defaults.bool(forKey: keyPrefix + "forceSSD")
        autoScale = defaults.object(forKey: keyPrefix + "autoScale") as? Bool ?? true
        colorOperations = defaults.object(forKey: keyPrefix + "colorOperations") as? Bool ?? false
        waylandDisplay = defaults.string(forKey: keyPrefix + "waylandDisplay") ?? "wayland-0"
        sshHost = defaults.string(forKey: keyPrefix + "sshHost") ?? ""
        sshUser = defaults.string(forKey: keyPrefix + "sshUser") ?? ""
        sshPort = defaults.object(forKey: keyPrefix + "sshPort") as? Int ?? 22
        sshPassword = defaults.string(forKey: keyPrefix + "sshPassword") ?? ""
        waypipeSSHPassword = defaults.string(forKey: keyPrefix + "waypipeSSHPassword") ?? ""
        logLevel = defaults.string(forKey: keyPrefix + "logLevel") ?? "info"
        defaultInputProfile = defaults.string(forKey: keyPrefix + "defaultInputProfile") ?? "direct"
        defaultBundledAppID = defaults.string(forKey: keyPrefix + "defaultBundledAppID") ?? "weston-simple-shm"
        defaultWaypipeEnabled = defaults.object(forKey: keyPrefix + "defaultWaypipeEnabled") as? Bool ?? true
        shakeToCloseEnabled = defaults.object(forKey: keyPrefix + "shakeToCloseEnabled") as? Bool ?? true
        hasCompletedWelcome = defaults.bool(forKey: keyPrefix + "hasCompletedWelcome")

        if let launchersData = defaults.data(forKey: keyPrefix + "globalClientLaunchers"),
           let launchers = try? JSONDecoder().decode([ClientLauncher].self, from: launchersData) {
            globalClientLaunchers = launchers
        }
        if let diagnosticsData = defaults.data(forKey: keyPrefix + "diagnostics"),
           let decoded = try? JSONDecoder().decode([SettingsDiagnosticEntry].self, from: diagnosticsData) {
            diagnostics = decoded
        }
    }

    public func save() {
        defaults.set(renderer, forKey: keyPrefix + "renderer")
        defaults.set(forceSSD, forKey: keyPrefix + "forceSSD")
        defaults.set(autoScale, forKey: keyPrefix + "autoScale")
        defaults.set(colorOperations, forKey: keyPrefix + "colorOperations")
        defaults.set(waylandDisplay, forKey: keyPrefix + "waylandDisplay")
        defaults.set(sshHost, forKey: keyPrefix + "sshHost")
        defaults.set(sshUser, forKey: keyPrefix + "sshUser")
        defaults.set(sshPort, forKey: keyPrefix + "sshPort")
        defaults.set(sshPassword, forKey: keyPrefix + "sshPassword")
        defaults.set(waypipeSSHPassword, forKey: keyPrefix + "waypipeSSHPassword")
        defaults.set(logLevel, forKey: keyPrefix + "logLevel")
        defaults.set(defaultInputProfile, forKey: keyPrefix + "defaultInputProfile")
        defaults.set(defaultBundledAppID, forKey: keyPrefix + "defaultBundledAppID")
        defaults.set(defaultWaypipeEnabled, forKey: keyPrefix + "defaultWaypipeEnabled")
        defaults.set(shakeToCloseEnabled, forKey: keyPrefix + "shakeToCloseEnabled")
        defaults.set(hasCompletedWelcome, forKey: keyPrefix + "hasCompletedWelcome")
        if let data = try? JSONEncoder().encode(globalClientLaunchers) {
            defaults.set(data, forKey: keyPrefix + "globalClientLaunchers")
        }
        if let diagnosticsData = try? JSONEncoder().encode(diagnostics) {
            defaults.set(diagnosticsData, forKey: keyPrefix + "diagnostics")
        }
    }

    public func resolvedSettings(for profile: MachineProfile) -> ResolvedMachineSettings {
        let normalizedSSHHost = profile.sshHost.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let normalizedSSHUser = profile.sshUser.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let normalizedCommand = profile.remoteCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let normalizedBundledApp = profile.runtimeOverrides.bundledAppID?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedRenderer = profile.runtimeOverrides.renderer?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedVulkanDriver = profile.runtimeOverrides.vulkanDriver?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedOpenGLDriver = profile.runtimeOverrides.openGLDriver?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedInputProfile = profile.runtimeOverrides.inputProfile?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedWaylandDisplay = profile.runtimeOverrides.waylandDisplay?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedWaypipePassword = profile.runtimeOverrides.waypipeSSHPassword ?? ""
        let normalizedLogLevel = profile.runtimeOverrides.logLevel?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        return ResolvedMachineSettings(
            machineID: profile.id,
            machineName: profile.name,
            machineType: profile.type,
            renderer: normalizedRenderer.isEmpty ? renderer : normalizedRenderer,
            vulkanDriver: normalizedVulkanDriver.isEmpty ? "moltenvk" : normalizedVulkanDriver,
            openGLDriver: normalizedOpenGLDriver.isEmpty ? "angle" : normalizedOpenGLDriver,
            dmabufEnabled: profile.runtimeOverrides.dmabufEnabled ?? true,
            forceSSD: profile.runtimeOverrides.forceSSD ?? forceSSD,
            autoScale: profile.runtimeOverrides.autoScale ?? autoScale,
            colorOperations: profile.runtimeOverrides.colorOperations ?? colorOperations,
            waylandDisplay: normalizedWaylandDisplay.isEmpty ? waylandDisplay : normalizedWaylandDisplay,
            sshHost: normalizedSSHHost.isEmpty ? sshHost : normalizedSSHHost,
            sshUser: normalizedSSHUser.isEmpty ? sshUser : normalizedSSHUser,
            sshPort: profile.sshPort > 0 ? profile.sshPort : sshPort,
            sshPassword: profile.sshPassword.isEmpty ? sshPassword : profile.sshPassword,
            waypipeSSHPassword: normalizedWaypipePassword.isEmpty ? waypipeSSHPassword : normalizedWaypipePassword,
            remoteCommand: normalizedCommand.isEmpty ? "weston-simple-shm" : normalizedCommand,
            waypipeEnabled: profile.runtimeOverrides.waypipeEnabled ?? defaultWaypipeEnabled,
            bundledAppID: normalizedBundledApp.isEmpty ? defaultBundledAppID : normalizedBundledApp,
            inputProfile: normalizedInputProfile.isEmpty ? defaultInputProfile : normalizedInputProfile,
            logLevel: normalizedLogLevel.isEmpty ? logLevel : normalizedLogLevel,
            shakeToCloseEnabled: profile.runtimeOverrides.shakeToCloseEnabled ?? shakeToCloseEnabled
        )
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
