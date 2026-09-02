import SwiftUI
import WawonaModel
import UniformTypeIdentifiers

/// Route destinations inside the machine editor's NavigationStack.
enum WWNMachineEditorRoute: Hashable {
  case bundledClient
}

// MARK: - Machine Profile

/// Identity card: display name, machine type, session thumbnail.
struct WWNMachineProfileEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: draft.machineTypeSymbol,
      title: "Machine Profile",
      tint: .accentColor,
      info: "Display name and machine kind. The type decides which sections below apply to this machine."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorFieldRow("Display Name") {
          TextField("e.g. Studio Linux VM", text: $draft.name)
            .textFieldStyle(.roundedBorder)
            .wwnA11y(WWNA11y.machinesEditorName, label: "Display Name")
        }
        WWNEditorFieldRow("Type") {
          Picker("", selection: $draft.type) {
            machineTypeOption("Native", kWWNMachineTypeNative, "display")
            machineTypeOption("SSH + Waypipe", kWWNMachineTypeSSHWaypipe, "arrow.triangle.2.circlepath")
            machineTypeOption("SSH Terminal", kWWNMachineTypeSSHTerminal, "terminal")
            #if !os(tvOS) && !os(watchOS)
            machineTypeOption("Virtual Machine", kWWNMachineTypeVirtualMachine, "desktopcomputer")
            machineTypeOption("Container", kWWNMachineTypeContainer, "shippingbox")
            #endif
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
          .wwnA11y(WWNA11y.machinesEditorType, label: "Machine Type")
        }
        Divider()
        WWNEditorToggleRow(
          "Show Session Thumbnail On Card",
          icon: "photo.on.rectangle.angled",
          footnote: "Saves the last frame from a machine session and shows it on the machine card.",
          isOn: $draft.machineThumbnailEnabled
        )
      }
    }
  }

  private func machineTypeOption(_ name: String, _ value: String, _ symbol: String) -> some View {
    Label(name, systemImage: symbol).tag(value)
  }
}

// MARK: - Native client

/// Native machines: bundled Wayland client, custom command or WASM module.
struct WWNNativeClientEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  @State private var showWasmFileImporter = false

  var body: some View {
    WWNEditorCard(
      icon: "app.badge.checkmark",
      title: "Wayland Client",
      tint: .blue,
      info: "Choose a bundled client to connect directly to the compositor via Wayland socket. No SSH or network required."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorFieldRow("Bundled Client", icon: clientIcon) {
          NavigationLink(value: WWNMachineEditorRoute.bundledClient) {
            HStack(spacing: 6) {
              Text(clientSummary)
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
        }

        #if !os(iOS)
        if draft.selectedClientId == kNativeClientCustomId {
          VStack(alignment: .leading, spacing: 8) {
            WWNEditorFieldRow("Custom Command", icon: "terminal") {
              WWNEditorCodeField("e.g. /usr/bin/my-wayland-app", text: $draft.customCommand)
            }
            WWNEditorCaption(
              text: "Absolute path or argv0 of a Wayland client. Runs against this machine's compositor socket."
            )
          }
          .padding(.top, 4)
        }
        #endif

        if draft.selectedClientId == kNativeClientWasmId {
          wasmRows
        }
      }
    }
  }

  private var clientSummary: String {
    if draft.selectedClientId == kNativeClientCustomId {
      return draft.customCommand.isEmpty ? "Custom Command" : draft.customCommand
    }
    if draft.selectedClientId == kNativeClientWasmId {
      if draft.wasmModulePath.isEmpty { return "Wawona Runtime (.wasm)" }
      return (draft.wasmModulePath as NSString).lastPathComponent
    }
    return kBundledClients.first { $0.id == draft.selectedClientId }?.name ?? draft.selectedClientId
  }

  private var clientIcon: String? {
    if draft.selectedClientId == kNativeClientCustomId {
      return "terminal.fill"
    }
    return kBundledClients.first { $0.id == draft.selectedClientId }?.icon
  }

  private var wasmRows: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(draft.wasmModulePath.isEmpty ? "No .wasm selected" : draft.wasmModulePath)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
        #if !os(tvOS)
        .textSelection(.enabled)
        #endif
      HStack(spacing: 10) {
        WWNEditorCodeField("Path to .wasm", text: $draft.wasmModulePath)
        Button("Choose…") {
          showWasmFileImporter = true
        }
        .buttonStyle(.bordered)
        if !draft.wasmModulePath.isEmpty {
          Button("Clear", role: .destructive) {
            draft.wasmModulePath = ""
          }
          .buttonStyle(.borderless)
        }
      }
      WWNEditorCaption(
        text: "Drop or pick a Wayland WASI `.wasm` (e.g. wayland-shm-rust.wasm). Runs via the bundled Wawona Runtime."
      )
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
        draft.wasmModulePath = stable
      } else {
        draft.wasmModulePath = url.path
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
}

