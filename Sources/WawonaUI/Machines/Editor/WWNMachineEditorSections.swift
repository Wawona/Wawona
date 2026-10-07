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
      info: "Three kinds only. Native Shell covers Wawona Terminal, Wayland clients, Wasm, and Waypipe (with optional SSH)."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorFieldRow("Display Name") {
          WawonaTextField("e.g. Studio Linux VM", text: $draft.name)
            .textFieldStyle(.roundedBorder)
            .wwnA11y(WWNA11y.machinesEditorName, label: "Display Name")
        }
        WWNEditorFieldRow("Type") {
          Picker("", selection: $draft.type) {
            machineTypeOption("Native Shell", kWWNMachineTypeNative, "terminal")
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
    WawonaLabel(name, systemImage: symbol).tag(value)
  }
}

/// Native Shell session mode: Terminal, Wayland, Wasm, or Waypipe.
struct WWNNativeShellSessionEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  var body: some View {
    WWNEditorCard(
      icon: "square.stack.3d.up",
      title: "Native Shell Session",
      tint: .blue,
      info: "Pick how this machine starts. Terminal is Wawona Terminal (local or SSH). Wayland and Wasm run as clients. Waypipe streams a remote or local compositor."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Session", selection: $draft.nativeShellKind) {
          Text("Terminal").tag(kWWNNativeShellKindTerminal)
          Text("Wayland").tag(kWWNNativeShellKindWayland)
          Text("Wasm").tag(kWWNNativeShellKindWasm)
          Text("Waypipe").tag(kWWNNativeShellKindWaypipe)
        }
        .pickerStyle(.segmented)
        .wwnA11y("wwn.machines.editor.nativeShell.kind", label: "Native Shell Session")

        if draft.nativeShellKind == kWWNNativeShellKindTerminal
          || draft.nativeShellKind == kWWNNativeShellKindWaypipe {
          WWNEditorToggleRow(
            "Use SSH",
            icon: "lock.shield",
            footnote: draft.nativeShellKind == kWWNNativeShellKindTerminal
              ? "Off: local Wawona Terminal. On: SSH into a remote shell."
              : "Off: local waypipe. On: SSH + waypipe to a remote host.",
            isOn: $draft.nativeShellUseSSH
          )
        }

        if draft.nativeShellKind == kWWNNativeShellKindTerminal {
          WWNEditorFieldRow("Custom Command", icon: "terminal") {
            WWNEditorCodeField(
              draft.nativeShellUseSSH ? "e.g. bash -l" : "e.g. htop (empty = interactive shell)",
              text: $draft.customCommand
            )
          }
          WWNEditorCaption(
            text: draft.nativeShellUseSSH
              ? "Command to run in the remote SSH session. Empty defaults to bash -l."
              : "Optional command for Wawona Terminal. Empty opens an interactive shell. Not foot and not weston-terminal."
          )
        }
      }
    }
  }
}

// MARK: - Native client

