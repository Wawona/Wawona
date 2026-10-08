import SwiftUI
import WawonaModel

/// Add / Edit machine profile editor.
///
/// Layout and state are split for separation of concerns:
/// - `WWNMachineEditorDraft`      — persisted fields, seeding, save mapping
/// - `WWNMachineEditorSections`   — one view per card (profile, client,
///   SSH, waypipe, display/input/graphics, env, session exit, …)
/// - `WWNMachineEditorComponents` — cross-platform card / row / field kit
///
/// tvOS keeps its dedicated 10-foot Form body below; macOS and iOS share the
/// card layout.
struct WWNMachineEditorView: View {
  let title: String
  let initial: WWNMachineProfile?
  let defaultType: String
  let onSave: (WWNMachineProfile) -> Void

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
  }

  var body: some View {
    #if os(iOS)
    if #available(iOS 16.0, *) {
      WWNMachineEditorViewModern(
        title: title,
        initial: initial,
        defaultType: defaultType,
        onSave: onSave
      )
    } else {
      WWNMachineEditorViewLegacy(
        title: title,
        initial: initial,
        defaultType: defaultType,
        onSave: onSave
      )
    }
    #else
    WWNMachineEditorViewModern(
      title: title,
      initial: initial,
      defaultType: defaultType,
      onSave: onSave
    )
    #endif
  }
}

