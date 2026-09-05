import SwiftUI
import WawonaModel

/// All persisted machine-editor fields as a single observable draft.
///
/// Seeding (`init(profile:defaultType:)`) and persistence (`makeProfile(initial:)`)
/// are verbatim transplants of the editor's former `@State` initialization and
/// `save()` mapping, so the redesigned UI changes nothing about what gets
/// stored. Pure helpers (`previewCommand`, host/port sanitizers) moved here so
/// section views stay declarative.
final class WWNMachineEditorDraft: ObservableObject {
  // MARK: Profile identity
  @Published var name: String
  @Published var type: String
  @Published var machineThumbnailEnabled: Bool

  // MARK: SSH / remote
  @Published var sshHost: String
  @Published var sshUser: String
  @Published var sshPort: String
  @Published var sshPassword: String
  @Published var sshKeyPath: String
  @Published var sshKeyPassphrase: String
  @Published var sshAuthMethod: Int
  @Published var remoteCommand: String

  // MARK: Native client
  @Published var selectedClientId: String
  @Published var customCommand: String
  @Published var wasmModulePath: String

  // MARK: Container
  @Published var containerRef: String
  @Published var entryCommand: String
  @Published var desktopSession: Bool
  @Published var imageArchivePath: String

  // MARK: Waypipe transport
  @Published var waypipeDisplayNumber: String
  @Published var waypipeCompress: String
  @Published var waypipeCompressLevel: String
  @Published var waypipeThreads: String
  @Published var waypipeVideo: String
  @Published var waypipeVideoEncoding: String
  @Published var waypipeVideoDecoding: String
  @Published var waypipeVideoBpf: String
  @Published var waypipeUseSSHConfig: Bool
  @Published var waypipeDebug: Bool
  @Published var waypipeNoGpu: Bool
  @Published var waypipeOneshot: Bool
  @Published var waypipeUnlinkSocket: Bool
  @Published var waypipeLoginShell: Bool
  @Published var waypipeVsock: Bool
  @Published var waypipeXwls: Bool
  @Published var waypipeTitlePrefix: String
  @Published var waypipeSecCtx: String

  // MARK: Display / Input / Graphics overrides
  @Published var forceServerSideDecorations: Bool
  @Published var autoScale: Bool
  @Published var respectSafeArea: Bool
  @Published var renderMacOSPointer: Bool
  @Published var nestedCompositorCursor: String
  @Published var touchInputType: String
  @Published var swapCmdWithAlt: Bool
  @Published var universalClipboard: Bool
  @Published var vulkanDriver: String
  @Published var openGLDriver: String
  @Published var compositorBackend: String
  @Published var dmabufEnabled: Bool
  @Published var colorOperations: Bool
  #if os(macOS)
  @Published var alwaysOnTop: Bool
  #endif

  // MARK: Session exit + environment
  @Published var shakeToCloseEnabled: Bool
  @Published var swipeBackToCloseEnabled: Bool
  @Published var environmentOverrides: EnvironmentOverrideMap

