import SwiftUI
import WawonaModel
import UniformTypeIdentifiers

private enum WWNMachineEditorRoute: Hashable {
  case bundledClient
}

struct WWNMachineEditorView: View {
  let title: String
  let initial: WWNMachineProfile?
  let defaultType: String
  let onSave: (WWNMachineProfile) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var name: String
  @State private var type: String
  @State private var sshHost: String
  @State private var sshUser: String
  @State private var sshPort: String
  @State private var sshPassword: String
  @State private var sshKeyPath: String
  @State private var sshKeyPassphrase: String
  @State private var sshAuthMethod: Int
  @State private var remoteCommand: String
  @State private var containerRef: String
  @State private var entryCommand: String
  @State private var desktopSession: Bool
  @State private var imageArchivePath: String
  @State private var showContainerHubSearch: Bool = false
  @State private var showContainerArchiveImporter: Bool = false
  @State private var containerImporting: Bool = false
  @State private var containerImportNote: String?

  @State private var selectedClientId: String
  @State private var customCommand: String
  @State private var wasmModulePath: String
  @State private var showWasmFileImporter: Bool = false
  @State private var machineThumbnailEnabled: Bool
  @State private var waypipeDisplayNumber: String
  @State private var waypipeCompress: String
  @State private var waypipeCompressLevel: String
  @State private var waypipeThreads: String
  @State private var waypipeVideo: String
  @State private var waypipeVideoEncoding: String
  @State private var waypipeVideoDecoding: String
  @State private var waypipeVideoBpf: String
  @State private var waypipeUseSSHConfig: Bool
  @State private var waypipeDebug: Bool
  @State private var waypipeNoGpu: Bool
  @State private var waypipeOneshot: Bool
  @State private var waypipeUnlinkSocket: Bool
  @State private var waypipeLoginShell: Bool
  @State private var waypipeVsock: Bool
  @State private var waypipeXwls: Bool
  @State private var waypipeTitlePrefix: String
  @State private var waypipeSecCtx: String
  @State private var forceServerSideDecorations: Bool
  @State private var autoScale: Bool
  @State private var respectSafeArea: Bool
  @State private var renderMacOSPointer: Bool
  @State private var nestedCompositorCursor: String
  @State private var touchInputType: String
  @State private var swapCmdWithAlt: Bool
  @State private var universalClipboard: Bool
  @State private var vulkanDriver: String
  @State private var openGLDriver: String
  @State private var compositorBackend: String
  @State private var dmabufEnabled: Bool
  @State private var colorOperations: Bool
  @State private var shakeToCloseEnabled: Bool
  @State private var swipeBackToCloseEnabled: Bool
  #if os(macOS)
  @State private var alwaysOnTop: Bool
  #endif
  @State private var environmentOverrides: EnvironmentOverrideMap
  @State private var showEnvironmentEditor = false
  @State private var editorPath = NavigationPath()

