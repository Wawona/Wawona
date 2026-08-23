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

public struct ResolvedMachineSettings: Hashable, Sendable {
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
    public var compositorBackend: String
}

@MainActor
public final class WawonaPreferences: ObservableObject {
    public static let shared = WawonaPreferences()

    private static var defaultVulkanDriver: String {
        #if os(tvOS) || os(watchOS)
        return "none"
        #elseif os(macOS) && arch(arm64)
        if #available(macOS 26.0, *) {
            return "kosmickrisp"
        }
        return "moltenvk"
        #else
        return "moltenvk"
        #endif
    }

    @Published public var renderer: String = "metal"
    @Published public var vulkanDriver: String = WawonaPreferences.defaultVulkanDriver
    @Published public var openGLDriver: String = "angle"
    @Published public var forceSSD: Bool = false
    @Published public var renderMacOSPointer: Bool = false
    /// "virtual" or "host"
    @Published public var nestedCompositorCursor: String = "virtual"
    @Published public var autoScale: Bool = true
    @Published public var colorOperations: Bool = true
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
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Multi-Touch" }
        switch trimmed.lowercased() {
        case "touchpad", "pointer", "virtual", "virtual-pointer", "trackpad":
            return "Touchpad"
        default:
            // "Multi-Touch", "multi-touch", "direct", "multitouch", …
            return "Multi-Touch"
        }
    }
    @Published public var defaultBundledAppID: String = ""
    @Published public var defaultWaypipeEnabled: Bool = true
    /// When true, Waypipe is launched with `--xwls` (XWayland integration) for supported sessions.
    @Published public var xwaylandSupport: Bool = false
    @Published public var compositorBackend: String = "auto"
    @Published public var nestedCompositorsSupport: Bool = true
    @Published public var multipleClients: Bool = true
    @Published public var universalClipboard: Bool = true
    @Published public var swapCmdWithAlt: Bool = true
    @Published public var resizeDisplayForVirtualKeyboard: Bool = true
    @Published public var waypipeCompress: String = "lz4"
    @Published public var waypipeVideo: String = "none"
    @Published public var waypipeRemoteCommand: String = ""
    @Published public var waypipeDebug: Bool = false
    @Published public var waypipeNoGpu: Bool = false
    @Published public var shakeToCloseEnabled: Bool = true
    @Published public var swipeBackToCloseEnabled: Bool = true
    @Published public var machineSessionThumbnailsEnabled: Bool = true
    @Published public var hasCompletedWelcome: Bool = false
    @Published public var globalClientLaunchers: [ClientLauncher] = ClientLauncher.presets
    @Published public var diagnostics: [SettingsDiagnosticEntry] = []
    /// Global environment overrides (`wawona.pref.environment.v1`). Absence of a key = inherit catalog/session default.
    @Published public var environmentOverrides: EnvironmentOverrideMap = [:]

    private let defaults = UserDefaults.standard
    private let keyPrefix = "wawona.pref."

    public init() {
        load()
    }

    public func load() {
        renderer = defaults.string(forKey: keyPrefix + "renderer") ?? "metal"
        vulkanDriver = defaults.string(forKey: "VulkanDriver") ?? WawonaPreferences.defaultVulkanDriver
        openGLDriver = defaults.string(forKey: "OpenGLDriver") ?? "angle"
        if defaults.object(forKey: "ForceServerSideDecorations") != nil {
            forceSSD = defaults.bool(forKey: "ForceServerSideDecorations")
        } else {
            forceSSD = defaults.bool(forKey: keyPrefix + "forceSSD")
        }
        renderMacOSPointer = defaults.bool(forKey: "RenderMacOSPointer")
        let nestedCursor = defaults.string(forKey: "NestedCompositorCursor") ?? "virtual"
        nestedCompositorCursor =
            (nestedCursor == "host" || nestedCursor == "virtual") ? nestedCursor : "virtual"
        autoScale = defaults.object(forKey: keyPrefix + "autoScale") as? Bool ?? true
        colorOperations = defaults.object(forKey: "ColorOperations") as? Bool
            ?? defaults.object(forKey: keyPrefix + "colorOperations") as? Bool ?? true
        waylandDisplay = defaults.string(forKey: keyPrefix + "waylandDisplay") ?? "wayland-0"
        sshHost = defaults.string(forKey: keyPrefix + "sshHost") ?? ""
        sshUser = defaults.string(forKey: keyPrefix + "sshUser") ?? ""
        sshPort = defaults.object(forKey: keyPrefix + "sshPort") as? Int ?? 22
        sshPassword = defaults.string(forKey: keyPrefix + "sshPassword") ?? ""
        if defaults.object(forKey: "SSHAuthMethod") != nil {
            sshAuthMethod = defaults.integer(forKey: "SSHAuthMethod")
        } else {
            sshAuthMethod = defaults.object(forKey: keyPrefix + "sshAuthMethod") as? Int ?? 0
        }
        sshKeyPath = defaults.string(forKey: "SSHKeyPath")
            ?? defaults.string(forKey: keyPrefix + "sshKeyPath") ?? ""
        sshKeyPassphrase = defaults.string(forKey: "SSHKeyPassphrase")
            ?? defaults.string(forKey: keyPrefix + "sshKeyPassphrase") ?? ""
        sshKeyType = defaults.string(forKey: "SSHKeyType")
            ?? defaults.string(forKey: keyPrefix + "sshKeyType") ?? "ed25519"
        waypipeSSHPassword = defaults.string(forKey: keyPrefix + "waypipeSSHPassword") ?? ""
        logLevel = defaults.string(forKey: keyPrefix + "logLevel") ?? "info"
        let loadedInput = defaults.string(forKey: keyPrefix + "defaultInputProfile")
            ?? defaults.string(forKey: "TouchInputType")
            ?? "Multi-Touch"
        defaultInputProfile = Self.normalizedTouchInputType(loadedInput)
        defaultBundledAppID = defaults.string(forKey: keyPrefix + "defaultBundledAppID") ?? "weston-terminal"
        defaultWaypipeEnabled = defaults.object(forKey: keyPrefix + "defaultWaypipeEnabled") as? Bool ?? true
        xwaylandSupport = defaults.object(forKey: keyPrefix + "xwaylandSupport") as? Bool
            ?? defaults.object(forKey: "WaypipeXwls") as? Bool ?? false
        compositorBackend = defaults.string(forKey: "CompositorBackend")
            ?? defaults.string(forKey: keyPrefix + "compositorBackend") ?? "auto"
        nestedCompositorsSupport = defaults.object(forKey: "NestedCompositorsSupport") as? Bool
            ?? defaults.object(forKey: keyPrefix + "nestedCompositorsSupport") as? Bool ?? true
        multipleClients = defaults.object(forKey: "MultipleClients") as? Bool
            ?? defaults.object(forKey: keyPrefix + "multipleClients") as? Bool ?? true
        universalClipboard = defaults.object(forKey: "UniversalClipboard") as? Bool
            ?? defaults.object(forKey: keyPrefix + "universalClipboard") as? Bool ?? true
        swapCmdWithAlt = defaults.object(forKey: "SwapCmdWithAlt") as? Bool
            ?? defaults.object(forKey: keyPrefix + "swapCmdWithAlt") as? Bool ?? true
        resizeDisplayForVirtualKeyboard = defaults.object(forKey: "resizeDisplayForVirtualKeyboard") as? Bool
            ?? defaults.object(forKey: keyPrefix + "resizeDisplayForVirtualKeyboard") as? Bool ?? true
        waypipeCompress = defaults.string(forKey: "WaypipeCompress")
            ?? defaults.string(forKey: keyPrefix + "waypipeCompress") ?? "lz4"
        waypipeVideo = defaults.string(forKey: "WaypipeVideo")
            ?? defaults.string(forKey: keyPrefix + "waypipeVideo") ?? "none"
        waypipeRemoteCommand = defaults.string(forKey: "WaypipeRemoteCommand")
            ?? defaults.string(forKey: keyPrefix + "waypipeRemoteCommand") ?? ""
        waypipeDebug = defaults.object(forKey: "WaypipeDebug") as? Bool
            ?? defaults.object(forKey: keyPrefix + "waypipeDebug") as? Bool ?? false
        waypipeNoGpu = defaults.object(forKey: "WaypipeNoGpu") as? Bool
            ?? defaults.object(forKey: keyPrefix + "waypipeNoGpu") as? Bool ?? false
        shakeToCloseEnabled = defaults.object(forKey: keyPrefix + "shakeToCloseEnabled") as? Bool ?? true
        swipeBackToCloseEnabled = defaults.object(forKey: keyPrefix + "swipeBackToCloseEnabled") as? Bool ?? true
        machineSessionThumbnailsEnabled =
            defaults.object(forKey: "MachineSessionThumbnailsEnabled") as? Bool
            ?? defaults.object(forKey: keyPrefix + "machineSessionThumbnailsEnabled") as? Bool
            ?? true
        hasCompletedWelcome = defaults.bool(forKey: keyPrefix + "hasCompletedWelcome")

        if let launchersData = defaults.data(forKey: keyPrefix + "globalClientLaunchers"),
           let launchers = try? JSONDecoder().decode([ClientLauncher].self, from: launchersData) {
            globalClientLaunchers = launchers
        }
        if let diagnosticsData = defaults.data(forKey: keyPrefix + "diagnostics"),
           let decoded = try? JSONDecoder().decode([SettingsDiagnosticEntry].self, from: diagnosticsData) {
            diagnostics = decoded
        }
        environmentOverrides = EnvironmentResolver.decodeMap(
            from: defaults.data(forKey: EnvironmentCatalog.storageKey)
        )
    }

    public func save() {
        defaults.set(renderer, forKey: keyPrefix + "renderer")
        defaults.set(vulkanDriver, forKey: "VulkanDriver")
        defaults.set(openGLDriver, forKey: "OpenGLDriver")
        let previousForceSSD = defaults.object(forKey: "ForceServerSideDecorations") as? Bool
            ?? defaults.bool(forKey: keyPrefix + "forceSSD")
        defaults.set(forceSSD, forKey: "ForceServerSideDecorations")
        defaults.set(forceSSD, forKey: keyPrefix + "forceSSD")
        // Bridge listens for this; without it, SwiftUI toggles only write
        // defaults and the Rust decoration policy never updates (weston stays
        // borderless even with Force SSD "on").
        if previousForceSSD != forceSSD {
            NotificationCenter.default.post(
                name: Notification.Name("WWNForceSSDChangedNotification"),
                object: nil
            )
        }
        defaults.set(renderMacOSPointer, forKey: "RenderMacOSPointer")
        defaults.set(
            (nestedCompositorCursor == "host") ? "host" : "virtual",
            forKey: "NestedCompositorCursor"
        )
        defaults.set(autoScale, forKey: keyPrefix + "autoScale")
        defaults.set(colorOperations, forKey: "ColorOperations")
        defaults.set(colorOperations, forKey: keyPrefix + "colorOperations")
        defaults.set(waylandDisplay, forKey: keyPrefix + "waylandDisplay")
        defaults.set(sshHost, forKey: keyPrefix + "sshHost")
        defaults.set(sshUser, forKey: keyPrefix + "sshUser")
        defaults.set(sshPort, forKey: keyPrefix + "sshPort")
        defaults.set(sshPassword, forKey: keyPrefix + "sshPassword")
        defaults.set(sshAuthMethod, forKey: keyPrefix + "sshAuthMethod")
        defaults.set(sshKeyPath, forKey: keyPrefix + "sshKeyPath")
        defaults.set(sshKeyPassphrase, forKey: keyPrefix + "sshKeyPassphrase")
        defaults.set(sshKeyType, forKey: keyPrefix + "sshKeyType")
        // Dual-sync ObjC Settings / waypipe keys so Machines + PTY share state.
        defaults.set(sshAuthMethod, forKey: "SSHAuthMethod")
        defaults.set(sshKeyPath, forKey: "SSHKeyPath")
        defaults.set(sshKeyPassphrase, forKey: "SSHKeyPassphrase")
        defaults.set(sshKeyType, forKey: "SSHKeyType")
        defaults.set(sshAuthMethod, forKey: "WaypipeSSHAuthMethod")
        defaults.set(sshKeyPath, forKey: "WaypipeSSHKeyPath")
        defaults.set(sshKeyPassphrase, forKey: "WaypipeSSHKeyPassphrase")
        defaults.set(waypipeSSHPassword, forKey: keyPrefix + "waypipeSSHPassword")
        defaults.set(logLevel, forKey: keyPrefix + "logLevel")
        defaults.set(defaultInputProfile, forKey: keyPrefix + "defaultInputProfile")
        defaults.set(defaultInputProfile, forKey: "TouchInputType")
        defaults.set(defaultBundledAppID, forKey: keyPrefix + "defaultBundledAppID")
        defaults.set(defaultWaypipeEnabled, forKey: keyPrefix + "defaultWaypipeEnabled")
        defaults.set(xwaylandSupport, forKey: keyPrefix + "xwaylandSupport")
        defaults.set(xwaylandSupport, forKey: "WaypipeXwls")
        defaults.set(compositorBackend, forKey: "CompositorBackend")
        defaults.set(compositorBackend, forKey: keyPrefix + "compositorBackend")
        defaults.set(nestedCompositorsSupport, forKey: "NestedCompositorsSupport")
        defaults.set(nestedCompositorsSupport, forKey: keyPrefix + "nestedCompositorsSupport")
        defaults.set(multipleClients, forKey: "MultipleClients")
        defaults.set(multipleClients, forKey: keyPrefix + "multipleClients")
        defaults.set(universalClipboard, forKey: "UniversalClipboard")
        defaults.set(universalClipboard, forKey: keyPrefix + "universalClipboard")
        defaults.set(swapCmdWithAlt, forKey: "SwapCmdWithAlt")
        defaults.set(swapCmdWithAlt, forKey: keyPrefix + "swapCmdWithAlt")
        defaults.set(resizeDisplayForVirtualKeyboard, forKey: "resizeDisplayForVirtualKeyboard")
        defaults.set(resizeDisplayForVirtualKeyboard, forKey: keyPrefix + "resizeDisplayForVirtualKeyboard")
        defaults.set(waypipeCompress, forKey: "WaypipeCompress")
        defaults.set(waypipeCompress, forKey: keyPrefix + "waypipeCompress")
        defaults.set(waypipeVideo, forKey: "WaypipeVideo")
        defaults.set(waypipeVideo, forKey: keyPrefix + "waypipeVideo")
        defaults.set(waypipeRemoteCommand, forKey: "WaypipeRemoteCommand")
        defaults.set(waypipeRemoteCommand, forKey: keyPrefix + "waypipeRemoteCommand")
        defaults.set(waypipeDebug, forKey: "WaypipeDebug")
        defaults.set(waypipeDebug, forKey: keyPrefix + "waypipeDebug")
        defaults.set(waypipeNoGpu, forKey: "WaypipeNoGpu")
        defaults.set(waypipeNoGpu, forKey: keyPrefix + "waypipeNoGpu")
        defaults.set(shakeToCloseEnabled, forKey: keyPrefix + "shakeToCloseEnabled")
        defaults.set(swipeBackToCloseEnabled, forKey: keyPrefix + "swipeBackToCloseEnabled")
        defaults.set(machineSessionThumbnailsEnabled, forKey: "MachineSessionThumbnailsEnabled")
        defaults.set(machineSessionThumbnailsEnabled, forKey: keyPrefix + "machineSessionThumbnailsEnabled")
        defaults.set(hasCompletedWelcome, forKey: keyPrefix + "hasCompletedWelcome")
        if let data = try? JSONEncoder().encode(globalClientLaunchers) {
            defaults.set(data, forKey: keyPrefix + "globalClientLaunchers")
        }
        if let diagnosticsData = try? JSONEncoder().encode(diagnostics) {
            defaults.set(diagnosticsData, forKey: keyPrefix + "diagnostics")
        }
        if let envData = EnvironmentResolver.encodeMap(environmentOverrides) {
            defaults.set(envData, forKey: EnvironmentCatalog.storageKey)
        } else {
            defaults.removeObject(forKey: EnvironmentCatalog.storageKey)
        }
        NotificationCenter.default.post(name: .wawonaPreferencesDidSave, object: self)
    }

    public func resolvedSettings(for profile: MachineProfile) -> ResolvedMachineSettings {
        let normalizedSSHHost = profile.sshHost.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let normalizedSSHUser = profile.sshUser.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let normalizedCommand = profile.remoteCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let normalizedBundledApp = profile.runtimeOverrides.bundledAppID?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedRenderer = profile.runtimeOverrides.renderer?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedVulkanDriver = profile.runtimeOverrides.vulkanDriver?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedOpenGLDriver = profile.runtimeOverrides.openGLDriver?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        // Empty/nil machine override → global default (then normalize legacy labels).
        let rawMachineInput = profile.runtimeOverrides.inputProfile?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedInputProfile = Self.normalizedTouchInputType(
            rawMachineInput.isEmpty ? defaultInputProfile : rawMachineInput
        )
        let normalizedWaylandDisplay = profile.runtimeOverrides.waylandDisplay?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedWaypipePassword = profile.runtimeOverrides.waypipeSSHPassword ?? ""
        let normalizedLogLevel = profile.runtimeOverrides.logLevel?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let normalizedCompositorBackend = profile.runtimeOverrides.compositorBackend?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        let resolvedWaypipeEnabled: Bool = {
            if profile.type == .native {
                return false
            }
            if profile.type == .sshWaypipe || profile.type == .sshTerminal {
                return profile.runtimeOverrides.waypipeEnabled ?? defaultWaypipeEnabled
            }
            return false
        }()

        return ResolvedMachineSettings(
            machineID: profile.id,
            machineName: profile.name,
            machineType: profile.type,
            renderer: normalizedRenderer.isEmpty ? renderer : normalizedRenderer,
            vulkanDriver: PlatformCapabilities.allowsGpuStack
                ? (normalizedVulkanDriver.isEmpty ? vulkanDriver : normalizedVulkanDriver)
                : "none",
            openGLDriver: PlatformCapabilities.allowsGpuStack
                ? (normalizedOpenGLDriver.isEmpty ? openGLDriver : normalizedOpenGLDriver)
                : "none",
            dmabufEnabled: PlatformCapabilities.allowsGpuStack
                ? (profile.runtimeOverrides.dmabufEnabled ?? true)
                : false,
            // Force SSD is macOS-only (#120): CSD only renders on macOS Wawona.
            // Everywhere else the resolved value is unconditionally SSD, so a
            // stored per-machine/global override can never yield a broken CSD
            // client on iOS/iPadOS/tvOS/watchOS/visionOS/Android.
            forceSSD: PlatformCapabilities.supportsClientSideDecorations
                ? (profile.runtimeOverrides.forceSSD ?? forceSSD)
                : true,
            renderMacOSPointer: profile.runtimeOverrides.renderMacOSPointer ?? renderMacOSPointer,
            nestedCompositorCursor: {
                let override = profile.runtimeOverrides.nestedCompositorCursor?
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
                if override == "host" || override == "virtual" { return override }
                return nestedCompositorCursor
            }(),
            autoScale: profile.runtimeOverrides.autoScale ?? autoScale,
            colorOperations: profile.runtimeOverrides.colorOperations ?? colorOperations,
            waylandDisplay: normalizedWaylandDisplay.isEmpty ? waylandDisplay : normalizedWaylandDisplay,
            sshHost: normalizedSSHHost.isEmpty ? sshHost : normalizedSSHHost,
            sshUser: normalizedSSHUser.isEmpty ? sshUser : normalizedSSHUser,
            sshPort: profile.sshPort > 0 ? profile.sshPort : sshPort,
            sshPassword: profile.sshPassword.isEmpty ? sshPassword : profile.sshPassword,
            waypipeSSHPassword: normalizedWaypipePassword.isEmpty ? waypipeSSHPassword : normalizedWaypipePassword,
            remoteCommand: normalizedCommand.isEmpty ? "weston-simple-shm" : normalizedCommand,
            waypipeEnabled: resolvedWaypipeEnabled,
            bundledAppID: normalizedBundledApp.isEmpty ? defaultBundledAppID : normalizedBundledApp,
            inputProfile: normalizedInputProfile,
            logLevel: normalizedLogLevel.isEmpty ? logLevel : normalizedLogLevel,
            shakeToCloseEnabled: profile.runtimeOverrides.shakeToCloseEnabled ?? shakeToCloseEnabled,
            swipeBackToCloseEnabled: profile.runtimeOverrides.swipeBackToCloseEnabled ?? swipeBackToCloseEnabled,
            compositorBackend: {
                let allowed = Set(["auto", "wayland", "drm"])
                if allowed.contains(normalizedCompositorBackend.lowercased()) {
                    return normalizedCompositorBackend.lowercased()
                }
                return compositorBackend
            }()
        )
    }

    /// Resolve environment rows for Settings UI / launch (machine > global > catalog/session).
    /// Pass `machineOverrideMap` to preview a draft (e.g. machine editor) without upserting yet.
    public func resolvedEnvironment(
        for profile: MachineProfile?,
        machineOverrideMap: EnvironmentOverrideMap? = nil,
        session: EnvironmentSessionContext = EnvironmentSessionContext(),
        stripBannedLocalShellKeys: Bool = false
    ) -> [ResolvedEnvironmentEntry] {
        var ctx = session
        let resolved = profile.map { resolvedSettings(for: $0) }
        ctx.waylandDisplay = resolved?.waylandDisplay ?? waylandDisplay
        ctx.vulkanDriver = resolved?.vulkanDriver ?? vulkanDriver
        ctx.openGLDriver = resolved?.openGLDriver ?? openGLDriver
        let backend = resolved?.compositorBackend ?? compositorBackend
        ctx.niriBackend = EnvironmentResolver.niriBackend(for: backend)
        let level = resolved?.logLevel ?? logLevel
        ctx.rustLog = EnvironmentResolver.rustLog(for: level)
        ctx.disableVulkan = (ctx.vulkanDriver == "none")
        ctx.disableEGL = (ctx.openGLDriver == "none")
        if ctx.anglePlatform.isEmpty {
            ctx.anglePlatform = "metal"
        }

        let machine =
            machineOverrideMap
            ?? profile?.runtimeOverrides.environment
            ?? [:]

        return EnvironmentResolver.resolve(
            globalOverrides: environmentOverrides,
            machineOverrides: machine,
            session: ctx,
            includeSecrets: false,
            stripBannedLocalShellKeys: stripBannedLocalShellKeys
        )
    }

    public func setEnvironmentOverride(name: String, override: EnvironmentOverride?) {
        var next = environmentOverrides
        if let override {
            next[name] = override
        } else {
            EnvironmentResolver.resetOne(&next, name: name)
        }
        environmentOverrides = next
        save()
    }

    public func resetEnvironmentManaged() {
        var next = environmentOverrides
        EnvironmentResolver.resetWawonaManaged(&next)
        environmentOverrides = next
        save()
    }

    public func resetEnvironmentAll() {
        var next = environmentOverrides
        EnvironmentResolver.resetAll(&next)
        environmentOverrides = next
        save()
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