/// Native machines: bundled Wayland client or WASM module.
struct WWNNativeClientEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  @State private var showWasmFileImporter = false

  var body: some View {
    WWNEditorCard(
      icon: "app.badge.checkmark",
      title: "Wayland Software",
      tint: .blue,
      info: "Compositors first, then clients by type (Terminals, Graphics, Demos, Other). Custom commands belong under Terminal."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WWNEditorFieldRow("Bundled Software", icon: clientIcon) {
          NavigationLink(destination: WWNNativeClientPickerView(selectedClientId: $draft.selectedClientId)) {
            HStack(spacing: 6) {
              Text(clientSummary)
                .foregroundColor(.secondary)
                .lineLimit(1)
              #if os(macOS)
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.65))
              #endif
            }
          }
          #if os(macOS)
          .buttonStyle(.plain)
          #endif
        }

        if draft.selectedClientId == kNativeClientWasmId {
          wasmRows
        }
      }
    }
  }

  private var clientSummary: String {
    if draft.selectedClientId == kNativeClientWasmId {
      if draft.wasmModulePath.isEmpty { return "Wawona Runtime (.wasm)" }
      return (draft.wasmModulePath as NSString).lastPathComponent
    }
    return kBundledClients.first { $0.id == draft.selectedClientId }?.name ?? draft.selectedClientId
  }

  private var clientIcon: String? {
    return kBundledClients.first { $0.id == draft.selectedClientId }?.icon
  }

  private var wasmRows: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(draft.wasmModulePath.isEmpty ? "No .wasm selected" : draft.wasmModulePath)
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(3)
        #if !os(tvOS)
        .backport.selectableText()
        #endif
      HStack(spacing: 10) {
        WWNEditorCodeField("Path to .wasm", text: $draft.wasmModulePath)
        WawonaButton("Choose…") {
          showWasmFileImporter = true
        }
        .backport.borderedButton()
        if !draft.wasmModulePath.isEmpty {
          WawonaButton("Clear", role: .destructive) {
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
    .backport.fileImporter(
      isPresented: $showWasmFileImporter,
      allowedContentTypes: [.filenameExtension("wasm")]
    ) { result in
      guard case .success(let url) = result else { return }
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }
      // Prefer copying into Documents/Wawona so sandboxed relaunches keep the file.
      if let stable = Self.importWasmModule(from: url) {
        draft.wasmModulePath = stable
      }
    }
    #endif
  }

  /// Copy a picked `.wasm` into Application Support / Documents so the path survives.
  static func importWasmModule(from url: URL) -> String? {
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

// MARK: - Wasm

/// Machines kind `wasm`: local file, wasm catalog, or a native-shell command.
struct WWNWasmEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  @State private var showWasmFileImporter = false
  @State private var showWasmCatalog = false
  @State private var catalogNote: String?

  var body: some View {
    WWNEditorCard(
      icon: "doc.badge.gearshape",
      title: "Wasm",
      tint: .purple,
      info: "Same as native shell: wasm hello-wasi-gui. Pick a local .wasm, search repo.wawona.io /wasm/v1, or type the wpm / wasm command. Native machines still run wasm from the shell."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Source", selection: $draft.wasmLaunchMode) {
          Text("Local file").tag("file")
          Text("Search repo").tag("repo")
          Text("Command").tag("command")
        }
        .pickerStyle(.segmented)
        .wwnA11y(WWNA11y.machinesEditorWasmSource, label: "Wasm source")

        switch draft.wasmLaunchMode {
        case "file":
          localFileRows
        case "repo":
          repoRows
        default:
          commandRows
        }

        if let catalogNote {
          WWNEditorCaption(text: catalogNote)
        }

        WWNEditorCaption(
          text: "Start runs wasm <file|package>. Empty file uses bundled hello-wasi-gui."
        )
      }
    }
    .sheet(isPresented: $showWasmCatalog) {
      WWNWasmCatalogSearchView { pkg in
        Task { await applyCatalogPackage(pkg) }
      }
    }
    #if !os(tvOS)
    .backport.fileImporter(
      isPresented: $showWasmFileImporter,
      allowedContentTypes: [.filenameExtension("wasm")]
    ) { result in
      guard case .success(let url) = result else { return }
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }
      if let stable = WWNNativeClientEditorSection.importWasmModule(from: url) {
        applyLocalFile(stable)
      } else {
        catalogNote = "Could not copy the selected module into Wawona."
      }
    }
    #endif
  }

  private var localFileRows: some View {
    VStack(alignment: .leading, spacing: 8) {
      WWNEditorFieldRow("Module", icon: "doc") {
        HStack(spacing: 8) {
          WWNEditorCodeField("hello-wasi-gui.wasm in Wawona/wasm-modules", text: $draft.wasmModulePath)
          #if !os(tvOS)
          WawonaButton("Choose…") { showWasmFileImporter = true }
            .backport.borderedButton()
          #endif
        }
      }
      let locals = WasmLaunch.listLocalModules()
      let installed = WasmLaunch.listInstalledWpmPackages()
      if !locals.isEmpty || !installed.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          if !locals.isEmpty {
            Text("Wawona folder")
              .font(.caption.weight(.semibold))
              .foregroundColor(.secondary)
            ForEach(locals, id: \.path) { url in
              WawonaButton(url.lastPathComponent) { applyLocalFile(url.path) }
                .buttonStyle(.borderless)
            }
          }
          if !installed.isEmpty {
            Text("wpm installed")
              .font(.caption.weight(.semibold))
              .foregroundColor(.secondary)
            ForEach(installed, id: \.name) { pkg in
              WawonaButton("\(pkg.name)  \((pkg.path as NSString).lastPathComponent)") {
                draft.wasmPackage = pkg.name
                draft.wasmModulePath = pkg.path
                draft.wasmCommand = "wasm \(pkg.name)"
              }
              .buttonStyle(.borderless)
            }
          }
        }
      }
    }
  }

  private var repoRows: some View {
    VStack(alignment: .leading, spacing: 8) {
      WWNEditorFieldRow("Package", icon: "shippingbox") {
        HStack(spacing: 8) {
          WWNEditorCodeField("hello-wasi-gui", text: $draft.wasmPackage)
          WawonaButton {
            showWasmCatalog = true
          } label: {
            WawonaLabel("Search catalog", systemImage: "magnifyingglass")
          }
          .wwnA11y(WWNA11y.machinesEditorWasmHub, label: "Search wasm catalog")
        }
      }
    }
  }

  private var commandRows: some View {
    VStack(alignment: .leading, spacing: 8) {
      WWNEditorFieldRow("Command", icon: "terminal") {
        WWNEditorCodeField("wasm hello-wasi-gui", text: $draft.wasmCommand)
          .wwnA11y(WWNA11y.machinesEditorWasmCommand, label: "Wasm command")
      }
      WWNEditorCaption(
        text: "Typed as in zsh: wasm hello-wasi-gui, wasm ./app.wasm, or wpm install hello-wasi-gui."
      )
    }
  }

  private func applyLocalFile(_ path: String) {
    draft.wasmModulePath = path
    draft.wasmPackage = ""
    draft.wasmCommand = "wasm \(path)"
    draft.wasmLaunchMode = "file"
  }

  private func applyCatalogPackage(_ pkg: WWNWasmCatalogPackage) async {
    draft.wasmPackage = pkg.name
    draft.wasmCommand = "wasm \(pkg.name)"
    draft.wasmLaunchMode = "repo"
    do {
      let path = try await WWNWasmCatalogClient.download(pkg)
      draft.wasmModulePath = path
      catalogNote = "Saved \(pkg.name) to the Wawona folder."
    } catch {
      draft.wasmModulePath = ""
      catalogNote = error.localizedDescription
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
            .foregroundColor(.secondary)
        }
        WWNEditorFieldRow("Image", icon: "shippingbox") {
          HStack(spacing: 8) {
            WWNEditorCodeField("e.g. alpine:3.20 or python:3.12-slim", text: $draft.containerRef)
              .wwnA11y(WWNA11y.machinesEditorContainerRef, label: "Container Image")
            #if os(macOS)
            WawonaButton {
              showContainerHubSearch = true
            } label: {
              WawonaLabel("Search Docker Hub", systemImage: "magnifyingglass")
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
    #if os(macOS)
    .backport.fileImporter(
      isPresented: $showContainerArchiveImporter,
      allowedContentTypes: [.item, .directory]
    ) { result in
      handleContainerArchiveImport(result)
    }
    #endif
  }

  @ViewBuilder
  private var archiveRows: some View {
    WawonaButton {
      showContainerArchiveImporter = true
    } label: {
      WawonaLabel("Import image archive…", systemImage: "square.and.arrow.down")
    }
    .disabled(containerImporting)
    if containerImporting {
      HStack(spacing: 6) {
        WawonaProgressView().backport.controlSize(.small)
        Text("Importing…").font(.caption).foregroundColor(.secondary)
      }
    }
    if let containerImportNote {
      Text(containerImportNote)
        .font(.caption)
        .foregroundColor(containerImportNote.hasPrefix("imported") ? .green : .red)
    }
    if !draft.imageArchivePath.isEmpty {
      HStack {
        Image(systemName: "internaldrive").foregroundColor(.secondary)
        Text("Archive: \((draft.imageArchivePath as NSString).lastPathComponent)")
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        WawonaButton("Clear") {
          draft.imageArchivePath = ""
          draft.containerRef = ""
          containerImportNote = nil
        }
        .buttonStyle(.borderless)
        .backport.controlSize(.small)
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
      let path = url.path
      containerImporting = true
      containerImportNote = nil
      Task {
        defer { url.stopAccessingSecurityScopedResource() }
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
          WWNEditorNumberField(text: $draft.sshPort, range: 1...65_535)
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
            WawonaButton("Generate Key", systemImage: "key") {
              if let path = try? WWNSSHKeygen.generateKeyType(
                "ed25519", passphrase: draft.sshKeyPassphrase
              ) {
                draft.sshKeyPath = path
                draft.sshAuthMethod = 1
              }
            }
            .backport.borderedButton()
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

        // Terminal Custom Command lives under Native Shell Session. Waypipe keeps Remote Command here.
        if draft.isWaypipeMachine {
          WWNEditorFieldRow("Remote Command", icon: "terminal") {
            WWNEditorCodeField("weston-simple-shm", text: $draft.remoteCommand)
          }
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
          WWNEditorNumberField(text: $draft.waypipeDisplayNumber, range: 0...255)
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
          WWNEditorNumberField(text: $draft.waypipeCompressLevel, range: 1...22)
        }
        WWNEditorFieldRow("Threads", icon: "cpu") {
          WWNEditorNumberField(text: $draft.waypipeThreads, range: 0...64)
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
          WWNEditorNumberField(
            text: $draft.waypipeVideoBpf,
            range: 1_000...100_000,
            automaticWhenEmpty: true
          )
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
          .foregroundColor(.secondary)
        Text("Per-Machine Overrides")
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.secondary)
        WWNEditorInfoButton(
          text: "Each card overrides the matching global default from Wawona Settings. Leave a control untouched to keep inheriting the global value."
        )
        Spacer()
        WawonaButton(action: onOpenSettings) {
          WawonaLabel("Open Wawona Settings", systemImage: "gearshape")
        }
        .backport.borderedButton()
        .backport.controlSize(.small)
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
          .backport.help(draft.openGLDriver == "none"
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
              .foregroundColor(.secondary)
              .frame(width: 18)
            Text("Nested compositor (weston, niri, or custom) draws its own cursor. The host virtual pointer stays hidden.")
              .font(.caption)
              .foregroundColor(.secondary)
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
        WWNEditorToggleRow(
          "Resize Display for Virtual Keyboard",
          icon: "keyboard.chevron.compact.down",
          footnote: "iOS and iPadOS shrink the Wayland output and shift the client above the OSK, like postmarketOS. A hardware keyboard leaves the client full size.",
          isOn: $draft.resizeDisplayForVirtualKeyboard
        )
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
      tint: WWNTagPalette.teal,
      info: "Per-machine overrides for variables Wawona injects. Inherited (dimmed) rows use global Settings → Environment Variables until you override them."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        WawonaButton(action: onEdit) {
          HStack {
            Text("Edit Environment Variables…")
            Spacer()
            Text(draft.environmentOverrides.isEmpty ? "Inherit global" : "\(draft.environmentOverrides.count) override(s)")
              .foregroundColor(.secondary)
          }
        }
        .buttonStyle(.plain)
        .accessibility(identifier: "wwn.settings.environment.machine")

        if !draft.environmentOverrides.isEmpty {
          Divider()
          ForEach(draft.environmentOverrides.keys.sorted(), id: \.self) { name in
            HStack {
              Text(name)
                .font(.system(.body, design: .monospaced))
              Spacer()
              if let override = draft.environmentOverrides[name] {
                Text(override.action == .unset ? "(unset)" : (override.value ?? ""))
                  .foregroundColor(.secondary)
                  .lineLimit(1)
              }
            }
            .font(.caption)
          }
          WawonaButton("Clear Machine Overrides", systemImage: "arrow.counterclockwise") {
            draft.environmentOverrides = [:]
          }
          .foregroundColor(.red)
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