  init(profile: WWNMachineProfile?, defaultType: String = kWWNMachineTypeNative) {
    name = profile?.name ?? ""
    type = profile?.type ?? defaultType
    sshHost = profile?.sshHost ?? ""
    sshUser = profile?.sshUser ?? ""
    sshPort = "\(max(1, profile?.sshPort ?? 22))"
    sshPassword = profile?.sshPassword ?? ""
    sshKeyPath = profile?.sshKeyPath ?? ""
    sshKeyPassphrase = profile?.sshKeyPassphrase ?? ""
    sshAuthMethod = profile?.sshAuthMethod ?? 0
    remoteCommand = profile?.remoteCommand ?? ""
    let containerSettings = profile?.containerSettings ?? [:]
    containerRef = (containerSettings["containerRef"] as? String) ?? ""
    entryCommand = (containerSettings["entryCommand"] as? String) ?? ""
    desktopSession = (containerSettings["desktopSession"] as? Bool)
      ?? ((profile?.type ?? defaultType) == kWWNMachineTypeContainer)
    imageArchivePath = (containerSettings["imageArchivePath"] as? String) ?? ""

    let runtimeOverrides: [String: Any] = profile?.runtimeOverrides ?? [:]
    let overrides: [String: Any] = profile?.settingsOverrides ?? [:]
    let prefs = WWNPreferencesManager.shared()
    let initialCustomCommand = (overrides["NativeCustomCommand"] as? String) ?? ""
    customCommand = initialCustomCommand
    wasmModulePath = (runtimeOverrides[kRuntimeWasmModulePathKey] as? String) ?? ""
    machineThumbnailEnabled = (runtimeOverrides["machineThumbnailEnabledOverride"] as? Bool)
      ?? WWNPreferencesManager.shared().machineSessionThumbnailsEnabled()
    waypipeDisplayNumber = (overrides["WaylandDisplayNumber"] as? NSNumber)?.stringValue ?? "\(prefs.waylandDisplayNumber())"
    waypipeCompress = overrides["WaypipeCompress"] as? String ?? prefs.waypipeCompress()
    waypipeCompressLevel = (overrides["WaypipeCompressLevel"] as? NSNumber)?.stringValue ?? (overrides["WaypipeCompressLevel"] as? String ?? prefs.waypipeCompressLevel())
    waypipeThreads = (overrides["WaypipeThreads"] as? NSNumber)?.stringValue ?? (overrides["WaypipeThreads"] as? String ?? prefs.waypipeThreads())
    waypipeVideo = overrides["WaypipeVideo"] as? String ?? prefs.waypipeVideo()
    waypipeVideoEncoding = overrides["WaypipeVideoEncoding"] as? String ?? prefs.waypipeVideoEncoding()
    waypipeVideoDecoding = overrides["WaypipeVideoDecoding"] as? String ?? prefs.waypipeVideoDecoding()
    waypipeVideoBpf = (overrides["WaypipeVideoBpf"] as? NSNumber)?.stringValue ?? (overrides["WaypipeVideoBpf"] as? String ?? prefs.waypipeVideoBpf())
    waypipeUseSSHConfig = (overrides["WaypipeUseSSHConfig"] as? Bool) ?? prefs.waypipeUseSSHConfig()
    waypipeDebug = (overrides["WaypipeDebug"] as? Bool) ?? prefs.waypipeDebug()
    waypipeNoGpu = profile?.waypipeDisableGpu ?? false
    waypipeOneshot = (overrides["WaypipeOneshot"] as? Bool) ?? prefs.waypipeOneshot()
    waypipeUnlinkSocket = (overrides["WaypipeUnlinkSocket"] as? Bool) ?? prefs.waypipeUnlinkSocket()
    waypipeLoginShell = (overrides["WaypipeLoginShell"] as? Bool) ?? prefs.waypipeLoginShell()
    waypipeVsock = (overrides["WaypipeVsock"] as? Bool) ?? prefs.waypipeVsock()
    waypipeXwls = (overrides["WaypipeXwls"] as? Bool) ?? prefs.waypipeXwls()
    waypipeTitlePrefix = overrides["WaypipeTitlePrefix"] as? String ?? prefs.waypipeTitlePrefix()
    waypipeSecCtx = overrides["WaypipeSecCtx"] as? String ?? prefs.waypipeSecCtx()
    forceServerSideDecorations = (overrides["ForceServerSideDecorations"] as? Bool) ?? prefs.forceServerSideDecorations()
    autoScale = (overrides["AutoScale"] as? Bool) ?? prefs.autoScale()
    respectSafeArea = (overrides["RespectSafeArea"] as? Bool) ?? prefs.respectSafeArea()
    touchInputType = overrides["TouchInputType"] as? String ?? prefs.touchInputType()
    swapCmdWithAlt = (overrides["SwapCmdWithAlt"] as? Bool) ?? prefs.swapCmdWithAlt()
    universalClipboard = (overrides["UniversalClipboard"] as? Bool) ?? prefs.universalClipboardEnabled()
    vulkanDriver = overrides["VulkanDriver"] as? String ?? prefs.vulkanDriver()
    openGLDriver = overrides["OpenGLDriver"] as? String ?? prefs.openglDriver()
    compositorBackend = overrides["CompositorBackend"] as? String ?? prefs.compositorBackend()
    dmabufEnabled = (overrides["DmabufEnabled"] as? Bool) ?? prefs.dmabufEnabled()
    colorOperations = (overrides["ColorOperations"] as? Bool) ?? prefs.colorOperations()
    shakeToCloseEnabled = (runtimeOverrides["shakeToCloseEnabled"] as? Bool)
      ?? (UserDefaults.standard.object(forKey: "wawona.pref.shakeToCloseEnabled") as? Bool ?? true)
    swipeBackToCloseEnabled = (runtimeOverrides["swipeBackToCloseEnabled"] as? Bool)
      ?? (UserDefaults.standard.object(forKey: "wawona.pref.swipeBackToCloseEnabled") as? Bool ?? true)
    #if os(macOS)
    alwaysOnTop = (runtimeOverrides["alwaysOnTop"] as? Bool) ?? false
    #endif
    environmentOverrides = Self.decodeEnvironmentOverrides(runtimeOverrides["environment"])

    let initialNativeClientId: String
    if let stored = runtimeOverrides["bundledAppID"] as? String, !stored.isEmpty {
      initialNativeClientId = stored
    } else if let stored = overrides["NativeClientId"] as? String, !stored.isEmpty {
      initialNativeClientId = stored
    } else if (overrides["WestonEnabled"] as? Bool) == true {
      initialNativeClientId = "weston"
    } else if (overrides["WestonTerminalEnabled"] as? Bool) == true {
      initialNativeClientId = "weston-terminal"
    } else if (overrides["WestonSimpleSHMEnabled"] as? Bool) == true {
      initialNativeClientId = "weston-simple-shm"
    } else if (overrides["FootEnabled"] as? Bool) == true {
      initialNativeClientId = "foot"
    } else {
      initialNativeClientId = "weston-terminal"
    }

    #if os(iOS)
    // iOS must not present or persist external custom command execution.
    var pointerClientId = initialNativeClientId
    var pointerCustom = initialCustomCommand
    if pointerClientId == kNativeClientCustomId {
      selectedClientId = "weston-terminal"
      customCommand = ""
      pointerClientId = "weston-terminal"
      pointerCustom = ""
    } else {
      selectedClientId = pointerClientId
    }
    let autoShowMacPointerDefault = !WWNMachineProfileStore.profileIndicatesNested(
      nativeClientId: pointerClientId,
      customCommand: pointerCustom
    )
    #else
    selectedClientId = initialNativeClientId
    let autoShowMacPointerDefault = !WWNMachineProfileStore.profileIndicatesNested(
      nativeClientId: initialNativeClientId,
      customCommand: initialCustomCommand
    )
    #endif
    renderMacOSPointer = (overrides["RenderMacOSPointer"] as? Bool) ?? autoShowMacPointerDefault
    let nestedCursorRaw =
      (overrides["NestedCompositorCursor"] as? String)
      ?? (overrides["nestedCompositorCursor"] as? String)
      ?? prefs.nestedCompositorCursor()
    nestedCompositorCursor = (nestedCursorRaw == "host") ? "host" : "virtual"
  }

