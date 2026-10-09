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

  /// Picker section (Compositors / Terminals / Graphics / Demos / Other).
  var softwareKind: BundledWaylandSoftwareKind {
    BundledWaylandSoftwareKind.kind(forClientId: id)
  }
}

extension Array where Element == BundledClient {
  /// Same grouping as `ClientLauncher.waylandPickerGrouped()` for the thick editor.
  func waylandPickerGrouped() -> [(kind: BundledWaylandSoftwareKind, clients: [BundledClient])] {
    BundledWaylandSoftwareKind.allCases.compactMap { kind in
      let group = filter {
        $0.id != "wawona-shell" && $0.id != "wawona-wasm"
          && BundledWaylandSoftwareKind.kind(forClientId: $0.id) == kind
      }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return group.isEmpty ? nil : (kind, group)
    }
  }
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

/// Native clients. wawona-shell is the host shell in the console view, with
/// no Wayland client. Never add modeb-tty, igetty, or igettyd.
let kAllBundledClients: [BundledClient] = [
  BundledClient(
    id: "wawona-shell",
    name: "None",
    prefsKey: "WawonaShellEnabled",
    icon: "terminal",
    description: "Wawona Terminal. No Wayland client"
  ),
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
    description: "Wayland WASI. Empty path runs bundled hello-wasi-gui (wl_shm) on every target"
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
let kRuntimeWasmLaunchModeKey = "wasmLaunchMode"
let kRuntimeWasmPackageKey = "wasmPackage"
let kRuntimeWasmCommandKey = "wasmCommand"

/// Posted by `WWNWaypipeRunner` when a bundled native `NSTask` exits (quit, crash, or Stop).
private let wwnNativeClientProcessDidTerminateNotification = Notification.Name(
  "WWNNativeClientProcessDidTerminateNotification")
private let wwnContainerBackendDidBecomeReadyNotification = Notification.Name(
  "WWNContainerBackendDidBecomeReadyNotification")
private let wwnContainerBackendDidStopNotification = Notification.Name(
  "WWNContainerBackendDidStopNotification")
private let wwnMachineProfilesChangedNotification = Notification.Name(
  "WWNMachineProfilesChangedNotification")

/// Relay start/stop opens the guest disk and joins the CPU thread. Never run
/// that work on the SwiftUI main actor.
private let wwnMachineSessionQueue = DispatchQueue(
  label: "com.aspauldingcode.wawona.machine-session",
  qos: .userInitiated)

@MainActor
final class WWNMachinesViewModel: ObservableObject {
  @Published private(set) var profiles: [WWNMachineProfile] = []
  @Published var connectionError: String?
  @Published private(set) var statusByMachineId: [String: WWNMachineTransientStatus] = [:]
  /// Machine ids the user pinned via the card context menu. Pinned machines
  /// occupy a prioritized grid section. Hard cap: `maxPinnedMachines`.
  @Published private(set) var pinnedMachineIds: Set<String> = []
  private static let pinnedDefaultsKey = "wawona.machines.pinnedMachineIds"
  /// Product limit: at most six pinned machines in the Machines grid.
  static let maxPinnedMachines = 6

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
  /// Bumps on every Start/Stop so a late background finish cannot overwrite a newer tap.
  private var sessionGeneration: [String: Int] = [:]
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
    let storedPins = UserDefaults.standard.stringArray(forKey: Self.pinnedDefaultsKey) ?? []
    // Enforce the hard pin cap even if older builds stored more than six.
    let cappedPins = Array(storedPins.prefix(Self.maxPinnedMachines))
    pinnedMachineIds = Set(cappedPins)
    if storedPins.count > Self.maxPinnedMachines {
      UserDefaults.standard.set(cappedPins, forKey: Self.pinnedDefaultsKey)
    }
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
    _ = WWNPreferencesManager.sharedManager()
    #if !SWIFT_PACKAGE
    // One-shot bridge: SwiftUI rewrite wrote `wawona.machineProfiles.v1` while
    // this catalog still uses `WWNMachineProfiles`. Import when empty.
    if WWNMachineProfileStore.loadProfiles().isEmpty {
      let domain = MachineProfileStore()
      for profile in domain.profiles {
        let objc = WWNMachineProfileBridge.makeObjC(from: profile)
        _ = WWNMachineProfileStore.upsertProfile(objc)
      }
    }
    #endif
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

  /// Returns `false` when pin was refused (already at `maxPinnedMachines`).
  @discardableResult
  func togglePinned(_ machineId: String) -> Bool {
    if pinnedMachineIds.contains(machineId) {
      pinnedMachineIds.remove(machineId)
      persistPinnedIds()
      return true
    }
    guard pinnedMachineIds.count < Self.maxPinnedMachines else {
      return false
    }
    pinnedMachineIds.insert(machineId)
    persistPinnedIds()
    return true
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

  /// Relay, SSH terminal, and the native shell show the guest console before
  /// the session queue runs start. Wayland clients stay on their own surface.
  private func presentGuestConsoleIfNeeded(_ profile: WWNMachineProfile) {
    let machineId = profile.machineId ?? ""
    guard !machineId.isEmpty else { return }
    let source: String
    if profile.type == kWWNMachineTypeVirtualMachine ||
      profile.type == kWWNMachineTypeContainer {
      #if os(tvOS) || os(watchOS) || os(visionOS)
      return
      #endif
      source = "relay"
    } else if WWNNativeShellConfiguration.isNativeShellFamily(profile.type)
      || profile.type == kWWNMachineTypeNative {
      let kind = WWNNativeShellConfiguration.kind(for: profile)
      let useSSH = WWNNativeShellConfiguration.usesSSH(for: profile)
      if kind == kWWNNativeShellKindTerminal && useSSH {
        source = "ssh"
      } else if kind == kWWNNativeShellKindTerminal {
        source = "shell"
      } else {
        return
      }
    } else {
      return
    }
    #if os(iOS) || os(tvOS) || os(visionOS)
    NotificationCenter.default.post(
      name: Notification.Name("WWNRelayGuestConsoleNeededNotification"),
      object: nil,
      userInfo: ["machineId": machineId, "source": source])
    #elseif os(macOS)
    WWNMacGuestConsole.shared.present(machineId: machineId, source: source)
    #else
    _ = source
    #endif
  }

  func connect(_ profile: WWNMachineProfile, onConnected: (() -> Void)? = nil) {
    connectionError = nil
    let machineId = profile.machineId ?? ""
    let isContainer = profile.type == kWWNMachineTypeContainer
    statusByMachineId[machineId] = isContainer ? .preparing : .connecting
    presentGuestConsoleIfNeeded(profile)
    let generation = bumpSessionGeneration(machineId)

    #if os(iOS) || os(tvOS) || os(visionOS)
    // Native Wayland clients may run concurrently. VM / waypipe / container
    // backends still share a single in-process engine on mobile. Stop those
    // off the main actor before switching. Never tear down an unrelated native client.
    var toStop: [WWNMachineProfile] = []
    if !WWNMachineSessionBridge.profileUsesNativeCompositorClient(profile) {
      toStop = profiles.filter {
        $0.machineId != machineId && status(for: $0.machineId) != .disconnected
      }
      for other in toStop {
        statusByMachineId[other.machineId] = .disconnected
        _ = bumpSessionGeneration(other.machineId)
      }
    }
    #else
    let toStop: [WWNMachineProfile] = []
    #endif

    if WWNMachineSessionBridge.profileUsesNativeCompositorClient(profile),
       WWNWaypipeRunner.shared == nil {
      let client = WWNMachineSessionBridge.nativeClientId(forProfile: profile) ?? ""
      if client != "wawona-shell" {
        statusByMachineId[machineId] = .error
        connectionError = "Wayland client runner is unavailable."
        return
      }
    }

    if isContainer {
      pendingContainerConnectCallbacks[machineId] = onConnected
    }

    // Mount Metal host on the main actor before the session queue launches the
    // Wayland client so the first SHM commits have an active presenter.
    revealSessionSurfaceIfNeeded(profile)

    wwnMachineSessionQueue.async {
      for other in toStop {
        WWNMachineSessionBridge.disconnectProfile(other)
      }
      var failure: String?
      do {
        try WWNMachineSessionBridge.connect(profile)
      } catch {
        failure = error.localizedDescription
        NSLog("Machine %@ failed to start: %@", machineId, error.localizedDescription)
      }
      let message = failure
      Task { @MainActor in
        guard self.sessionGeneration[machineId] == generation else { return }
        if let message {
          self.statusByMachineId[machineId] = .error
          self.connectionError = message
          self.pendingContainerConnectCallbacks.removeValue(forKey: machineId)
          return
        }
        if isContainer {
          // Stay "Starting container" until WWNContainerRunner reports the VM is
          // booted (WWNContainerBackendDidBecomeReadyNotification). Not a compile.
          return
        }
        self.statusByMachineId[machineId] = .connected
        self.touchLastUsed(machineId)
        onConnected?()
      }
    }
  }

  /// Native Wayland / wasm clients and macOS MicroVM waypipe clients draw into
  /// the host compositor surface.
  private func revealSessionSurfaceIfNeeded(_ profile: WWNMachineProfile) {
    #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
    if WWNMachineSessionBridge.profileUsesVirtualMachineBackend(profile) {
      WWNMainWindowRouter.shared.showSessionSurface()
      return
    }
    guard WWNMachineSessionBridge.profileUsesNativeCompositorClient(profile) else { return }
    let client = WWNMachineSessionBridge.nativeClientId(forProfile: profile) ?? ""
    if client == "wawona-shell" { return }
    WWNMainWindowRouter.shared.showSessionSurface()
    #endif
  }

  private func bumpSessionGeneration(_ machineId: String) -> Int {
    let next = (sessionGeneration[machineId] ?? 0) + 1
    sessionGeneration[machineId] = next
    return next
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
    let machineId = profile.machineId ?? ""
    statusByMachineId[machineId] = .disconnected
    _ = bumpSessionGeneration(machineId)
    #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
    // Leave the compositor surface when the focused native client stops.
    let stillNative = profiles.contains {
      $0.machineId != machineId
        && status(for: $0.machineId) == .connected
        && WWNMachineSessionBridge.profileUsesNativeCompositorClient($0)
    }
    if !stillNative {
      WWNMainWindowRouter.shared.hideSessionSurface()
    }
    #endif
    #if os(iOS) || os(tvOS) || os(visionOS)
    if !machineId.isEmpty {
      NotificationCenter.default.post(
        name: Notification.Name("WWNRelayGuestConsoleNeededNotification"),
        object: nil,
        userInfo: ["machineId": machineId, "source": "close"])
    }
    #elseif os(macOS)
    WWNMacGuestConsole.shared.dismiss(machineId: machineId)
    #endif
    wwnMachineSessionQueue.async {
      WWNMachineSessionBridge.disconnectProfile(profile)
    }
  }

  func focusRunningMachine(_ profile: WWNMachineProfile) {
    guard status(for: profile.machineId) == .connected ||
            status(for: profile.machineId) == .connecting else {
      return
    }
    touchLastUsed(profile.machineId)
    WWNMachineProfileStore.setActiveMachineId(profile.machineId)
    revealSessionSurfaceIfNeeded(profile)
    #if os(macOS)
    _ = WWNCompositorBridge.sharedBridge.focusClientWindows(forMachineId: profile.machineId)
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
    return WWNPreferencesManager.sharedManager().machineSessionThumbnailsEnabled()
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
    #if !SWIFT_PACKAGE
    return WWNMachineThumbnailStore.thumbnail(forMachineId: machineId)
    #else
    _ = machineId
    return nil
    #endif
  }

  private func captureThumbnail(for machineId: String) -> Bool {
    #if !SWIFT_PACKAGE
    return WWNMachineThumbnailStore.captureAndSaveThumbnail(forMachineId: machineId)
    #else
    _ = machineId
    return false
    #endif
  }

  private func deleteThumbnail(for machineId: String) {
    #if !SWIFT_PACKAGE
    WWNMachineThumbnailStore.deleteThumbnail(forMachineId: machineId)
    #else
    _ = machineId
    #endif
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
    let runner = WWNWaypipeRunner.shared
    for profile in profiles {
      let st = status(for: profile.machineId)
      guard st == .connected || st == .connecting else { continue }

      let running: Bool = {
        if WWNMachineSessionBridge.profileRequiresWaypipeTransport(profile) {
          return runner.isRunning
        }
        if WWNMachineSessionBridge.profileUsesNativeCompositorClient(profile) {
          // Per-machine binding: two weston-terminal profiles must not share
          // a single global "running" bit or one will look taken over.
          return runner.isBundledClientRunning(forMachineId: profile.machineId)
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
    WWNNativeShellConfiguration.userFacingTypeName(profile.type)
  }

  func machineScopeLabel(for profile: WWNMachineProfile) -> String {
    if profile.type == kWWNMachineTypeVirtualMachine
      || profile.type == kWWNMachineTypeContainer {
      return "Local"
    }
    if WWNNativeShellConfiguration.usesSSH(for: profile)
      && (WWNNativeShellConfiguration.kind(for: profile) == kWWNNativeShellKindTerminal
        || WWNNativeShellConfiguration.kind(for: profile) == kWWNNativeShellKindWaypipe) {
      return "Remote"
    }
    return "Local"
  }

  func machineSubtitle(for profile: WWNMachineProfile) -> String {
    if profile.type == kWWNMachineTypeVirtualMachine {
      #if os(macOS)
      return "VM profile (MicroVM + waypipe)"
      #else
      return "VM profile (Wawona Relay)"
      #endif
    }
    if profile.type == kWWNMachineTypeContainer {
      return "Container profile (Wawona Relay)"
    }
    let kind = WWNNativeShellConfiguration.kind(for: profile)
    let useSSH = WWNNativeShellConfiguration.usesSSH(for: profile)
    switch kind {
    case kWWNNativeShellKindTerminal:
      if useSSH {
        if profile.sshHost.isEmpty { return "SSH endpoint not configured" }
        let user = profile.sshUser.isEmpty ? "user" : profile.sshUser
        return "\(user)@\(profile.sshHost)"
      }
      return "Wawona Terminal"
    case kWWNNativeShellKindWasm:
      return wasmSummary(for: profile)
    case kWWNNativeShellKindWaypipe:
      if useSSH {
        if profile.sshHost.isEmpty { return "SSH endpoint not configured" }
        let user = profile.sshUser.isEmpty ? "user" : profile.sshUser
        return "Waypipe \(user)@\(profile.sshHost)"
      }
      return "Waypipe (local)"
    default:
      if let name = selectedClientName(for: profile) {
        return name
      }
      return "No client configured"
    }
  }

  func wasmSummary(for profile: WWNMachineProfile) -> String {
    let runtime: [String: Any] = profile.runtimeOverrides
    let cmd = (runtime[kRuntimeWasmCommandKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cmd.isEmpty { return cmd }
    let pkg = (runtime[kRuntimeWasmPackageKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !pkg.isEmpty { return "wasm \(pkg)" }
    let path = (runtime[kRuntimeWasmModulePathKey] as? String) ?? ""
    if !path.isEmpty { return (path as NSString).lastPathComponent }
    return "wasm hello-wasi-gui"
  }

  func selectedClientId(for profile: WWNMachineProfile) -> String? {
    WWNMachineSessionBridge.nativeClientId(forProfile: profile)
  }

  func selectedClientName(for profile: WWNMachineProfile) -> String? {
    if WWNNativeShellConfiguration.kind(for: profile) == kWWNNativeShellKindTerminal {
      let custom = (profile.settingsOverrides as [String: Any])["NativeCustomCommand"] as? String ?? ""
      let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
      let remote = profile.remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
      return remote.isEmpty ? "Wawona Terminal" : remote
    }
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
    if profile.type == kWWNMachineTypeVirtualMachine
      || profile.type == kWWNMachineTypeContainer {
      return "Backend: Wawona Relay"
    }
    let kind = WWNNativeShellConfiguration.kind(for: profile)
    switch kind {
    case kWWNNativeShellKindTerminal:
      let custom = (profile.settingsOverrides as [String: Any])["NativeCustomCommand"] as? String ?? ""
      let cmd = custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? profile.remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        : custom.trimmingCharacters(in: .whitespacesAndNewlines)
      if WWNNativeShellConfiguration.usesSSH(for: profile) {
        return cmd.isEmpty ? "Wawona Terminal over SSH" : "SSH: \(cmd)"
      }
      return cmd.isEmpty ? "Wawona Terminal (local shell)" : "Runs: \(cmd)"
    case kWWNNativeShellKindWasm:
      return "Runs: \(wasmSummary(for: profile))"
    case kWWNNativeShellKindWaypipe:
      let command = profile.remoteCommand.isEmpty ? "weston-simple-shm" : profile.remoteCommand
      return "Waypipe command: \(command)"
    default:
      if let clientName = selectedClientName(for: profile) {
        return "Runs: \(clientName)"
      }
      return "No client configured. Edit to select one"
    }
  }

  func launchCommandString(for profile: WWNMachineProfile) -> String {
    if WWNMachineSessionBridge.profileRequiresWaypipeTransport(profile) {
      if !profile.remoteCommand.isEmpty {
        return profile.remoteCommand
      }
      let overrides: [String: Any] = profile.settingsOverrides
      return overrides["WaypipeRemoteCommand"] as? String ?? ""
    }
    if WWNNativeShellConfiguration.kind(for: profile) == kWWNNativeShellKindWasm {
      return wasmSummary(for: profile)
    }
    if WWNNativeShellConfiguration.kind(for: profile) == kWWNNativeShellKindTerminal {
      let custom = (profile.settingsOverrides as [String: Any])["NativeCustomCommand"] as? String ?? ""
      let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
      return profile.remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let clientId = selectedClientId(for: profile) {
      if clientId == kNativeClientCustomId {
        let cmd = (profile.settingsOverrides as [String: Any])["NativeCustomCommand"] as? String ?? ""
        return cmd
      }
      return clientId
    }
    return ""
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
    if profile.type == kWWNMachineTypeVirtualMachine
      || profile.type == kWWNMachineTypeContainer {
      #if os(tvOS) || os(watchOS)
      return false
      #else
      return true
      #endif
    }
    if WWNMachineSessionBridge.profileRequiresWaypipeTransport(profile) {
      return true
    }
    if WWNMachineSessionBridge.profileUsesNativeCompositorClient(profile) {
      return selectedClientId(for: profile) != nil
    }
    return false
  }
}