// MARK: - Container

/// Container machines: image + command + (macOS) archive import / desktop
/// session. Advanced settings (memory, mounts, ports) live in Machine
/// Settings; empty fields inherit global Settings → Containers.
struct WWNContainerEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  @State private var showContainerHubSearch = false
  @State private var showContainerArchiveImporter = false
  @State private var containerImporting = false
  @State private var containerImportNote: String?

  var body: some View {
    WWNEditorCard(
      icon: "shippingbox",
      title: "Container",
      tint: .orange,
      info: "Empty fields inherit the global Settings → Containers defaults. Memory, mounts and ports are configured in Machine Settings."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorFieldRow("Backend", icon: "cpu") {
          Text("containerization.framework")
            .foregroundStyle(.secondary)
        }
        WWNEditorFieldRow("Image", icon: "shippingbox") {
          HStack(spacing: 8) {
            WWNEditorCodeField("e.g. alpine:3.20 or python:3.12-slim", text: $draft.containerRef)
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
        WWNEditorFieldRow("Command", icon: "terminal") {
          WWNEditorCodeField("e.g. /bin/sh", text: $draft.entryCommand)
            .wwnA11y(WWNA11y.machinesEditorContainerCommand, label: "Container Command")
        }

        #if os(macOS)
        archiveRows

        Divider()

        WWNEditorToggleRow(
          "Desktop session",
          icon: "macwindow",
          footnote: "Runs a full desktop session in the container: wwn-containerd injects the guest waypipe and bridges the container's Wayland session into Wawona as windows.",
          isOn: $draft.desktopSession
        )
        .wwnA11y(WWNA11y.machinesEditorContainerDesktop, label: "Desktop session")
        #endif
      }
    }
    .sheet(isPresented: $showContainerHubSearch) {
      WWNContainerHubSearchView { selected in
        draft.containerRef = selected
      }
    }
    .fileImporter(
      isPresented: $showContainerArchiveImporter,
      allowedContentTypes: [.item, .directory]
    ) { result in
      handleContainerArchiveImport(result)
    }
  }

  @ViewBuilder
  private var archiveRows: some View {
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
    if !draft.imageArchivePath.isEmpty {
      HStack {
        Image(systemName: "internaldrive").foregroundStyle(.secondary)
        Text("Archive: \((draft.imageArchivePath as NSString).lastPathComponent)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        Button("Clear") {
          draft.imageArchivePath = ""
          draft.containerRef = ""
          containerImportNote = nil
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
      }
    }
  }

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
          draft.containerRef = imported.canonical
          draft.imageArchivePath = imported.ociLayout
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
}

// MARK: - Remote SSH

/// SSH connection card for remote machines (SSH + Waypipe / SSH Terminal).
struct WWNRemoteSSHEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: "lock.shield",
      title: draft.isWaypipeMachine ? "SSH + Waypipe" : "SSH Connection",
      tint: .blue,
      info: draft.isWaypipeMachine
        ? "Connects to a remote host via SSH and proxies the Wayland protocol using waypipe."
        : "Connects to a remote host via SSH and opens a terminal session."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorFieldRow("Host", icon: "server.rack") {
          WWNEditorCodeField("host.example.com", text: $draft.sshHost)
        }
        WWNEditorFieldRow("User", icon: "person") {
          WWNEditorCodeField("username", text: $draft.sshUser)
        }
        WWNEditorFieldRow("Port", icon: "number") {
          WWNEditorCodeField("22", text: $draft.sshPort)
        }
        WWNEditorFieldRow("SSH Key Path", icon: "key") {
          WWNEditorCodeField("~/.ssh/id_ed25519", text: $draft.sshKeyPath)
        }
        WWNEditorFieldRow("Auth Method", icon: "lock") {
          Picker("", selection: $draft.sshAuthMethod) {
            Text("Password").tag(0)
            Text("Public Key").tag(1)
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
        }

        if draft.sshAuthMethod == 0 {
          WWNEditorFieldRow("Password", icon: "lock.fill") {
            WWNEditorSecureField("Optional", text: $draft.sshPassword)
          }
        } else {
          WWNEditorFieldRow("Key Passphrase", icon: "lock.fill") {
            WWNEditorSecureField("Optional", text: $draft.sshKeyPassphrase)
          }
          HStack(spacing: 8) {
            Button("Generate Key (ed25519)") {
              if let path = try? WWNSSHKeygen.generateKeyType(
                "ed25519", passphrase: draft.sshKeyPassphrase
              ) {
                draft.sshKeyPath = path
                draft.sshAuthMethod = 1
              }
            }
            .buttonStyle(.bordered)
            #if os(macOS)
            WWNEditorInfoButton(
              text: "Also: Import GPG SSH key via Settings → SSH (gpg --export-ssh-key)."
            )
            #endif
          }
          WWNEditorCaption(
            text: "Also: Import GPG SSH key via Settings → SSH (gpg --export-ssh-key)."
          )
        }

        WWNEditorFieldRow(draft.isWaypipeMachine ? "Remote Command" : "SSH Command", icon: "terminal") {
          WWNEditorCodeField(draft.isWaypipeMachine ? "weston-simple-shm" : "bash -l", text: $draft.remoteCommand)
        }
      }
    }
  }
}

