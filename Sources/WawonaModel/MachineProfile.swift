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

    /// Remote SSH session types. Native, VM, and container do not use SSH/Waypipe fields.
    public var isSSH: Bool {
        switch self {
        case .sshWaypipe, .sshTerminal: return true
        default: return false
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

/// Per-machine container configuration (machine type `container`).
///
/// Every field is optional: a nil field inherits the global Wawona Settings →
/// Containers default at resolution time, so a brand-new container machine
/// created with empty fields runs exactly the global defaults.
///
/// JSON keys match the Android `ContainerSettings` schema (`runtime`,
/// `containerRef`, `entryCommand`, `notes`) and extend it with the macOS
/// Apple `container` CLI surface (memory/shm/mounts/ports/…). Unknown keys on
/// other platforms are ignored on decode.
public struct ContainerMachineSettings: Codable, Hashable, Sendable {
    /// Backend runtime label. Fixed per build target (macOS:
    /// "containerization"); kept as a display/record field, never user-set.
    public var runtime: String?
    /// OCI image reference, e.g. `alpine:3.20`, `python:3.12-slim`,
    /// `ghcr.io/org/app`. Docker Hub shorthand is accepted.
    public var containerRef: String?
    /// Command (and args) to run in the container; maps to the CLI's
    /// `[cmd...]` positional args.
    public var entryCommand: String?
    /// Free-form notes shown in the machine editor.
    public var notes: String?
    /// `--memory` (1MiB granularity, K/M/G/T/P suffixes accepted).
    public var memory: String?
    /// `--shm-size` (e.g. 64M, 1G).
    public var shmSize: String?
    /// `--mount` specs (`type=<>,source=<>,target=<>,readonly`).
    public var mounts: [String]?
    /// `--publish` specs (`[host-ip:]host-port:container-port[/protocol]`).
    public var ports: [String]?
    /// `--platform` (e.g. linux/arm64); takes precedence over os/arch.
    public var platform: String?
    /// `--read-only`: mount the container rootfs read-only.
    public var readOnly: Bool?
    /// `--init`: run an init process (signal forwarding + zombie reaping).
    public var initProcess: Bool?
    /// `--rm`: remove the container after it stops.
    public var remove: Bool?
    /// `--kernel` path override (maps to WAWONA_VM_KERNEL).
    public var kernelPath: String?
    /// Prebuilt vminitd initfs override (maps to WAWONA_VM_INITFS).
    public var initfsPath: String?
    /// vsock port the guest waypipe server binds (maps to
    /// `--wayland-vsock-port` when the GUI session attaches).
    public var vsockPort: Int?
    /// Desktop session: attach the container's Wayland session to Wawona via
    /// the waypipe vsock bridge (a window per surface, or one window for a
    /// nested compositor image). Product default is ON when the key is absent.
    /// Explicit false keeps a terminal-only (weston-terminal) session.
    public var desktopSession: Bool?
    /// Local OCI layout directory to run from instead of pulling `containerRef`
    /// from a registry (`--image-archive`). Emitted by `container import` next
    /// to the unpacked rootfs.
    public var imageArchivePath: String?

    public init(
        runtime: String? = nil,
        containerRef: String? = nil,
        entryCommand: String? = nil,
        notes: String? = nil,
        memory: String? = nil,
        shmSize: String? = nil,
        mounts: [String]? = nil,
        ports: [String]? = nil,
        platform: String? = nil,
        readOnly: Bool? = nil,
        initProcess: Bool? = nil,
        remove: Bool? = nil,
        kernelPath: String? = nil,
        initfsPath: String? = nil,
        vsockPort: Int? = nil,
        desktopSession: Bool? = nil,
        imageArchivePath: String? = nil
    ) {
        self.runtime = runtime
        self.containerRef = containerRef
        self.entryCommand = entryCommand
        self.notes = notes
        self.memory = memory
        self.shmSize = shmSize
        self.mounts = mounts
        self.ports = ports
        self.platform = platform
        self.readOnly = readOnly
        self.initProcess = initProcess
        self.remove = remove
        self.kernelPath = kernelPath
        self.initfsPath = initfsPath
        self.vsockPort = vsockPort
        self.desktopSession = desktopSession
        self.imageArchivePath = imageArchivePath
    }
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
    /// "virtual" or "host". Nested compositor cursor grab when virtual cursor is on.
    public var nestedCompositorCursor: String?
    public var autoScale: Bool?
    public var waylandDisplay: String?
    public var colorOperations: Bool?
    public var waypipeSSHPassword: String?
    public var logLevel: String?
    public var shakeToCloseEnabled: Bool?
    public var swipeBackToCloseEnabled: Bool?
    /// Per-machine Display Backend override (`auto` | `wayland` | `drm`).
    public var compositorBackend: String?
    /// Absolute or sandbox-relative path to a Wayland `.wasm` for `bundledAppID == wawona-wasm`.
    public var wasmModulePath: String?
    /// Explicit env overrides (#157). Never stash in settingsOverrides. Codable drops unknown keys.
    public var environment: EnvironmentOverrideMap?

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
        nestedCompositorCursor: String? = nil,
        autoScale: Bool? = nil,
        waylandDisplay: String? = nil,
        colorOperations: Bool? = nil,
        waypipeSSHPassword: String? = nil,
        logLevel: String? = nil,
        shakeToCloseEnabled: Bool? = nil,
        swipeBackToCloseEnabled: Bool? = nil,
        compositorBackend: String? = nil,
        wasmModulePath: String? = nil,
        environment: EnvironmentOverrideMap? = nil
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
        self.nestedCompositorCursor = nestedCompositorCursor
        self.autoScale = autoScale
        self.waylandDisplay = waylandDisplay
        self.colorOperations = colorOperations
        self.waypipeSSHPassword = waypipeSSHPassword
        self.logLevel = logLevel
        self.shakeToCloseEnabled = shakeToCloseEnabled
        self.swipeBackToCloseEnabled = swipeBackToCloseEnabled
        self.compositorBackend = compositorBackend
        self.wasmModulePath = wasmModulePath
        self.environment = environment
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
    /// Container machine configuration (nil = inherit all global defaults).
    public var containerSettings: ContainerMachineSettings?

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
        case containerSettings
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
        runtimeOverrides: MachineRuntimeOverrides = MachineRuntimeOverrides(),
        containerSettings: ContainerMachineSettings? = nil
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
        self.containerSettings = containerSettings
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
        containerSettings = try container.decodeIfPresent(ContainerMachineSettings.self, forKey: .containerSettings)
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
        try container.encodeIfPresent(containerSettings, forKey: .containerSettings)
    }
}

// MARK: - Wawona Swinging Bridge eligibility

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
    /// For Swinging Bridge v1 this is intentionally restricted to **weston nested**
    /// (`weston` running `--backend=wayland`); other nesting hosts are out of
    /// scope (see Wawona-Swinging-Bridge README "Scope").
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

    /// Nested Wayland compositor that paints `wl_pointer` itself (weston, niri,
    /// sway, labwc, …). Host and virtual cursor overlays must stay hidden.
    /// Keep in sync with `WWNMachineProfileStore
    /// profileIndicatesNestedWithNativeClientId:customCommand:`.
    /// Not Swinging Bridge (`isNestedCompositorClient` is weston-only).
    public var nestedCompositorDrawsOwnCursor: Bool {
        guard type == .native else { return false }
        let cid = resolvedNativeClientId
        if cid == "weston" || cid.hasSuffix("/weston") { return true }
        if cid == "niri" || cid.hasSuffix("/niri") { return true }
        if cid != "custom" { return false }
        let cmd = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cmd.isEmpty { return false }
        if cmd.contains("weston-simple-shm") || cmd.contains("weston-terminal") { return false }
        if cmd == "foot" || cmd.hasSuffix("/foot") || cmd.hasSuffix(" foot") { return false }
        let nestedHints = [
            "sway", "cage", "hyprland", "wayfire", "labwc",
            "cosmic-comp", "cosmic_comp", "gnome-shell", "mutter", "kwin",
            "niri", "river", "tinywl", "wf-panel",
        ]
        if nestedHints.contains(where: { cmd.contains($0) }) { return true }
        return cmd.contains("weston")
    }

    /// The Wawona Swinging Bridge desktop machine may be selected **only** when it
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
