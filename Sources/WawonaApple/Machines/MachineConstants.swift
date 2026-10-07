import Foundation

/// Machine type / CLI recipe string constants (replaces deleted ObjC `.m` defs).
public let kWWNMachineTypeSSHWaypipe = "ssh_waypipe"
public let kWWNMachineTypeSSHTerminal = "ssh_terminal"
public let kWWNMachineTypeNative = "native"
public let kWWNMachineTypeWasm = "wasm"
public let kWWNMachineTypeVirtualMachine = "virtual_machine"
public let kWWNMachineTypeContainer = "container"

/// User-facing Machines kinds. Everything else folds into Native Shell session modes.
public let kWWNSelectableMachineTypes: [String] = [
    kWWNMachineTypeNative,
    kWWNMachineTypeVirtualMachine,
    kWWNMachineTypeContainer,
]

/// Native Shell session modes (settingsOverrides `NativeShellKind`).
public let kWWNNativeShellKindTerminal = "terminal"
public let kWWNNativeShellKindWayland = "wayland"
public let kWWNNativeShellKindWasm = "wasm"
public let kWWNNativeShellKindWaypipe = "waypipe"
public let kWWNPrefsNativeShellKind = "NativeShellKind"
public let kWWNPrefsNativeShellUseSSH = "NativeShellUseSSH"

public let kWWNCLIRecipeKey = "cliRecipeKey"
public let kWWNMachineOrigin = "origin"
public let kWWNMachineOriginCLI = "cli"
public let kWWNMachineOriginManual = "manual"

extension Notification.Name {
    public static let WWNMachineProfilesChanged =
        Notification.Name("WWNMachineProfilesChangedNotification")
}

/// Resolves Native Shell session mode from a profile (including legacy types).
public enum WWNNativeShellConfiguration {
    public static func kind(for profile: WWNMachineProfile) -> String {
        let overrides = profile.settingsOverrides as? [String: Any] ?? [:]
        if let stored = overrides[kWWNPrefsNativeShellKind] as? String, !stored.isEmpty {
            return stored
        }
        switch profile.type {
        case kWWNMachineTypeWasm:
            return kWWNNativeShellKindWasm
        case kWWNMachineTypeSSHTerminal:
            return kWWNNativeShellKindTerminal
        case kWWNMachineTypeSSHWaypipe:
            return kWWNNativeShellKindWaypipe
        case kWWNMachineTypeNative:
            let client = bundledClientId(in: profile) ?? ""
            if client == "wawona-shell" || client.isEmpty {
                return kWWNNativeShellKindTerminal
            }
            if client == "wawona-wasm" {
                return kWWNNativeShellKindWasm
            }
            return kWWNNativeShellKindWayland
        default:
            return kWWNNativeShellKindTerminal
        }
    }

    public static func usesSSH(for profile: WWNMachineProfile) -> Bool {
        let overrides = profile.settingsOverrides as? [String: Any] ?? [:]
        if let stored = overrides[kWWNPrefsNativeShellUseSSH] as? Bool {
            return stored
        }
        switch profile.type {
        case kWWNMachineTypeSSHTerminal, kWWNMachineTypeSSHWaypipe:
            return true
        default:
            // Do not infer SSH from a leftover host field on Wayland/Terminal local.
            return false
        }
    }

    public static func isNativeShellFamily(_ type: String) -> Bool {
        type == kWWNMachineTypeNative
            || type == kWWNMachineTypeWasm
            || type == kWWNMachineTypeSSHWaypipe
            || type == kWWNMachineTypeSSHTerminal
    }

    public static func userFacingTypeName(_ type: String) -> String {
        switch type {
        case kWWNMachineTypeNative, kWWNMachineTypeWasm,
             kWWNMachineTypeSSHWaypipe, kWWNMachineTypeSSHTerminal:
            return "Native Shell"
        case kWWNMachineTypeVirtualMachine:
            return "Virtual Machine"
        case kWWNMachineTypeContainer:
            return "Container"
        default:
            return type
        }
    }

    public static func bundledClientId(in profile: WWNMachineProfile) -> String? {
        if let runtime = profile.runtimeOverrides as? [String: Any],
           let bundled = runtime["bundledAppID"] as? String, !bundled.isEmpty {
            return bundled
        }
        if let overrides = profile.settingsOverrides as? [String: Any],
           let native = overrides["NativeClientId"] as? String, !native.isEmpty {
            return native
        }
        return nil
    }
}
