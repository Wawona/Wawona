import Foundation
import Combine
import WawonaModel
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
  /// ANGLE / iland / Vulkan demos. Hidden when PlatformCapabilities.allowsGpuStack is false.
  var requiresGpuStack: Bool = false
}

/// Bundled clients visible on this platform (GPU demos omitted on tvOS/watchOS).
var kBundledClients: [BundledClient] {
  kAllBundledClients.filter { client in
    if client.requiresGpuStack {
      return PlatformCapabilities.allowsGpuStack
    }
    return true
  }
}

let kAllBundledClients: [BundledClient] = [
  BundledClient(
    id: "weston-terminal",
    name: "Weston Terminal",
    prefsKey: "WestonTerminalEnabled",
    icon: "terminal",
    description: "Terminal emulator. Uses host cursor"
  ),
  BundledClient(
    id: "weston-simple-shm",
    name: "Weston Simple SHM",
    prefsKey: "WestonSimpleSHMEnabled",
    icon: "square.on.square.dashed",
    description: "Minimal shared-memory Wayland client"
  ),
  BundledClient(
    id: "weston",
    name: "Weston",
    prefsKey: "WestonEnabled",
    icon: "rectangle.on.rectangle",
    description: "Wayland reference compositor (nested compositor)"
  ),
  BundledClient(
    id: "niri",
    name: "Niri",
    prefsKey: "NiriEnabled",
    icon: "rectangle.split.3x1",
    description: "Scrollable-tiling compositor (nested compositor)"
  ),
  BundledClient(
    id: "foot",
    name: "Foot Terminal",
    prefsKey: "FootEnabled",
    icon: "character.cursor.ibeam",
    description: "Lightweight Wayland terminal emulator"
  ),
  BundledClient(
    id: "weston-flower",
    name: "Weston Flower",
    prefsKey: "WestonFlowerEnabled",
    icon: "leaf",
    description: "Animated cairo demo (toytoolkit)"
  ),
  BundledClient(
    id: "kmscube",
    name: "KMS Cube",
    prefsKey: "KmscubeEnabled",
    icon: "cube",
    description: "Spinning GL cube via iland + ANGLE (userland KMS)",
    requiresGpuStack: true
  ),
  BundledClient(
    id: "gbm-es2-demo",
    name: "GBM ES2 Demo",
    prefsKey: "GbmEs2DemoEnabled",
    icon: "cube.fill",
    description: "ds-hwang gbm_es2_demo. DRM/GBM/GLES2 over iland (KMS)",
    requiresGpuStack: true
  ),
  BundledClient(
    id: "opengl-cube",
    name: "OpenGL Cube",
    prefsKey: "OpenglCubeEnabled",
    icon: "cube",
    description: "GLES cube via Wayland-EGL (iland + ANGLE)",
    requiresGpuStack: true
  ),
  BundledClient(
    id: "vkcube",
    name: "Vulkan Cube",
    prefsKey: "VkcubeEnabled",
    icon: "cube",
    description: "Vulkan API smoke test",
    requiresGpuStack: true
  ),
  BundledClient(
    id: "weston-simple-egl",
    name: "Weston Simple EGL",
    prefsKey: "WestonSimpleEglEnabled",
    icon: "cube.transparent",
    description: "Wayland EGL demo client (iland + ANGLE)",
    requiresGpuStack: true
  ),
  BundledClient(
    id: "weston-smoke",
    name: "Weston Smoke",
    prefsKey: "WestonSmokeEnabled",
    icon: "cloud",
    description: "Smoke particle cairo demo"
  ),
  BundledClient(
    id: "weston-clickdot",
    name: "Weston Clickdot",
    prefsKey: "WestonClickdotEnabled",
    icon: "circle.grid.2x2",
    description: "Pointer click visualization demo"
  ),
  BundledClient(
    id: "weston-eventdemo",
    name: "Weston Event Demo",
    prefsKey: "WestonEventdemoEnabled",
    icon: "hand.tap",
    description: "Input event logging demo"
  ),
  BundledClient(
    id: "weston-resizor",
    name: "Weston Resizor",
    prefsKey: "WestonResizorEnabled",
    icon: "arrow.up.left.and.arrow.down.right",
    description: "Interactive resize demo"
  ),
  BundledClient(
    id: "weston-cliptest",
    name: "Weston Cliptest",
    prefsKey: "WestonCliptestEnabled",
    icon: "scissors",
    description: "Clipping region demo"
  ),
  BundledClient(
    id: "weston-transformed",
    name: "Weston Transformed",
    prefsKey: "WestonTransformedEnabled",
    icon: "rotate.3d",
    description: "Buffer transform demo"
  ),
  BundledClient(
    id: "weston-stacking",
    name: "Weston Stacking",
    prefsKey: "WestonStackingEnabled",
    icon: "square.stack.3d.up",
    description: "Subsurface stacking demo"
  ),
  BundledClient(
    id: "weston-dnd",
    name: "Weston DnD",
    prefsKey: "WestonDndEnabled",
    icon: "arrow.right.doc.on.clipboard",
    description: "Drag-and-drop demo"
  ),
  BundledClient(
    id: "weston-image",
    name: "Weston Image",
    prefsKey: "WestonImageEnabled",
    icon: "photo",
    description: "PNG image loader demo"
  ),
  BundledClient(
    id: "weston-scaler",
    name: "Weston Scaler",
    prefsKey: "WestonScalerEnabled",
    icon: "arrow.up.left.and.down.right.magnifyingglass",
    description: "Viewport scaler demo"
  ),
  BundledClient(
    id: "weston-editor",
    name: "Weston Editor",
    prefsKey: "WestonEditorEnabled",
    icon: "pencil",
    description: "Text editor demo"
  ),
  BundledClient(
    id: "weston-constraints",
    name: "Weston Constraints",
    prefsKey: "WestonConstraintsEnabled",
    icon: "lock.rectangle.stack",
    description: "Pointer constraints demo"
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
  #if os(macOS)
  /// Avoid re-hitting the ObjC thumbnail store on every SwiftUI body eval
  /// (window moves re-layout Machines and previously reloaded NSImage each time).
  private var thumbnailCache: [String: NSImage] = [:]
  #endif

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

  func deleteAllProfiles() {
    // Stop any active native/remote sessions before profile storage is cleared.
    for profile in profiles where status(for: profile.machineId) != .disconnected {
      disconnect(profile)
    }
    profiles = WWNMachineProfileStore.deleteAllProfiles()
    statusByMachineId.removeAll()
  }

  func status(for machineId: String) -> WWNMachineTransientStatus {
    statusByMachineId[machineId] ?? .disconnected
  }

  func connect(_ profile: WWNMachineProfile, onConnected: (() -> Void)? = nil) {
    statusByMachineId[profile.machineId] = .connecting

    #if os(iOS) || os(tvOS) || os(visionOS)
    // Native Wayland clients may run concurrently. VM / waypipe / container
    // backends still share a single in-process engine on mobile. Stop those
    // before switching. Never tear down an unrelated native client.
    if profile.type != kWWNMachineTypeNative {
      for other in profiles where other.machineId != profile.machineId &&
        status(for: other.machineId) != .disconnected {
        disconnect(other)
      }
    }
    #endif
    // Native clients (and macOS VM/container NSTasks) are tracked per
    // machineId. Connecting one must never tear down another.

    // VM (wwn-vms) and container (wwn-containers) profiles are driven through the
    // session bridge, which delegates to WWNVirtualMachineRunner /
    // WWNContainerRunner. They fall through to the WWNMachineSessionBridge.connect
    // path below like every other backed machine type.

    if profile.type == kWWNMachineTypeNative,
       WWNWaypipeRunner.shared() == nil {
      statusByMachineId[profile.machineId] = .error
      return
    }

    do {
      // ObjC `+ (BOOL)connectProfile:error:` imports to Swift as the throwing
      // method `connect(_:)` (error-peeling + trailing-noun drop).
      try WWNMachineSessionBridge.connect(profile)
    } catch {
      statusByMachineId[profile.machineId] = .error
      return
    }

    statusByMachineId[profile.machineId] = .connected
    onConnected?()
  }

  func disconnect(_ profile: WWNMachineProfile) {
    captureThumbnailIfEnabled(for: profile)
    WWNMachineSessionBridge.disconnectProfile(profile)
    statusByMachineId[profile.machineId] = .disconnected
  }

  func focusRunningMachine(_ profile: WWNMachineProfile) {
    guard status(for: profile.machineId) == .connected ||
            status(for: profile.machineId) == .connecting else {
      return
    }
    WWNMachineProfileStore.setActiveMachineId(profile.machineId)
    #if os(macOS)
    _ = WWNCompositorBridge.shared().focusClientWindows(forMachineId: profile.machineId)
    #elseif os(iOS) || os(tvOS) || os(visionOS)
    // Minimize returns to Machines without killing the session; Focus must
    // reverse that and reveal the live compositor again.
    NotificationCenter.default.post(
      name: .WWNClientFocusRequested,
      object: nil,
      userInfo: ["machineId": profile.machineId]
    )
    #else
    _ = profile
    #endif
  }

  func thumbnailImage(for profile: WWNMachineProfile) -> WWNPlatformImage? {
    #if os(macOS)
    guard isThumbnailEnabled(for: profile) else {
      return nil
    }
    return cachedThumbnailImage(for: profile.machineId)
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

  private func cachedThumbnailImage(for machineId: String) -> NSImage? {
    if let cached = thumbnailCache[machineId] {
      return cached
    }
    guard let image = loadThumbnailImage(for: machineId) else {
      return nil
    }
    thumbnailCache[machineId] = image
    return image
  }

  private func loadThumbnailImage(for machineId: String) -> NSImage? {
    guard let storeClass = NSClassFromString("WWNMachineThumbnailStore") as AnyObject? else {
      return nil
    }
    let selector = NSSelectorFromString("thumbnailForMachineId:")
    guard storeClass.responds(to: selector) else {
      return nil
    }
    typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    let imp = storeClass.method(for: selector)
    let fn = unsafeBitCast(imp, to: Fn.self)
    return fn(storeClass, selector, machineId as NSString)?.takeUnretainedValue() as? NSImage
  }

  private func captureThumbnail(for machineId: String) -> Bool {
    guard let storeClass = NSClassFromString("WWNMachineThumbnailStore") as AnyObject? else {
      return false
    }
    let selector = NSSelectorFromString("captureAndSaveThumbnailForMachineId:")
    guard storeClass.responds(to: selector) else {
      return false
    }
    typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Bool
    let imp = storeClass.method(for: selector)
    let fn = unsafeBitCast(imp, to: Fn.self)
    return fn(storeClass, selector, machineId as NSString)
  }

  private func deleteThumbnail(for machineId: String) {
    guard let storeClass = NSClassFromString("WWNMachineThumbnailStore") as AnyObject? else {
      return
    }
    let selector = NSSelectorFromString("deleteThumbnailForMachineId:")
    guard storeClass.responds(to: selector) else {
      return
    }
    typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Void
    let imp = storeClass.method(for: selector)
    let fn = unsafeBitCast(imp, to: Fn.self)
    fn(storeClass, selector, machineId as NSString)
  }

  private func captureThumbnailIfEnabled(for profile: WWNMachineProfile) {
    guard isThumbnailEnabled(for: profile) else {
      return
    }
    if captureThumbnail(for: profile.machineId) {
      thumbnailCache.removeValue(forKey: profile.machineId)
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
    for profile in profiles {
      let st = status(for: profile.machineId)
      guard st == .connected || st == .connecting else { continue }

      let running: Bool = {
        if profile.type == kWWNMachineTypeNative {
          // Per-machine binding: two weston-terminal profiles must not share
          // a single global "running" bit or one will look taken over.
          return runner.isBundledClientRunning(forMachineId: profile.machineId)
        }
        if profile.type == kWWNMachineTypeSSHWaypipe ||
            profile.type == kWWNMachineTypeSSHTerminal {
          return runner.isRunning
        }
        return false
      }()

      if !running {
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
      // Backend engine is fixed per build target, not user-selected (Residual E).
      return "VM profile (Virtualization.framework)"
    case kWWNMachineTypeContainer:
      return "Container profile (containerization.framework)"
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
      return "No client configured. Edit to select one"
    case kWWNMachineTypeSSHWaypipe:
      let command = profile.remoteCommand.isEmpty ? "weston-simple-shm" : profile.remoteCommand
      return "Waypipe command: \(command)"
    case kWWNMachineTypeSSHTerminal:
      let command = profile.remoteCommand.isEmpty ? "terminal default" : profile.remoteCommand
      return "SSH terminal command: \(command)"
    case kWWNMachineTypeVirtualMachine:
      return "Backend: Virtualization.framework"
    case kWWNMachineTypeContainer:
      return "Backend: containerization.framework"
    default:
      return "No remote transport required"
    }
  }

  func launchCommandString(for profile: WWNMachineProfile) -> String {
    switch profile.type {
    case kWWNMachineTypeNative:
      if let clientId = selectedClientId(for: profile) {
        if clientId == kNativeClientCustomId {
          let cmd = (profile.settingsOverrides as [String: Any])["NativeCustomCommand"] as? String ?? ""
          return cmd
        }
        return clientId
      }
      return ""
    case kWWNMachineTypeSSHWaypipe, kWWNMachineTypeSSHTerminal:
      if !profile.remoteCommand.isEmpty {
        return profile.remoteCommand
      }
      let overrides: [String: Any] = profile.settingsOverrides
      return overrides["WaypipeRemoteCommand"] as? String ?? ""
    default:
      return ""
    }
  }

  func searchableText(for profile: WWNMachineProfile) -> String {
    let command = launchCommandString(for: profile)
    return [
      profile.name,
      profile.sshHost,
      profile.sshUser,
      machineTypeLabel(for: profile),
      machineSubtitle(for: profile),
      machineConfigurationSummary(for: profile),
      command,
    ]
    .filter { !$0.isEmpty }
    .joined(separator: " ")
    .lowercased()
  }

  func launchSupported(for profile: WWNMachineProfile) -> Bool {
    if profile.type == kWWNMachineTypeNative {
      return selectedClientId(for: profile) != nil
    }
    if profile.type == kWWNMachineTypeSSHWaypipe ||
      profile.type == kWWNMachineTypeSSHTerminal {
      return true
    }
    #if os(tvOS) || os(watchOS)
    // Matrix: watchOS/tvOS are native + remote only.
    return false
    #else
    return profile.type == kWWNMachineTypeVirtualMachine ||
      profile.type == kWWNMachineTypeContainer
    #endif
  }
}

