import Foundation
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

#if os(macOS)
typealias WWNPlatformImage = NSImage
#elseif os(iOS) || os(tvOS) || os(visionOS)
typealias WWNPlatformImage = UIImage
#endif

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
    id: "weston-simple-shm",
    name: "Weston Simple SHM",
    prefsKey: "WestonSimpleSHMEnabled",
    icon: "square.on.square.dashed",
    description: "Minimal shared-memory Wayland client",
    isNestedCompositor: false
  ),
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
    id: "foot",
    name: "Foot Terminal",
    prefsKey: "FootEnabled",
    icon: "character.cursor.ibeam",
    description: "Lightweight Wayland terminal emulator",
    isNestedCompositor: false
  ),
]

let kNativeClientCustomId = "custom"

/// Posted by `WWNWaypipeRunner` when a bundled native `NSTask` exits (quit, crash, or Stop).
private let wwnNativeClientProcessDidTerminateNotification = Notification.Name(
  "WWNNativeClientProcessDidTerminateNotification")

@MainActor
final class WWNMachinesViewModel: ObservableObject {
  @Published private(set) var profiles: [WWNMachineProfile] = []
  @Published private(set) var statusByMachineId: [String: WWNMachineTransientStatus] = [:]
  @Published var selectedFilter: WWNMachineFilter = .all

  private var nativeProcessTerminateObserver: NSObjectProtocol?