  // MARK: - Persistence (verbatim `save()` mapping)

  func makeProfile(initial: WWNMachineProfile?) -> WWNMachineProfile {
    let profile = initial ?? WWNMachineProfile.default()
    profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Machine" : name
    profile.type = type
    profile.sshHost = sanitizeSSHHost(sshHost)
    profile.sshUser = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.sshPort = normalizeSSHPort(sshPort)
    profile.sshPassword = sshPassword
    profile.sshKeyPath = sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.sshKeyPassphrase = sshKeyPassphrase
    profile.sshAuthMethod = sshAuthMethod
    profile.remoteCommand = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.waypipeCompress = waypipeCompress
    profile.waypipeThreads = waypipeThreads
    profile.waypipeVideo = waypipeVideo
    profile.waypipeDebug = waypipeDebug
    profile.waypipeOneshot = waypipeOneshot
    profile.waypipeDisableGpu = waypipeNoGpu
    profile.waypipeLoginShell = waypipeLoginShell
    profile.waypipeTitlePrefix = waypipeTitlePrefix
    profile.waypipeSecCtx = waypipeSecCtx
    // vmSubtype / containerSubtype are no longer user-editable (Residual E):
    // the backend engine is fixed per build target. Leave profile defaults as-is.

    // Container machines persist image ref + command in containerSettings
    // (read by WWNContainerRunner). Advanced fields (memory, mounts, ports,
    // kernel paths) are edited in Machine Settings and preserved untouched.
    if type == kWWNMachineTypeContainer {
      var containerSettings = profile.containerSettings
      let ref = containerRef.trimmingCharacters(in: .whitespacesAndNewlines)
      let cmd = entryCommand.trimmingCharacters(in: .whitespacesAndNewlines)
      if ref.isEmpty {
        containerSettings.removeValue(forKey: "containerRef")
      } else {
        containerSettings["containerRef"] = ref
      }
      if cmd.isEmpty {
        containerSettings.removeValue(forKey: "entryCommand")
      } else {
        containerSettings["entryCommand"] = cmd
      }
      // Always persist so Off stays Off (absent key defaults to desktop ON).
      containerSettings["desktopSession"] = desktopSession
      let archive = imageArchivePath.trimmingCharacters(in: .whitespacesAndNewlines)
      if archive.isEmpty {
        containerSettings.removeValue(forKey: "imageArchivePath")
      } else {
        containerSettings["imageArchivePath"] = archive
      }
      if (containerSettings["runtime"] as? String)?.isEmpty ?? true {
        containerSettings["runtime"] = "containerization"
      }
      profile.containerSettings = containerSettings
    }

    var overrides: [String: Any] = profile.settingsOverrides
    var runtimeOverrides: [String: Any] = profile.runtimeOverrides
    overrides["NativeClientId"] = selectedClientId
    overrides["NativeCustomCommand"] = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    overrides["WestonEnabled"] = selectedClientId == "weston"
    overrides["WestonTerminalEnabled"] = selectedClientId == "weston-terminal"
    overrides["WestonSimpleSHMEnabled"] = selectedClientId == "weston-simple-shm"
    overrides["FootEnabled"] = selectedClientId == "foot"
    overrides["NiriEnabled"] = selectedClientId == "niri"

    if type == kWWNMachineTypeNative {
      let trimmedCustom = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
      let autoPointer = !WWNMachineProfileStore.profileIndicatesNested(
        nativeClientId: selectedClientId,
        customCommand: trimmedCustom
      )
      if renderMacOSPointer == autoPointer {
        overrides.removeValue(forKey: "RenderMacOSPointer")
      } else {
        overrides["RenderMacOSPointer"] = renderMacOSPointer
      }
    } else {
      overrides["RenderMacOSPointer"] = renderMacOSPointer
    }
    overrides["NestedCompositorCursor"] =
      (nestedCompositorCursor == "host") ? "host" : "virtual"
    #if os(tvOS)
    // Fill-primary: Wayland CSD cannot stand alone on tvOS, so SSD stays on.
    // Persist the graphics/input the editor actually shows. Do not force
    // Vulkan off; that made every GPU client refuse after Save.
    overrides["ForceServerSideDecorations"] = true
    overrides["TouchInputType"] = touchInputType
    overrides["VulkanDriver"] = vulkanDriver
    overrides["OpenGLDriver"] = openGLDriver
    overrides["DmabufEnabled"] = dmabufEnabled
    overrides["ColorOperations"] = colorOperations
    #else
    overrides["ForceServerSideDecorations"] = forceServerSideDecorations
    overrides["TouchInputType"] = touchInputType
    overrides["VulkanDriver"] = vulkanDriver
    overrides["OpenGLDriver"] = openGLDriver
    overrides["DmabufEnabled"] = dmabufEnabled
    overrides["ColorOperations"] = colorOperations
    #endif
    overrides["CompositorBackend"] = compositorBackend
    overrides["AutoScale"] = autoScale
    #if os(iOS) || os(tvOS)
    overrides["RespectSafeArea"] = respectSafeArea
    #endif
    overrides["SwapCmdWithAlt"] = swapCmdWithAlt
    overrides["UniversalClipboard"] = universalClipboard
    overrides["WaylandDisplayNumber"] = Int(waypipeDisplayNumber) ?? 0
    overrides["WaypipeCompress"] = waypipeCompress
    overrides["WaypipeCompressLevel"] = Int(waypipeCompressLevel) ?? 7
    overrides["WaypipeThreads"] = Int(waypipeThreads) ?? 0
    overrides["WaypipeVideo"] = waypipeVideo
    overrides["WaypipeVideoEncoding"] = waypipeVideoEncoding
    overrides["WaypipeVideoDecoding"] = waypipeVideoDecoding
    overrides["WaypipeVideoBpf"] = waypipeVideoBpf
    overrides["WaypipeUseSSHConfig"] = waypipeUseSSHConfig
    overrides["WaypipeRemoteCommand"] = profile.remoteCommand
    overrides["WaypipeDebug"] = waypipeDebug
    overrides["WaypipeNoGpu"] = waypipeNoGpu
    overrides["WaypipeOneshot"] = waypipeOneshot
    overrides["WaypipeUnlinkSocket"] = waypipeUnlinkSocket
    overrides["WaypipeLoginShell"] = waypipeLoginShell
    overrides["WaypipeVsock"] = waypipeVsock
    overrides["WaypipeXwls"] = waypipeXwls
    overrides["WaypipeTitlePrefix"] = waypipeTitlePrefix
    overrides["WaypipeSecCtx"] = waypipeSecCtx
    overrides["SSHHost"] = profile.sshHost
    overrides["SSHUser"] = profile.sshUser
    overrides["SSHPort"] = profile.sshPort
    overrides["SSHAuthMethod"] = profile.sshAuthMethod
    overrides["SSHPassword"] = profile.sshPassword
    overrides["SSHKeyPath"] = profile.sshKeyPath
    overrides["SSHKeyPassphrase"] = profile.sshKeyPassphrase

    runtimeOverrides["useBundledApp"] = (type == kWWNMachineTypeNative && !selectedClientId.isEmpty)
    if type == kWWNMachineTypeNative {
      runtimeOverrides["bundledAppID"] = selectedClientId
    } else {
      runtimeOverrides.removeValue(forKey: "bundledAppID")
      runtimeOverrides.removeValue(forKey: "useBundledApp")
    }
    let trimmedWasm = wasmModulePath.trimmingCharacters(in: .whitespacesAndNewlines)
    if selectedClientId == kNativeClientWasmId && !trimmedWasm.isEmpty {
      runtimeOverrides[kRuntimeWasmModulePathKey] = trimmedWasm
    } else {
      runtimeOverrides.removeValue(forKey: kRuntimeWasmModulePathKey)
    }
    runtimeOverrides["inputProfile"] = touchInputType
    runtimeOverrides["waypipeEnabled"] = (type == kWWNMachineTypeSSHWaypipe || type == kWWNMachineTypeSSHTerminal)
    if machineThumbnailEnabled != WWNPreferencesManager.shared().machineSessionThumbnailsEnabled() {
      runtimeOverrides["machineThumbnailEnabledOverride"] = machineThumbnailEnabled
    } else {
      runtimeOverrides.removeValue(forKey: "machineThumbnailEnabledOverride")
    }
    let globalShake =
      UserDefaults.standard.object(forKey: "wawona.pref.shakeToCloseEnabled") as? Bool ?? true
    let globalSwipeBack =
      UserDefaults.standard.object(forKey: "wawona.pref.swipeBackToCloseEnabled") as? Bool ?? true
    if shakeToCloseEnabled != globalShake {
      runtimeOverrides["shakeToCloseEnabled"] = shakeToCloseEnabled
    } else {
      runtimeOverrides.removeValue(forKey: "shakeToCloseEnabled")
    }
    if swipeBackToCloseEnabled != globalSwipeBack {
      runtimeOverrides["swipeBackToCloseEnabled"] = swipeBackToCloseEnabled
    } else {
      runtimeOverrides.removeValue(forKey: "swipeBackToCloseEnabled")
    }
    #if os(macOS)
    if alwaysOnTop {
      runtimeOverrides["alwaysOnTop"] = true
    } else {
      runtimeOverrides.removeValue(forKey: "alwaysOnTop")
    }
    #endif
    runtimeOverrides["legacySettingsOverrides"] = overrides
    if environmentOverrides.isEmpty {
      runtimeOverrides.removeValue(forKey: "environment")
    } else if let encoded = Self.encodeEnvironmentOverrides(environmentOverrides) {
      runtimeOverrides["environment"] = encoded
    }

    profile.settingsOverrides = overrides
    profile.runtimeOverrides = runtimeOverrides
    return profile
  }

