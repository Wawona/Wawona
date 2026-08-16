import Foundation

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
    /// iPhone/iPad send-side companion documents (WatchConnectivity). Not a watchOS catalog twin.
    case appleWatch
    case advanced
    case desktop
    case waypipe
    case ssh
    case about

    public var title: String {
        switch self {
        case .display: return "Display"
        case .input: return "Input"
        case .graphics: return "Graphics"
        case .connection: return "Connection"
        case .environment: return "Env Vars"
        case .localShell: return "Local Shell"
        case .appleWatch: return "Apple Watch"
        case .advanced: return "Advanced"
        case .desktop: return "Desktop"
        case .waypipe: return "Waypipe"
        case .ssh: return "SSH"
        case .about: return "About"
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
        case .appleWatch: return "applewatch"
        case .advanced: return "gearshape.2"
        case .desktop: return "macwindow.on.rectangle"
        case .waypipe: return "arrow.triangle.2.circlepath"
        case .ssh: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

public enum GlobalSettingsFieldID: String, Sendable, CaseIterable {
    case autoScale
    case forceSSD
    case respectSafeArea
    case virtualCursor
    case nestedCompositorCursor
    case touchInputType
    case resizeDisplayForVirtualKeyboard
    case swapCmdWithAlt
    case universalClipboard
    case renderer
    case vulkanDriver
    case openGLDriver
    case dmabufEnabled
    case waylandDisplay
    case defaultWaylandClient
    case environmentTable
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
    case colorOperations
    case nestedCompositors
    case compositorBackend
    case multipleClients
    case logLevel
    case shakeToClose
    case swipeBackToClose
    case aboutVersion
    case aboutPlatform
    case aboutAuthor
    case aboutSource
    case aboutSponsors
    case aboutPortfolio
    case watchCompanionStatus
    case watchSendDocument
    case watchOpenDocumentsHint
}

/// Single catalog for global Wawona Settings. Watch, iOS, and macOS must
/// render the same section/field IDs for a given host. Never a second
/// free-text "Input Profile" beside Touch Input Type.
public struct GlobalSettingsCatalog: Sendable {
    public static func visibleSections(for host: GlobalSettingsHost) -> [GlobalSettingsSectionID] {
        switch host {
        case .macOS:
            return [
                .display, .input, .graphics, .connection, .environment, .localShell,
                .advanced, .desktop, .waypipe, .ssh, .about,
            ]
        case .iOS:
            return [
                .display, .input, .graphics, .connection, .environment, .localShell,
                .appleWatch, .advanced, .waypipe, .ssh, .about,
            ]
        case .visionOS:
            return [
                .display, .input, .graphics, .connection, .environment, .localShell,
                .advanced, .waypipe, .ssh, .about,
            ]
        case .android, .linux:
            return [
                .display, .input, .graphics, .connection, .environment,
                .advanced, .waypipe, .ssh, .about,
            ]
        case .tvOS:
            return [
                .display, .input, .graphics, .connection, .environment,
                .advanced, .waypipe, .ssh, .about,
            ]
        case .watchOS:
            return [
                .display, .input, .graphics, .connection, .environment,
                .waypipe, .ssh, .advanced, .about,
            ]
        }
    }

    public static func visibleFields(
        in section: GlobalSettingsSectionID,
        for host: GlobalSettingsHost
    ) -> [GlobalSettingsFieldID] {
        switch section {
        case .display:
            var fields: [GlobalSettingsFieldID] = [.autoScale]
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
            fields.append(contentsOf: [.vulkanDriver, .openGLDriver, .dmabufEnabled])
            return fields
        case .connection:
            return [.waylandDisplay, .defaultWaylandClient]
        case .environment:
            return [.environmentTable]
        case .localShell:
            return []
        case .appleWatch:
            return host == .iOS
                ? [.watchCompanionStatus, .watchSendDocument, .watchOpenDocumentsHint]
                : []
        case .advanced:
            var fields: [GlobalSettingsFieldID] = [
                .colorOperations,
                .nestedCompositors,
                .compositorBackend,
                .multipleClients,
                .logLevel,
            ]
            if host != .tvOS {
                fields.append(.shakeToClose)
            }
            if host == .iOS || host == .watchOS || host == .visionOS || host == .android {
                fields.append(.swipeBackToClose)
            }
            return fields
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
                .aboutVersion, .aboutPlatform, .aboutAuthor,
                .aboutSource, .aboutSponsors, .aboutPortfolio,
            ]
        }
    }
}
