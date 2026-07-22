import Combine
import Foundation

public enum MachineType: String, Codable, CaseIterable, Sendable {
    case native
    case sshWaypipe = "ssh_waypipe"
    case sshTerminal = "ssh_terminal"
    case virtualMachine = "virtual_machine"
    case container
}

extension MachineType {
    /// Human-readable type name for pickers and lists (matches macOS editor wording; not the storage `rawValue`).
    public var userFacingName: String {
        switch self {
        case .native: return "Native"
        case .sshWaypipe: return "SSH + Waypipe"
        case .sshTerminal: return "SSH Terminal"
        case .virtualMachine: return "Virtual Machine"
        case .container: return "Container"
        }
    }

    /// Backend engine label for virtual-machine and container types.
    ///
    /// The engine is fixed per build target by the `wwn-vms` / `wwn-containers`
    /// capability lanes and is never user-configurable (Residual E). This is a
    /// read-only display string; it returns `nil` for types without a distinct
    /// engine.
    public var backendEngineLabel: String? {
        switch self {
        case .virtualMachine:
            #if os(macOS)
            return "Virtualization.framework"
            #else
            return "QEMU (TCTI)"
            #endif
        case .container:
            #if os(macOS)
            return "containerization.framework"
            #else
            return "container-in-VM"
            #endif
        default:
            return nil
        }
    }

    /// SF Symbol name for this machine type (shared across iOS and watchOS).
    public var symbolName: String {
        switch self {
        case .native: return "desktopcomputer"
        case .sshWaypipe: return "network"
        case .sshTerminal: return "terminal"
        case .virtualMachine: return "cube"
        case .container: return "shippingbox"
        }
    }
}

public enum MachineStatus: String, Codable, CaseIterable, Sendable {
    case disconnected
    case connecting
    case connected
    case degraded
    case error
}

public struct MachineRuntimeOverrides: Codable, Hashable, Sendable {
    public var renderer: String?
    public var vulkanDriver: String?
    public var openGLDriver: String?
    public var dmabufEnabled: Bool?
    public var inputProfile: String?
    public var bundledAppID: String?
    public var waypipeEnabled: Bool?
    public var forceSSD: Bool?
    public var renderMacOSPointer: Bool?
    public var autoScale: Bool?
    public var waylandDisplay: String?
    public var colorOperations: Bool?
    public var waypipeSSHPassword: String?
    public var logLevel: String?
    public var shakeToCloseEnabled: Bool?
    public var swipeBackToCloseEnabled: Bool?

    public init(
        renderer: String? = nil,
        vulkanDriver: String? = nil,
        openGLDriver: String? = nil,
        dmabufEnabled: Bool? = nil,
        inputProfile: String? = nil,
        bundledAppID: String? = nil,
        waypipeEnabled: Bool? = nil,
        forceSSD: Bool? = nil,
        renderMacOSPointer: Bool? = nil,
        autoScale: Bool? = nil,
        waylandDisplay: String? = nil,
        colorOperations: Bool? = nil,
        waypipeSSHPassword: String? = nil,
        logLevel: String? = nil,
        shakeToCloseEnabled: Bool? = nil,
        swipeBackToCloseEnabled: Bool? = nil
    ) {
        self.renderer = renderer
        self.vulkanDriver = vulkanDriver
        self.openGLDriver = openGLDriver
        self.dmabufEnabled = dmabufEnabled
        self.inputProfile = inputProfile
        self.bundledAppID = bundledAppID
        self.waypipeEnabled = waypipeEnabled
        self.forceSSD = forceSSD
        self.renderMacOSPointer = renderMacOSPointer
        self.autoScale = autoScale
        self.waylandDisplay = waylandDisplay
        self.colorOperations = colorOperations
        self.waypipeSSHPassword = waypipeSSHPassword
        self.logLevel = logLevel
        self.shakeToCloseEnabled = shakeToCloseEnabled
        self.swipeBackToCloseEnabled = swipeBackToCloseEnabled
    }
}

