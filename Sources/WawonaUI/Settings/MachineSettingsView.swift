import SwiftUI
import WawonaModel

/// Per-machine configuration: each field falls back to global `WawonaPreferences` when unset (`resolvedSettings(for:)`).
public struct MachineSettingsView: View {
    @ObservedObject public var preferences: WawonaPreferences
    @ObservedObject public var profileStore: MachineProfileStore
    public var machineID: String?

    @State var selectedID: String?
    @State var draft: MachineProfile?

    public init(
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore,
        machineID: String? = nil
    ) {
        self._preferences = ObservedObject(wrappedValue: preferences)
        self._profileStore = ObservedObject(wrappedValue: profileStore)
        self.machineID = machineID
    }

    public var body: some View {
        Form {
            if PlatformGlobalSettings.isAvailable {
                Section {
                    Button("Open Wawona Settings…") {
                        PlatformGlobalSettings.open()
                    }
                    Text(draft?.type.isSSH == true
                         ? "Global defaults (Display, Input, Graphics, Waypipe, SSH). Values below override those settings for this machine only."
                         : "Global defaults (Display, Input, Graphics). Values below override those settings for this machine only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Machine") {
                if profileStore.profiles.isEmpty {
                    Text("No machine profiles available.")
                        .foregroundStyle(.secondary)
                } else {
                    #if os(watchOS)
                    if let mid = machineID, let pick = profileStore.profiles.first(where: { $0.id == mid }) {
                        Text(pick.name)
                            .font(.headline)
                    } else {
                        Picker("Profile", selection: Binding(
                            get: { selectedID ?? profileStore.profiles.first?.id ?? "" },
                            set: {
                                selectedID = $0
                                loadDraft()
                            }
                        )) {
                            ForEach(profileStore.profiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .wwnDisclosurePicker()
                    }
                    #else
                    Picker("Profile", selection: Binding(
                        get: { selectedID ?? profileStore.profiles.first?.id ?? "" },
                        set: {
                            selectedID = $0
                            loadDraft()
                        }
                    )) {
                        ForEach(profileStore.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .wwnDisclosurePicker()
                    #endif
                }
            }

            if let draft {
                machineConfigurationSection(for: draft)
                if draft.type.isSSH {
                    sshWaypipeSection()
                }
                displaySection()
                inputSection()
                graphicsSection()
                advancedSection()
                environmentSection()
                resolvedPreviewSection(for: draft)
                actionsSection()
            }
        }

        .navigationTitle("Machine Settings")
        .onAppear {
            selectedID = machineID ?? profileStore.activeMachineId ?? profileStore.profiles.first?.id
            loadDraft()
        }
    }

    @ViewBuilder
    private func displaySection() -> some View {
        Section("Display") {
            // Force SSD is macOS-only: CSD only renders on macOS Wawona, so
            // every other target is effectively always SSD (#120). Hiding the
            // toggle elsewhere avoids a control that cannot change anything.
            if PlatformCapabilities.supportsClientSideDecorations {
                Toggle("Force Server-Side Decorations", isOn: forceSSDBinding)
            }
            Toggle("Auto Scale", isOn: autoScaleBinding)
            TextField("Wayland Display", text: waylandDisplayBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private func machineConfigurationSection(for profile: MachineProfile) -> some View {
        Section("Machine Configuration") {
            TextField("Name", text: nameBinding)
            Picker("Type", selection: typeBinding) {
                ForEach(PlatformCapabilities.availableMachineTypes, id: \.self) { t in
                    Text(t.userFacingName).tag(t)
                }
            }
            .wwnDisclosurePicker()

            if profile.type == .native {
                #if os(macOS)
                Picker("Wayland Client", selection: bundledAppIDSelectionBinding) {
                    ForEach(ClientLauncher.presets) { launcher in
                        Text(launcher.displayName).tag(launcher.name)
                    }
                }
                .wwnDisclosurePicker()
                #else
                NavigationLink {
                    BundledClientPickerView(selection: bundledAppIDSelectionBinding)
                } label: {
                    HStack {
                        Text("Wayland Client")
                        Spacer()
                        Text(wasmClientSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                #endif
                if resolvedBundledAppID == "wawona-wasm" {
                    TextField("Wasm module path", text: wasmModulePathBinding)
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                    Text("Wayland WASI `.wasm` run by the Wawona Runtime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
            TextField("User", text: sshUserBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
            TextField("Port", text: Binding(
                get: { String(draft?.sshPort ?? 22) },
                set: { value in
                    updateDraft { $0.sshPort = Int(value) ?? $0.sshPort }
                }
            ))
            .wawonaTextFieldNoAutocaps()
            .autocorrectionDisabled()
            SecureField("Password", text: sshPasswordBinding)
                .textContentType(.password)
            SecureField("Waypipe Password (optional override)", text: waypipeSSHPasswordBinding)
                .textContentType(.password)
            TextField("Remote Command", text: remoteCommandBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()

            Toggle("Enable Waypipe", isOn: waypipeEnabledBinding)
        }
    }

    @ViewBuilder
    private func inputSection() -> some View {
        Section("Input") {
            if draft?.nestedCompositorDrawsOwnCursor == true {
                Text("Nested compositor (weston, niri, or custom) draws its own cursor. The host virtual pointer stays hidden in Multi-Touch and Touchpad. Show Virtual Cursor applies only to non-compositor clients.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Show Virtual Cursor", isOn: renderMacOSPointerBinding)
                #if os(macOS)
                Picker("Nested Compositor Cursor", selection: nestedCompositorCursorBinding) {
                    Text("Virtual Pointer").tag("virtual")
                    Text("macOS Cursor").tag("host")
                }
                .wwnDisclosurePicker()
                .disabled(!(draft?.runtimeOverrides.renderMacOSPointer ?? preferences.renderMacOSPointer))
                #endif
                Text("Nested and iland DRM compositors hide and grab the host pointer. They draw their own cursor. Show Virtual Cursor is only for non-compositor clients.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            #if os(tvOS)
            Text("Touch Input Type: Touchpad (tvOS)")
                .foregroundStyle(.secondary)
            #else
            Picker("Touch Input Type", selection: touchInputTypeBinding) {
                Text("Multi-Touch").tag("Multi-Touch")
                Text("Touchpad").tag("Touchpad")
            }
            .wwnDisclosurePicker()
            Text("Overrides global Settings → Input. Multi-Touch is required for many Wayland clients (Weston panel, terminals); Touchpad uses a virtual pointer.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Global default: \(WawonaPreferences.normalizedTouchInputType(preferences.defaultInputProfile))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            #endif
        }
    }

    @ViewBuilder
    private func graphicsSection() -> some View {
        Section("Graphics") {
            TextField("Renderer", text: rendererBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
            if PlatformCapabilities.allowsGpuStack {
                TextField("Vulkan Driver", text: vulkanDriverBinding)
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                TextField("OpenGL Driver", text: openGLDriverBinding)
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                Toggle("Enable DMABUF", isOn: dmabufEnabledBinding)
            } else {
                Text("GPU stack unavailable on this platform.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Toggle("Enable HDR", isOn: colorOperationsBinding)
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
            .wwnDisclosurePicker()
            Picker("Display Backend", selection: compositorBackendBinding) {
                Text("Inherit global (\(preferences.compositorBackend))").tag("")
                Text("Auto").tag("auto")
                Text("Wayland (nested)").tag("wayland")
                Text("DRM").tag("drm")
            }
            .wwnDisclosurePicker()
            #if os(tvOS)
            Toggle("Menu / Shake to Exit Machine", isOn: shakeToCloseBinding)
            #else
            Toggle("Shake to Exit Machine", isOn: shakeToCloseBinding)
            #endif
            #if !os(tvOS)
            Toggle("Swipe Back to Exit Machine", isOn: swipeBackToCloseBinding)
            #endif
        }
    }

    @ViewBuilder
    private func environmentSection() -> some View {
        Section("Environment Variables") {
            if let draft {
                NavigationLink {
                    EnvironmentVariablesView(
                        preferences: preferences,
                        profileStore: profileStore,
                        machineID: draft.id,
                        perMachine: true
                    )
                } label: {
                    HStack {
                        Text("Environment Variables")
                        Spacer()
                        let count = draft.runtimeOverrides.environment?.count ?? 0
                        Text(count == 0 ? "Inherit global" : "\(count) override(s)")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("wwn.settings.environment.machine")
            }
        }
    }

    @ViewBuilder
    private func resolvedPreviewSection(for profile: MachineProfile) -> some View {
        let resolved = preferences.resolvedSettings(for: profile)
        Section("Resolved Runtime (Machine > Global)") {
            Text("Renderer: \(resolved.renderer)")
            Text("Vulkan Driver: \(resolved.vulkanDriver)")
            Text("OpenGL Driver: \(resolved.openGLDriver)")
            Text("DMABUF: \(resolved.dmabufEnabled ? "Enabled" : "Disabled")")
            Text("Force SSD: \(resolved.forceSSD ? "Enabled" : "Disabled")")
            if profile.nestedCompositorDrawsOwnCursor {
                Text("Host cursor overlay: Hidden (nested compositor draws its own)")
            } else {
                Text("Show Virtual Cursor: \(resolved.renderMacOSPointer ? "Enabled" : "Disabled")")
            }
            Text("Auto Scale: \(resolved.autoScale ? "Enabled" : "Disabled")")
            Text("HDR: \(resolved.colorOperations ? "Enabled" : "Disabled")")
            Text("Display: \(resolved.waylandDisplay)")
            Text("Touch Input: \(WawonaPreferences.normalizedTouchInputType(resolved.inputProfile))")
            if profile.type.isSSH {
                Text("Host: \(resolved.sshHost)")
                Text("User: \(resolved.sshUser)")
                Text("Port: \(resolved.sshPort)")
                Text("Waypipe Password: \(resolved.waypipeSSHPassword.isEmpty ? "Inherit global" : "Per-machine override")")
                Text("Waypipe: \(resolved.waypipeEnabled ? "Enabled" : "Disabled")")
            }
            Text("Bundled App: \(resolved.bundledAppID.isEmpty ? "Off" : resolved.bundledAppID)")
            Text("Log Level: \(resolved.logLevel)")
            #if os(tvOS)
            Text("Menu / Shake to Exit: \(resolved.shakeToCloseEnabled ? "Enabled" : "Disabled")")
            #else
            Text("Shake to Exit: \(resolved.shakeToCloseEnabled ? "Enabled" : "Disabled")")
            Text("Swipe Back to Exit: \(resolved.swipeBackToCloseEnabled ? "Enabled" : "Disabled")")
            #endif
        }
    }

    @ViewBuilder
    private func actionsSection() -> some View {
        Section {
            Button("Save Machine Settings") {
                guard let latestDraft = draft else { return }
                profileStore.upsert(latestDraft)
                profileStore.activeMachineId = latestDraft.id
                profileStore.save()
                MachineRuntimeSettingsApplicator.apply(profile: latestDraft, preferences: preferences)
            }
        }
    }

    private func loadDraft() {
        guard var profile = profileStore.profiles.first(where: { $0.id == selectedID }) else {
            draft = nil
            return
        }
        #if os(iOS) || os(watchOS)
        if profile.type == .container {
            profile.type = .native
        }
        #if os(watchOS)
        if profile.type == .virtualMachine {
            profile.type = .native
        }
        #endif
        #endif
        draft = profile
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { draft?.name ?? "" },
            set: { value in updateDraft { $0.name = value } }
        )
    }

    private var typeBinding: Binding<MachineType> {
        Binding(
            get: { draft?.type ?? MachineType.native },
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

    private var sshPasswordBinding: Binding<String> {
        Binding(
            get: { draft?.sshPassword ?? "" },
            set: { value in updateDraft { $0.sshPassword = value } }
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

    private var wasmClientSummary: String {
        if resolvedBundledAppID == "wawona-wasm" {
            let path = draft?.runtimeOverrides.wasmModulePath?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty {
                return (path as NSString).lastPathComponent
            }
        }
        return ClientLauncher.displayName(for: resolvedBundledAppID)
    }

    private var wasmModulePathBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.wasmModulePath ?? "" },
            set: { value in
                updateDraft { profile in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    profile.runtimeOverrides.wasmModulePath = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    private var bundledAppIDSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedBundledAppID },
            set: { value in
                updateDraft { profile in
                    profile.runtimeOverrides.bundledAppID = value
                    if value != "wawona-wasm" {
                        profile.runtimeOverrides.wasmModulePath = nil
                    }
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

    private var touchInputTypeBinding: Binding<String> {
        Binding(
            get: {
                let raw = draft?.runtimeOverrides.inputProfile ?? preferences.defaultInputProfile
                return WawonaPreferences.normalizedTouchInputType(raw)
            },
            set: { value in
                let normalized = WawonaPreferences.normalizedTouchInputType(value)
                updateDraft { $0.runtimeOverrides.inputProfile = normalized }
            }
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

    private var compositorBackendBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.compositorBackend ?? "" },
            set: { value in
                updateDraft {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    $0.runtimeOverrides.compositorBackend = trimmed.isEmpty ? nil : trimmed
                }
            }
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

    private func updateDraft(_ mutate: (inout MachineProfile) -> Void) {
        guard draft != nil else { return }
        var copy = draft!
        mutate(&copy)
        draft = copy
    }
}

private extension View {
    @ViewBuilder
    func wwnDisclosurePicker() -> some View {
        #if os(macOS)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.navigationLink)
        #endif
    }
}
