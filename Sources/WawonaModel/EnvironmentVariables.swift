import Foundation

// MARK: - Override action

/// Persisted env override: set a value or force-unset.
public struct EnvironmentOverride: Codable, Hashable, Sendable {
    public enum Action: String, Codable, Hashable, Sendable {
        case set
        case unset
    }

    public var action: Action
    public var value: String?

    public init(action: Action, value: String? = nil) {
        self.action = action
        self.value = value
    }

    public static func set(_ value: String) -> EnvironmentOverride {
        EnvironmentOverride(action: .set, value: value)
    }

    public static var unset: EnvironmentOverride {
        EnvironmentOverride(action: .unset, value: nil)
    }
}

public typealias EnvironmentOverrideMap = [String: EnvironmentOverride]

// MARK: - Catalog

public enum EnvironmentMutability: String, Codable, Hashable, Sendable, CaseIterable {
    case computed
    case managed
    case defaulted
    case user
    case secret
}

public enum EnvironmentCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case session
    case graphics
    case shell
    case xdg
    case fonts
    case input
    case debug
    case secrets
    case user
}

public struct EnvironmentCatalogEntry: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var category: EnvironmentCategory
    public var mutability: EnvironmentMutability
    public var ownedBy: String?
    /// Literal default, or a resolver token (e.g. `waylandDisplay`, `term`).
    public var defaultToken: String
    public var resettable: Bool
    public var help: String?

    public init(
        name: String,
        category: EnvironmentCategory,
        mutability: EnvironmentMutability,
        ownedBy: String? = nil,
        defaultToken: String = "",
        resettable: Bool = true,
        help: String? = nil
    ) {
        self.name = name
        self.category = category
        self.mutability = mutability
        self.ownedBy = ownedBy
        self.defaultToken = defaultToken
        self.resettable = resettable
        self.help = help
    }
}

/// Keep in sync with `contracts/environment-catalog.yaml` (#157 / #158).
public enum EnvironmentCatalog {
    public static let storageKey = "wawona.pref.environment.v1"

