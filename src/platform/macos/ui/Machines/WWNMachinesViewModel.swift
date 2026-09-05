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
  case preparing
  case connected
  case degraded
  case error

  var title: String {
    switch self {
    case .disconnected: return "Disconnected"
    case .connecting: return "Connecting"
    case .preparing: return "Starting container"
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

/// Bundled clients visible on this platform (GPU demos omitted on watchOS).
var kBundledClients: [BundledClient] {
  kAllBundledClients.filter { client in
    if PlatformCapabilities.glesClientIds.contains(client.id) {
      return PlatformCapabilities.openGLDriverEnabled
    }
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
    id: "wawona-wasm",
    name: "Wawona Runtime (.wasm)",
    prefsKey: "WawonaWasmEnabled",
    icon: "doc.badge.gearshape",
    description: "Wayland WASI module from the filesystem (Wawona Runtime)"
  ),
  BundledClient(
    id: "weston",
    name: "Weston",
    prefsKey: "WestonEnabled",
    icon: "rectangle.on.rectangle",
    description: "Wayland reference compositor. Nested Wayland or iland DRM/KMS (Display Backend). Mode B Take Over uses DRM."
  ),
  BundledClient(
    id: "niri",
    name: "Niri",
    prefsKey: "NiriEnabled",
    icon: "rectangle.split.3x1",
    description: "Scrollable-tiling compositor. Nested Wayland or iland DRM/KMS (Display Backend). Mode B Take Over uses DRM."
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
    description: "Vulkan cube. Mode A: Wayland client. Mode B Take Over: vkcube-kms (iland DRM/KMS/GBM).",
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
/// Per-machine Wayland client: Wawona Runtime interprets a `.wasm` document.
let kNativeClientWasmId = "wawona-wasm"
/// `runtimeOverrides` key for the selected module path (absolute or Documents-relative).
let kRuntimeWasmModulePathKey = "wasmModulePath"

/// Posted by `WWNWaypipeRunner` when a bundled native `NSTask` exits (quit, crash, or Stop).
private let wwnNativeClientProcessDidTerminateNotification = Notification.Name(
  "WWNNativeClientProcessDidTerminateNotification")
private let wwnContainerBackendDidBecomeReadyNotification = Notification.Name(
  "WWNContainerBackendDidBecomeReadyNotification")
private let wwnContainerBackendDidStopNotification = Notification.Name(
  "WWNContainerBackendDidStopNotification")
private let wwnMachineProfilesChangedNotification = Notification.Name(
  "WWNMachineProfilesChangedNotification")

@MainActor
final class WWNMachinesViewModel: ObservableObject {
  @Published private(set) var profiles: [WWNMachineProfile] = []
  @Published private(set) var statusByMachineId: [String: WWNMachineTransientStatus] = [:]
  /// Machine ids the user pinned via the card context menu. Pinned machines
  /// sort first in the grid. Persisted per app in UserDefaults.
  @Published private(set) var pinnedMachineIds: Set<String> = []
  private static let pinnedDefaultsKey = "wawona.machines.pinnedMachineIds"

  // MARK: Sorting

  /// Finder-style sort criteria. Pinned machines always stay on top; the
  /// selected key only orders inside the pinned / unpinned groups.
  enum SortKey: String, CaseIterable {
    case dateCreated
    case dateLastUsed
    case name
    case kind

    var title: String {
      switch self {
      case .dateCreated: return "Date Created"
      case .dateLastUsed: return "Date Last Used"
      case .name: return "Name"
      case .kind: return "Kind"
      }
    }
  }

  /// Persisted sort state (per app, like pins).
  @Published private(set) var sortKey: SortKey
  @Published private(set) var sortAscending: Bool
  private static let sortKeyDefaultsKey = "wawona.machines.sortKey"
  private static let sortAscendingDefaultsKey = "wawona.machines.sortAscending"

  // MARK: Machine metadata (timestamps)

  /// First-seen / last-used timestamps per machineId, persisted alongside the
  /// profiles. Existing machines get a creation date the first time they are
  /// seen after this feature ships.
  @Published private(set) var createdAtByMachine: [String: Date] = [:]
  @Published private(set) var lastUsedAtByMachine: [String: Date] = [:]
  private static let metadataDefaultsKey = "wawona.machines.metadata"
  #if os(macOS)
  /// Avoid re-hitting the ObjC thumbnail store on every SwiftUI body eval
  /// (window moves re-layout Machines and previously reloaded NSImage each time).
  private var thumbnailCache: [String: NSImage] = [:]
  #endif

  private var nativeProcessTerminateObserver: NSObjectProtocol?
  private var containerReadyObserver: NSObjectProtocol?
  private var containerStopObserver: NSObjectProtocol?
  private var profilesChangedObserver: NSObjectProtocol?
  private var profilesChangedDistributedObserver: NSObjectProtocol?
  private var pendingContainerConnectCallbacks: [String: () -> Void] = [:]

  init() {
    pinnedMachineIds = Set(UserDefaults.standard.stringArray(forKey: Self.pinnedDefaultsKey) ?? [])
    sortKey = SortKey(rawValue: UserDefaults.standard.string(forKey: Self.sortKeyDefaultsKey) ?? "")
      ?? .dateCreated
    sortAscending = UserDefaults.standard.object(forKey: Self.sortAscendingDefaultsKey) == nil
      ? true
      : UserDefaults.standard.bool(forKey: Self.sortAscendingDefaultsKey)
    loadMetadata()
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
    containerReadyObserver = NotificationCenter.default.addObserver(
      forName: wwnContainerBackendDidBecomeReadyNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      Task { @MainActor [weak self] in
        self?.handleContainerReady(note)
      }
    }
    containerStopObserver = NotificationCenter.default.addObserver(
      forName: wwnContainerBackendDidStopNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      Task { @MainActor [weak self] in
        self?.handleContainerStop(note)
      }
    }
    profilesChangedObserver = NotificationCenter.default.addObserver(
      forName: wwnMachineProfilesChangedNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.reload()
      }
    }
    #if os(macOS)
    profilesChangedDistributedObserver = DistributedNotificationCenter.default()
      .addObserver(
        forName: wwnMachineProfilesChangedNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          // CLI process may have just written UserDefaults; synchronize first.
          UserDefaults.standard.synchronize()
          self?.reload()
        }
      }
    #endif
  }

  deinit {
    if let nativeProcessTerminateObserver {
      NotificationCenter.default.removeObserver(nativeProcessTerminateObserver)
    }
    if let containerReadyObserver {
      NotificationCenter.default.removeObserver(containerReadyObserver)
    }
    if let containerStopObserver {
      NotificationCenter.default.removeObserver(containerStopObserver)
    }
    if let profilesChangedObserver {
      NotificationCenter.default.removeObserver(profilesChangedObserver)
    }
    #if os(macOS)
    if let profilesChangedDistributedObserver {
      DistributedNotificationCenter.default()
        .removeObserver(profilesChangedDistributedObserver)
    }
    #endif
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
    // Swift persist leftover OpenGLDriver=none → ANGLE, then ObjC profile JSON
    // rewrite. Machines UI on tvOS never created WawonaPreferences otherwise.
    _ = WawonaPreferences.shared
    _ = WWNPreferencesManager.shared()
    profiles = WWNMachineProfileStore.loadProfiles()
    for profile in profiles {
      if statusByMachineId[profile.machineId] == nil {
        statusByMachineId[profile.machineId] = .disconnected
      }
    }
    // First-seen timestamps power "Date Created" sorting.
    var created = createdAtByMachine
    var changed = false
    for profile in profiles where created[profile.machineId] == nil {
      created[profile.machineId] = Date()
      changed = true
    }
    if changed {
      createdAtByMachine = created
      persistMetadata()
    }
    WWNMachineTagStore.shared.pruneAssignments(
      keeping: Set(profiles.map { $0.machineId })
    )
  }

  func upsert(_ profile: WWNMachineProfile) {
    var runtime = Dictionary(uniqueKeysWithValues:
      (profile.runtimeOverrides as? [String: Any] ?? [:]).map { ($0.key, $0.value) })
    if runtime["origin"] == nil {
      runtime["origin"] = "manual"
      profile.runtimeOverrides = runtime
    }
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
    removePinned(profile.machineId)
    createdAtByMachine.removeValue(forKey: profile.machineId)
    lastUsedAtByMachine.removeValue(forKey: profile.machineId)
    persistMetadata()
  }

  func deleteAllProfiles() {
    // Stop any active native/remote sessions before profile storage is cleared.
    for profile in profiles where status(for: profile.machineId) != .disconnected {
      disconnect(profile)
    }
    profiles = WWNMachineProfileStore.deleteAllProfiles()
    statusByMachineId.removeAll()
    if !pinnedMachineIds.isEmpty {
      pinnedMachineIds.removeAll()
      persistPinnedIds()
    }
    createdAtByMachine.removeAll()
    lastUsedAtByMachine.removeAll()
    persistMetadata()
  }

  func status(for machineId: String) -> WWNMachineTransientStatus {
    statusByMachineId[machineId] ?? .disconnected
  }

  // MARK: - Pinning

  func isPinned(_ machineId: String) -> Bool {
    pinnedMachineIds.contains(machineId)
  }

  func togglePinned(_ machineId: String) {
    if pinnedMachineIds.contains(machineId) {
      pinnedMachineIds.remove(machineId)
    } else {
      pinnedMachineIds.insert(machineId)
    }
    persistPinnedIds()
  }

  private func removePinned(_ machineId: String) {
    guard pinnedMachineIds.remove(machineId) != nil else { return }
    persistPinnedIds()
  }

  private func persistPinnedIds() {
    UserDefaults.standard.set(Array(pinnedMachineIds), forKey: Self.pinnedDefaultsKey)
  }

  // MARK: - Sorting + metadata

  func setSortKey(_ key: SortKey) {
    sortKey = key
    UserDefaults.standard.set(key.rawValue, forKey: Self.sortKeyDefaultsKey)
  }

  func setSortAscending(_ ascending: Bool) {
    sortAscending = ascending
    UserDefaults.standard.set(ascending, forKey: Self.sortAscendingDefaultsKey)
  }

  func dateCreated(for machineId: String) -> Date {
    createdAtByMachine[machineId] ?? .distantPast
  }

  func dateLastUsed(for machineId: String) -> Date {
    lastUsedAtByMachine[machineId] ?? .distantPast
  }

  /// Record a machine as "used now" (connect / focus).
  func touchLastUsed(_ machineId: String) {
    lastUsedAtByMachine[machineId] = Date()
    persistMetadata()
  }

  private func loadMetadata() {
    guard let raw = UserDefaults.standard.dictionary(forKey: Self.metadataDefaultsKey) else {
      return
    }
    var created: [String: Date] = [:]
    var lastUsed: [String: Date] = [:]
    for (machineId, value) in raw {
      guard let payload = value as? [String: Double] else { continue }
      if let ts = payload["createdAt"] {
        created[machineId] = Date(timeIntervalSince1970: ts)
      }
      if let ts = payload["lastUsedAt"] {
        lastUsed[machineId] = Date(timeIntervalSince1970: ts)
      }
    }
    createdAtByMachine = created
    lastUsedAtByMachine = lastUsed
  }

  private func persistMetadata() {
    var payload: [String: [String: Double]] = [:]
    let ids = Set(createdAtByMachine.keys).union(lastUsedAtByMachine.keys)
    for machineId in ids {
      var entry: [String: Double] = [:]
      if let created = createdAtByMachine[machineId] {
        entry["createdAt"] = created.timeIntervalSince1970
      }
      if let lastUsed = lastUsedAtByMachine[machineId] {
        entry["lastUsedAt"] = lastUsed.timeIntervalSince1970
      }
      payload[machineId] = entry
    }
    UserDefaults.standard.set(payload, forKey: Self.metadataDefaultsKey)
  }

  /// Order profiles for display: pinned first (always), then the selected
  /// sort key in the stored direction. Within equal keys, name breaks ties
  /// (creation order as a final fallback keeps the order stable).
  func displayOrder(_ profilesToSort: [WWNMachineProfile]) -> [WWNMachineProfile] {
    profilesToSort.sorted { lhs, rhs in
      let lhsPinned = isPinned(lhs.machineId)
      let rhsPinned = isPinned(rhs.machineId)
      if lhsPinned != rhsPinned {
        return lhsPinned
      }
      let ascending = sortAscending
      func ordered(_ a: Date, _ b: Date) -> Bool {
        ascending ? a < b : a > b
      }
      func ordered(_ a: String, _ b: String) -> Bool {
        ascending
          ? a.localizedCaseInsensitiveCompare(b) == .orderedAscending
          : a.localizedCaseInsensitiveCompare(b) == .orderedDescending
      }
      switch sortKey {
      case .dateCreated:
        let a = dateCreated(for: lhs.machineId)
        let b = dateCreated(for: rhs.machineId)
        if a != b { return ordered(a, b) }
      case .dateLastUsed:
        let a = dateLastUsed(for: lhs.machineId)
        let b = dateLastUsed(for: rhs.machineId)
        if a != b { return ordered(a, b) }
      case .name:
        return ordered(lhs.name, rhs.name)
      case .kind:
        let kindOrder = ordered(
          machineTypeLabel(for: lhs),
          machineTypeLabel(for: rhs)
        )
        if lhs.type != rhs.type { return kindOrder }
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  func connect(_ profile: WWNMachineProfile, onConnected: (() -> Void)? = nil) {
    let isContainer = profile.type == kWWNMachineTypeContainer
    statusByMachineId[profile.machineId] =
      isContainer ? .preparing : .connecting

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

    if isContainer {
      pendingContainerConnectCallbacks[profile.machineId] = onConnected
    }

    do {
      try WWNMachineSessionBridge.connect(profile)
    } catch {
      statusByMachineId[profile.machineId] = .error
      pendingContainerConnectCallbacks.removeValue(forKey: profile.machineId)
      return
    }

    if isContainer {
      // Stay "Starting container" until WWNContainerRunner reports the VM is
      // booted (WWNContainerBackendDidBecomeReadyNotification). Not a compile.
      return
    }

    statusByMachineId[profile.machineId] = .connected
    touchLastUsed(profile.machineId)
    onConnected?()
  }

  private func handleContainerReady(_ note: Notification) {
    guard let machineId = note.userInfo?["machineId"] as? String else { return }
    guard status(for: machineId) == .preparing else { return }
    statusByMachineId[machineId] = .connected
    touchLastUsed(machineId)
    let callback = pendingContainerConnectCallbacks.removeValue(forKey: machineId)
    callback?()
  }

  private func handleContainerStop(_ note: Notification) {
    guard let machineId = note.userInfo?["machineId"] as? String else { return }
    // If it never reached ready, the backend failed to boot rather than a
    // clean stop.
    let failedToBecomeReady = status(for: machineId) == .preparing
    statusByMachineId[machineId] = failedToBecomeReady ? .error : .disconnected
    pendingContainerConnectCallbacks.removeValue(forKey: machineId)
    if WWNMachineProfileStore.activeMachineId() == machineId {
      WWNMachineProfileStore.setActiveMachineId(nil)
    }
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
    touchLastUsed(profile.machineId)
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
      return "VM profile (QEMU + HVF)"
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
    if clientId == kNativeClientWasmId {
      let path = (profile.runtimeOverrides as [String: Any])[kRuntimeWasmModulePathKey] as? String ?? ""
      if !path.isEmpty {
        return (path as NSString).lastPathComponent
      }
      return "Wawona Runtime (.wasm)"
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
      return "Backend: QEMU + HVF (Hypervisor.framework)"
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

