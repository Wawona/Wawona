import Foundation

public enum MachineEditorIntent: Sendable {
    case updateName(String)
    case updateType(String)
    case updateLauncher(String)
    case updateSSHHost(String)
    case updateSSHUser(String)
    case updateSSHPort(String)
    case updateSSHPassword(String)
    case updateRemoteCommand(String)
    case updateVMSubtype(String)
    case updateContainerSubtype(String)
    case updateInputProfile(String)
    case updateBundledAppID(String)
    case updateWaypipeEnabled(Bool)
}

public enum MachineEditorFieldID: String, Sendable, CaseIterable {
    case name
    case type
    case launcher
    case sshHost
    case sshUser
    case sshPort
    case sshPassword
    case remoteCommand
    case vmSubtype
    case containerSubtype
    case inputProfile
    case bundledAppID
    case waypipeEnabled
}

public struct MachineEditorFieldMetadata: Sendable, Hashable {
    public var id: MachineEditorFieldID
    public var label: String
    public var helperText: String?
    public var required: Bool

    public init(
        id: MachineEditorFieldID,
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

public struct MachineEditorState: Sendable, Hashable {
    public var id: String?
    public var name: String
    public var typeRawValue: String
    public var selectedLauncherName: String
    public var sshHost: String
    public var sshUser: String
    public var sshPortText: String
    public var sshPassword: String
    public var remoteCommand: String
    public var vmSubtype: String
    public var containerSubtype: String
    public var inputProfile: String
    public var bundledAppID: String
    public var waypipeEnabled: Bool

    public init(
        id: String? = nil,
        name: String = "",
        typeRawValue: String = "native",
        selectedLauncherName: String = "weston-simple-shm",
        sshHost: String = "",
        sshUser: String = "",
        sshPortText: String = "22",
        sshPassword: String = "",
        remoteCommand: String = "",
        vmSubtype: String = "",
        containerSubtype: String = "",
        inputProfile: String = "direct",
        bundledAppID: String = "",
        waypipeEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.typeRawValue = typeRawValue
        self.selectedLauncherName = selectedLauncherName
        self.sshHost = sshHost
        self.sshUser = sshUser
        self.sshPortText = sshPortText
        self.sshPassword = sshPassword
        self.remoteCommand = remoteCommand
        self.vmSubtype = vmSubtype
        self.containerSubtype = containerSubtype
        self.inputProfile = inputProfile
        self.bundledAppID = bundledAppID
        self.waypipeEnabled = waypipeEnabled
    }

    public var isNative: Bool { typeRawValue == "native" }
    public var isSSH: Bool { typeRawValue == "ssh_waypipe" || typeRawValue == "ssh_terminal" }
    public var isVirtualMachine: Bool { typeRawValue == "virtual_machine" }
    public var isContainer: Bool { typeRawValue == "container" }
}

public enum MachineEditorValidationIssue: String, Sendable {
    case missingName
    case missingSSHHost
    case missingSSHUser
    case invalidSSHPort
    case missingVMSubtype
    case missingContainerSubtype
}

/// Declared as `struct` to keep cross-platform generated bindings stable.
public struct MachineEditorValidation: Sendable {
    public static func sanitizeSSHHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if value.isEmpty { return "" }

        // Drop accidental scheme prefixes.
        if let schemeRange = value.range(of: "://") {
            value = String(value[schemeRange.upperBound...])
        }

        // Keep only authority portion if path/query was pasted.
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        if let question = value.firstIndex(of: "?") {
            value = String(value[..<question])
        }
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash])
        }

        // Remove whitespace and obvious shell metacharacters.
        let disallowed = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`$;&|<>\\"))
        value = value.unicodeScalars
            .filter { !disallowed.contains($0) }
            .map(String.init)
            .joined()

        // Strip accidental host:port to keep host and port fields separated.
        if value.hasPrefix("[") {
            if let closing = value.firstIndex(of: "]"), value.index(after: closing) < value.endIndex,
               value[value.index(after: closing)] == ":" {
                let suffix = value[value.index(closing, offsetBy: 2)...]
                if suffix.allSatisfy(\.isNumber) {
                    value = String(value[..<closing]) + "]"
                }
            }
        } else if let colon = value.lastIndex(of: ":") {
            let hostPart = value[..<colon]
            let portPart = value[value.index(after: colon)...]
            if !hostPart.contains(":") && !portPart.isEmpty && portPart.allSatisfy(\.isNumber) {
                value = String(hostPart)
            }
        }

        return value
    }

    public static func normalizeSSHPort(_ raw: String, fallback: Int = 22) -> Int {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard let parsed = Int(trimmed), (1...65535).contains(parsed) else {
            return fallback
        }
        return parsed
    }

    public static func normalizeSSHPortText(_ raw: String, fallback: Int = 22) -> String {
        String(normalizeSSHPort(raw, fallback: fallback))
    }

    public static func visibleFields(for state: MachineEditorState) -> [MachineEditorFieldID] {
        var fields: [MachineEditorFieldID] = [MachineEditorFieldID.name, MachineEditorFieldID.type]
        if state.isNative {
            fields.append(MachineEditorFieldID.launcher)
            fields.append(MachineEditorFieldID.bundledAppID)
        } else if state.isSSH {
            fields.append(contentsOf: [
                MachineEditorFieldID.sshHost,
                MachineEditorFieldID.sshUser,
                MachineEditorFieldID.sshPort,
                MachineEditorFieldID.sshPassword,
                MachineEditorFieldID.remoteCommand,
                MachineEditorFieldID.waypipeEnabled,
            ])
        } else if state.isVirtualMachine {
            fields.append(MachineEditorFieldID.vmSubtype)
        } else if state.isContainer {
            fields.append(MachineEditorFieldID.containerSubtype)
        }
        fields.append(MachineEditorFieldID.inputProfile)
        return fields
    }

    public static func metadata(for field: MachineEditorFieldID) -> MachineEditorFieldMetadata {
        switch field {
        case .name:
            return MachineEditorFieldMetadata(id: .name, label: "Name", helperText: "Display name for this machine profile.", required: true)
        case .type:
            return MachineEditorFieldMetadata(id: .type, label: "Type", helperText: "Select native or remote session mode.", required: true)
        case .launcher:
            return MachineEditorFieldMetadata(id: .launcher, label: "Wayland Client", helperText: "Launcher used for local native sessions.")
        case .sshHost:
            return MachineEditorFieldMetadata(id: .sshHost, label: "Host", helperText: "Remote host or IP address.", required: true)
        case .sshUser:
            return MachineEditorFieldMetadata(id: .sshUser, label: "Username", helperText: "SSH username.", required: true)
        case .sshPort:
            return MachineEditorFieldMetadata(id: .sshPort, label: "Port", helperText: "SSH port (1-65535).", required: true)
        case .sshPassword:
            return MachineEditorFieldMetadata(id: .sshPassword, label: "Password", helperText: "Optional when key auth is used.")
        case .remoteCommand:
            return MachineEditorFieldMetadata(id: .remoteCommand, label: "Remote Command", helperText: "Command to execute after SSH session starts.")
        case .vmSubtype:
            return MachineEditorFieldMetadata(id: .vmSubtype, label: "VM Type", helperText: "Virtualization backend/profile name.", required: true)
        case .containerSubtype:
            return MachineEditorFieldMetadata(id: .containerSubtype, label: "Container Type", helperText: "Container runtime/profile name.", required: true)
        case .inputProfile:
            return MachineEditorFieldMetadata(id: .inputProfile, label: "Input Profile", helperText: "Input behavior profile.", required: true)
        case .bundledAppID:
            return MachineEditorFieldMetadata(id: .bundledAppID, label: "Bundled App", helperText: "Bundled native app identifier.")
        case .waypipeEnabled:
            return MachineEditorFieldMetadata(id: .waypipeEnabled, label: "Waypipe Enabled")
        }
    }

    public static func validate(_ state: MachineEditorState) -> [MachineEditorValidationIssue] {
        var issues: [MachineEditorValidationIssue] = []
        if state.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            issues.append(MachineEditorValidationIssue.missingName)
        }
        if state.isSSH {
            if sanitizeSSHHost(state.sshHost).isEmpty {
                issues.append(MachineEditorValidationIssue.missingSSHHost)
            }
            if state.sshUser.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                issues.append(MachineEditorValidationIssue.missingSSHUser)
            }
            let port = normalizeSSHPort(state.sshPortText, fallback: -1)
            guard (1...65535).contains(port) else {
                issues.append(MachineEditorValidationIssue.invalidSSHPort)
                return issues
            }
        }
        if state.isVirtualMachine && state.vmSubtype.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            issues.append(MachineEditorValidationIssue.missingVMSubtype)
        }
        if state.isContainer && state.containerSubtype.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            issues.append(MachineEditorValidationIssue.missingContainerSubtype)
        }
        return issues
    }

    public static func normalizedPort(from state: MachineEditorState) -> Int {
        normalizeSSHPort(state.sshPortText)
    }
}