// MARK: - Waypipe transport

/// Per-machine Waypipe overrides.
struct WWNWaypipeEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: "arrow.triangle.2.circlepath",
      title: "Waypipe Transport",
      tint: .green,
      info: "Per-machine Waypipe and transport settings. These override global defaults."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorFieldRow("Display Number", icon: "number") {
          WWNEditorCodeField("0", text: $draft.waypipeDisplayNumber)
        }
        WWNEditorFieldRow("Compression", icon: "arrow.left.arrow.right") {
          Picker("", selection: $draft.waypipeCompress) {
            Text("none").tag("none")
            Text("lz4").tag("lz4")
            Text("zstd").tag("zstd")
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
        }
        WWNEditorFieldRow("Compression Level", icon: "slider.horizontal.3") {
          WWNEditorCodeField("7", text: $draft.waypipeCompressLevel)
        }
        WWNEditorFieldRow("Threads", icon: "cpu") {
          WWNEditorCodeField("0 = auto", text: $draft.waypipeThreads)
        }
        WWNEditorFieldRow("Video Codec", icon: "film") {
          Picker("", selection: $draft.waypipeVideo) {
            Text("none").tag("none")
            Text("h264").tag("h264")
            Text("vp9").tag("vp9")
            Text("av1").tag("av1")
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
        }
        WWNEditorFieldRow("Video Encoding", icon: "arrow.up.right.video") {
          Picker("", selection: $draft.waypipeVideoEncoding) {
            Text("hw").tag("hw")
            Text("sw").tag("sw")
            Text("hwenc").tag("hwenc")
            Text("swenc").tag("swenc")
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
        }
        WWNEditorFieldRow("Video Decoding", icon: "arrow.down.left.video") {
          Picker("", selection: $draft.waypipeVideoDecoding) {
            Text("hw").tag("hw")
            Text("sw").tag("sw")
            Text("hwdec").tag("hwdec")
            Text("swdec").tag("swdec")
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
        }
        WWNEditorFieldRow("Bits Per Frame", icon: "gauge") {
          WWNEditorCodeField("Optional", text: $draft.waypipeVideoBpf)
        }
        WWNEditorFieldRow("Title Prefix", icon: "textformat") {
          WWNEditorCodeField("Optional", text: $draft.waypipeTitlePrefix)
        }
        WWNEditorFieldRow("Sec Context", icon: "lock.shield") {
          WWNEditorCodeField("Optional", text: $draft.waypipeSecCtx)
        }

        Divider()

        WWNEditorToggleRow("Use SSH Config", icon: "server.rack", isOn: $draft.waypipeUseSSHConfig)
        WWNEditorToggleRow("Debug Mode", icon: "ladybug", isOn: $draft.waypipeDebug)
        WWNEditorToggleRow(
          "Disable GPU",
          icon: "cpu",
          footnote: "Off: allow dmabuf/GPU (clients keep GL/VK/ANGLE/llvmpipe). On: Waypipe --no-gpu SHM only.",
          isOn: $draft.waypipeNoGpu
        )
        WWNEditorToggleRow("One-shot", icon: "1.circle", isOn: $draft.waypipeOneshot)
        WWNEditorToggleRow("Unlink Socket", icon: "link", isOn: $draft.waypipeUnlinkSocket)
        WWNEditorToggleRow("Login Shell", icon: "terminal", isOn: $draft.waypipeLoginShell)
        WWNEditorToggleRow("VSock", icon: "network", isOn: $draft.waypipeVsock)
        WWNEditorToggleRow("XWayland", icon: "xmark", isOn: $draft.waypipeXwls)
      }
    }
  }
}

