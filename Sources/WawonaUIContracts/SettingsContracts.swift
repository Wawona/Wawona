import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum ConnectionSettingsIntent: Sendable {
    case updateWaylandDisplay(String)
    case testSSHConnection
    case testWaypipeCommand
    case runDependencyDiagnostics
}

public enum ConnectionSettingsFieldID: String, Sendable, CaseIterable {
    case waylandDisplay
    case sshHost
    case sshUser
    case sshPort
    case sshPassword
    case waypipeCommand
    case diagnostics
}

public struct ConnectionSettingsFieldMetadata: Sendable, Hashable {
    public var id: ConnectionSettingsFieldID
    public var label: String
    public var helperText: String?
    public var required: Bool

    public init(
        id: ConnectionSettingsFieldID,
        label: String,
        helperText: String? = nil,
        required: Bool = false
    ) {
        self.id = id
        self.label = label
        self.helperText = helperText
        self.required = required
    }
}

public struct ConnectionSettingsState: Sendable, Hashable {
    public var waylandDisplay: String
    public var sshHost: String
    public var sshUser: String
    public var sshPortText: String
    public var sshPassword: String
    public var waypipeCommand: String
    public var latestDiagnosticsSummary: String

    public init(
        waylandDisplay: String = "wayland-0",
        sshHost: String = "",
        sshUser: String = "",
        sshPortText: String = "22",
        sshPassword: String = "",
        waypipeCommand: String = "weston-simple-shm",
        latestDiagnosticsSummary: String = ""
    ) {
        self.waylandDisplay = waylandDisplay
        self.sshHost = sshHost
        self.sshUser = sshUser
        self.sshPortText = sshPortText
        self.sshPassword = sshPassword
        self.waypipeCommand = waypipeCommand
        self.latestDiagnosticsSummary = latestDiagnosticsSummary
    }
}

public enum ConnectionSettingsValidationIssue: String, Sendable {
    case emptyWaylandDisplay
    case emptySSHHost
    case emptySSHUser
    case invalidSSHPort
    case emptyWaypipeCommand
}

/// Declared as `struct` to keep cross-platform generated bindings stable.
public struct ConnectionSettingsValidation: Sendable {
    public static func metadata(for field: ConnectionSettingsFieldID) -> ConnectionSettingsFieldMetadata {
        switch field {
        case .waylandDisplay:
            return ConnectionSettingsFieldMetadata(
                id: .waylandDisplay,
                label: "Wayland Display",
                helperText: "Socket name used by compositor clients (for example: wayland-0).",
                required: true
            )
        case .sshHost:
            return ConnectionSettingsFieldMetadata(id: .sshHost, label: "SSH Host", required: true)
        case .sshUser:
            return ConnectionSettingsFieldMetadata(id: .sshUser, label: "SSH User", required: true)
        case .sshPort:
            return ConnectionSettingsFieldMetadata(id: .sshPort, label: "SSH Port", required: true)
        case .sshPassword:
            return ConnectionSettingsFieldMetadata(id: .sshPassword, label: "SSH Password")
        case .waypipeCommand:
            return ConnectionSettingsFieldMetadata(id: .waypipeCommand, label: "Waypipe Command", required: true)
        case .diagnostics:
            return ConnectionSettingsFieldMetadata(id: .diagnostics, label: "Diagnostics")
        }
    }

    public static func validate(_ state: ConnectionSettingsState) -> [ConnectionSettingsValidationIssue] {
        var issues: [ConnectionSettingsValidationIssue] = []
        if state.waylandDisplay.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            issues.append(ConnectionSettingsValidationIssue.emptyWaylandDisplay)
        }
        if state.sshHost.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            issues.append(ConnectionSettingsValidationIssue.emptySSHHost)
        }
        if state.sshUser.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            issues.append(ConnectionSettingsValidationIssue.emptySSHUser)
        }
        if let p = Int(state.sshPortText), (1...65535).contains(p) {
            // valid
        } else {
            issues.append(ConnectionSettingsValidationIssue.invalidSSHPort)
        }
        if state.waypipeCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            issues.append(ConnectionSettingsValidationIssue.emptyWaypipeCommand)
        }
        return issues
    }

    public static func normalizedDisplay(_ state: ConnectionSettingsState) -> String {
        let trimmed = state.waylandDisplay.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return trimmed.isEmpty ? "wayland-0" : trimmed
    }

    public static func normalizedSSHPort(_ state: ConnectionSettingsState) -> Int {
        Int(state.sshPortText) ?? 22
    }
}