  private static func decodeEnvironmentOverrides(_ raw: Any?) -> EnvironmentOverrideMap {
    guard let raw else { return [:] }
    if let map = raw as? EnvironmentOverrideMap {
      return map
    }
    guard JSONSerialization.isValidJSONObject(raw),
          let data = try? JSONSerialization.data(withJSONObject: raw),
          let decoded = try? JSONDecoder().decode(EnvironmentOverrideMap.self, from: data)
    else {
      return [:]
    }
    return decoded
  }

  private static func encodeEnvironmentOverrides(_ map: EnvironmentOverrideMap) -> [String: Any]? {
    guard let data = try? JSONEncoder().encode(map),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return obj
  }

  // MARK: - Pure helpers

  var isRemote: Bool {
    type == kWWNMachineTypeSSHWaypipe || type == kWWNMachineTypeSSHTerminal
  }

  var isWaypipeMachine: Bool {
    type == kWWNMachineTypeSSHWaypipe
  }

  var selectedClientDrawsOwnCursor: Bool {
    type == kWWNMachineTypeNative &&
      WWNMachineProfileStore.profileIndicatesNested(
        nativeClientId: selectedClientId,
        customCommand: customCommand
      )
  }

  /// SF Symbol for the currently selected machine type (card header).
  var machineTypeSymbol: String {
    switch type {
    case kWWNMachineTypeNative: return "display"
    case kWWNMachineTypeSSHWaypipe: return "arrow.triangle.2.circlepath"
    case kWWNMachineTypeSSHTerminal: return "terminal"
    case kWWNMachineTypeVirtualMachine: return "desktopcomputer"
    case kWWNMachineTypeContainer: return "shippingbox"
    default: return "server.rack"
    }
  }

