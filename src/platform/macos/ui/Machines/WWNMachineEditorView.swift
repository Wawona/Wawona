import SwiftUI

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

  @State private var selectedClientId: String
  @State private var customCommand: String
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

    let runtimeOverrides: [String: Any] = initial?.runtimeOverrides ?? [:]
    let overrides: [String: Any] = initial?.settingsOverrides ?? [:]
    let prefs = WWNPreferencesManager.shared()
    let initialCustomCommand = (overrides["NativeCustomCommand"] as? String) ?? ""
    _customCommand = State(initialValue: initialCustomCommand)
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
          TextField("Display Name", text: $name)
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
                selectedClientId: $selectedClientId,
                customCommand: $customCommand
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
          }
        }

        if isRemote {
          Section("Remote SSH") {
            TextField("Host", text: $sshHost)
            TextField("User", text: $sshUser)
            TextField("Port", text: $sshPort)
            SecureField("Password", text: $sshPassword)
            TextField("Remote Command", text: $remoteCommand)
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
          Toggle("Universal Clipboard", isOn: $universalClipboard)
          Button("Open Wawona Settings…") {
            WWNPreferences.shared().show(nil)
          }
        } header: {
          Text("Display")
        }

        Section {
          Toggle("Long-press Menu to Exit Machine", isOn: $shakeToCloseEnabled)
        } header: {
          Text("Session Exit")
        } footer: {
          Text(
            "Siri Remote has no shake API. Short Menu/Back sends Escape to the "
              + "Wayland client. Long-press Menu (~1s) confirms leaving the session "
              + "when this is enabled (same preference key as Shake to Exit on iPhone)."
          )
        }
      }
      // Default tvOS Form chrome is glass over the Machines grid — unreadable at 10ft.
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
    }
    .preferredColorScheme(.dark)
    .presentationBackground(Color(white: 0.07))
  }
  #endif

  private var desktopMobileEditorBody: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          sectionCard("Connection Profile", subtitle: "Name and type for this machine profile.") {
            labeledField("Display Name") {
              TextField("e.g. Studio Linux VM", text: $name)
                .textFieldStyle(.roundedBorder)
            }
            labeledField("Type") {
              Picker("", selection: $type) {
                machineTypeOptions
              }
              .pickerStyle(.menu)
              .labelsHidden()
            }
            Divider()
            Toggle("Show Session Thumbnail On Card", isOn: $machineThumbnailEnabled)
              .toggleStyle(.switch)
          }

          if type == kWWNMachineTypeNative {
            nativeClientSection
          }

          if isRemote {
            remoteConnectivitySection
            waypipeOverridesSection
            commandPreviewSection
          }

          displayInputGraphicsSection

          sectionCard("Session Exit", subtitle: "Per-machine overrides for closing an active session.") {
            Toggle("Shake to Exit Machine", isOn: $shakeToCloseEnabled)
            Toggle("Swipe Back to Exit Machine", isOn: $swipeBackToCloseEnabled)
          }

          if type == kWWNMachineTypeVirtualMachine {
            virtualMachineSection
          }

          if type == kWWNMachineTypeContainer {
            containerSection
          }
        }
        .padding(16)
        .frame(maxWidth: 880, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
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
    }
    #if os(macOS)
    .frame(minWidth: 640, idealWidth: 760, maxWidth: 920, minHeight: 560, idealHeight: 760)
    #endif
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
      Toggle("Show Virtual Cursor", isOn: $renderMacOSPointer)
      labeledField("Nested Compositor Cursor") {
        Picker("", selection: $nestedCompositorCursor) {
          Text("Virtual Pointer").tag("virtual")
          #if os(macOS)
          Text("macOS Cursor").tag("host")
          #else
          Text("Host Cursor").tag("host")
          #endif
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(!renderMacOSPointer)
      }
      Text("When nested compositors run, grab the virtual pointer or the real host cursor. Requires Show Virtual Cursor.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .opacity(renderMacOSPointer ? 1 : 0.45)
        .padding(.leading, 24)
      labeledField("Touch Input Type") {
        Picker("", selection: $touchInputType) {
          Text("Multi-Touch").tag("Multi-Touch")
          Text("Touchpad").tag("Touchpad")
        }
        .pickerStyle(.menu)
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
        .pickerStyle(.menu)
        .labelsHidden()
      }
      labeledField("OpenGL Driver") {
        Picker("", selection: $openGLDriver) {
          Text("None").tag("none")
          Text("ANGLE").tag("angle")
        }
        .pickerStyle(.menu)
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
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(openGLDriver == "none")
        .help(openGLDriver == "none"
          ? "DRM/KMS presents through iland, which needs an OpenGL driver."
          : "Wayland runs the client nested inside Wawona. DRM/KMS runs it against wwn-iland's userspace display stack, as it would on bare metal.")
      }
      Toggle("Enable DMABUF", isOn: $dmabufEnabled)
      Toggle("HDR / Color Operations", isOn: $colorOperations)
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
    return kBundledClients.first { $0.id == selectedClientId }?.name ?? selectedClientId
  }

  private var nativeClientSection: some View {
    sectionCard(
      "Wayland Client",
      subtitle: "Choose a bundled client to connect directly to the compositor via Wayland socket. No SSH or network required."
    ) {
      NavigationLink {
        WWNNativeClientPickerView(
          selectedClientId: $selectedClientId,
          customCommand: $customCommand
        )
      } label: {
        HStack {
          Text("Bundled Client")
            .foregroundStyle(.primary)
          Spacer()
          Text(nativeClientSummary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
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
        .pickerStyle(.menu)
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
        .pickerStyle(.menu)
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
        .pickerStyle(.menu)
        .labelsHidden()
      }
      labeledField("Video Encoding") {
        Picker("", selection: $waypipeVideoEncoding) {
          Text("hw").tag("hw")
          Text("sw").tag("sw")
          Text("hwenc").tag("hwenc")
          Text("swenc").tag("swenc")
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }
      labeledField("Video Decoding") {
        Picker("", selection: $waypipeVideoDecoding) {
          Text("hw").tag("hw")
          Text("sw").tag("sw")
          Text("hwdec").tag("hwdec")
          Text("swdec").tag("swdec")
        }
        .pickerStyle(.menu)
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
        Text("Virtualization.framework")
          .foregroundStyle(.secondary)
      }
      Text("The VM engine is fixed per build target (Virtualization.framework on macOS) and is not user-configurable.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Container Section

  private var containerSection: some View {
    sectionCard("Container", subtitle: "Container runtime is selected automatically for this platform.") {
      labeledField("Backend") {
        Text("containerization.framework")
          .foregroundStyle(.secondary)
      }
      labeledField("Startup Command") {
        TextField("weston-simple-shm", text: $remoteCommand)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
      }
      Text("Container launch support is currently placeholder behavior until runtime integration is complete.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

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
    // Desktop window chrome is unusable on the 10-foot UI; never persist SSD/GPU stack.
    overrides["ForceServerSideDecorations"] = false
    overrides["VulkanDriver"] = "none"
    overrides["OpenGLDriver"] = "none"
    overrides["DmabufEnabled"] = false
    overrides["ColorOperations"] = false
    overrides["TouchInputType"] = "Touchpad"
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
    runtimeOverrides["bundledAppID"] = selectedClientId
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

    profile.settingsOverrides = overrides
    profile.runtimeOverrides = runtimeOverrides

    onSave(profile)
    dismiss()
  }
}

private struct WWNNativeClientPickerView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var selectedClientId: String
  @Binding var customCommand: String

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
    #if os(tvOS)
    .background {
      Color(white: 0.07).ignoresSafeArea()
    }
    #endif
  }

  @ViewBuilder
  private func clientOption(_ client: BundledClient) -> some View {
    let isSelected = selectedClientId == client.id
    Button {
      selectedClientId = client.id
      // Match Android/iOS: choosing a bundled client pops the picker immediately.
      dismiss()
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
    let isSelected = selectedClientId == kNativeClientCustomId
    VStack(alignment: .leading, spacing: 8) {
      Button {
        selectedClientId = kNativeClientCustomId
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
            Text("Run any Wayland-compatible executable")
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

      if isSelected {
        TextField("e.g. /usr/bin/my-wayland-app", text: $customCommand)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
          .autocorrectionDisabled()
          .padding(.leading, 68)
      }
    }
  }
}

private extension View {
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
#endif