#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNMachineEditorViewModern: View {
  let title: String
  let initial: WWNMachineProfile?
  let defaultType: String
  let onSave: (WWNMachineProfile) -> Void

  @Environment(\.presentationMode) private var presentationMode

  @WawonaStateObject private var draft: WWNMachineEditorDraft
  @State private var showEnvironmentEditor = false

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
    _draft = WawonaStateObject(
      wrappedValue: WWNMachineEditorDraft(profile: initial, defaultType: defaultType)
    )
  }

  private func dismiss() {
    presentationMode.wrappedValue.dismiss()
  }

  var body: some View {
    #if os(tvOS)
    tvosEditorBody
    #else
    desktopMobileEditorBody
    #endif
  }

  // MARK: - tvOS (10-foot Form; Siri Remote)

  #if os(tvOS)
  private var tvosEditorBody: some View {
    NavigationStack {
      Form {
        Section {
          WWNTvFormTextField("Display Name", text: $draft.name, prompt: "Enter a name")
          Picker("Type", selection: $draft.type) {
            machineTypeOptions
          }
          .pickerStyle(.navigationLink)
          Toggle("Show Session Thumbnail", isOn: $draft.machineThumbnailEnabled)
        } header: {
          Text("Connection Profile")
        } footer: {
          Text("tvOS supports Native Shell only (Terminal, Wayland, Wasm, Waypipe). VM and Container are hidden.")
        }

        if draft.type == kWWNMachineTypeNative {
          Section("Native Shell Session") {
            Picker("Session", selection: $draft.nativeShellKind) {
              Text("Terminal").tag(kWWNNativeShellKindTerminal)
              Text("Wayland").tag(kWWNNativeShellKindWayland)
              Text("Wasm").tag(kWWNNativeShellKindWasm)
              Text("Waypipe").tag(kWWNNativeShellKindWaypipe)
            }
            .pickerStyle(.navigationLink)
            if draft.nativeShellKind == kWWNNativeShellKindTerminal
              || draft.nativeShellKind == kWWNNativeShellKindWaypipe {
              Toggle("Use SSH", isOn: $draft.nativeShellUseSSH)
            }
            if draft.nativeShellKind == kWWNNativeShellKindTerminal {
              WWNTvFormTextField(
                "Custom command",
                text: $draft.customCommand,
                prompt: draft.nativeShellUseSSH ? "bash -l" : "htop (empty = interactive shell)"
              )
            }
          }

          if draft.nativeShellKind == kWWNNativeShellKindWasm {
            Section("Wasm") {
              Picker("Source", selection: $draft.wasmLaunchMode) {
                Text("Local file").tag("file")
                Text("Search repo").tag("repo")
                Text("Command").tag("command")
              }
              .pickerStyle(.navigationLink)
              if draft.wasmLaunchMode == "file" {
                WWNTvFormTextField("Wasm module path", text: $draft.wasmModulePath)
              } else if draft.wasmLaunchMode == "repo" {
                WWNTvFormTextField("Package", text: $draft.wasmPackage, prompt: "hello-wasi-gui")
                NavigationLink {
                  WWNWasmCatalogSearchView { pkg in
                    Task {
                      draft.wasmPackage = pkg.name
                      draft.wasmCommand = "wasm \(pkg.name)"
                      draft.wasmLaunchMode = "repo"
                      if let path = try? await WWNWasmCatalogClient.download(pkg) {
                        draft.wasmModulePath = path
                      }
                    }
                  }
                } label: {
                  Label("Search Catalog", systemImage: "magnifyingglass")
                }
              } else {
                WWNTvFormTextField("Command", text: $draft.wasmCommand, prompt: "wasm hello-wasi-gui")
              }
            }
          }

          if draft.nativeShellKind == kWWNNativeShellKindWayland {
            Section("Wayland Software") {
              NavigationLink {
                WWNNativeClientPickerView(
                  selectedClientId: $draft.selectedClientId
                )
              } label: {
                HStack {
                  Text("Bundled Software")
                  Spacer()
                  Text(nativeClientSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }
            }
          }
        }

        if draft.isRemote {
          Section("Remote SSH") {
            WWNTvFormTextField("Host", text: $draft.sshHost)
            WWNTvFormTextField("User", text: $draft.sshUser)
            WWNTvFormTextField(
              "Port",
              text: $draft.sshPort,
              prompt: "22",
              numericRange: 1...65_535
            )
            Picker("Auth", selection: $draft.sshAuthMethod) {
              Text("Password").tag(0)
              Text("Public Key").tag(1)
            }
            .pickerStyle(.navigationLink)
            if draft.sshAuthMethod == 0 {
              WWNTvFormTextField("Password", text: $draft.sshPassword, secure: true)
            } else {
              WWNTvFormTextField("Key Path", text: $draft.sshKeyPath)
              WWNTvFormTextField("Key Passphrase", text: $draft.sshKeyPassphrase, secure: true)
            }
            if draft.isWaypipeMachine {
              WWNTvFormTextField("Remote Command", text: $draft.remoteCommand)
            }
          }

          Section("Waypipe") {
            Picker("Compress", selection: $draft.waypipeCompress) {
              Text("None").tag("none")
              Text("LZ4").tag("lz4")
              Text("Zstd").tag("zstd")
            }
            .pickerStyle(.navigationLink)
            Toggle("Debug", isOn: $draft.waypipeDebug)
            Toggle("Login Shell", isOn: $draft.waypipeLoginShell)
            Toggle("XWayland", isOn: $draft.waypipeXwls)
          }

          Section("Command Preview") {
            Text(draft.previewCommand)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }

        Section {
          Toggle("Auto Scale", isOn: $draft.autoScale)
          Toggle("Respect Safe Area", isOn: $draft.respectSafeArea)
          Picker("Display Backend", selection: $draft.compositorBackend) {
            Text("Auto").tag("auto")
            Text("Wayland (nested)").tag("wayland")
            Text("DRM/KMS (wwn-iland)").tag("drm")
          }
          .pickerStyle(.navigationLink)
          Button("Open Wawona Settings", systemImage: "gearshape") {
            openGlobalSettings()
          }
        } header: {
          Text("Display")
        } footer: {
          Text("Nested weston/niri use Wayland. DRM is userspace iland, not a real /dev/dri node.")
        }

        Section {
          Picker("Vulkan Driver", selection: $draft.vulkanDriver) {
            Text("None").tag("none")
            if PlatformCapabilities.allowsGpuStack {
              Text("MoltenVK").tag("moltenvk")
            }
          }
          .pickerStyle(.navigationLink)
          Picker("OpenGL Driver", selection: $draft.openGLDriver) {
            Text("None").tag("none")
            if PlatformCapabilities.allowsGlesStack {
              Text("ANGLE").tag("angle")
            }
          }
          .pickerStyle(.navigationLink)
          Toggle("Enable DMABUF", isOn: $draft.dmabufEnabled)
          Toggle("Enable HDR", isOn: $draft.colorOperations)
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
                draft.environmentOverrides.isEmpty
                  ? "Inherit global"
                  : "\(draft.environmentOverrides.count) override(s)"
              )
              .foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("wwn.settings.environment.machine")
        }

        Section {
          Toggle("Menu / Shake to Exit Machine", isOn: $draft.shakeToCloseEnabled)
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
            .backport.glassToolbarButton()
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .backport.glassProminentToolbarButton()
        }
      }
      .fullScreenCover(isPresented: $showEnvironmentEditor) {
        NavigationStack {
          EnvironmentVariablesView(
            preferences: WawonaPreferences.shared,
            perMachine: true,
            draftMachineOverrides: $draft.environmentOverrides
          )
          .toolbar {
            ToolbarItem(placement: .navigation) {
              Button {
                showEnvironmentEditor = false
              } label: {
                Image(systemName: "chevron.left")
              }
              .backport.glassToolbarButton()
              .accessibilityLabel("Back")
            }
          }
        }
        .presentationBackground(Color(white: 0.07))
      }
    }
    .preferredColorScheme(.dark)
    .presentationBackground(Color(white: 0.07))
  }

  @ViewBuilder
  private var machineTypeOptions: some View {
    Text("Native Shell").tag(kWWNMachineTypeNative)
    #if !os(tvOS) && !os(watchOS)
    Text("Virtual Machine").tag(kWWNMachineTypeVirtualMachine)
    Text("Container").tag(kWWNMachineTypeContainer)
    #endif
  }
  #endif

  // MARK: - macOS / iOS card layout

  private var desktopMobileEditorBody: some View {
    WawonaBackport<Any>.navigation {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          WWNMachineProfileEditorSection(draft: draft)

          if draft.type == kWWNMachineTypeNative {
            WWNNativeShellSessionEditorSection(draft: draft)

            switch draft.nativeShellKind {
            case kWWNNativeShellKindWayland:
              WWNNativeClientEditorSection(draft: draft)
            case kWWNNativeShellKindWasm:
              WWNWasmEditorSection(draft: draft)
            case kWWNNativeShellKindWaypipe:
              if draft.nativeShellUseSSH {
                WWNRemoteSSHEditorSection(draft: draft)
              }
              WWNWaypipeEditorSection(draft: draft)
              if draft.nativeShellUseSSH {
                WWNLaunchCommandEditorSection(command: draft.previewCommand)
              }
            case kWWNNativeShellKindTerminal:
              if draft.nativeShellUseSSH {
                WWNRemoteSSHEditorSection(draft: draft)
                WWNLaunchCommandEditorSection(command: draft.previewCommand)
              }
            default:
              EmptyView()
            }
          }

          if draft.type == kWWNMachineTypeContainer {
            WWNContainerEditorSection(draft: draft)
          }

          WWNMachineOverridesHeader(onOpenSettings: openGlobalSettings)
          WWNMachineDisplayEditorSection(draft: draft)
          WWNMachineInputEditorSection(draft: draft)
          WWNMachineGraphicsEditorSection(draft: draft)

          WWNEnvironmentVariablesEditorSection(draft: draft) {
            showEnvironmentEditor = true
          }

          WWNSessionExitEditorSection(draft: draft)

          if draft.type == kWWNMachineTypeVirtualMachine {
            WWNVirtualMachineEditorSection(draft: draft)
          }
        }
        .padding(16)
        .frame(maxWidth: 880, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      .navigationTitle(title)
      .wwnA11y(WWNA11y.machinesEditor, label: title)
      .modifier(WWNEditorChromeToolbar(onCancel: dismiss, onSave: save))
      .sheet(isPresented: $showEnvironmentEditor) {
        WawonaBackport<Any>.navigation {
          EnvironmentVariablesView(
            preferences: WawonaPreferences.shared,
            perMachine: true,
            draftMachineOverrides: $draft.environmentOverrides
          )
          .modifier(WWNEditorEnvBackToolbar(onBack: { showEnvironmentEditor = false }))
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

  private var nativeClientSummary: String {
    if draft.selectedClientId == kNativeClientWasmId {
      if draft.wasmModulePath.isEmpty { return "Wawona Runtime (.wasm)" }
      return (draft.wasmModulePath as NSString).lastPathComponent
    }
    return kBundledClients.first { $0.id == draft.selectedClientId }?.name ?? draft.selectedClientId
  }

  private func openGlobalSettings() {
    #if os(macOS)
    WWNUnifiedWindowController.sharedController().showSettings()
    #elseif os(iOS) || os(tvOS) || os(visionOS)
    WWNMainWindowRouter.shared.showSettings()
    #endif
  }

  // MARK: - Save

  private func save() {
    let profile = draft.makeProfile(initial: initial)
    onSave(profile)
    dismiss()
  }
}

// MARK: - Editor chrome (iOS 13: navigationBarItems; iOS 14+: toolbar)

private struct WWNEditorChromeToolbar: ViewModifier {
  let onCancel: () -> Void
  let onSave: () -> Void

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
      content.toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
            .backport.glassToolbarButton()
            .wwnA11y(WWNA11y.machinesEditorCancel, label: "Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: onSave)
            .backport.glassProminentToolbarButton()
            .wwnA11y(WWNA11y.machinesEditorSave, label: "Save")
        }
      }
    } else {
      #if os(iOS)
      content.navigationBarItems(
        leading: Button("Cancel", action: onCancel),
        trailing: Button("Save", action: onSave)
      )
      #else
      content
      #endif
    }
  }
}

private struct WWNEditorEnvBackToolbar: ViewModifier {
  let onBack: () -> Void

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
      content.toolbar {
        ToolbarItem(placement: .navigation) {
          Button(action: onBack) {
            Image(systemName: "chevron.left")
          }
          .backport.glassToolbarButton()
          .accessibilityLabel("Back")
        }
      }
    } else {
      #if os(iOS)
      content.navigationBarItems(leading: Button("Back", action: onBack))
      #else
      content
      #endif
    }
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
#if os(iOS)
@available(iOS 16.0, *)
#endif
private struct WWNTvFormTextField: View {
  let title: String
  @Binding var text: String
  var prompt: String = ""
  var secure: Bool = false
  var numericRange: ClosedRange<Int>?

  @State private var showEditor = false
  @State private var draft = ""

  init(
    _ title: String,
    text: Binding<String>,
    prompt: String = "",
    secure: Bool = false,
    numericRange: ClosedRange<Int>? = nil
  ) {
    self.title = title
    self._text = text
    self.prompt = prompt
    self.secure = secure
    self.numericRange = numericRange
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
      Button("OK") {
        if let numericRange {
          let fallback = min(max(Int(text) ?? numericRange.lowerBound, numericRange.lowerBound), numericRange.upperBound)
          let parsed = Int(draft) ?? fallback
          text = String(min(max(parsed, numericRange.lowerBound), numericRange.upperBound))
        } else {
          text = draft
        }
      }
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

#if os(iOS)
/// Minimal Add/Edit form for iOS 13–14 hosts.
struct WWNMachineEditorViewLegacy: View {
  let title: String
  let initial: WWNMachineProfile?
  let defaultType: String
  let onSave: (WWNMachineProfile) -> Void

  @Environment(\.presentationMode) private var presentationMode
  @WawonaStateObject private var draft: WWNMachineEditorDraft

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
    _draft = WawonaStateObject(
      wrappedValue: WWNMachineEditorDraft(profile: initial, defaultType: defaultType)
    )
  }

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Machine Profile")) {
          TextField("Display Name", text: $draft.name)
          Picker("Type", selection: $draft.type) {
            Text("Native Shell").tag(kWWNMachineTypeNative)
            Text("Virtual Machine").tag(kWWNMachineTypeVirtualMachine)
            Text("Container").tag(kWWNMachineTypeContainer)
          }
        }
        if draft.type == kWWNMachineTypeNative {
          Section(header: Text("Native Shell Session")) {
            Picker("Session", selection: $draft.nativeShellKind) {
              Text("Terminal").tag(kWWNNativeShellKindTerminal)
              Text("Wayland").tag(kWWNNativeShellKindWayland)
              Text("Wasm").tag(kWWNNativeShellKindWasm)
              Text("Waypipe").tag(kWWNNativeShellKindWaypipe)
            }
            .pickerStyle(SegmentedPickerStyle())
          }
        }
      }
      .navigationBarTitle(Text(title), displayMode: .inline)
      .navigationBarItems(
        leading: Button("Cancel") { presentationMode.wrappedValue.dismiss() },
        trailing: Button("Save") {
          onSave(draft.makeProfile(initial: initial))
          presentationMode.wrappedValue.dismiss()
        }
      )
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }
}
#endif