public struct MachineProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: MachineType
    public var sshHost: String
    public var sshUser: String
    public var sshPort: Int
    public var sshPassword: String
    public var sshAuthMethod: Int
    public var sshKeyPath: String
    public var sshKeyPassphrase: String
    public var remoteCommand: String
    public var launchers: [ClientLauncher]
    public var favorite: Bool
    public var runtimeOverrides: MachineRuntimeOverrides

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case sshHost
        case sshUser
        case sshPort
        case sshPassword
        case sshAuthMethod
        case sshKeyPath
        case sshKeyPassphrase
        case remoteCommand
        case launchers
        case favorite
        case runtimeOverrides
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: MachineType = .native,
        sshHost: String = "",
        sshUser: String = "",
        sshPort: Int = 22,
        sshPassword: String = "",
        sshAuthMethod: Int = 0,
        sshKeyPath: String = "",
        sshKeyPassphrase: String = "",
        remoteCommand: String = "weston-simple-shm",
        launchers: [ClientLauncher] = [],
        favorite: Bool = false,
        runtimeOverrides: MachineRuntimeOverrides = MachineRuntimeOverrides()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.sshHost = sshHost
        self.sshUser = sshUser
        self.sshPort = sshPort
        self.sshPassword = sshPassword
        self.sshAuthMethod = sshAuthMethod
        self.sshKeyPath = sshKeyPath
        self.sshKeyPassphrase = sshKeyPassphrase
        self.remoteCommand = remoteCommand
        self.launchers = launchers
        self.favorite = favorite
        self.runtimeOverrides = runtimeOverrides
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed"
        type = try container.decodeIfPresent(MachineType.self, forKey: .type) ?? MachineType.native
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshUser = try container.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshPassword = try container.decodeIfPresent(String.self, forKey: .sshPassword) ?? ""
        sshAuthMethod = try container.decodeIfPresent(Int.self, forKey: .sshAuthMethod) ?? 0
        sshKeyPath = try container.decodeIfPresent(String.self, forKey: .sshKeyPath) ?? ""
        sshKeyPassphrase = try container.decodeIfPresent(String.self, forKey: .sshKeyPassphrase) ?? ""
        remoteCommand = try container.decodeIfPresent(String.self, forKey: .remoteCommand) ?? "weston-simple-shm"
        // vmSubtype / containerSubtype were removed (Residual E): backend
        // selection is fixed per build target, not user-editable. Any such keys
        // in legacy JSON are ignored on decode.
        launchers = try container.decodeIfPresent([ClientLauncher].self, forKey: .launchers) ?? []
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        runtimeOverrides = try container.decodeIfPresent(MachineRuntimeOverrides.self, forKey: .runtimeOverrides) ?? MachineRuntimeOverrides()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(sshHost, forKey: .sshHost)
        try container.encode(sshUser, forKey: .sshUser)
        try container.encode(sshPort, forKey: .sshPort)
        try container.encode(sshPassword, forKey: .sshPassword)
        try container.encode(sshAuthMethod, forKey: .sshAuthMethod)
        try container.encode(sshKeyPath, forKey: .sshKeyPath)
        try container.encode(sshKeyPassphrase, forKey: .sshKeyPassphrase)
        try container.encode(remoteCommand, forKey: .remoteCommand)
        try container.encode(launchers, forKey: .launchers)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(runtimeOverrides, forKey: .runtimeOverrides)
    }
}

// MARK: - App Bridge (anowaW) eligibility

extension MachineProfile {
    /// The effective client id this native machine launches, resolved from the
    /// runtime override (`bundledAppID`) or the auto-launch launcher, else the
    /// `remoteCommand`. Lowercased and trimmed.
    public var resolvedNativeClientId: String {
        let candidate = runtimeOverrides.bundledAppID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty { return candidate.lowercased() }
        if let auto = launchers.first(where: { $0.autoLaunch }) ?? launchers.first {
            let name = auto.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name.lowercased() }
        }
        return remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when this is a local-only native machine whose client is a **nested
    /// Wayland compositor** rather than a plain Weston demo client
    /// (`weston-terminal`, `weston-simple-shm`, `foot`, toytoolkit).
    ///
    /// For anowaW v1 this is intentionally restricted to **weston nested**
    /// (`weston` running `--backend=wayland`); other nesting hosts are out of
    /// scope (see wwn-anowaW README "Scope").
    public var isNestedCompositorClient: Bool {
        guard type == .native else { return false }
        let cid = resolvedNativeClientId
        // Reject demo/toolkit clients explicitly.
        if cid.contains("weston-terminal") || cid.contains("weston-simple-shm") { return false }
        if cid == "foot" || cid.hasSuffix("/foot") || cid.hasSuffix(" foot") { return false }
        // v1: only the nested `weston` compositor qualifies.
        return cid == "weston" || cid.hasSuffix("/weston")
            || cid.contains("weston --backend=wayland")
            || cid.contains("weston-backend=wayland")
    }

    /// The App Bridge (anowaW) desktop machine may be selected **only** when it
    /// is a local-only, nested-Weston native machine. Mirrors the Kotlin
    /// `MachineProfile.isAppBridgeEligible` and the ObjC
    /// `profileEligibleForAppBridge:`.
    public var isAppBridgeEligible: Bool {
        type == .native && isNestedCompositorClient
    }
}

@MainActor
public final class MachineProfileStore: ObservableObject {
    public static let profilesKey = "wawona.machineProfiles.v1"
    public static let activeMachineIdKey = "wawona.activeMachineId.v1"

    @Published public private(set) var profiles: [MachineProfile] = []
    @Published public var activeMachineId: String?

    public init() {
        load()
    }

    public func load() {
        let defaults = UserDefaults.standard
        activeMachineId = defaults.string(forKey: Self.activeMachineIdKey)
        var payload: Data?
        if let data = defaults.data(forKey: Self.profilesKey) {
            payload = data
        } else if let legacyString = defaults.string(forKey: Self.profilesKey) {
            payload = legacyString.data(using: .utf8)
        }
        guard let data = payload else {
            profiles = []
            return
        }
        do {
            profiles = try JSONDecoder().decode([MachineProfile].self, from: data)
            // Canonicalize persisted representation to data payload.
            save()
        } catch {
            profiles = []
        }
    }

    public func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.profilesKey)
        }
        defaults.set(activeMachineId, forKey: Self.activeMachineIdKey)
    }

    public func upsert(_ profile: MachineProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            var next = profiles
            next[idx] = profile
            profiles = next
        } else {
            profiles = profiles + [profile]
        }
        save()
    }

    public func delete(id: String) {
        profiles = profiles.filter { $0.id != id }
        if activeMachineId == id {
            activeMachineId = nil
        }
        save()
    }

    public func profile(for id: String?) -> MachineProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }
}