// MARK: - Global Settings catalog (all shipped platforms)

/// Host the Settings catalog is being rendered for. Mirrors product targets,
/// not capability gates. Use `visibleSections` / `visibleFields` to hide
/// Desktop (macOS-only), GPU rows, or store-forbidden surfaces.
public enum GlobalSettingsHost: String, Sendable, CaseIterable {
    case macOS
    case iOS
    case tvOS
    case watchOS
    case visionOS
    case android
    case linux
}

public enum GlobalSettingsSectionID: String, Sendable, CaseIterable, Hashable {
    case display
    case input
    case graphics
    case connection
    case environment
    case localShell
    /// Global machine-session gestures (shake / swipe / tvOS Menu). Not the Machines window.
    case machines
    /// Apple iCloud Drive sync for shell HOME. Omit on Android, Linux, and tvOS
    /// (iCloud Drive is unavailable on tvOS; Apple QA1935). watchOS shows status only.
    case iCloudSync
    /// iPhone/iPad send-side companion documents (WatchConnectivity). Not a watchOS catalog twin.
    case appleWatch
    case advanced
    case desktop
    case waypipe
    case ssh
    case about
    case dependencies

    public var title: String {
        switch self {
        case .display: return "Display"
        case .input: return "Input"
        case .graphics: return "Graphics"
        case .connection: return "Connection"
        case .environment: return "Env Vars"
        case .localShell: return "Local Shell"
        case .machines: return "Machines"
        case .iCloudSync: return "iCloud Sync"
        case .appleWatch: return "Apple Watch"
        case .advanced: return "Advanced"
        case .desktop: return "Desktop"
        case .waypipe: return "Waypipe"
        case .ssh: return "SSH"
        case .about: return "About"
        case .dependencies: return "Dependencies"
        }
    }

    /// ObjC `WWNPreferencesSection.accessibilityIdentifier`. localShell uses
    /// a dotted token (`local.shell`); other slugs match `rawValue`.
    public var objcAccessibilityIdentifier: String {
        switch self {
        case .localShell: return "wwn.settings.local.shell"
        default: return "wwn.settings.\(rawValue)"
        }
    }

    public var systemImage: String {
        switch self {
        case .display: return "display"
        case .input: return "hand.tap"
        case .graphics: return "cpu"
        case .connection: return "network"
        case .environment: return "list.bullet.rectangle"
        case .localShell: return "terminal"
        case .machines: return "desktopcomputer"
        case .iCloudSync: return "icloud"
        case .appleWatch: return "applewatch"
        case .advanced: return "gearshape.2"
        case .desktop: return "macwindow.on.rectangle"
        case .waypipe: return "arrow.triangle.2.circlepath"
        case .ssh: return "lock.shield"
        case .about: return "info.circle"
        case .dependencies: return "shippingbox"
        }
    }
}

public enum GlobalSettingsFieldID: String, Sendable, CaseIterable {
    case forceSSD
    case respectSafeArea
    case colorOperations
    case virtualCursor
    case nestedCompositorCursor
    case touchInputType
    case touchPointerEmulation
    case resizeDisplayForVirtualKeyboard
    case swapCmdWithAlt
    case universalClipboard
    case renderer
    case vulkanDriver
    case openGLDriver
    case waylandDisplay
    case defaultWaylandClient
    case environmentTable
    case resetShellDotfiles
    case resetSystemTree
    case importFileToHome
    case iCloudSyncEnabled
    case iCloudSyncStatus
    case waypipeByDefault
    case waypipeCompress
    case waypipeVideo
    case waypipeRemoteCommand
    case waypipeDebug
    case waypipeNoGpu
    case waypipeXwayland
    case waypipePassword
    case sshHost
    case sshUser
    case sshPort
    case sshAuthMethod
    case sshPassword
    case sshKeyType
    case sshKeyPath
    case sshKeyPassphrase
    case sshGenerateKey
    case nestedCompositors
    case compositorBackend
    case multipleClients
    case logLevel
    case shakeToClose
    case swipeBackToClose
    case sessionThumbnails
    case vmEngine
    case vmVsockPort
    case containerRuntime
    case containerImageStore
    case machinesStatus
    case aboutVersion
    case aboutBuild
    case aboutPlatform
    case aboutAuthor
    case aboutWebsite
    case aboutSource
    case aboutSponsors
    case watchCompanionStatus
    case watchSendDocument
    case watchOpenDocumentsHint
    case dependenciesInventory
}