    public static let entries: [EnvironmentCatalogEntry] = [
        // Session
        .init(name: "XDG_RUNTIME_DIR", category: .session, mutability: .computed, defaultToken: "xdgRuntimeDir", help: "Runtime directory for the Wayland socket."),
        .init(name: "WAYLAND_DISPLAY", category: .session, mutability: .managed, ownedBy: "waylandDisplay", defaultToken: "waylandDisplay", help: "Socket name clients connect to."),
        .init(name: "WAYLAND_SOCKET", category: .session, mutability: .computed, defaultToken: "", help: "Inherited fd socket; usually cleared for multi-client launches."),
        .init(name: "WAWONA_NESTED_WAYLAND_DISPLAY", category: .session, mutability: .computed, defaultToken: "nestedWaylandDisplay"),
        .init(name: "WAWONA_OUTPUT_SCALE", category: .session, mutability: .computed, defaultToken: "outputScale"),
        .init(name: "NIRI_BACKEND", category: .session, mutability: .managed, ownedBy: "compositorBackend", defaultToken: "niriBackend", help: "Mapped from Display Backend."),
        .init(name: "NIRI_CONFIG", category: .session, mutability: .computed, defaultToken: "niriConfig"),
        .init(name: "WESTON_CONFIG_FILE", category: .session, mutability: .computed, defaultToken: "westonConfigFile"),
        .init(name: "WESTON_DATA_DIR", category: .session, mutability: .computed, defaultToken: "westonDataDir"),
        .init(name: "WESTON_MODULE_DIR", category: .session, mutability: .computed, defaultToken: "westonModuleDir"),
        .init(name: "WESTON_BACKEND_DIR", category: .session, mutability: .computed, defaultToken: "westonBackendDir"),
        // Graphics
        .init(name: "VK_DRIVER_FILES", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanIcd"),
        .init(name: "VK_ICD_FILENAMES", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanIcd"),
        .init(name: "WWN_VULKAN_LIBRARY", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanLibrary"),
        .init(name: "WWN_VULKAN_LIBRARY_FALLBACKS", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanFallbacks"),
        .init(name: "WWN_VULKAN_DRIVER", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanDriver"),
        .init(name: "WWN_OPENGL_DRIVER", category: .graphics, mutability: .managed, ownedBy: "openGLDriver", defaultToken: "openGLDriver"),
        .init(name: "WWN_DISABLE_VULKAN", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: ""),
        .init(name: "WWN_DISABLE_EGL", category: .graphics, mutability: .managed, ownedBy: "openGLDriver", defaultToken: ""),
        .init(name: "ANGLE_DEFAULT_PLATFORM", category: .graphics, mutability: .managed, ownedBy: "openGLDriver", defaultToken: "anglePlatform"),
        .init(name: "WWN_SWIFTSHADER_LIBRARY", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "swiftshaderLibrary"),
        // Shell
        .init(name: "HOME", category: .shell, mutability: .computed, defaultToken: "home"),
        .init(name: "USER", category: .shell, mutability: .defaulted, defaultToken: "mobile"),
        .init(name: "LOGNAME", category: .shell, mutability: .defaulted, defaultToken: "mobile"),
        .init(name: "SHELL", category: .shell, mutability: .computed, defaultToken: "shell"),
        .init(name: "WAWONA_SHELL", category: .shell, mutability: .computed, defaultToken: "shell"),
        .init(name: "WAWONA_ZSH_IN_PROCESS", category: .shell, mutability: .defaulted, defaultToken: "1"),
        .init(name: "TERM", category: .shell, mutability: .defaulted, defaultToken: "xterm-256color", help: "Terminal type for PTY / weston-terminal."),
        .init(name: "PATH", category: .shell, mutability: .computed, defaultToken: "path"),
        .init(name: "ZDOTDIR", category: .shell, mutability: .computed, defaultToken: "home"),
        .init(name: "WAWONA_ROOTFS", category: .shell, mutability: .computed, defaultToken: "rootfs"),
        .init(name: "WAWONA_BUNDLE_ROOTFS", category: .shell, mutability: .computed, defaultToken: "bundleRootfs"),
        .init(name: "WAWONA_FILES_DIR", category: .shell, mutability: .computed, defaultToken: "filesDir"),
        .init(name: "PROMPT", category: .shell, mutability: .defaulted, defaultToken: "%F{cyan}%~%f %# "),
        .init(name: "PS1", category: .shell, mutability: .defaulted, defaultToken: "%F{cyan}%~%f %# "),
        // XDG
        .init(name: "XDG_CONFIG_HOME", category: .xdg, mutability: .computed, defaultToken: "xdgConfigHome"),
        .init(name: "XDG_CACHE_HOME", category: .xdg, mutability: .computed, defaultToken: "xdgCacheHome"),
        .init(name: "XDG_DATA_HOME", category: .xdg, mutability: .computed, defaultToken: "xdgDataHome"),
        .init(name: "XDG_STATE_HOME", category: .xdg, mutability: .computed, defaultToken: "xdgStateHome"),
        .init(name: "XDG_DATA_DIRS", category: .xdg, mutability: .computed, defaultToken: "xdgDataDirs"),
        // Fonts / input
        .init(name: "FONTCONFIG_FILE", category: .fonts, mutability: .computed, defaultToken: "fontconfigFile"),
        .init(name: "FONTCONFIG_PATH", category: .fonts, mutability: .computed, defaultToken: "fontconfigPath"),
        .init(name: "WAWONA_MONO_FONT", category: .fonts, mutability: .computed, defaultToken: "monoFont"),
        .init(name: "WAWONA_SANS_FONT", category: .fonts, mutability: .computed, defaultToken: "sansFont"),
        .init(name: "WAWONA_TERMINAL_FONT_SIZE", category: .fonts, mutability: .defaulted, defaultToken: "12"),
        .init(name: "XKB_CONFIG_ROOT", category: .input, mutability: .computed, defaultToken: "xkbConfigRoot"),
        .init(name: "XKB_DEFAULT_LAYOUT", category: .input, mutability: .defaulted, defaultToken: "us"),
        .init(name: "XKB_DEFAULT_VARIANT", category: .input, mutability: .defaulted, defaultToken: ""),
        .init(name: "XCURSOR_PATH", category: .fonts, mutability: .computed, defaultToken: "xcursorPath"),
        .init(name: "XCURSOR_THEME", category: .fonts, mutability: .defaulted, defaultToken: "Adwaita"),
        // Debug
        .init(name: "RUST_LOG", category: .debug, mutability: .managed, ownedBy: "logLevel", defaultToken: "rustLog", help: "Mapped from Log Level."),
        .init(name: "RUST_BACKTRACE", category: .debug, mutability: .defaulted, defaultToken: "1"),
        .init(name: "WAWONA_AUTO_CMD", category: .debug, mutability: .computed, defaultToken: ""),
        // Secrets
        .init(name: "SSHPASS", category: .secrets, mutability: .secret, ownedBy: "sshPassword", defaultToken: "", resettable: false),
        .init(name: "WAYPIPE_SSH_PASSWORD", category: .secrets, mutability: .secret, ownedBy: "sshPassword", defaultToken: "", resettable: false),
    ]

    public static var byName: [String: EnvironmentCatalogEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
    }

    public static var catalogNames: Set<String> {
        Set(entries.map(\.name))
    }

    public static var uiEntries: [EnvironmentCatalogEntry] {
        entries.filter { $0.mutability != .secret }
    }
}

// MARK: - Resolved row

public enum EnvironmentValueSource: String, Hashable, Sendable {
    case catalogDefault = "Wawona default"
    case firstClassSetting = "Settings"
    case globalOverride = "Global"
    case machineOverride = "This machine"
    case session = "Session"
    case host = "Host"
    case userExtra = "User"
}

public struct ResolvedEnvironmentEntry: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var value: String?
    /// True when the resolved action is unset (variable should not be present).
    public var isUnset: Bool
    public var source: EnvironmentValueSource
    public var mutability: EnvironmentMutability
    public var category: EnvironmentCategory
    public var ownedBy: String?
    public var help: String?
    public var isOverridden: Bool
    public var isSecret: Bool

    public init(
        name: String,
        value: String?,
        isUnset: Bool = false,
        source: EnvironmentValueSource,
        mutability: EnvironmentMutability,
        category: EnvironmentCategory,
        ownedBy: String? = nil,
        help: String? = nil,
        isOverridden: Bool = false,
        isSecret: Bool = false
    ) {
        self.name = name
        self.value = value
        self.isUnset = isUnset
        self.source = source
        self.mutability = mutability
        self.category = category
        self.ownedBy = ownedBy
        self.help = help
        self.isOverridden = isOverridden
        self.isSecret = isSecret
    }

    /// Display value for UI (secrets never show real content).
    public var displayValue: String {
        if isSecret { return "(set by SSH Settings)" }
        if isUnset { return "(unset)" }
        return value ?? ""
    }
}

// MARK: - Session context (computed / managed defaults)

/// Values the platform fills at resolve time (socket paths, drivers, rootfs, …).
public struct EnvironmentSessionContext: Hashable, Sendable {
    public var waylandDisplay: String
    public var xdgRuntimeDir: String
    public var nestedWaylandDisplay: String
    public var outputScale: String
    public var niriBackend: String
    public var niriConfig: String
    public var westonConfigFile: String
    public var westonDataDir: String
    public var westonModuleDir: String
    public var westonBackendDir: String
    public var vulkanIcd: String
    public var vulkanLibrary: String
    public var vulkanFallbacks: String
    public var vulkanDriver: String
    public var openGLDriver: String
    public var anglePlatform: String
    public var swiftshaderLibrary: String
    public var disableVulkan: Bool
    public var disableEGL: Bool
    public var home: String
    public var shell: String
    public var path: String
    public var rootfs: String
    public var bundleRootfs: String
    public var filesDir: String
    public var xdgConfigHome: String
    public var xdgCacheHome: String
    public var xdgDataHome: String
    public var xdgStateHome: String
    public var xdgDataDirs: String
    public var fontconfigFile: String
    public var fontconfigPath: String
    public var monoFont: String
    public var sansFont: String
    public var xkbConfigRoot: String
    public var xcursorPath: String
    public var rustLog: String
    public var userName: String

    public init(
        waylandDisplay: String = "wayland-0",
        xdgRuntimeDir: String = "",
        nestedWaylandDisplay: String = "",
        outputScale: String = "1",
        niriBackend: String = "nested",
        niriConfig: String = "",
        westonConfigFile: String = "",
        westonDataDir: String = "",
        westonModuleDir: String = "",
        westonBackendDir: String = "",
        vulkanIcd: String = "",
        vulkanLibrary: String = "",
        vulkanFallbacks: String = "",
        vulkanDriver: String = "moltenvk",
        openGLDriver: String = "angle",
        anglePlatform: String = "metal",
        swiftshaderLibrary: String = "",
        disableVulkan: Bool = false,
        disableEGL: Bool = false,
        home: String = "",
        shell: String = "/usr/bin/zsh",
        path: String = "/usr/bin:/bin",
        rootfs: String = "",
        bundleRootfs: String = "",
        filesDir: String = "",
        xdgConfigHome: String = "",
        xdgCacheHome: String = "",
        xdgDataHome: String = "",
        xdgStateHome: String = "",
        xdgDataDirs: String = "",
        fontconfigFile: String = "",
        fontconfigPath: String = "",
        monoFont: String = "",
        sansFont: String = "",
        xkbConfigRoot: String = "",
        xcursorPath: String = "",
        rustLog: String = "info",
        userName: String = "mobile"
    ) {
        self.waylandDisplay = waylandDisplay
        self.xdgRuntimeDir = xdgRuntimeDir
        self.nestedWaylandDisplay = nestedWaylandDisplay
        self.outputScale = outputScale
        self.niriBackend = niriBackend
        self.niriConfig = niriConfig
        self.westonConfigFile = westonConfigFile
        self.westonDataDir = westonDataDir
        self.westonModuleDir = westonModuleDir
        self.westonBackendDir = westonBackendDir
        self.vulkanIcd = vulkanIcd
        self.vulkanLibrary = vulkanLibrary
        self.vulkanFallbacks = vulkanFallbacks
        self.vulkanDriver = vulkanDriver
        self.openGLDriver = openGLDriver
        self.anglePlatform = anglePlatform
        self.swiftshaderLibrary = swiftshaderLibrary
        self.disableVulkan = disableVulkan
        self.disableEGL = disableEGL
        self.home = home
        self.shell = shell
        self.path = path
        self.rootfs = rootfs
        self.bundleRootfs = bundleRootfs
        self.filesDir = filesDir
        self.xdgConfigHome = xdgConfigHome
        self.xdgCacheHome = xdgCacheHome
        self.xdgDataHome = xdgDataHome
        self.xdgStateHome = xdgStateHome
        self.xdgDataDirs = xdgDataDirs
        self.fontconfigFile = fontconfigFile
        self.fontconfigPath = fontconfigPath
        self.monoFont = monoFont
        self.sansFont = sansFont
        self.xkbConfigRoot = xkbConfigRoot
        self.xcursorPath = xcursorPath
        self.rustLog = rustLog
        self.userName = userName
    }

    public func resolveToken(_ token: String) -> String? {
        switch token {
        case "", "empty": return ""
        case "waylandDisplay": return waylandDisplay
        case "xdgRuntimeDir": return xdgRuntimeDir
        case "nestedWaylandDisplay": return nestedWaylandDisplay
        case "outputScale": return outputScale
        case "niriBackend": return niriBackend
        case "niriConfig": return niriConfig
        case "westonConfigFile": return westonConfigFile
        case "westonDataDir": return westonDataDir
        case "westonModuleDir": return westonModuleDir
        case "westonBackendDir": return westonBackendDir
        case "vulkanIcd": return vulkanIcd
        case "vulkanLibrary": return vulkanLibrary
        case "vulkanFallbacks": return vulkanFallbacks
        case "vulkanDriver": return vulkanDriver
        case "openGLDriver": return openGLDriver
        case "anglePlatform": return anglePlatform
        case "swiftshaderLibrary": return swiftshaderLibrary
        case "home": return home
        case "shell": return shell
        case "path": return path
        case "rootfs": return rootfs
        case "bundleRootfs": return bundleRootfs
        case "filesDir": return filesDir
        case "xdgConfigHome": return xdgConfigHome
        case "xdgCacheHome": return xdgCacheHome
        case "xdgDataHome": return xdgDataHome
        case "xdgStateHome": return xdgStateHome
        case "xdgDataDirs": return xdgDataDirs
        case "fontconfigFile": return fontconfigFile
        case "fontconfigPath": return fontconfigPath
        case "monoFont": return monoFont
        case "sansFont": return sansFont
        case "xkbConfigRoot": return xkbConfigRoot
        case "xcursorPath": return xcursorPath
        case "rustLog": return rustLog
        case "mobile": return userName
        default:
            // Literal default stored as the token itself (e.g. xterm-256color).
            return token
        }
    }
}

// MARK: - Merge / reset

public enum EnvironmentResolver {
    /// Banned on Apple-mobile local shell spawn even if user extras set them.
    public static let strippedLocalShellPrefixes = ["DYLD_", "LD_"]

    public static func isBannedLocalShellKey(_ name: String) -> Bool {
        strippedLocalShellPrefixes.contains { name.hasPrefix($0) }
    }

    public static func decodeMap(from data: Data?) -> EnvironmentOverrideMap {
        guard let data, !data.isEmpty else { return [:] }
        return (try? JSONDecoder().decode(EnvironmentOverrideMap.self, from: data)) ?? [:]
    }

    public static func encodeMap(_ map: EnvironmentOverrideMap) -> Data? {
        guard !map.isEmpty else { return nil }
        return try? JSONEncoder().encode(map)
    }

    /// Reset one key (delete override → inherit).
    public static func resetOne(_ map: inout EnvironmentOverrideMap, name: String) {
        map.removeValue(forKey: name)
    }

    /// Drop overrides for catalog names; keep user extras.
    public static func resetWawonaManaged(_ map: inout EnvironmentOverrideMap) {
        let catalog = EnvironmentCatalog.catalogNames
        map = map.filter { !catalog.contains($0.key) }
    }

    public static func resetAll(_ map: inout EnvironmentOverrideMap) {
        map.removeAll()
    }

    /// Merge precedence: machine > global > first-class/session defaults.
    public static func resolve(
        globalOverrides: EnvironmentOverrideMap,
        machineOverrides: EnvironmentOverrideMap,
        session: EnvironmentSessionContext,
        includeSecrets: Bool = false,
        stripBannedLocalShellKeys: Bool = false
    ) -> [ResolvedEnvironmentEntry] {
        var rows: [ResolvedEnvironmentEntry] = []
        var seen = Set<String>()

        for entry in EnvironmentCatalog.entries {
            if entry.mutability == .secret && !includeSecrets {
                rows.append(ResolvedEnvironmentEntry(
                    name: entry.name,
                    value: nil,
                    isUnset: false,
                    source: .firstClassSetting,
                    mutability: .secret,
                    category: entry.category,
                    ownedBy: entry.ownedBy,
                    help: entry.help,
                    isOverridden: false,
                    isSecret: true
                ))
                seen.insert(entry.name)
                continue
            }

            let resolved = resolveOne(
                name: entry.name,
                catalog: entry,
                globalOverrides: globalOverrides,
                machineOverrides: machineOverrides,
                session: session
            )
            rows.append(resolved)
            seen.insert(entry.name)
        }

        // User extras not in catalog.
        let extraKeys = Set(globalOverrides.keys).union(machineOverrides.keys).subtracting(seen)
        for name in extraKeys.sorted() {
            if stripBannedLocalShellKeys && isBannedLocalShellKey(name) { continue }
            let resolved = resolveOne(
                name: name,
                catalog: EnvironmentCatalogEntry(
                    name: name,
                    category: .user,
                    mutability: .user,
                    defaultToken: ""
                ),
                globalOverrides: globalOverrides,
                machineOverrides: machineOverrides,
                session: session
            )
            rows.append(resolved)
        }

        if stripBannedLocalShellKeys {
            rows = rows.filter { !isBannedLocalShellKey($0.name) }
        }

        return rows.sorted { $0.name < $1.name }
    }

    /// Flat name → value for spawn/setenv (omits unset and secrets unless requested).
    public static func applyMap(
        from rows: [ResolvedEnvironmentEntry],
        includeSecrets: Bool = false
    ) -> [String: String] {
        var out: [String: String] = [:]
        for row in rows {
            if row.isSecret && !includeSecrets { continue }
            if row.isUnset { continue }
            if let value = row.value {
                out[row.name] = value
            }
        }
        return out
    }

    /// Names that should be unsetenv'd.
    public static func unsetNames(from rows: [ResolvedEnvironmentEntry]) -> [String] {
        rows.filter(\.isUnset).map(\.name)
    }

    private static func resolveOne(
        name: String,
        catalog: EnvironmentCatalogEntry,
        globalOverrides: EnvironmentOverrideMap,
        machineOverrides: EnvironmentOverrideMap,
        session: EnvironmentSessionContext
    ) -> ResolvedEnvironmentEntry {
        if let machine = machineOverrides[name] {
            return entry(from: machine, name: name, catalog: catalog, source: .machineOverride, overridden: true)
        }
        if let global = globalOverrides[name] {
            return entry(from: global, name: name, catalog: catalog, source: .globalOverride, overridden: true)
        }

        // First-class / computed defaults from session.
        let (value, source) = catalogDefault(catalog: catalog, session: session)
        return ResolvedEnvironmentEntry(
            name: name,
            value: value,
            isUnset: false,
            source: source,
            mutability: catalog.mutability,
            category: catalog.category,
            ownedBy: catalog.ownedBy,
            help: catalog.help,
            isOverridden: false,
            isSecret: catalog.mutability == .secret
        )
    }

    private static func entry(
        from override: EnvironmentOverride,
        name: String,
        catalog: EnvironmentCatalogEntry,
        source: EnvironmentValueSource,
        overridden: Bool
    ) -> ResolvedEnvironmentEntry {
        switch override.action {
        case .unset:
            return ResolvedEnvironmentEntry(
                name: name,
                value: nil,
                isUnset: true,
                source: source,
                mutability: catalog.mutability,
                category: catalog.category,
                ownedBy: catalog.ownedBy,
                help: catalog.help,
                isOverridden: overridden,
                isSecret: catalog.mutability == .secret
            )
        case .set:
            return ResolvedEnvironmentEntry(
                name: name,
                value: override.value ?? "",
                isUnset: false,
                source: source,
                mutability: catalog.mutability,
                category: catalog.category,
                ownedBy: catalog.ownedBy,
                help: catalog.help,
                isOverridden: overridden,
                isSecret: catalog.mutability == .secret
            )
        }
    }

    private static func catalogDefault(
        catalog: EnvironmentCatalogEntry,
        session: EnvironmentSessionContext
    ) -> (String?, EnvironmentValueSource) {
        switch catalog.mutability {
        case .secret:
            return (nil, .firstClassSetting)
        case .computed:
            let v = session.resolveToken(catalog.defaultToken)
            return (v, .session)
        case .managed:
            // Special managed toggles.
            if catalog.name == "WWN_DISABLE_VULKAN" {
                return (session.disableVulkan ? "1" : nil, .firstClassSetting)
            }
            if catalog.name == "WWN_DISABLE_EGL" {
                return (session.disableEGL ? "1" : nil, .firstClassSetting)
            }
            let v = session.resolveToken(catalog.defaultToken)
            return (v, .firstClassSetting)
        case .defaulted:
            let v = session.resolveToken(catalog.defaultToken)
            return (v, .catalogDefault)
        case .user:
            return (nil, .userExtra)
        }
    }

    /// Map CompositorBackend setting → NIRI_BACKEND value.
    public static func niriBackend(for compositorBackend: String) -> String {
        switch compositorBackend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "drm", "tty": return "tty"
        default: return "nested"
        }
    }

    /// Map logLevel → RUST_LOG.
    public static func rustLog(for logLevel: String) -> String {
        switch logLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug": return "debug"
        case "warn", "warning": return "warn"
        case "error": return "error"
        default: return "info"
        }
    }
}