// MARK: - Launch command preview

struct WWNLaunchCommandEditorSection: View {
  let command: String

  var body: some View {
    WWNEditorCard(
      icon: "terminal",
      title: "Launch Command",
      tint: .gray,
      info: "Effective launch command for this machine profile."
    ) {
      WWNEditorCommandBlock(command: command)
    }
  }
}

// MARK: - Display / Input / Graphics

/// Header above the Display / Input / Graphics override cards, with the
/// shortcut to global Settings.
struct WWNMachineOverridesHeader: View {
  var onOpenSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 10) {
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        Text("Per-Machine Overrides")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        #if os(macOS)
        WWNEditorInfoButton(
          text: "Each card overrides the matching global default from Wawona Settings. Leave a control untouched to keep inheriting the global value."
        )
        #endif
        Spacer()
        Button(action: onOpenSettings) {
          Label("Open Wawona Settings…", systemImage: "gearshape")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      WWNEditorCaption(
        text: "Each card overrides the matching global default from Wawona Settings. Leave a control untouched to keep inheriting the global value."
      )
    }
    .padding(.horizontal, 4)
    .padding(.top, 6)
  }
}

struct WWNMachineDisplayEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: "display",
      title: "Display",
      tint: .blue,
      info: "Per-machine overrides for the global Settings → Display values."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorToggleRow(
          "Force Server-Side Decorations",
          icon: "macwindow",
          footnote: "When off, weston-family clients draw their own window frames.",
          isOn: $draft.forceServerSideDecorations
        )
        #if os(macOS)
        WWNEditorToggleRow(
          "Always on Top",
          icon: "pin",
          footnote: "Keeps this machine's window above all other windows, even when it isn't focused.",
          isOn: $draft.alwaysOnTop
        )
        #endif
        WWNEditorToggleRow("Auto Scale", icon: "arrow.up.left.and.arrow.down.right", isOn: $draft.autoScale)
        #if os(iOS) || os(tvOS)
        WWNEditorToggleRow("Respect Safe Area", icon: "rectangle.inset.filled", isOn: $draft.respectSafeArea)
        #endif
        Divider()
        // Nested compositors (niri, weston) support both. Running them nested
        // when they could drive iland's userspace KMS wastes that path, so make
        // it a choice instead of a hardcode.
        WWNEditorFieldRow(
          "Display Backend",
          icon: "display",
          footnote: "Wayland runs the client nested inside Wawona. DRM/KMS runs it against wwn-iland's userspace display stack, as it would on bare metal."
        ) {
          Picker("", selection: $draft.compositorBackend) {
            Text("Auto").tag("auto")
            Text("Wayland (nested)").tag("wayland")
            Text("DRM/KMS (wwn-iland)").tag("drm")
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
          .disabled(draft.openGLDriver == "none")
          .help(draft.openGLDriver == "none"
            ? "DRM/KMS presents through iland, which needs an OpenGL driver."
            : "Wayland runs the client nested inside Wawona. DRM/KMS runs it against wwn-iland's userspace display stack, as it would on bare metal.")
        }
      }
    }
  }
}

