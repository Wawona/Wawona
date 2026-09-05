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

  @Environment(\.dismiss) private var dismiss

  @StateObject private var draft: WWNMachineEditorDraft
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
    _draft = StateObject(
      wrappedValue: WWNMachineEditorDraft(profile: initial, defaultType: defaultType)
    )
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
          Text("tvOS supports Native and Remote (SSH) machines only.")
        }

        if draft.type == kWWNMachineTypeNative {
          Section("Wayland Client") {
            NavigationLink {
              WWNNativeClientPickerView(
                selectedClientId: $draft.selectedClientId
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
            if draft.selectedClientId == kNativeClientCustomId {
              WWNTvFormTextField("Custom command", text: $draft.customCommand, prompt: "/usr/bin/my-wayland-app")
              Text("e.g. /usr/bin/my-wayland-app")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            #endif
            if draft.selectedClientId == kNativeClientWasmId {
              WWNTvFormTextField("Wasm module path", text: $draft.wasmModulePath)
            }
          }
        }

        if draft.isRemote {
          Section("Remote SSH") {
            WWNTvFormTextField("Host", text: $draft.sshHost)
            WWNTvFormTextField("User", text: $draft.sshUser)
            WWNTvFormTextField("Port", text: $draft.sshPort)
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
            WWNTvFormTextField("Remote Command", text: $draft.remoteCommand)
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
          Button("Open Wawona Settings…") {
            WWNPreferences.shared().show(nil)
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
            draftMachineOverrides: $draft.environmentOverrides
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
  #endif

  // MARK: - macOS / iOS card layout

  private var desktopMobileEditorBody: some View {
    NavigationStack(path: $editorPath) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          WWNMachineProfileEditorSection(draft: draft)

          if draft.type == kWWNMachineTypeNative {
            WWNNativeClientEditorSection(draft: draft)
          }

          if draft.type == kWWNMachineTypeContainer {
            WWNContainerEditorSection(draft: draft)
          }

          if draft.isRemote {
            WWNRemoteSSHEditorSection(draft: draft)
            WWNWaypipeEditorSection(draft: draft)
            WWNLaunchCommandEditorSection(command: draft.previewCommand)
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
            selectedClientId: $draft.selectedClientId,
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
            draftMachineOverrides: $draft.environmentOverrides
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

  private var nativeClientSummary: String {
    if draft.selectedClientId == kNativeClientCustomId {
      return draft.customCommand.isEmpty ? "Custom Command" : draft.customCommand
    }
    if draft.selectedClientId == kNativeClientWasmId {
      if draft.wasmModulePath.isEmpty { return "Wawona Runtime (.wasm)" }
      return (draft.wasmModulePath as NSString).lastPathComponent
    }
    return kBundledClients.first { $0.id == draft.selectedClientId }?.name ?? draft.selectedClientId
  }

  private func openGlobalSettings() {
    #if os(iOS) || os(tvOS) || os(visionOS)
    WWNPreferences.shared().show(nil)
    #elseif os(macOS)
    WWNPreferences.shared().show(NSApp)
    #endif
  }

  private func popEditorRoute() {
    if !editorPath.isEmpty {
      editorPath.removeLast()
    }
  }

  // MARK: - Save

  private func save() {
    let profile = draft.makeProfile(initial: initial)
    onSave(profile)
    dismiss()
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

// MARK: - Bundled client picker (shared macOS / iOS / tvOS)

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