  init(
    title: String,
    initial: WWNMachineProfile?,
    defaultType: String = kWWNMachineTypeNative,
    onSave: @escaping (WWNMachineProfile) -> Void
  ) {
    self.title = title
    self.initial = initial
    self.defaultType = defaultType
    self.onSave = onSave
    _name = State(initialValue: initial?.name ?? "")
    _type = State(initialValue: initial?.type ?? defaultType)
    _sshHost = State(initialValue: initial?.sshHost ?? "")
    _sshUser = State(initialValue: initial?.sshUser ?? "")
    _sshPort = State(initialValue: "\(max(1, initial?.sshPort ?? 22))")
    _sshPassword = State(initialValue: initial?.sshPassword ?? "")
    _sshKeyPath = State(initialValue: initial?.sshKeyPath ?? "")
    _sshKeyPassphrase = State(initialValue: initial?.sshKeyPassphrase ?? "")
    _sshAuthMethod = State(initialValue: initial?.sshAuthMethod ?? 0)
    _remoteCommand = State(initialValue: initial?.remoteCommand ?? "")
    let containerSettings = initial?.containerSettings ?? [:]
    _containerRef = State(
      initialValue: (containerSettings["containerRef"] as? String) ?? "")
    _entryCommand = State(
      initialValue: (containerSettings["entryCommand"] as? String) ?? "")
    _desktopSession = State(
      initialValue: (containerSettings["desktopSession"] as? Bool)
        ?? ((initial?.type ?? defaultType) == kWWNMachineTypeContainer))
    _imageArchivePath = State(
      initialValue: (containerSettings["imageArchivePath"] as? String) ?? "")

    let runtimeOverrides: [String: Any] = initial?.runtimeOverrides ?? [:]
    let overrides: [String: Any] = initial?.settingsOverrides ?? [:]
    let prefs = WWNPreferencesManager.shared()
    let initialCustomCommand = (overrides["NativeCustomCommand"] as? String) ?? ""
    _customCommand = State(initialValue: initialCustomCommand)
    let initialWasmPath = (runtimeOverrides[kRuntimeWasmModulePathKey] as? String) ?? ""
    _wasmModulePath = State(initialValue: initialWasmPath)
    _machineThumbnailEnabled = State(
      initialValue: (runtimeOverrides["machineThumbnailEnabledOverride"] as? Bool)
        ?? WWNPreferencesManager.shared().machineSessionThumbnailsEnabled()
    )
    _waypipeDisplayNumber = State(initialValue: (overrides["WaylandDisplayNumber"] as? NSNumber)?.stringValue ?? "\(prefs.waylandDisplayNumber())")
    _waypipeCompress = State(initialValue: overrides["WaypipeCompress"] as? String ?? prefs.waypipeCompress())
    _waypipeCompressLevel = State(initialValue: (overrides["WaypipeCompressLevel"] as? NSNumber)?.stringValue ?? (overrides["WaypipeCompressLevel"] as? String ?? prefs.waypipeCompressLevel()))
    _waypipeThreads = State(initialValue: (overrides["WaypipeThreads"] as? NSNumber)?.stringValue ?? (overrides["WaypipeThreads"] as? String ?? prefs.waypipeThreads()))
    _waypipeVideo = State(initialValue: overrides["WaypipeVideo"] as? String ?? prefs.waypipeVideo())
    _waypipeVideoEncoding = State(initialValue: overrides["WaypipeVideoEncoding"] as? String ?? prefs.waypipeVideoEncoding())
    _waypipeVideoDecoding = State(initialValue: overrides["WaypipeVideoDecoding"] as? String ?? prefs.waypipeVideoDecoding())
    _waypipeVideoBpf = State(initialValue: (overrides["WaypipeVideoBpf"] as? NSNumber)?.stringValue ?? (overrides["WaypipeVideoBpf"] as? String ?? prefs.waypipeVideoBpf()))
    _waypipeUseSSHConfig = State(initialValue: (overrides["WaypipeUseSSHConfig"] as? Bool) ?? prefs.waypipeUseSSHConfig())
    _waypipeDebug = State(initialValue: (overrides["WaypipeDebug"] as? Bool) ?? prefs.waypipeDebug())
    _waypipeNoGpu = State(initialValue: (overrides["WaypipeNoGpu"] as? Bool) ?? prefs.waypipeNoGpu())
    _waypipeOneshot = State(initialValue: (overrides["WaypipeOneshot"] as? Bool) ?? prefs.waypipeOneshot())
    _waypipeUnlinkSocket = State(initialValue: (overrides["WaypipeUnlinkSocket"] as? Bool) ?? prefs.waypipeUnlinkSocket())
    _waypipeLoginShell = State(initialValue: (overrides["WaypipeLoginShell"] as? Bool) ?? prefs.waypipeLoginShell())
    _waypipeVsock = State(initialValue: (overrides["WaypipeVsock"] as? Bool) ?? prefs.waypipeVsock())
    _waypipeXwls = State(initialValue: (overrides["WaypipeXwls"] as? Bool) ?? prefs.waypipeXwls())
    _waypipeTitlePrefix = State(initialValue: overrides["WaypipeTitlePrefix"] as? String ?? prefs.waypipeTitlePrefix())
    _waypipeSecCtx = State(initialValue: overrides["WaypipeSecCtx"] as? String ?? prefs.waypipeSecCtx())
    _forceServerSideDecorations = State(initialValue: (overrides["ForceServerSideDecorations"] as? Bool) ?? prefs.forceServerSideDecorations())
    _autoScale = State(initialValue: (overrides["AutoScale"] as? Bool) ?? prefs.autoScale())
    _respectSafeArea = State(initialValue: (overrides["RespectSafeArea"] as? Bool) ?? prefs.respectSafeArea())
    _touchInputType = State(initialValue: overrides["TouchInputType"] as? String ?? prefs.touchInputType())
    _swapCmdWithAlt = State(initialValue: (overrides["SwapCmdWithAlt"] as? Bool) ?? prefs.swapCmdWithAlt())
    _universalClipboard = State(initialValue: (overrides["UniversalClipboard"] as? Bool) ?? prefs.universalClipboardEnabled())
    _vulkanDriver = State(initialValue: overrides["VulkanDriver"] as? String ?? prefs.vulkanDriver())
    _openGLDriver = State(initialValue: overrides["OpenGLDriver"] as? String ?? prefs.openglDriver())
    _compositorBackend = State(initialValue: overrides["CompositorBackend"] as? String ?? prefs.compositorBackend())
    _dmabufEnabled = State(initialValue: (overrides["DmabufEnabled"] as? Bool) ?? prefs.dmabufEnabled())
    _colorOperations = State(initialValue: (overrides["ColorOperations"] as? Bool) ?? prefs.colorOperations())
    _shakeToCloseEnabled = State(
      initialValue: (runtimeOverrides["shakeToCloseEnabled"] as? Bool)
        ?? (UserDefaults.standard.object(forKey: "wawona.pref.shakeToCloseEnabled") as? Bool ?? true)
    )
    _swipeBackToCloseEnabled = State(
      initialValue: (runtimeOverrides["swipeBackToCloseEnabled"] as? Bool)
        ?? (UserDefaults.standard.object(forKey: "wawona.pref.swipeBackToCloseEnabled") as? Bool ?? true)
    )
    #if os(macOS)
    _alwaysOnTop = State(initialValue: (runtimeOverrides["alwaysOnTop"] as? Bool) ?? false)
    #endif
    _environmentOverrides = State(
      initialValue: Self.decodeEnvironmentOverrides(runtimeOverrides["environment"])
    )

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
      _selectedClientId = State(initialValue: "weston-terminal")
      _customCommand = State(initialValue: "")
      pointerClientId = "weston-terminal"
      pointerCustom = ""
    } else {
      _selectedClientId = State(initialValue: pointerClientId)
    }
    let autoShowMacPointerDefault = !WWNMachineProfileStore.profileIndicatesNested(
      nativeClientId: pointerClientId,
      customCommand: pointerCustom
    )
    #else
    _selectedClientId = State(initialValue: initialNativeClientId)
    let autoShowMacPointerDefault = !WWNMachineProfileStore.profileIndicatesNested(
      nativeClientId: initialNativeClientId,
      customCommand: initialCustomCommand
    )
    #endif
    _renderMacOSPointer = State(
      initialValue: (overrides["RenderMacOSPointer"] as? Bool) ?? autoShowMacPointerDefault
    )
    let nestedCursorRaw =
      (overrides["NestedCompositorCursor"] as? String)
      ?? (overrides["nestedCompositorCursor"] as? String)
      ?? prefs.nestedCompositorCursor()
    _nestedCompositorCursor = State(
      initialValue: (nestedCursorRaw == "host") ? "host" : "virtual"
    )
  }

  var body: some View {
    #if os(tvOS)
    tvosEditorBody
    #else
    desktopMobileEditorBody
    #endif
  }

  #if os(tvOS)
  /// Form-based editor: navigation-link pickers and large focusable rows for Siri Remote.
  private var tvosEditorBody: some View {
    NavigationStack {
      Form {
        Section {
          WWNTvFormTextField("Display Name", text: $name, prompt: "Enter a name")
          Picker("Type", selection: $type) {
            machineTypeOptions
          }
          .pickerStyle(.navigationLink)
          Toggle("Show Session Thumbnail", isOn: $machineThumbnailEnabled)
        } header: {
          Text("Connection Profile")
        } footer: {
          Text("tvOS supports Native and Remote (SSH) machines only.")
        }

        if type == kWWNMachineTypeNative {
          Section("Wayland Client") {
            NavigationLink {
              WWNNativeClientPickerView(
                selectedClientId: $selectedClientId
              )
            } label: {
              HStack {
                Text("Bundled Client")
                Spacer()
                Text(nativeClientSummary)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
            #if !os(iOS)
            if selectedClientId == kNativeClientCustomId {
              WWNTvFormTextField("Custom command", text: $customCommand, prompt: "/usr/bin/my-wayland-app")
              Text("e.g. /usr/bin/my-wayland-app")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            #endif
            if selectedClientId == kNativeClientWasmId {
              WWNTvFormTextField("Wasm module path", text: $wasmModulePath)
            }
          }
        }

        if isRemote {
          Section("Remote SSH") {
            WWNTvFormTextField("Host", text: $sshHost)
            WWNTvFormTextField("User", text: $sshUser)
            WWNTvFormTextField("Port", text: $sshPort)
            Picker("Auth", selection: $sshAuthMethod) {
              Text("Password").tag(0)
              Text("Public Key").tag(1)
            }
            .pickerStyle(.navigationLink)
            if sshAuthMethod == 0 {
              WWNTvFormTextField("Password", text: $sshPassword, secure: true)
            } else {
              WWNTvFormTextField("Key Path", text: $sshKeyPath)
              WWNTvFormTextField("Key Passphrase", text: $sshKeyPassphrase, secure: true)
            }
            WWNTvFormTextField("Remote Command", text: $remoteCommand)
          }

          Section("Waypipe") {
            Picker("Compress", selection: $waypipeCompress) {
              Text("None").tag("none")
              Text("LZ4").tag("lz4")
              Text("Zstd").tag("zstd")
            }
            .pickerStyle(.navigationLink)
            Toggle("Debug", isOn: $waypipeDebug)
            Toggle("Login Shell", isOn: $waypipeLoginShell)
            Toggle("XWayland", isOn: $waypipeXwls)
          }

          Section("Command Preview") {
            Text(previewCommand)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }

        Section {
          Toggle("Auto Scale", isOn: $autoScale)
          Toggle("Respect Safe Area", isOn: $respectSafeArea)
          Picker("Display Backend", selection: $compositorBackend) {
            Text("Auto").tag("auto")
            Text("Wayland (nested)").tag("wayland")
            Text("DRM/KMS (wwn-iland)").tag("drm")
          }
          .pickerStyle(.navigationLink)
          Button("Open Wawona Settings…") {
            WWNPreferences.shared().show(nil)
          }
        } header: {
          Text("Display")
        } footer: {
          Text("Nested weston/niri use Wayland. DRM is userspace iland, not a real /dev/dri node.")
        }

        Section {
          Picker("Vulkan Driver", selection: $vulkanDriver) {
            Text("None").tag("none")
            if PlatformCapabilities.allowsGpuStack {
              Text("MoltenVK").tag("moltenvk")
            }
          }
          .pickerStyle(.navigationLink)
          Picker("OpenGL Driver", selection: $openGLDriver) {
            Text("None").tag("none")
            if PlatformCapabilities.allowsGlesStack {
              Text("ANGLE").tag("angle")
            }
          }
          .pickerStyle(.navigationLink)
          Toggle("Enable DMABUF", isOn: $dmabufEnabled)
          Toggle("Enable HDR", isOn: $colorOperations)
        } header: {
          Text("Graphics")
        } footer: {
          Text("MoltenVK is Vulkan to Metal. ANGLE is OpenGL ES to Metal. Same drivers as iOS.")
        }

        Section("Environment Variables") {
          Button {
            showEnvironmentEditor = true
          } label: {
            HStack {
              Text("Edit Environment Variables…")
              Spacer()
              Text(
                environmentOverrides.isEmpty
                  ? "Inherit global"
                  : "\(environmentOverrides.count) override(s)"
              )
              .foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("wwn.settings.environment.machine")
        }

        Section {
          Toggle("Menu / Shake to Exit Machine", isOn: $shakeToCloseEnabled)
        } header: {
          Text("Session Exit")
        } footer: {
          Text(
            "Menu/Back on the Siri Remote (or Simulator remote) confirms leaving "
              + "the session. Shake the original black 1st-generation Siri Remote "
              + "(GCMotion) does the same when this is on. Silver 2nd/3rd-gen remotes "
              + "and the iPhone Apple TV Remote have no motion. Play/Pause toggles "
              + "the keyboard. Swipe the clickpad to move the pointer, then click "
              + "Select. The TV/Home button leaves Wawona for the Apple TV Home "
              + "screen and is not an in-app Back."
          )
        }
      }
      // Default tvOS Form chrome is glass over the Machines grid. Unreadable at 10ft.
      // Note: `.scrollContentBackground` is unavailable on tvOS; opaque background is enough.
      .background {
        Color(white: 0.07).ignoresSafeArea()
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
        }
      }
      .fullScreenCover(isPresented: $showEnvironmentEditor) {
        NavigationStack {
          EnvironmentVariablesView(
            preferences: WawonaPreferences.shared,
            perMachine: true,
            draftMachineOverrides: $environmentOverrides
          )
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { showEnvironmentEditor = false }
            }
          }
        }
        .presentationBackground(Color(white: 0.07))
      }
    }
    .preferredColorScheme(.dark)
    .presentationBackground(Color(white: 0.07))
  }
  #endif

  private var desktopMobileEditorBody: some View {
    NavigationStack(path: $editorPath) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          sectionCard("Connection Profile", subtitle: "Name and type for this machine profile.") {
            labeledField("Display Name") {
              TextField("e.g. Studio Linux VM", text: $name)
                .textFieldStyle(.roundedBorder)
                .wwnA11y(WWNA11y.machinesEditorName, label: "Display Name")
            }
            labeledField("Type") {
              Picker("", selection: $type) {
                machineTypeOptions
              }
              .wwnPlatformPickerStyle()
              .labelsHidden()
              .wwnA11y(WWNA11y.machinesEditorType, label: "Machine Type")
            }
            Divider()
            Toggle("Show Session Thumbnail On Card", isOn: $machineThumbnailEnabled)
              .toggleStyle(.switch)
          }

          if type == kWWNMachineTypeNative {
            nativeClientSection
          }

          if type == kWWNMachineTypeContainer {
            containerSection
          }

          if isRemote {
            remoteConnectivitySection
            waypipeOverridesSection
            commandPreviewSection
          }

          displayInputGraphicsSection

          environmentVariablesSection

          sectionCard("Session Exit", subtitle: "Per-machine overrides for closing an active session.") {
            Toggle("Shake to Exit Machine", isOn: $shakeToCloseEnabled)
            Toggle("Swipe Back to Exit Machine", isOn: $swipeBackToCloseEnabled)
          }

          if type == kWWNMachineTypeVirtualMachine {
            virtualMachineSection
          }
        }
        .padding(16)
        .frame(maxWidth: 880, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      #if os(macOS)
      .wwnMachineConfigScrollEdgeEffect()
      #endif
      .navigationTitle(title)
      .wwnA11y(WWNA11y.machinesEditor, label: title)
      .toolbar {
        if editorPath.isEmpty {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
              .wwnA11y(WWNA11y.machinesEditorCancel, label: "Cancel")
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
              .wwnA11y(WWNA11y.machinesEditorSave, label: "Save")
          }
        }
      }
      .navigationDestination(for: WWNMachineEditorRoute.self) { route in
        switch route {
        case .bundledClient:
          WWNNativeClientPickerView(
            selectedClientId: $selectedClientId,
            onPicked: popEditorRoute
          )
          #if os(macOS)
          .wwnMachineConfigScrollEdgeEffect()
          .wwnMachineConfigUnifiedToolbar()
          #endif
        }
      }
      #if os(macOS)
      .wwnMachineConfigUnifiedToolbar()
      #endif
      .sheet(isPresented: $showEnvironmentEditor) {
        NavigationStack {
          EnvironmentVariablesView(
            preferences: WawonaPreferences.shared,
            perMachine: true,
            draftMachineOverrides: $environmentOverrides
          )
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { showEnvironmentEditor = false }
            }
          }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
      }
    }
    #if os(macOS)
    .frame(minWidth: 640, idealWidth: 760, maxWidth: 920, minHeight: 560, idealHeight: 760)
    #endif
  }

  private var environmentVariablesSection: some View {
    sectionCard(
      "Environment Variables",
      subtitle: "Per-machine overrides for variables Wawona injects. Inherited (dimmed) rows use global Settings → Environment Variables until you override them."
    ) {
      Button {
        showEnvironmentEditor = true
      } label: {
        HStack {
          Text("Edit Environment Variables…")
          Spacer()
          Text(environmentOverrides.isEmpty ? "Inherit global" : "\(environmentOverrides.count) override(s)")
            .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("wwn.settings.environment.machine")

      if !environmentOverrides.isEmpty {
        ForEach(environmentOverrides.keys.sorted(), id: \.self) { name in
          HStack {
            Text(name)
              .font(.body.monospaced())
            Spacer()
            if let override = environmentOverrides[name] {
              Text(override.action == .unset ? "(unset)" : (override.value ?? ""))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .font(.caption)
        }
        Button("Clear machine overrides") {
          environmentOverrides = [:]
        }
        .foregroundStyle(.red)
      }
    }
  }

  private var displayInputGraphicsSection: some View {
    sectionCard("Display / Input / Graphics", subtitle: "Per-machine overrides for global Display, Input, Graphics, and HDR settings.") {
      #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
      Button("Open Wawona Settings…") {
        #if os(iOS) || os(tvOS) || os(visionOS)
        WWNPreferences.shared().show(nil)
        #elseif os(macOS)
        WWNPreferences.shared().show(NSApp)
        #endif
      }
      #endif
      Toggle("Force Server-Side Decorations", isOn: $forceServerSideDecorations)
      #if os(macOS)
      VStack(alignment: .leading, spacing: 2) {
        Toggle("Always on Top", isOn: $alwaysOnTop)
        Text("Keeps this machine's window above all other windows, even when it isn't focused.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.leading, 24)
      }
      #endif
      Toggle("Auto Scale", isOn: $autoScale)
      #if os(iOS) || os(tvOS)
      Toggle("Respect Safe Area", isOn: $respectSafeArea)
      #endif
      if selectedClientDrawsOwnCursor {
        Text("Nested compositor (weston, niri, or custom) draws its own cursor. The host virtual pointer stays hidden.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.leading, 24)
      } else {
        Toggle("Show Virtual Cursor", isOn: $renderMacOSPointer)
        #if os(macOS)
        labeledField("Nested Compositor Cursor") {
          Picker("", selection: $nestedCompositorCursor) {
            Text("Virtual Pointer").tag("virtual")
            Text("macOS Cursor").tag("host")
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
          .disabled(!renderMacOSPointer)
        }
        #endif
        Text("Nested and iland DRM compositors hide and grab the host pointer. They draw their own cursor. Show Virtual Cursor is only for non-compositor clients.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .opacity(renderMacOSPointer ? 1 : 0.45)
          .padding(.leading, 24)
      }
      labeledField("Touch Input Type") {
        Picker("", selection: $touchInputType) {
          Text("Multi-Touch").tag("Multi-Touch")
          Text("Touchpad").tag("Touchpad")
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
      }
      Toggle("Swap CMD with ALT", isOn: $swapCmdWithAlt)
      Toggle("Universal Clipboard", isOn: $universalClipboard)
      labeledField("Vulkan Driver") {
        Picker("", selection: $vulkanDriver) {
          Text("None").tag("none")
#if os(macOS)
          Text("MoltenVK").tag("moltenvk")
          Text("KosmicKrisp").tag("kosmickrisp")
#elseif !os(tvOS) && !os(watchOS)
          Text("MoltenVK").tag("moltenvk")
#endif
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
      }
      labeledField("OpenGL Driver") {
        Picker("", selection: $openGLDriver) {
          Text("None").tag("none")
          Text("ANGLE").tag("angle")
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
      }
      // Nested compositors (niri, weston) support both. Running them nested
      // when they could drive iland's userspace KMS wastes that path, so make
      // it a choice instead of a hardcode.
      labeledField("Display Backend") {
        Picker("", selection: $compositorBackend) {
          Text("Auto").tag("auto")
          Text("Wayland (nested)").tag("wayland")
          Text("DRM/KMS (wwn-iland)").tag("drm")
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
        .disabled(openGLDriver == "none")
        .help(openGLDriver == "none"
          ? "DRM/KMS presents through iland, which needs an OpenGL driver."
          : "Wayland runs the client nested inside Wawona. DRM/KMS runs it against wwn-iland's userspace display stack, as it would on bare metal.")
      }
      Toggle("Enable DMABUF", isOn: $dmabufEnabled)
      Toggle("Enable HDR", isOn: $colorOperations)
    }
  }

  // MARK: - Machine Type Options

  @ViewBuilder
  private var machineTypeOptions: some View {
    Text("Native").tag(kWWNMachineTypeNative)
    Text("SSH + Waypipe").tag(kWWNMachineTypeSSHWaypipe)
    Text("SSH Terminal").tag(kWWNMachineTypeSSHTerminal)
    #if !os(tvOS) && !os(watchOS)
    Text("Virtual Machine").tag(kWWNMachineTypeVirtualMachine)
    Text("Container").tag(kWWNMachineTypeContainer)
    #endif
  }

  // MARK: - Native Client Section

  private var nativeClientSummary: String {
    if selectedClientId == kNativeClientCustomId {
      return customCommand.isEmpty ? "Custom Command" : customCommand
    }
    if selectedClientId == kNativeClientWasmId {
      if wasmModulePath.isEmpty { return "Wawona Runtime (.wasm)" }
      return (wasmModulePath as NSString).lastPathComponent
    }
    return kBundledClients.first { $0.id == selectedClientId }?.name ?? selectedClientId
  }

  private var bundledClientRowIcon: String? {
    if selectedClientId == kNativeClientCustomId {
      return "terminal.fill"
    }
    return kBundledClients.first { $0.id == selectedClientId }?.icon
  }

  private func popEditorRoute() {
    if !editorPath.isEmpty {
      editorPath.removeLast()
    }
  }

  private var nativeClientSection: some View {
    sectionCard(
      "Wayland Client",
      subtitle: "Choose a bundled client to connect directly to the compositor via Wayland socket. No SSH or network required."
    ) {
      NavigationLink(value: WWNMachineEditorRoute.bundledClient) {
        HStack {
          Text("Bundled Client")
            .foregroundStyle(.primary)
          Spacer()
          if let icon = bundledClientRowIcon {
            Image(systemName: icon)
              .foregroundStyle(.secondary)
          }
          Text(nativeClientSummary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          #if os(macOS)
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
          #endif
        }
      }
      #if os(macOS)
      .buttonStyle(.plain)
      #endif

      #if !os(iOS)
      if selectedClientId == kNativeClientCustomId {
        customCommandRows
      }
      #endif

      if selectedClientId == kNativeClientWasmId {
        wasmModulePickerRows
      }
    }
  }

  @ViewBuilder
  private var customCommandRows: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Custom command")
        .font(.subheadline.weight(.semibold))
      TextField("e.g. /usr/bin/my-wayland-app", text: $customCommand)
        .textFieldStyle(.roundedBorder)
        .wwnDisableAutocapitalization()
        .autocorrectionDisabled()
        .font(.system(.body, design: .monospaced))
      Text("Absolute path or argv0 of a Wayland client. Runs against this machine’s compositor socket.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(.top, 4)
  }

  @ViewBuilder
  private var wasmModulePickerRows: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Wasm module")
        .font(.subheadline.weight(.semibold))
      Text(
        wasmModulePath.isEmpty
          ? "No .wasm selected"
          : wasmModulePath
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(3)
      #if !os(tvOS)
      .textSelection(.enabled)
      #endif

      HStack(spacing: 10) {
        #if os(tvOS)
        TextField("Path to .wasm", text: $wasmModulePath)
          .textFieldStyle(.roundedBorder)
        #else
        Button("Choose…") {
          showWasmFileImporter = true
        }
        .buttonStyle(.bordered)
        TextField("Path", text: $wasmModulePath)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
        #endif
        if !wasmModulePath.isEmpty {
          Button("Clear", role: .destructive) {
            wasmModulePath = ""
          }
          .buttonStyle(.borderless)
        }
      }
      Text("Drop or pick a Wayland WASI `.wasm` (e.g. wayland-shm-rust.wasm). Runs via the bundled Wawona Runtime.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(.top, 4)
    #if !os(tvOS)
    .fileImporter(
      isPresented: $showWasmFileImporter,
      allowedContentTypes: [UTType(filenameExtension: "wasm") ?? .data],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }
      // Prefer copying into Documents/Wawona so sandboxed relaunches keep the file.
      if let stable = Self.importWasmModule(from: url) {
        wasmModulePath = stable
      } else {
        wasmModulePath = url.path
      }
    }
    #endif
  }

  /// Copy a picked `.wasm` into Application Support / Documents so the path survives.
  private static func importWasmModule(from url: URL) -> String? {
    let name = url.lastPathComponent
    guard name.lowercased().hasSuffix(".wasm") else {
      // Still allow non-suffixed picks if magic is checked at launch.
      return copyWasmIntoWawonaDir(from: url, preferredName: name.hasSuffix(".wasm") ? name : name + ".wasm")
    }
    return copyWasmIntoWawonaDir(from: url, preferredName: name)
  }

  private static func copyWasmIntoWawonaDir(from url: URL, preferredName: String) -> String? {
    let fm = FileManager.default
    let base: URL
    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
      base = docs.appendingPathComponent("Wawona", isDirectory: true)
    } else if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      base = appSupport.appendingPathComponent("Wawona", isDirectory: true)
    } else {
      return nil
    }
    let destDir = base.appendingPathComponent("wasm-modules", isDirectory: true)
    do {
      try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
      let dest = destDir.appendingPathComponent(preferredName)
      if fm.fileExists(atPath: dest.path) {
        try fm.removeItem(at: dest)
      }
      try fm.copyItem(at: url, to: dest)
      return dest.path
    } catch {
      return nil
    }
  }

  // MARK: - Remote Connectivity Section

  private var remoteConnectivitySection: some View {
    let isWaypipe = type == kWWNMachineTypeSSHWaypipe
    return sectionCard(
      isWaypipe ? "SSH + Waypipe" : "SSH Connection",
      subtitle: isWaypipe
        ? "Connects to a remote host via SSH and proxies the Wayland protocol using waypipe."
        : "Connects to a remote host via SSH and opens a terminal session."
    ) {
      labeledField("Host") {
        TextField("host.example.com", text: $sshHost)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
      }
      labeledField("User") {
        TextField("username", text: $sshUser)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
      }
      labeledField("Port") {
        TextField("22", text: $sshPort)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
      labeledField("SSH Key Path") {
        TextField("~/.ssh/id_ed25519", text: $sshKeyPath)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
      labeledField("Auth Method") {
        Picker("", selection: $sshAuthMethod) {
          Text("Password").tag(0)
          Text("Public Key").tag(1)
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
      }
      if sshAuthMethod == 0 {
        labeledField("Password") {
          SecureField("Optional", text: $sshPassword)
            .textFieldStyle(.roundedBorder)
        }
      } else {
        labeledField("Key Passphrase") {
          SecureField("Optional", text: $sshKeyPassphrase)
            .textFieldStyle(.roundedBorder)
        }
        Button("Generate Key (ed25519)") {
          if let path = try? WWNSSHKeygen.generateKeyType(
            "ed25519", passphrase: sshKeyPassphrase
          ) {
            sshKeyPath = path
            sshAuthMethod = 1
          }
        }
        .buttonStyle(.bordered)
        Text("Also: Import GPG SSH key via Settings → SSH (gpg --export-ssh-key).")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      labeledField(isWaypipe ? "Remote Command" : "SSH Command") {
        TextField(isWaypipe ? "weston-simple-shm" : "bash -l", text: $remoteCommand)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
    }
  }

  private var waypipeOverridesSection: some View {
    sectionCard("Waypipe Overrides", subtitle: "Per-machine Waypipe and transport settings. These override global defaults.") {
      labeledField("Display Number") {
        TextField("0", text: $waypipeDisplayNumber)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
      labeledField("Compression") {
        Picker("", selection: $waypipeCompress) {
          Text("none").tag("none")
          Text("lz4").tag("lz4")
          Text("zstd").tag("zstd")
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
      }
      labeledField("Compression Level") {
        TextField("7", text: $waypipeCompressLevel)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
      labeledField("Threads") {
        TextField("0", text: $waypipeThreads)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
      labeledField("Video Codec") {
        Picker("", selection: $waypipeVideo) {
          Text("none").tag("none")
          Text("h264").tag("h264")
          Text("vp9").tag("vp9")
          Text("av1").tag("av1")
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
      }
      labeledField("Video Encoding") {
        Picker("", selection: $waypipeVideoEncoding) {
          Text("hw").tag("hw")
          Text("sw").tag("sw")
          Text("hwenc").tag("hwenc")
          Text("swenc").tag("swenc")
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
      }
      labeledField("Video Decoding") {
        Picker("", selection: $waypipeVideoDecoding) {
          Text("hw").tag("hw")
          Text("sw").tag("sw")
          Text("hwdec").tag("hwdec")
          Text("swdec").tag("swdec")
        }
        .wwnPlatformPickerStyle()
        .labelsHidden()
      }
      labeledField("Bits Per Frame") {
        TextField("Optional", text: $waypipeVideoBpf)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
      labeledField("Title Prefix") {
        TextField("Optional", text: $waypipeTitlePrefix)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
      }
      labeledField("Sec Context") {
        TextField("Optional", text: $waypipeSecCtx)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
      Toggle("Use SSH Config", isOn: $waypipeUseSSHConfig)
      Toggle("Debug Mode", isOn: $waypipeDebug)
      Toggle("Disable GPU", isOn: $waypipeNoGpu)
      Text("Off: allow dmabuf/GPU (clients keep GL/VK/ANGLE/llvmpipe). On: Waypipe --no-gpu SHM only.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Toggle("One-shot", isOn: $waypipeOneshot)
      Toggle("Unlink Socket", isOn: $waypipeUnlinkSocket)
      Toggle("Login Shell", isOn: $waypipeLoginShell)
      Toggle("VSock", isOn: $waypipeVsock)
      Toggle("XWayland", isOn: $waypipeXwls)
    }
  }

  private var commandPreviewSection: some View {
    sectionCard("Command Preview", subtitle: "Effective launch command for this machine profile.") {
      Text(previewCommand)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        #if !os(tvOS)
        .textSelection(.enabled)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
        )
    }
  }

  // MARK: - Virtual Machine Section

  private var virtualMachineSection: some View {
    sectionCard("Virtual Machine", subtitle: "Hypervisor is selected automatically for this platform.") {
      labeledField("Backend") {
        Text("QEMU + HVF")
          .foregroundStyle(.secondary)
      }
      Text("The VM engine is fixed per build target (QEMU + Hypervisor.framework on macOS; QEMU-TCTI on iOS; QEMU + KVM/TCG on Android) and is not user-configurable.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Container Section

  private var containerSection: some View {
    let card = sectionCard("Container", subtitle: "Apple Containerization runs this image in a per-container VM.") {
      labeledField("Backend") {
        Text("containerization.framework")
          .foregroundStyle(.secondary)
      }
      labeledField("Image") {
        HStack(spacing: 8) {
          TextField("e.g. alpine:3.20 or python:3.12-slim", text: $containerRef)
            .textFieldStyle(.roundedBorder)
            .wwnDisableAutocapitalization()
            .autocorrectionDisabled()
            .wwnA11y(WWNA11y.machinesEditorContainerRef, label: "Container Image")
          #if os(macOS)
          Button {
            showContainerHubSearch = true
          } label: {
            Label("Search Docker Hub", systemImage: "magnifyingglass")
          }
          .wwnA11y(WWNA11y.machinesEditorContainerHub, label: "Search Docker Hub")
          #endif
        }
      }
      #if os(macOS)
      Button {
        showContainerArchiveImporter = true
      } label: {
        Label("Import image archive…", systemImage: "square.and.arrow.down")
      }
      .disabled(containerImporting)
      if containerImporting {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text("Importing…").font(.caption).foregroundStyle(.secondary)
        }
      }
      if let containerImportNote {
        Text(containerImportNote)
          .font(.caption)
          .foregroundStyle(containerImportNote.hasPrefix("imported") ? .green : .red)
      }
      if !imageArchivePath.isEmpty {
        HStack {
          Image(systemName: "internaldrive").foregroundStyle(.secondary)
          Text("Archive: \(displayContainerArchivePath)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Clear") {
            imageArchivePath = ""
            containerRef = ""
            containerImportNote = nil
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
        }
      }
      #endif
      labeledField("Command") {
        TextField("e.g. /bin/sh", text: $entryCommand)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
          .wwnA11y(WWNA11y.machinesEditorContainerCommand, label: "Container Command")
      }
      #if os(macOS)
      Toggle("Desktop session", isOn: $desktopSession)
        .wwnA11y(WWNA11y.machinesEditorContainerDesktop, label: "Desktop session")
      #endif
      Text("Empty fields inherit the global Settings > Containers defaults. Memory, mounts and ports are configured in Machine Settings.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    #if os(macOS)
    return card
      .sheet(isPresented: $showContainerHubSearch) {
        WWNContainerHubSearchView { selected in
          containerRef = selected
        }
      }
      .fileImporter(
        isPresented: $showContainerArchiveImporter,
        allowedContentTypes: [.item, .directory]
      ) { result in
        handleContainerArchiveImport(result)
      }
    #else
    return card
    #endif
  }

  private var displayContainerArchivePath: String {
    (imageArchivePath as NSString).lastPathComponent
  }

  #if os(macOS)
  private func handleContainerArchiveImport(_ result: Result<URL, Error>) {
    switch result {
    case .success(let url):
      guard url.startAccessingSecurityScopedResource() else {
        containerImportNote = "import failed: permission denied"
        return
      }
      defer { url.stopAccessingSecurityScopedResource() }
      let path = url.path
      containerImporting = true
      containerImportNote = nil
      Task {
        do {
          let imported = try await ContainerImageManager.importFromDiskResolved(path) { _ in }
          containerRef = imported.canonical
          imageArchivePath = imported.ociLayout
          containerImportNote = "imported \(imported.canonical)"
        } catch {
          containerImportNote = "import failed: \(error.localizedDescription)"
        }
        containerImporting = false
      }
    case .failure(let error):
      containerImportNote = "import failed: \(error.localizedDescription)"
    }
  }
  #endif

  // MARK: - Helpers

  private var isRemote: Bool {
    type == kWWNMachineTypeSSHWaypipe || type == kWWNMachineTypeSSHTerminal
  }

  private var previewCommand: String {
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

  private func shellQuote(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
    return "'\(escaped)'"
  }

  private func sanitizeSSHHost(_ raw: String) -> String {
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

  private func normalizeSSHPort(_ raw: String) -> Int {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = Int(trimmed), (1...65535).contains(parsed) else { return 22 }
    return parsed
  }

  private var isCompact: Bool {
    #if os(iOS)
    horizontalSizeClass == .compact
    #else
    false
    #endif
  }

  @ViewBuilder
  private func sectionCard<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      content()
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }

  private var selectedClientDrawsOwnCursor: Bool {
    type == kWWNMachineTypeNative &&
      WWNMachineProfileStore.profileIndicatesNested(
        nativeClientId: selectedClientId,
        customCommand: customCommand
      )
  }

  @ViewBuilder
  private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 10) {
        Text(label)
          .font(.subheadline.weight(.semibold))
          .frame(width: 150, alignment: .leading)
        content()
      }
      VStack(alignment: .leading, spacing: 6) {
        Text(label)
          .font(.subheadline.weight(.semibold))
        content()
      }
    }
  }

  // MARK: - Save

  private func save() {
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

    onSave(profile)
    dismiss()
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
}

#if os(macOS)
private extension View {
  /// Soft fade where editor cards meet the unified titlebar.
  @ViewBuilder
  func wwnMachineConfigScrollEdgeEffect() -> some View {
    if #available(macOS 26.0, *) {
      self.scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      self
    }
  }

  /// Frosted material so scrolling content blurs under Cancel / Save.
  @ViewBuilder
  func wwnMachineConfigUnifiedToolbar() -> some View {
    if #available(macOS 26.0, *) {
      self
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbarTitleDisplayMode(.inline)
    } else {
      self
    }
  }
}
#endif

private struct WWNNativeClientPickerView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var selectedClientId: String
  var onPicked: (() -> Void)? = nil
  @State private var draftId: String = ""

  private var shownId: String {
    draftId.isEmpty ? selectedClientId : draftId
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(kBundledClients) { client in
          clientOption(client)
        }
        #if !os(iOS)
        customClientOption
        #endif
      }
      .padding(16)
    }
    .navigationTitle("Wayland Client")
    .onAppear {
      if draftId.isEmpty {
        draftId = selectedClientId
      }
    }
    #if os(tvOS)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") {
          selectedClientId = shownId
          dismiss()
        }
      }
    }
    .background {
      Color(white: 0.07).ignoresSafeArea()
    }
    #endif
  }

  private func choose(_ id: String) {
    #if os(tvOS)
    draftId = id
    #else
    selectedClientId = id
    if let onPicked {
      onPicked()
    } else {
      dismiss()
    }
    #endif
  }

  @ViewBuilder
  private func clientOption(_ client: BundledClient) -> some View {
    let isSelected = shownId == client.id
    Button {
      choose(client.id)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .frame(width: 28, alignment: .center)
        Image(systemName: client.icon)
          .font(.title3)
          .foregroundStyle(Color.accentColor)
          .frame(width: 28, alignment: .center)
        VStack(alignment: .leading, spacing: 2) {
          Text(client.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text(client.description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .contentShape(Rectangle())
      .padding(.vertical, 6)
      .padding(.horizontal, 8)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
      )
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var customClientOption: some View {
    let isSelected = shownId == kNativeClientCustomId
    Button {
      choose(kNativeClientCustomId)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .frame(width: 28, alignment: .center)
        Image(systemName: "terminal.fill")
          .font(.title3)
          .foregroundStyle(Color.accentColor)
          .frame(width: 28, alignment: .center)
        VStack(alignment: .leading, spacing: 2) {
          Text("Custom Command")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text("Enter the executable on the machine editor")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .contentShape(Rectangle())
      .padding(.vertical, 6)
      .padding(.horizontal, 8)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
      )
    }
    .buttonStyle(.plain)
  }
}

private extension View {
  @ViewBuilder
  func wwnPlatformPickerStyle() -> some View {
    #if os(macOS)
    self.pickerStyle(.menu)
    #else
    self.pickerStyle(.navigationLink)
    #endif
  }

  @ViewBuilder
  func wwnDisableAutocapitalization() -> some View {
    #if os(iOS)
    self.textInputAutocapitalization(.never)
    #else
    self
    #endif
  }
}

#if os(tvOS)
extension TextFieldStyle where Self == PlainTextFieldStyle {
  /// tvOS does not ship RoundedBorderTextFieldStyle; map calls to plain style.
  static var roundedBorder: PlainTextFieldStyle { .plain }
}

/// One Form row, matching Picker/Toggle. A bare `TextField` in a tvOS Form
/// draws its own capsule inside the row's capsule (a double button).
/// Selecting the row opens the system keyboard in an alert instead.
private struct WWNTvFormTextField: View {
  let title: String
  @Binding var text: String
  var prompt: String = ""
  var secure: Bool = false

  @State private var showEditor = false
  @State private var draft = ""

  init(_ title: String, text: Binding<String>, prompt: String = "", secure: Bool = false) {
    self.title = title
    self._text = text
    self.prompt = prompt
    self.secure = secure
  }

  var body: some View {
    Button {
      draft = text
      showEditor = true
    } label: {
      LabeledContent(title) {
        Text(displayValue)
          .foregroundStyle(text.isEmpty ? .secondary : .primary)
          .multilineTextAlignment(.trailing)
      }
    }
    .buttonStyle(.plain)
    .alert(title, isPresented: $showEditor) {
      if secure {
        SecureField(prompt.isEmpty ? title : prompt, text: $draft)
      } else {
        TextField(prompt.isEmpty ? title : prompt, text: $draft)
      }
      Button("OK") { text = draft }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var displayValue: String {
    if text.isEmpty {
      return prompt.isEmpty ? "Required" : prompt
    }
    if secure {
      return String(repeating: "•", count: min(text.count, 8))
    }
    return text
  }
}
#endif