struct WWNMachineInputEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: "keyboard",
      title: "Input",
      tint: .purple,
      info: "Per-machine overrides for the global Settings → Input values."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        if draft.selectedClientDrawsOwnCursor {
          // No host-pointer control exists for nested compositors; explain why.
          HStack(spacing: 8) {
            Image(systemName: "cursorarrow")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .frame(width: 18)
            Text("Nested compositor (weston, niri, or custom) draws its own cursor. The host virtual pointer stays hidden.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else {
          WWNEditorToggleRow(
            "Show Virtual Cursor",
            icon: "cursorarrow",
            footnote: "Nested and iland DRM compositors hide and grab the host pointer. They draw their own cursor. Show Virtual Cursor is only for non-compositor clients.",
            isOn: $draft.renderMacOSPointer
          )
          #if os(macOS)
          WWNEditorFieldRow("Nested Compositor Cursor", icon: "cursorarrow.click") {
            Picker("", selection: $draft.nestedCompositorCursor) {
              Text("Virtual Pointer").tag("virtual")
              Text("macOS Cursor").tag("host")
            }
            .wwnPlatformPickerStyle()
            .labelsHidden()
            .disabled(!draft.renderMacOSPointer)
          }
          #endif
        }
        Divider()
        WWNEditorFieldRow("Touch Input Type", icon: "hand.tap") {
          Picker("", selection: $draft.touchInputType) {
            Text("Multi-Touch").tag("Multi-Touch")
            Text("Touchpad").tag("Touchpad")
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
        }
        WWNEditorToggleRow("Swap CMD with ALT", icon: "command", isOn: $draft.swapCmdWithAlt)
        WWNEditorToggleRow("Universal Clipboard", icon: "doc.on.clipboard", isOn: $draft.universalClipboard)
      }
    }
  }
}

struct WWNMachineGraphicsEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: "cpu",
      title: "Graphics",
      tint: .red,
      info: "Per-machine overrides for the global Settings → Graphics values. Driver defaults are picked for the hardware automatically."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorFieldRow("Vulkan Driver", icon: "cube") {
          Picker("", selection: $draft.vulkanDriver) {
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
        WWNEditorFieldRow("OpenGL Driver", icon: "triangle") {
          Picker("", selection: $draft.openGLDriver) {
            Text("None").tag("none")
            Text("ANGLE").tag("angle")
          }
          .wwnPlatformPickerStyle()
          .labelsHidden()
        }
        WWNEditorToggleRow("Enable DMABUF", icon: "square.on.square", isOn: $draft.dmabufEnabled)
        WWNEditorToggleRow(
          "Enable HDR",
          icon: "sun.max",
          footnote: "Color profiles and HDR via the color operations pipeline.",
          isOn: $draft.colorOperations
        )
      }
    }
  }
}

// MARK: - Environment Variables

struct WWNEnvironmentVariablesEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft
  var onEdit: () -> Void

  var body: some View {
    WWNEditorCard(
      icon: "list.bullet.rectangle",
      title: "Environment Variables",
      tint: .teal,
      info: "Per-machine overrides for variables Wawona injects. Inherited (dimmed) rows use global Settings → Environment Variables until you override them."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        Button(action: onEdit) {
          HStack {
            Text("Edit Environment Variables…")
            Spacer()
            Text(draft.environmentOverrides.isEmpty ? "Inherit global" : "\(draft.environmentOverrides.count) override(s)")
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wwn.settings.environment.machine")

        if !draft.environmentOverrides.isEmpty {
          Divider()
          ForEach(draft.environmentOverrides.keys.sorted(), id: \.self) { name in
            HStack {
              Text(name)
                .font(.body.monospaced())
              Spacer()
              if let override = draft.environmentOverrides[name] {
                Text(override.action == .unset ? "(unset)" : (override.value ?? ""))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
            .font(.caption)
          }
          Button("Clear machine overrides") {
            draft.environmentOverrides = [:]
          }
          .foregroundStyle(.red)
        }
      }
    }
  }
}

// MARK: - Session Exit

struct WWNSessionExitEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: "rectangle.portrait.and.arrow.right",
      title: "Session Exit",
      tint: .orange,
      info: "Per-machine overrides for closing an active session."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorToggleRow("Shake to Exit Machine", icon: "iphone.gen3", isOn: $draft.shakeToCloseEnabled)
        WWNEditorToggleRow("Swipe Back to Exit Machine", icon: "hand.draw", isOn: $draft.swipeBackToCloseEnabled)
      }
    }
  }
}

// MARK: - Virtual Machine

struct WWNVirtualMachineEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: "desktopcomputer.and.macbook",
      title: "Virtual Machine",
      tint: .indigo,
      info: "The VM engine is fixed per build target (QEMU + Hypervisor.framework on macOS; QEMU-TCTI on iOS; QEMU + KVM/TCG on Android) and is not user-configurable."
    ) {
      WWNEditorFieldRow("Backend", icon: "cpu") {
        Text("QEMU + HVF")
          .foregroundStyle(.secondary)
      }
    }
  }
}
