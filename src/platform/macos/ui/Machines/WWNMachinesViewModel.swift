import Foundation
import Combine

@objc enum WWNMachineTransientStatus: Int, CaseIterable {
  case disconnected
  case connecting
  case connected
  case degraded
  case error

  var title: String {
    switch self {
    case .disconnected: return "Disconnected"
    case .connecting: return "Connecting"
    case .connected: return "Connected"
    case .degraded: return "Degraded"
    case .error: return "Error"
    }
  }
}

struct BundledClient: Identifiable, Hashable {
  let id: String
  let name: String
  let prefsKey: String
  let icon: String
  let description: String
  let isNestedCompositor: Bool
}

let kBundledClients: [BundledClient] = [
  BundledClient(
    id: "weston",
    name: "Weston",
    prefsKey: "WestonEnabled",
    icon: "rectangle.on.rectangle",
    description: "Wayland reference compositor (renders its own cursor)",
    isNestedCompositor: true
  ),
  BundledClient(
    id: "weston-terminal",
    name: "Weston Terminal",
    prefsKey: "WestonTerminalEnabled",
    icon: "terminal",
    description: "Terminal emulator — uses host cursor",
    isNestedCompositor: false
  ),
  BundledClient(
    id: "weston-simple-shm",
    name: "Weston Simple SHM",
    prefsKey: "WestonSimpleSHMEnabled",
    icon: "square.on.square.dashed",
    description: "Minimal shared-memory Wayland client",
    isNestedCompositor: false
  ),
  BundledClient(
    id: "foot",
    name: "Foot Terminal",
    prefsKey: "FootEnabled",
    icon: "character.cursor.ibeam",
    description: "Lightweight Wayland terminal emulator",
    isNestedCompositor: false
  ),
]

let kNativeClientCustomId = "custom"

@MainActor
final class WWNMachinesViewModel: ObservableObject {
  @Published private(set) var profiles: [WWNMachineProfile] = []
  @Published private(set) var statusByMachineId: [String: WWNMachineTransientStatus] = [:]
  @Published var selectedFilter: WWNMachineFilter = .all

  init() {
    reload()
  }

  var activeMachineId: String? {
    WWNMachineProfileStore.activeMachineId()
  }

  var filteredProfiles: [WWNMachineProfile] {
    switch selectedFilter {
    case .all:
      return profiles
    case .local:
      return profiles.filter { profile in
        profile.type == kWWNMachineTypeNative ||
          profile.type == kWWNMachineTypeVirtualMachine ||
          profile.type == kWWNMachineTypeContainer
      }
    case .remote:
      return profiles.filter { profile in
        profile.type == kWWNMachineTypeSSHWaypipe ||
          profile.type == kWWNMachineTypeSSHTerminal
      }
    }
  }

  var connectedCount: Int {
    profiles.reduce(0) { partial, profile in
      partial + (status(for: profile.machineId) == .connected ? 1 : 0)
    }
  }

  var launchableCount: Int {
    profiles.reduce(0) { partial, profile in
      partial + (launchSupported(for: profile) ? 1 : 0)
    }
  }

  func reload() {
    profiles = WWNMachineProfileStore.loadProfiles()
    for profile in profiles {
      if statusByMachineId[profile.machineId] == nil {
        statusByMachineId[profile.machineId] = .disconnected
      }
    }
  }

  func upsert(_ profile: WWNMachineProfile) {
    profiles = WWNMachineProfileStore.upsertProfile(profile)
    if statusByMachineId[profile.machineId] == nil {
      statusByMachineId[profile.machineId] = .disconnected
    }
  }

  func delete(_ profile: WWNMachineProfile) {
    profiles = WWNMachineProfileStore.deleteProfile(byId: profile.machineId)
    statusByMachineId.removeValue(forKey: profile.machineId)
  }

  func status(for machineId: String) -> WWNMachineTransientStatus {
    statusByMachineId[machineId] ?? .disconnected
  }

  func connect(_ profile: WWNMachineProfile, onConnected: (() -> Void)? = nil) {
    statusByMachineId[profile.machineId] = .connecting
    WWNPreferencesManager.shared().syncFromCanonicalWawonaPreferences()
    WWNMachineProfileStore.applyMachine(toRuntimePrefs: profile)
    WWNMachineProfileStore.setActiveMachineId(profile.machineId)

    if profile.type == kWWNMachineTypeNative {
      guard let runner = WWNWaypipeRunner.shared() else {
        statusByMachineId[profile.machineId] = .error
        return
      }
      // Stop any previously running native client before starting a new one.
      runner.stopWeston()
      runner.stopWestonTerminal()
      runner.stopWestonSimpleSHM()
      runner.stopFoot()

      switch selectedClientId(for: profile) ?? "" {
      case "weston":
        runner.launchWeston()
      case "weston-terminal":
        runner.launchWestonTerminal()
      case "weston-simple-shm":
        runner.launchWestonSimpleSHM()
      case "foot":
        runner.launchFoot()
      default:
        break
      }

      statusByMachineId[profile.machineId] = .connected
      onConnected?()
      return
    }

    if profile.type == kWWNMachineTypeVirtualMachine ||
      profile.type == kWWNMachineTypeContainer {
      statusByMachineId[profile.machineId] = .degraded
      return
    }

    WWNWaypipeRunner.shared().launchWaypipe(WWNPreferencesManager.shared())
    statusByMachineId[profile.machineId] = .connected
    onConnected?()
  }

