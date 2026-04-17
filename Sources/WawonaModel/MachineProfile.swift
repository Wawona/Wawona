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
    public var autoScale: Bool?
    public var waylandDisplay: String?
    public var colorOperations: Bool?

    public init(
        renderer: String? = nil,
        vulkanDriver: String? = nil,
        openGLDriver: String? = nil,
        dmabufEnabled: Bool? = nil,
        inputProfile: String? = nil,
        bundledAppID: String? = nil,
        waypipeEnabled: Bool? = nil,
        forceSSD: Bool? = nil,
        autoScale: Bool? = nil,
        waylandDisplay: String? = nil,
        colorOperations: Bool? = nil
    ) {
        self.renderer = renderer
        self.vulkanDriver = vulkanDriver
        self.openGLDriver = openGLDriver
        self.dmabufEnabled = dmabufEnabled
        self.inputProfile = inputProfile
        self.bundledAppID = bundledAppID
        self.waypipeEnabled = waypipeEnabled
        self.forceSSD = forceSSD
        self.autoScale = autoScale
        self.waylandDisplay = waylandDisplay
        self.colorOperations = colorOperations
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
    public var remoteCommand: String
    public var vmSubtype: String
    public var containerSubtype: String
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
        case remoteCommand
        case vmSubtype
        case containerSubtype
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
        remoteCommand: String = "weston-simple-shm",
        vmSubtype: String = "",
        containerSubtype: String = "",
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
        self.remoteCommand = remoteCommand
        self.vmSubtype = vmSubtype
        self.containerSubtype = containerSubtype
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
        remoteCommand = try container.decodeIfPresent(String.self, forKey: .remoteCommand) ?? "weston-simple-shm"
        vmSubtype = try container.decodeIfPresent(String.self, forKey: .vmSubtype) ?? ""
        containerSubtype = try container.decodeIfPresent(String.self, forKey: .containerSubtype) ?? ""
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
        try container.encode(remoteCommand, forKey: .remoteCommand)
        try container.encode(vmSubtype, forKey: .vmSubtype)
        try container.encode(containerSubtype, forKey: .containerSubtype)
        try container.encode(launchers, forKey: .launchers)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(runtimeOverrides, forKey: .runtimeOverrides)
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
