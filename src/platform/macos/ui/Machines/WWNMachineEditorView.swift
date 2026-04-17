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
  @State private var sshPassword: String
  @State private var sshKeyPath: String
  @State private var sshKeyPassphrase: String
  @State private var sshAuthMethod: Int
  @State private var remoteCommand: String
  @State private var vmSubtype: String
  @State private var containerSubtype: String

  @State private var selectedClientId: String
  @State private var customCommand: String
  @State private var customIsNestedCompositor: Bool
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
  @State private var renderMacOSPointer: Bool
  @State private var touchInputType: String
  @State private var swapCmdWithAlt: Bool
  @State private var universalClipboard: Bool
  @State private var vulkanDriver: String
  @State private var openGLDriver: String
  @State private var dmabufEnabled: Bool
  @State private var colorOperations: Bool

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
    _sshPassword = State(initialValue: initial?.sshPassword ?? "")
    _sshKeyPath = State(initialValue: initial?.sshKeyPath ?? "")
    _sshKeyPassphrase = State(initialValue: initial?.sshKeyPassphrase ?? "")
    _sshAuthMethod = State(initialValue: initial?.sshAuthMethod ?? 0)
    _remoteCommand = State(initialValue: initial?.remoteCommand ?? "")
    _vmSubtype = State(initialValue: initial?.vmSubtype ?? "qemu")
    _containerSubtype = State(initialValue: initial?.containerSubtype ?? "docker")

    let runtimeOverrides: [String: Any] = initial?.runtimeOverrides ?? [:]
    let overrides: [String: Any] = initial?.settingsOverrides ?? [:]
    let prefs = WWNPreferencesManager.shared()
    _customCommand = State(initialValue: (overrides["NativeCustomCommand"] as? String) ?? "")
    _customIsNestedCompositor = State(initialValue: (overrides["RenderMacOSPointer"] as? Bool) == false)
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
    _renderMacOSPointer = State(initialValue: (overrides["RenderMacOSPointer"] as? Bool) ?? prefs.renderMacOSPointer())
    _touchInputType = State(initialValue: overrides["TouchInputType"] as? String ?? prefs.touchInputType())
    _swapCmdWithAlt = State(initialValue: (overrides["SwapCmdWithAlt"] as? Bool) ?? prefs.swapCmdWithAlt())
    _universalClipboard = State(initialValue: (overrides["UniversalClipboard"] as? Bool) ?? prefs.universalClipboardEnabled())
    _vulkanDriver = State(initialValue: overrides["VulkanDriver"] as? String ?? prefs.vulkanDriver())
    _openGLDriver = State(initialValue: overrides["OpenGLDriver"] as? String ?? prefs.openglDriver())
    _dmabufEnabled = State(initialValue: (overrides["DmabufEnabled"] as? Bool) ?? prefs.dmabufEnabled())
    _colorOperations = State(initialValue: (overrides["ColorOperations"] as? Bool) ?? prefs.colorOperations())

    if let stored = runtimeOverrides["bundledAppID"] as? String, !stored.isEmpty {
      _selectedClientId = State(initialValue: stored)
    } else if let stored = overrides["NativeClientId"] as? String, !stored.isEmpty {
      _selectedClientId = State(initialValue: stored)
    } else if (overrides["WestonEnabled"] as? Bool) == true {
      _selectedClientId = State(initialValue: "weston")
    } else if (overrides["WestonTerminalEnabled"] as? Bool) == true {
      _selectedClientId = State(initialValue: "weston-terminal")
    } else if (overrides["WestonSimpleSHMEnabled"] as? Bool) == true {
      _selectedClientId = State(initialValue: "weston-simple-shm")
    } else if (overrides["FootEnabled"] as? Bool) == true {
      _selectedClientId = State(initialValue: "foot")
    } else {
      _selectedClientId = State(initialValue: "weston-simple-shm")
    }

    #if os(iOS)
    // iOS must not present or persist external custom command execution.
    if _selectedClientId.wrappedValue == kNativeClientCustomId {
      _selectedClientId = State(initialValue: "weston-simple-shm")
      _customCommand = State(initialValue: "")
    }
    #endif
  }

  var body: some View {
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
          }

          displayInputGraphicsSection

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
      Toggle("Force Server-Side Decorations", isOn: $forceServerSideDecorations)
      Toggle("Auto Scale", isOn: $autoScale)
      Toggle("Show macOS Cursor", isOn: $renderMacOSPointer)
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
          Text("MoltenVK").tag("moltenvk")
          Text("KosmicKrisp").tag("kosmickrisp")
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }
      labeledField("OpenGL Driver") {
        Picker("", selection: $openGLDriver) {
          Text("None").tag("none")
          Text("ANGLE").tag("angle")
          Text("MoltenGL").tag("moltengl")
        }
        .pickerStyle(.menu)
        .labelsHidden()
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
    Text("Virtual Machine").tag(kWWNMachineTypeVirtualMachine)
    Text("Container").tag(kWWNMachineTypeContainer)
  }

  // MARK: - Native Client Section

  private var nativeClientSection: some View {
    sectionCard(
      "Wayland Client",
      subtitle: "Choose a bundled client to connect directly to the compositor via Wayland socket. No SSH or network required."
    ) {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(kBundledClients) { client in
          clientOption(client)
        }
        #if !os(iOS)
        customClientOption
        #endif
      }
    }
  }

  @ViewBuilder
  private func clientOption(_ client: BundledClient) -> some View {
    let isSelected = selectedClientId == client.id
    Button {
      selectedClientId = client.id
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

        Toggle(isOn: $customIsNestedCompositor) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Nested Compositor")
              .font(.caption.weight(.semibold))
            Text("Enable if this client renders its own cursor (e.g. another Wayland compositor)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .toggleStyle(.switch)
        .padding(.leading, 68)
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

  // MARK: - Virtual Machine Section

  private var virtualMachineSection: some View {
    sectionCard("Virtual Machine", subtitle: "Hypervisor metadata for launch orchestration.") {
      labeledField("VM Subtype") {
        TextField("qemu, utm, ...", text: $vmSubtype)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
      }
      Text("VM launch support is currently placeholder behavior until runtime integration is complete.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Container Section

  private var containerSection: some View {
    sectionCard("Container", subtitle: "Container runtime and startup command.") {
      labeledField("Container Subtype") {
        TextField("docker, podman, ...", text: $containerSubtype)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
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
    profile.sshHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.sshUser = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
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
    profile.vmSubtype = vmSubtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "qemu" : vmSubtype
    profile.containerSubtype =
      containerSubtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "docker" : containerSubtype

    var overrides: [String: Any] = profile.settingsOverrides
    var runtimeOverrides: [String: Any] = profile.runtimeOverrides
    overrides["NativeClientId"] = selectedClientId
    overrides["NativeCustomCommand"] = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    overrides["WestonEnabled"] = selectedClientId == "weston"
    overrides["WestonTerminalEnabled"] = selectedClientId == "weston-terminal"
    overrides["WestonSimpleSHMEnabled"] = selectedClientId == "weston-simple-shm"
    overrides["FootEnabled"] = selectedClientId == "foot"

    overrides["RenderMacOSPointer"] = renderMacOSPointer
    overrides["ForceServerSideDecorations"] = forceServerSideDecorations
    overrides["AutoScale"] = autoScale
    overrides["TouchInputType"] = touchInputType
    overrides["SwapCmdWithAlt"] = swapCmdWithAlt
    overrides["UniversalClipboard"] = universalClipboard
    overrides["VulkanDriver"] = vulkanDriver
    overrides["OpenGLDriver"] = openGLDriver
    overrides["DmabufEnabled"] = dmabufEnabled
    overrides["ColorOperations"] = colorOperations
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
    overrides["SSHAuthMethod"] = profile.sshAuthMethod
    overrides["SSHPassword"] = profile.sshPassword
    overrides["SSHKeyPath"] = profile.sshKeyPath
    overrides["SSHKeyPassphrase"] = profile.sshKeyPassphrase

    runtimeOverrides["useBundledApp"] = (type == kWWNMachineTypeNative && !selectedClientId.isEmpty)
    runtimeOverrides["bundledAppID"] = selectedClientId
    runtimeOverrides["waypipeEnabled"] = (type == kWWNMachineTypeSSHWaypipe || type == kWWNMachineTypeSSHTerminal)
    if machineThumbnailEnabled != WWNPreferencesManager.shared().machineSessionThumbnailsEnabled() {
      runtimeOverrides["machineThumbnailEnabledOverride"] = machineThumbnailEnabled
    } else {
      runtimeOverrides.removeValue(forKey: "machineThumbnailEnabledOverride")
    }
    runtimeOverrides["legacySettingsOverrides"] = overrides

    profile.settingsOverrides = overrides
    profile.runtimeOverrides = runtimeOverrides

    onSave(profile)
    dismiss()
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