  init() {
    reload()
    nativeProcessTerminateObserver = NotificationCenter.default.addObserver(
      forName: wwnNativeClientProcessDidTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.captureThumbnailForActiveMachineIfNeeded()
        self?.syncNativeConnectionStatusFromRunner()
      }
    }
  }

  deinit {
    if let nativeProcessTerminateObserver {
      NotificationCenter.default.removeObserver(nativeProcessTerminateObserver)
    }
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
    #if os(macOS)
    deleteThumbnail(for: profile.machineId)
    #endif
    profiles = WWNMachineProfileStore.deleteProfile(byId: profile.machineId)
    statusByMachineId.removeValue(forKey: profile.machineId)
  }

  func status(for machineId: String) -> WWNMachineTransientStatus {
    statusByMachineId[machineId] ?? .disconnected
  }

  func connect(_ profile: WWNMachineProfile, onConnected: (() -> Void)? = nil) {
    statusByMachineId[profile.machineId] = .connecting

    if profile.type == kWWNMachineTypeNative,
       WWNWaypipeRunner.shared() == nil {
      statusByMachineId[profile.machineId] = .error
      return
    }

    WWNPreferencesManager.shared().syncFromCanonicalWawonaPreferences()
    WWNMachineProfileStore.applyMachine(toRuntimePrefs: profile)
    WWNMachineProfileStore.setActiveMachineId(profile.machineId)

    if profile.type == kWWNMachineTypeNative {
      launchNativeClientIfNeeded(for: profile)
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
    captureThumbnailIfEnabled(for: profile)

    if profile.type == kWWNMachineTypeNative {
      let runner = WWNWaypipeRunner.shared()
      switch selectedClientId(for: profile) {
      case "weston":
        runner?.stopWeston()
      case "weston-terminal":
        runner?.stopWestonTerminal()
      case "weston-simple-shm":
        runner?.stopWestonSimpleSHM()
      case "foot":
        runner?.stopFoot()
      default:
        break
      }
    } else if profile.type == kWWNMachineTypeSSHWaypipe ||
                profile.type == kWWNMachineTypeSSHTerminal {
      WWNWaypipeRunner.shared().stopWaypipe()
    }

    statusByMachineId[profile.machineId] = .disconnected
    if WWNMachineProfileStore.activeMachineId() == profile.machineId {
      WWNMachineProfileStore.setActiveMachineId(nil)
    }
  }

  #if os(macOS)
  func focusRunningMachine(_ profile: WWNMachineProfile) {
    guard status(for: profile.machineId) == .connected ||
            status(for: profile.machineId) == .connecting else {
      return
    }
    WWNMachineProfileStore.setActiveMachineId(profile.machineId)
    _ = WWNCompositorBridge.shared().focusClientWindows(forMachineId: profile.machineId)
  }
  #else
  func focusRunningMachine(_ profile: WWNMachineProfile) {
    _ = profile
  }
  #endif

  func thumbnailImage(for profile: WWNMachineProfile) -> WWNPlatformImage? {
    #if os(macOS)
    guard isThumbnailEnabled(for: profile) else {
      return nil
    }
    return loadThumbnailImage(for: profile.machineId)
    #else
    _ = profile
    return nil
    #endif
  }

  #if os(macOS)
  private func isThumbnailEnabled(for profile: WWNMachineProfile) -> Bool {
    let runtimeOverrides: [String: Any] = profile.runtimeOverrides
    if let override = runtimeOverrides["machineThumbnailEnabledOverride"] as? Bool {
      return override
    }
    return WWNPreferencesManager.shared().machineSessionThumbnailsEnabled()
  }

  private func loadThumbnailImage(for machineId: String) -> NSImage? {
    guard let storeClass = NSClassFromString("WWNMachineThumbnailStore") as? NSObject.Type else {
      return nil
    }
    let selector = NSSelectorFromString("thumbnailForMachineId:")
    guard storeClass.responds(to: selector),
          let result = storeClass.perform(selector, with: machineId)?.takeUnretainedValue() else {
      return nil
    }
    return result as? NSImage
  }

  private func captureThumbnail(for machineId: String) -> Bool {
    guard let storeClass = NSClassFromString("WWNMachineThumbnailStore") as? NSObject.Type else {
      return false
    }
    let selector = NSSelectorFromString("captureAndSaveThumbnailForMachineId:")
    guard storeClass.responds(to: selector),
          let result = storeClass.perform(selector, with: machineId)?.takeUnretainedValue() else {
      return false
    }
    return (result as? NSNumber)?.boolValue ?? false
  }

  private func deleteThumbnail(for machineId: String) {
    guard let storeClass = NSClassFromString("WWNMachineThumbnailStore") as? NSObject.Type else {
      return
    }
    let selector = NSSelectorFromString("deleteThumbnailForMachineId:")
    guard storeClass.responds(to: selector) else {
      return
    }
    _ = storeClass.perform(selector, with: machineId)
  }

  private func captureThumbnailIfEnabled(for profile: WWNMachineProfile) {
    guard isThumbnailEnabled(for: profile) else {
      return
    }
    if captureThumbnail(for: profile.machineId) {
      objectWillChange.send()
    }
  }

  private func captureThumbnailForActiveMachineIfNeeded() {
    guard let machineId = WWNMachineProfileStore.activeMachineId(),
          let profile = profiles.first(where: { $0.machineId == machineId }) else {
      return
    }
    captureThumbnailIfEnabled(for: profile)
  }
  #else
  private func captureThumbnailIfEnabled(for profile: WWNMachineProfile) {
    _ = profile
  }

  private func captureThumbnailForActiveMachineIfNeeded() {}
  #endif

  /// Aligns UI "connected" with `WWNWaypipeRunner` (e.g. user quit Weston outside Stop).
  private func syncNativeConnectionStatusFromRunner() {
    guard let runner = WWNWaypipeRunner.shared() else { return }
    for profile in profiles where profile.type == kWWNMachineTypeNative {
      guard let clientId = selectedClientId(for: profile) else { continue }
      let running: Bool = {
        switch clientId {
        case "weston":
          return runner.westonRunning
        case "weston-terminal":
          return runner.westonTerminalRunning
        case "weston-simple-shm":
          return runner.isWestonSimpleSHMRunning
        case "foot":
          return runner.footRunning
        default:
          return false
        }
      }()
      let st = status(for: profile.machineId)
      if (st == .connected || st == .connecting), !running {
        statusByMachineId[profile.machineId] = .disconnected
        if WWNMachineProfileStore.activeMachineId() == profile.machineId {
          WWNMachineProfileStore.setActiveMachineId(nil)
        }
      }
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
      let command = profile.remoteCommand.isEmpty ? "weston-simple-shm" : profile.remoteCommand
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

  private func launchNativeClientIfNeeded(for profile: WWNMachineProfile) {
    guard profile.type == kWWNMachineTypeNative else { return }
    guard let runner = WWNWaypipeRunner.shared() else { return }
    switch selectedClientId(for: profile) {
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