  func disconnect(_ profile: WWNMachineProfile) {
    if profile.type == kWWNMachineTypeNative {
      let prefs = WWNPreferencesManager.shared()
      prefs.setWestonEnabled(false)
      prefs.setWestonTerminalEnabled(false)
      prefs.setWestonSimpleSHMEnabled(false)
      prefs.setFootEnabled(false)
      prefs.setEnableLauncher(false)
    } else if profile.type == kWWNMachineTypeSSHWaypipe ||
                profile.type == kWWNMachineTypeSSHTerminal {
      WWNWaypipeRunner.shared().stopWaypipe()
    }

    statusByMachineId[profile.machineId] = .disconnected
    if WWNMachineProfileStore.activeMachineId() == profile.machineId {
      WWNMachineProfileStore.setActiveMachineId(nil)
    }
  }

  var isAnyMachineRunning: Bool {
    statusByMachineId.values.contains { $0 == .connected || $0 == .connecting }
  }

  func machineTypeLabel(for profile: WWNMachineProfile) -> String {
    switch profile.type {
    case kWWNMachineTypeNative:
      return "Native"
    case kWWNMachineTypeSSHWaypipe:
      return "SSH + Waypipe"
    case kWWNMachineTypeSSHTerminal:
      return "SSH Terminal"
    case kWWNMachineTypeVirtualMachine:
      return "Virtual Machine"
    case kWWNMachineTypeContainer:
      return "Container"
    default:
      return profile.type
    }
  }

  func machineScopeLabel(for profile: WWNMachineProfile) -> String {
    switch profile.type {
    case kWWNMachineTypeNative, kWWNMachineTypeVirtualMachine, kWWNMachineTypeContainer:
      return "Local"
    default:
      return "Remote"
    }
  }

  func machineSubtitle(for profile: WWNMachineProfile) -> String {
    switch profile.type {
    case kWWNMachineTypeNative:
      if let name = selectedClientName(for: profile) {
        return name
      }
      return "No client configured"
    case kWWNMachineTypeVirtualMachine:
      let subtype = profile.vmSubtype.isEmpty ? "qemu" : profile.vmSubtype
      return "VM profile (\(subtype.uppercased()))"
    case kWWNMachineTypeContainer:
      let subtype = profile.containerSubtype.isEmpty ? "docker" : profile.containerSubtype
      return "Container profile (\(subtype.uppercased()))"
    default:
      if profile.sshHost.isEmpty {
        return "SSH endpoint not configured"
      }
      let user = profile.sshUser.isEmpty ? "user" : profile.sshUser
      return "\(user)@\(profile.sshHost)"
    }
  }

  func selectedClientId(for profile: WWNMachineProfile) -> String? {
    guard profile.type == kWWNMachineTypeNative else { return nil }
    let runtimeOverrides: [String: Any] = profile.runtimeOverrides
    if let clientId = runtimeOverrides["bundledAppID"] as? String, !clientId.isEmpty {
      return clientId
    }
    let overrides: [String: Any] = profile.settingsOverrides
    if let clientId = overrides["NativeClientId"] as? String, !clientId.isEmpty {
      return clientId
    }
    for client in kBundledClients {
      if (overrides[client.prefsKey] as? Bool) == true {
        return client.id
      }
    }
    return nil
  }

  func selectedClientName(for profile: WWNMachineProfile) -> String? {
    guard let clientId = selectedClientId(for: profile) else { return nil }
    if clientId == kNativeClientCustomId {
      let cmd = (profile.settingsOverrides as [String: Any])["NativeCustomCommand"] as? String ?? ""
      return cmd.isEmpty ? "Custom command" : cmd
    }
    return kBundledClients.first { $0.id == clientId }?.name
  }

  func machineConfigurationSummary(for profile: WWNMachineProfile) -> String {
    switch profile.type {
    case kWWNMachineTypeNative:
      if let clientName = selectedClientName(for: profile) {
        return "Runs: \(clientName)"
      }
      return "No client configured — edit to select one"
    case kWWNMachineTypeSSHWaypipe:
      let command = profile.remoteCommand.isEmpty ? "weston-terminal" : profile.remoteCommand
      return "Waypipe command: \(command)"
    case kWWNMachineTypeSSHTerminal:
      let command = profile.remoteCommand.isEmpty ? "terminal default" : profile.remoteCommand
      return "SSH terminal command: \(command)"
    case kWWNMachineTypeVirtualMachine:
      return "Subtype: \(profile.vmSubtype.isEmpty ? "qemu" : profile.vmSubtype)"
    case kWWNMachineTypeContainer:
      return "Subtype: \(profile.containerSubtype.isEmpty ? "docker" : profile.containerSubtype)"
    default:
      return "No remote transport required"
    }
  }

  func launchSupported(for profile: WWNMachineProfile) -> Bool {
    if profile.type == kWWNMachineTypeNative {
      return selectedClientId(for: profile) != nil
    }
    return profile.type == kWWNMachineTypeSSHWaypipe ||
      profile.type == kWWNMachineTypeSSHTerminal
  }
}

enum WWNMachineFilter: String, CaseIterable, Identifiable, Hashable {
  case all = "All Machines"
  case local = "Local"
  case remote = "Remote"

  var id: String { rawValue }

  /// The sensible machine type to default to when adding a new profile from this filter.
  var defaultMachineType: String {
    switch self {
    case .remote: return kWWNMachineTypeSSHWaypipe
    default:      return kWWNMachineTypeNative
    }
  }
}