/// Single catalog for global Wawona Settings. Watch, iOS, and macOS must
/// render the same section/field IDs for a given host. Never a second
/// free-text "Input Profile" beside Touch Input Type.
///
/// Section *order* is owned by Rust `src/domain/settings_catalog.rs`
/// (`visible_sections` / `settings_visible_sections`). Do not grow this
/// list independently. Field visibility stays here until that lift.
///
/// Prefer the C trampoline (`wawona_settings_visible_sections`) when
/// `libwawona.a` is linked. UniFFI `settings_visible_sections` is the
/// same list once bindgen can run. SPM / Watch tests keep the fallback.
public struct GlobalSettingsCatalog: Sendable {
    public static var currentHost: GlobalSettingsHost {
        #if os(macOS)
        .macOS
        #elseif os(iOS)
        .iOS
        #elseif os(tvOS)
        .tvOS
        #elseif os(watchOS)
        .watchOS
        #elseif os(visionOS)
        .visionOS
        #else
        .linux
        #endif
    }

    public static func visibleSections(for host: GlobalSettingsHost) -> [GlobalSettingsSectionID] {
        if let rust = rustVisibleSections(for: host), !rust.isEmpty {
            return rust
        }
        return fallbackVisibleSections(for: host)
    }

    /// Frozen mirror of `settings_catalog::visible_sections`. Used when the
    /// rust domain library is not linked (SPM tests, Watch 32-bit stub).
    public static func fallbackVisibleSections(for host: GlobalSettingsHost) -> [GlobalSettingsSectionID] {
        switch host {
        case .macOS:
            return [
                .display, .input, .graphics, .connection, .environment, .localShell,
                .machines, .iCloudSync, .advanced, .desktop, .waypipe, .ssh, .about,
                .dependencies,
            ]
        case .iOS:
            var sections: [GlobalSettingsSectionID] = [
                .display, .input, .graphics, .connection, .environment, .localShell,
                .machines, .iCloudSync, .appleWatch, .advanced,
            ]
            // Store IPA omits Desktop. Mode B tipa / Sileo compile with WWN_MODE_B.
            #if WWN_MODE_B
            sections.append(.desktop)
            #endif
            sections.append(contentsOf: [.waypipe, .ssh, .about, .dependencies])
            return sections
        case .visionOS:
            return [
                .display, .input, .graphics, .connection, .environment, .localShell,
                .machines, .iCloudSync, .advanced, .waypipe, .ssh, .about,
                .dependencies,
            ]
        case .android:
            return [
                .display, .input, .graphics, .connection, .environment, .localShell,
                .machines, .advanced, .waypipe, .ssh, .about, .dependencies,
            ]
        case .linux:
            return [
                .display, .input, .graphics, .connection, .environment, .localShell,
                .machines, .advanced, .waypipe, .ssh, .about, .dependencies,
            ]
        case .tvOS:
            return [
                .display, .input, .graphics, .connection, .environment,
                .machines, .advanced, .waypipe, .ssh, .about,
                .dependencies,
            ]
        case .watchOS:
            return [
                .display, .input, .graphics, .connection, .environment,
                .machines, .iCloudSync, .waypipe, .ssh, .advanced, .about,
                .dependencies,
            ]
        }
    }

