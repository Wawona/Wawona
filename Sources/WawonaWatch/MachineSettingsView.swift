#if os(watchOS)
import SwiftUI
import WawonaModel

/// Watch-local full per-machine configuration editor.
/// Parity with WawonaUI `MachineSettingsView` (watch stays independent of that module).
struct MachineSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    var machineID: String?

    @State private var selectedID: String?
    @State private var draft: MachineProfile?
    @State private var showingGlobalSettings = false

    var body: some View {
        Form {
            Section {
                Button("Open Wawona Settings…") {
                    WatchKitGlobalSettings.registerHost()
                    showingGlobalSettings = true
                }
                Text("Global defaults (Display, Graphics, Connection, SSH, Advanced). Values below override them for this machine only.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Machine") {
                if profileStore.profiles.isEmpty {
                    Text("No machine profiles available.")
                        .foregroundStyle(.secondary)
                } else if let machineID,
                          let profile = profileStore.profiles.first(where: { $0.id == machineID }) {
                    Text(profile.name)
                        .font(.headline)
                } else {
                    Picker("Profile", selection: Binding(
                        get: { selectedID ?? profileStore.profiles.first?.id ?? "" },
                        set: { value in
                            selectedID = value
                            loadDraft()
                        }
                    )) {
                        ForEach(profileStore.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                }
            }

            if let draft {
                machineConfigurationSection(for: draft)
                if draft.type == .sshWaypipe || draft.type == .sshTerminal {
                    sshWaypipeSection()
                }
                displaySection()
                inputSection()
                graphicsSection()
                advancedSection()
                resolvedPreviewSection(for: draft)
                actionsSection()
            }
        }
        .navigationTitle("Machine Settings")
        .onAppear {
            selectedID = machineID ?? profileStore.activeMachineId ?? profileStore.profiles.first?.id
            loadDraft()
        }
        .sheet(isPresented: $showingGlobalSettings) {
            WatchGlobalSettingsView()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func machineConfigurationSection(for profile: MachineProfile) -> some View {
        Section("Machine Configuration") {
            TextField("Name", text: nameBinding)
            Picker("Type", selection: typeBinding) {
                ForEach(PlatformCapabilities.availableMachineTypes, id: \.self) { t in
                    Text(t.userFacingName).tag(t)
                }
            }
            .pickerStyle(.navigationLink)

            if profile.type == .native {
                NavigationLink {
                    WatchBundledClientPickerView(selection: bundledAppIDSelectionBinding)
                } label: {
                    HStack {
                        Text("Wayland Client")
                        Spacer()
                        Text(ClientLauncher.displayName(for: resolvedBundledAppID))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let backend = profile.type.backendEngineLabel {
                LabeledContent("Backend", value: backend)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sshWaypipeSection() -> some View {
        Section("SSH / Waypipe") {
            TextField("Host", text: sshHostBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("User", text: sshUserBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Port", text: sshPortBinding)
            Picker("Auth", selection: sshAuthMethodBinding) {
                Text("Password").tag(0)
                Text("Public Key").tag(1)
            }
            if (draft?.sshAuthMethod ?? 0) == 0 {
                SecureField("Password", text: sshPasswordBinding)
            } else {
                TextField("Key Path", text: sshKeyPathBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Key Passphrase", text: sshKeyPassphraseBinding)
                Button("Generate ed25519 Key") {
                    if let path = try? WWNSSHKeygen.generateKeyType(
                        "ed25519",
                        passphrase: draft?.sshKeyPassphrase ?? ""
                    ) {
                        updateDraft {
                            $0.sshKeyPath = path
                            $0.sshAuthMethod = 1
                        }
                    }
                }
            }
            SecureField("Waypipe Password (optional)", text: waypipeSSHPasswordBinding)
            TextField("Remote Command", text: remoteCommandBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Toggle("Enable Waypipe", isOn: waypipeEnabledBinding)
                .disabled(draft?.type == .native)
        }
    }

    @ViewBuilder
    private func displaySection() -> some View {
        Section("Display") {
            // Force SSD is macOS-only (#120): watchOS always draws SSD, so the
            // toggle would be inert here.
            if PlatformCapabilities.supportsClientSideDecorations {
                Toggle("Force Server-Side Decorations", isOn: forceSSDBinding)
            }
            Toggle("Auto Scale", isOn: autoScaleBinding)
            TextField("Wayland Display", text: waylandDisplayBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private func inputSection() -> some View {
        Section("Input") {
            Toggle("Show Virtual Cursor", isOn: renderMacOSPointerBinding)
            Picker("Nested Compositor Cursor", selection: nestedCompositorCursorBinding) {
                Text("Virtual Pointer").tag("virtual")
                Text("Host Cursor").tag("host")
            }
            .disabled(!(draft?.runtimeOverrides.renderMacOSPointer ?? preferences.renderMacOSPointer))
            TextField("Input Profile", text: inputProfileBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text("Global default: \(preferences.defaultInputProfile)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func graphicsSection() -> some View {
        Section("Graphics") {
            Picker("Renderer", selection: rendererBinding) {
                Text("metal").tag("metal")
                Text("software").tag("software")
            }
            // watchOS has no GPU stack (ANGLE/Vulkan) — keep fields for profile
            // portability but mark them clearly.
            if PlatformCapabilities.allowsGpuStack {
                TextField("Vulkan Driver", text: vulkanDriverBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("OpenGL Driver", text: openGLDriverBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Enable DMABUF", isOn: dmabufEnabledBinding)
                Toggle("HDR / Color Operations", isOn: colorOperationsBinding)
            } else {
                Text("GPU stack not available on watchOS (native + remote only).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("HDR / Color Operations", isOn: colorOperationsBinding)
            }
        }
    }

    @ViewBuilder
    private func advancedSection() -> some View {
        Section("Advanced") {
            Picker("Log Level", selection: logLevelBinding) {
                Text("Debug").tag("debug")
                Text("Info").tag("info")
                Text("Warn").tag("warn")
                Text("Error").tag("error")
            }
            Toggle("Shake to Exit Machine", isOn: shakeToCloseBinding)
            Toggle("Swipe Back to Exit Machine", isOn: swipeBackToCloseBinding)
        }
    }

    @ViewBuilder
    private func resolvedPreviewSection(for profile: MachineProfile) -> some View {
        let resolved = preferences.resolvedSettings(for: profile)
        Section("Resolved Runtime (Machine > Global)") {
            Text("Renderer: \(resolved.renderer)")
            Text("Force SSD: \(resolved.forceSSD ? "On" : "Off")")
            Text("Virtual Cursor: \(resolved.renderMacOSPointer ? "On" : "Off")")
            Text("Nested Cursor: \(resolved.nestedCompositorCursor)")
            Text("Auto Scale: \(resolved.autoScale ? "On" : "Off")")
            Text("HDR: \(resolved.colorOperations ? "On" : "Off")")
            Text("Display: \(resolved.waylandDisplay)")
            Text("Input: \(resolved.inputProfile)")
            Text("Host: \(resolved.sshHost.isEmpty ? "—" : resolved.sshHost)")
            Text("User: \(resolved.sshUser.isEmpty ? "—" : resolved.sshUser)")
            Text("Port: \(resolved.sshPort)")
            Text("Waypipe: \(resolved.waypipeEnabled ? "On" : "Off")")
            Text("Bundled App: \(resolved.bundledAppID.isEmpty ? "Off" : resolved.bundledAppID)")
            Text("Log Level: \(resolved.logLevel)")
            Text("Shake to Exit: \(resolved.shakeToCloseEnabled ? "On" : "Off")")
            Text("Swipe Back to Exit: \(resolved.swipeBackToCloseEnabled ? "On" : "Off")")
        }
    }

    @ViewBuilder
    private func actionsSection() -> some View {
        Section {
            Button("Save Machine Settings") {
                guard var latest = draft else { return }
                if latest.type == .native {
                    let client = latest.runtimeOverrides.bundledAppID?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !client.isEmpty {
                        latest.launchers = ClientLauncher.presets.filter { $0.name == client }
                    }
                }
                profileStore.upsert(latest)
                profileStore.activeMachineId = latest.id
                profileStore.save()
                draft = latest
            }
        }
    }

    // MARK: - Draft helpers

    private func loadDraft() {
        guard var profile = profileStore.profiles.first(where: { $0.id == selectedID }) else {
            draft = nil
            return
        }
        if profile.type == .container || profile.type == .virtualMachine {
            profile.type = .native
        }
        draft = profile
    }

    private func updateDraft(_ mutate: (inout MachineProfile) -> Void) {
        guard var copy = draft else { return }
        mutate(&copy)
        draft = copy
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { draft?.name ?? "" },
            set: { value in updateDraft { $0.name = value } }
        )
    }

    private var typeBinding: Binding<MachineType> {
        Binding(
            get: { draft?.type ?? .native },
            set: { value in updateDraft { $0.type = value } }
        )
    }

    private var sshHostBinding: Binding<String> {
        Binding(
            get: { draft?.sshHost ?? "" },
            set: { value in updateDraft { $0.sshHost = value } }
        )
    }

    private var sshUserBinding: Binding<String> {
        Binding(
            get: { draft?.sshUser ?? "" },
            set: { value in updateDraft { $0.sshUser = value } }
        )
    }

    private var sshPortBinding: Binding<String> {
        Binding(
            get: { String(draft?.sshPort ?? 22) },
            set: { value in
                updateDraft { profile in
                    profile.sshPort = Int(value) ?? profile.sshPort
                }
            }
        )
    }

    private var sshPasswordBinding: Binding<String> {
        Binding(
            get: { draft?.sshPassword ?? "" },
            set: { value in updateDraft { $0.sshPassword = value } }
        )
    }

    private var sshAuthMethodBinding: Binding<Int> {
        Binding(
            get: { draft?.sshAuthMethod ?? 0 },
            set: { value in updateDraft { $0.sshAuthMethod = value } }
        )
    }

    private var sshKeyPathBinding: Binding<String> {
        Binding(
            get: { draft?.sshKeyPath ?? "" },
            set: { value in updateDraft { $0.sshKeyPath = value } }
        )
    }

    private var sshKeyPassphraseBinding: Binding<String> {
        Binding(
            get: { draft?.sshKeyPassphrase ?? "" },
            set: { value in updateDraft { $0.sshKeyPassphrase = value } }
        )
    }

    private var remoteCommandBinding: Binding<String> {
        Binding(
            get: { draft?.remoteCommand ?? "" },
            set: { value in updateDraft { $0.remoteCommand = value } }
        )
    }

    private var waypipeSSHPasswordBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.waypipeSSHPassword ?? preferences.waypipeSSHPassword },
            set: { value in updateDraft { $0.runtimeOverrides.waypipeSSHPassword = value } }
        )
    }

    private var resolvedBundledAppID: String {
        let raw = draft?.runtimeOverrides.bundledAppID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? preferences.defaultBundledAppID : raw
    }

    private var bundledAppIDSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedBundledAppID },
            set: { value in
                updateDraft { profile in
                    profile.runtimeOverrides.bundledAppID = value
                    profile.launchers = ClientLauncher.presets.filter { $0.name == value }
                }
            }
        )
    }

    private var waypipeEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft?.runtimeOverrides.waypipeEnabled ?? preferences.defaultWaypipeEnabled },
            set: { value in updateDraft { $0.runtimeOverrides.waypipeEnabled = value } }
        )
    }

    private var inputProfileBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.inputProfile ?? preferences.defaultInputProfile },
            set: { value in updateDraft { $0.runtimeOverrides.inputProfile = value } }
        )
    }

    private var rendererBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.renderer ?? preferences.renderer },
            set: { value in updateDraft { $0.runtimeOverrides.renderer = value } }
        )
    }

    private var vulkanDriverBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.vulkanDriver ?? preferences.vulkanDriver },
            set: { value in updateDraft { $0.runtimeOverrides.vulkanDriver = value } }
        )
    }

    private var openGLDriverBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.openGLDriver ?? "angle" },
            set: { value in updateDraft { $0.runtimeOverrides.openGLDriver = value } }
        )
    }

    private var dmabufEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft?.runtimeOverrides.dmabufEnabled ?? true },
            set: { value in updateDraft { $0.runtimeOverrides.dmabufEnabled = value } }
        )
    }

    private var forceSSDBinding: Binding<Bool> {
        Binding(
            get: { draft?.runtimeOverrides.forceSSD ?? preferences.forceSSD },
            set: { value in updateDraft { $0.runtimeOverrides.forceSSD = value } }
        )
    }

    private var renderMacOSPointerBinding: Binding<Bool> {
        Binding(
            get: { draft?.runtimeOverrides.renderMacOSPointer ?? preferences.renderMacOSPointer },
            set: { value in updateDraft { $0.runtimeOverrides.renderMacOSPointer = value } }
        )
    }

    private var nestedCompositorCursorBinding: Binding<String> {
        Binding(
            get: {
                let value = draft?.runtimeOverrides.nestedCompositorCursor
                    ?? preferences.nestedCompositorCursor
                return (value == "host") ? "host" : "virtual"
            },
            set: { value in
                updateDraft {
                    $0.runtimeOverrides.nestedCompositorCursor =
                        (value == "host") ? "host" : "virtual"
                }
            }
        )
    }

    private var autoScaleBinding: Binding<Bool> {
        Binding(
            get: { draft?.runtimeOverrides.autoScale ?? preferences.autoScale },
            set: { value in updateDraft { $0.runtimeOverrides.autoScale = value } }
        )
    }

    private var waylandDisplayBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.waylandDisplay ?? preferences.waylandDisplay },
            set: { value in updateDraft { $0.runtimeOverrides.waylandDisplay = value } }
        )
    }

    private var colorOperationsBinding: Binding<Bool> {
        Binding(
            get: { draft?.runtimeOverrides.colorOperations ?? preferences.colorOperations },
            set: { value in updateDraft { $0.runtimeOverrides.colorOperations = value } }
        )
    }

    private var logLevelBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.logLevel ?? preferences.logLevel },
            set: { value in updateDraft { $0.runtimeOverrides.logLevel = value } }
        )
    }

    private var shakeToCloseBinding: Binding<Bool> {
        Binding(
            get: { draft?.runtimeOverrides.shakeToCloseEnabled ?? preferences.shakeToCloseEnabled },
            set: { value in updateDraft { $0.runtimeOverrides.shakeToCloseEnabled = value } }
        )
    }

    private var swipeBackToCloseBinding: Binding<Bool> {
        Binding(
            get: {
                draft?.runtimeOverrides.swipeBackToCloseEnabled
                    ?? preferences.swipeBackToCloseEnabled
            },
            set: { value in updateDraft { $0.runtimeOverrides.swipeBackToCloseEnabled = value } }
        )
    }
}
#endif
