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
  @State private var remoteCommand: String
  @State private var vmSubtype: String
  @State private var containerSubtype: String

  @State private var selectedClientId: String
  @State private var customCommand: String
  @State private var enableLauncher: Bool
  @State private var customIsNestedCompositor: Bool

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
    _remoteCommand = State(initialValue: initial?.remoteCommand ?? "")
    _vmSubtype = State(initialValue: initial?.vmSubtype ?? "qemu")
    _containerSubtype = State(initialValue: initial?.containerSubtype ?? "docker")

    let runtimeOverrides: [String: Any] = initial?.runtimeOverrides ?? [:]
    let overrides: [String: Any] = initial?.settingsOverrides ?? [:]
    _enableLauncher = State(initialValue: (runtimeOverrides["useBundledApp"] as? Bool) ?? ((overrides["EnableLauncher"] as? Bool) ?? false))
    _customCommand = State(initialValue: (overrides["NativeCustomCommand"] as? String) ?? "")
    _customIsNestedCompositor = State(initialValue: (overrides["RenderMacOSPointer"] as? Bool) == false)

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
      _selectedClientId = State(initialValue: "weston")
    }
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
          }

          if type == kWWNMachineTypeNative {
            nativeClientSection
          }

          if isRemote {
            remoteConnectivitySection
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
        customClientOption

        Divider()

        Toggle(isOn: $enableLauncher) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Client Launcher")
              .font(.subheadline.weight(.semibold))
            Text("Allow launching additional Wayland clients from the compositor")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .toggleStyle(.switch)
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
      labeledField("Password") {
        SecureField("Optional", text: $sshPassword)
          .textFieldStyle(.roundedBorder)
      }
      labeledField("SSH Key Path") {
        TextField("~/.ssh/id_ed25519", text: $sshKeyPath)
          .textFieldStyle(.roundedBorder)
          .wwnDisableAutocapitalization()
      }
      labeledField(isWaypipe ? "Remote Command" : "SSH Command") {
        TextField(isWaypipe ? "weston-terminal" : "bash -l", text: $remoteCommand)
          .textFieldStyle(.roundedBorder)
      }
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
        TextField("weston-terminal", text: $remoteCommand)
          .textFieldStyle(.roundedBorder)
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
    profile.remoteCommand = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.vmSubtype = vmSubtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "qemu" : vmSubtype
    profile.containerSubtype =
      containerSubtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "docker" : containerSubtype

    var overrides: [String: Any] = profile.settingsOverrides
    var runtimeOverrides: [String: Any] = profile.runtimeOverrides
    overrides["NativeClientId"] = selectedClientId
    overrides["NativeCustomCommand"] = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    overrides["EnableLauncher"] = enableLauncher
    overrides["WestonEnabled"] = selectedClientId == "weston"
    overrides["WestonTerminalEnabled"] = selectedClientId == "weston-terminal"
    overrides["WestonSimpleSHMEnabled"] = selectedClientId == "weston-simple-shm"
    overrides["FootEnabled"] = selectedClientId == "foot"

    let isNested: Bool
    if selectedClientId == kNativeClientCustomId {
      isNested = customIsNestedCompositor
    } else {
      isNested = kBundledClients.first(where: { $0.id == selectedClientId })?.isNestedCompositor ?? false
    }
    overrides["RenderMacOSPointer"] = !isNested

    runtimeOverrides["useBundledApp"] = enableLauncher
    runtimeOverrides["bundledAppID"] = selectedClientId
    runtimeOverrides["waypipeEnabled"] = (type == kWWNMachineTypeSSHWaypipe || type == kWWNMachineTypeSSHTerminal)
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
