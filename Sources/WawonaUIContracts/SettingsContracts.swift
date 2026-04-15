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
        waypipeCommand: String = "weston-terminal",
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