    /// C trampoline in `src/domain/c_api.rs`. dlsym so SPM tests that do
    /// not link `libwawona.a` still compile. Watch 32-bit stays on fallback.
    private static func rustVisibleSections(for host: GlobalSettingsHost) -> [GlobalSettingsSectionID]? {
        #if canImport(Darwin)
        typealias CatalogFn = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
        typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        guard
            let catalogSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "wawona_settings_visible_sections"),
            let freeSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "wawona_domain_string_free")
        else {
            return nil
        }
        let catalog = unsafeBitCast(catalogSym, to: CatalogFn.self)
        let free = unsafeBitCast(freeSym, to: FreeFn.self)
        return host.rawValue.withCString { cHost in
            guard let raw = catalog(cHost) else { return nil }
            defer { free(raw) }
            let joined = String(cString: raw)
            guard !joined.isEmpty else { return nil }
            let parsed: [GlobalSettingsSectionID] = joined
                .split(separator: ",")
                .compactMap { GlobalSettingsSectionID(rawValue: String($0)) }
            return parsed.isEmpty ? nil : parsed
        }
        #else
        return nil
        #endif
    }

    public static func visibleFields(
        in section: GlobalSettingsSectionID,
        for host: GlobalSettingsHost
    ) -> [GlobalSettingsFieldID] {
        switch section {
        case .display:
            var fields: [GlobalSettingsFieldID] = [.colorOperations]
            if host == .macOS {
                fields.append(.forceSSD)
            }
            if host == .iOS {
                fields.append(.respectSafeArea)
            }
            return fields
        case .input:
            var fields: [GlobalSettingsFieldID] = [
                .virtualCursor,
                .nestedCompositorCursor,
            ]
            if host != .tvOS {
                fields.append(.touchInputType)
                fields.append(.touchPointerEmulation)
            }
            fields.append(contentsOf: [
                .resizeDisplayForVirtualKeyboard,
                .swapCmdWithAlt,
                .universalClipboard,
            ])
            return fields
        case .graphics:
            var fields: [GlobalSettingsFieldID] = []
            if host == .watchOS {
                fields.append(.renderer)
            }
            fields.append(contentsOf: [.vulkanDriver, .openGLDriver])
            return fields
        case .connection:
            return [.waylandDisplay, .defaultWaylandClient]
        case .environment:
            return [.environmentTable]
        case .localShell:
            if host == .tvOS || host == .watchOS {
                return []
            }
            var fields: [GlobalSettingsFieldID] = [.resetShellDotfiles, .resetSystemTree]
            if host != .linux {
                fields.append(.importFileToHome)
            }
            return fields
        case .machines:
            var fields: [GlobalSettingsFieldID] = [.shakeToClose]
            if host == .iOS || host == .watchOS || host == .visionOS || host == .android {
                fields.append(.swipeBackToClose)
            }
            fields.append(.sessionThumbnails)
            switch host {
            case .macOS, .iOS, .android, .linux:
                fields.append(contentsOf: [
                    .vmEngine, .vmVsockPort, .containerRuntime, .containerImageStore,
                    .machinesStatus,
                ])
            case .tvOS, .watchOS, .visionOS:
                break
            }
            return fields
        case .iCloudSync:
            switch host {
            case .macOS, .iOS, .visionOS:
                return [.iCloudSyncEnabled, .iCloudSyncStatus]
            case .watchOS:
                return [.iCloudSyncStatus]
            case .tvOS, .android, .linux:
                return []
            }
        case .appleWatch:
            return host == .iOS
                ? [.watchCompanionStatus, .watchSendDocument, .watchOpenDocumentsHint]
                : []
        case .advanced:
            return [
                .nestedCompositors,
                .compositorBackend,
                .multipleClients,
                .logLevel,
            ]
        case .desktop:
            return host == .macOS ? [] : []
        case .waypipe:
            return [
                .waypipeByDefault,
                .waypipeXwayland,
                .waypipePassword,
                .waypipeCompress,
                .waypipeVideo,
                .waypipeRemoteCommand,
                .waypipeDebug,
                .waypipeNoGpu,
            ]
        case .ssh:
            return [
                .sshHost, .sshUser, .sshPort, .sshAuthMethod, .sshPassword,
                .sshKeyType, .sshKeyPath, .sshKeyPassphrase, .sshGenerateKey,
            ]
        case .about:
            return [
                .aboutVersion, .aboutBuild, .aboutPlatform, .aboutWebsite,
                .aboutAuthor, .aboutSource, .aboutSponsors,
            ]
        case .dependencies:
            return [.dependenciesInventory]
        }
    }
}