  var previewCommand: String {
    let host = sanitizeSSHHost(sshHost)
    let user = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
    let command = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    let port = normalizeSSHPort(sshPort)

    if host.isEmpty {
      return "Preview unavailable: SSH host is empty"
    }

    let target = user.isEmpty ? host : "\(user)@\(host)"
    let effectiveCommand = command.isEmpty
      ? (type == kWWNMachineTypeSSHWaypipe ? "weston-simple-shm" : "bash -l")
      : command

    if type == kWWNMachineTypeSSHWaypipe {
      var parts: [String] = ["waypipe"]

      let compress = waypipeCompress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let compressLevel = waypipeCompressLevel.trimmingCharacters(in: .whitespacesAndNewlines)
      if !compress.isEmpty {
        parts.append("--compress")
        if compress != "none" && !compressLevel.isEmpty {
          parts.append(shellQuote("\(compress)=\(compressLevel)"))
        } else {
          parts.append(shellQuote(compress))
        }
      }

      if waypipeDebug { parts.append("--debug") }
      if waypipeNoGpu { parts.append("--no-gpu") }
      if waypipeOneshot { parts.append("--oneshot") }
      if waypipeUnlinkSocket { parts.append("--unlink-socket") }
      if waypipeLoginShell { parts.append("--login-shell") }
      if waypipeVsock { parts.append("--vsock") }
      if waypipeXwls { parts.append("--xwls") }

      let threads = waypipeThreads.trimmingCharacters(in: .whitespacesAndNewlines)
      if !threads.isEmpty {
        parts.append("--threads")
        parts.append(shellQuote(threads))
      }

      let titlePrefix = waypipeTitlePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
      if !titlePrefix.isEmpty {
        parts.append("--title-prefix")
        parts.append(shellQuote(titlePrefix))
      }

      let secCtx = waypipeSecCtx.trimmingCharacters(in: .whitespacesAndNewlines)
      if !secCtx.isEmpty {
        parts.append("--secctx")
        parts.append(shellQuote(secCtx))
      }

      parts.append("ssh")
      if !waypipeUseSSHConfig {
        parts.append("-F")
        parts.append("/dev/null")
      }
      parts.append("-p")
      parts.append(String(port))
      parts.append("-o")
      parts.append("StrictHostKeyChecking=accept-new")
      parts.append("-o")
      parts.append("BatchMode=no")
      if sshAuthMethod == 1 {
        let keyPath = sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyPath.isEmpty {
          parts.append("-i")
          parts.append(shellQuote(keyPath))
        }
      }
      parts.append(shellQuote(target))
      parts.append(shellQuote(effectiveCommand))
      return parts.joined(separator: " ")
    }

    return "ssh -p \(port) \(shellQuote(target)) \(shellQuote(effectiveCommand))"
  }

  func shellQuote(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
    return "'\(escaped)'"
  }

  func sanitizeSSHHost(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return "" }
    if let schemeRange = value.range(of: "://") {
      value = String(value[schemeRange.upperBound...])
    }
    if let slash = value.firstIndex(of: "/") {
      value = String(value[..<slash])
    }
    if let query = value.firstIndex(of: "?") {
      value = String(value[..<query])
    }
    if let fragment = value.firstIndex(of: "#") {
      value = String(value[..<fragment])
    }
    let disallowed = CharacterSet.whitespacesAndNewlines
      .union(CharacterSet(charactersIn: "\"'`$;&|<>\\"))
    value = value.unicodeScalars
      .filter { !disallowed.contains($0) }
      .map(String.init)
      .joined()
    if value.hasPrefix("[") {
      if let closing = value.firstIndex(of: "]"),
         value.index(after: closing) < value.endIndex,
         value[value.index(after: closing)] == ":" {
        let suffix = value[value.index(closing, offsetBy: 2)...]
        if suffix.allSatisfy(\.isNumber) {
          value = String(value[...closing])
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

  func normalizeSSHPort(_ raw: String) -> Int {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = Int(trimmed), (1...65535).contains(parsed) else { return 22 }
    return parsed
  }
}
