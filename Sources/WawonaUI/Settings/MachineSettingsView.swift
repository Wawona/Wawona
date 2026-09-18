import SwiftUI
import WawonaModel
#if !os(tvOS)
import UniformTypeIdentifiers
#endif

/// Per-machine configuration: each field falls back to global `WawonaPreferences` when unset (`resolvedSettings(for:)`).
public struct MachineSettingsView: View {
    @ObservedObject public var preferences: WawonaPreferences
    @ObservedObject public var profileStore: MachineProfileStore
    public var machineID: String?

    @State var selectedID: String?
    @State var draft: MachineProfile?
    @State private var fileImportTarget: MachineSettingsFileImport?

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
                    Button("Open Wawona Settings", systemImage: "gearshape") {
                        PlatformGlobalSettings.open()
                    }
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
                            get: { resolvedSelectedID ?? "" },
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
                    NativeSettingsRow("Profile") {
                        Picker("", selection: Binding(
                            get: { resolvedSelectedID ?? "" },
                            set: {
                                selectedID = $0
                                loadDraft()
                            }
                        )) {
                            ForEach(profileStore.profiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .nativeSettingsPickerStyle()
                    }
                    #endif
                }
            }

            if let draft {
                machineConfigurationSection(for: draft)
                if draft.type.isSSH {
                    sshWaypipeSection()
                }
                if draft.type == .container {
                    containerSection()
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
            syncSelectionFromStore()
        }
        .onChange(of: machineID) { _, _ in
            syncSelectionFromStore()
        }
        .onChange(of: profileStore.profiles.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) {
                self.selectedID = ids.first
                loadDraft()
            } else if draft == nil {
                loadDraft()
            }
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: Binding(
                get: { fileImportTarget != nil },
                set: { if !$0 { fileImportTarget = nil } }
            ),
            allowedContentTypes: fileImportTarget == .wasm
                ? [UTType(filenameExtension: "wasm") ?? .data]
                : [.item]
        ) { result in
            let target = fileImportTarget
            fileImportTarget = nil
            guard case .success(let url) = result else { return }
            switch target {
            case .wasm:
                wasmModulePathBinding.wrappedValue = url.path
            case .containerKernel:
                containerKernelPathBinding.wrappedValue = url.path
            case .containerInitfs:
                containerInitfsPathBinding.wrappedValue = url.path
            case .none:
                break
            }
        }
        #endif
    }

    @ViewBuilder
    private func containerSection() -> some View {
        Section {
            NativeSettingsRow("Image", summary: "OCI image reference") {
                TextField("", text: containerImageRefBinding)
                    .labelsHidden()
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            NativeSettingsRow("Command", summary: "Process and arguments") {
                TextField("", text: containerCommandBinding)
                    .labelsHidden()
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            NativeSettingsRow(
                "Memory",
                summary: "MiB, or inherit",
                help: "Sets a bounded memory limit from 64 MiB through 1,048,576 MiB. Clear the field to inherit the global default."
            ) {
                TextField(
                    "",
                    value: containerMemoryMiBBinding,
                    format: .number,
                    prompt: Text("Inherit")
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
            }
            NativeSettingsRow("Read-Only Rootfs") {
                Toggle("", isOn: containerReadOnlyBinding).labelsHidden()
            }
            NativeSettingsRow(
                "Init Process",
                help: "Runs a small init process for signal forwarding and zombie reaping."
            ) {
                Toggle("", isOn: containerInitProcessBinding).labelsHidden()
            }
            #if !os(tvOS)
            NativeSettingsRow(
                "Kernel",
                summary: containerKernelSummary,
                help: "Choose a local kernel image. If unset, Wawona discovers the configured global kernel."
            ) {
                Button("Choose", systemImage: "folder") {
                    fileImportTarget = .containerKernel
                }
            }
            NativeSettingsRow(
                "Initfs",
                summary: containerInitfsSummary,
                help: "Choose a local init filesystem. If unset, Wawona uses the configured global initfs."
            ) {
                Button("Choose", systemImage: "folder") {
                    fileImportTarget = .containerInitfs
                }
            }
            #endif
        } header: {
            Text("Container")
        }
    }

    @ViewBuilder
    private func displaySection() -> some View {
        Section("Display") {
            // Force SSD is macOS-only: CSD only renders on macOS Wawona, so
            // every other target is effectively always SSD (#120). Hiding the
            // toggle elsewhere avoids a control that cannot change anything.
            if PlatformCapabilities.supportsClientSideDecorations {
                NativeSettingsRow(
                    "Server-Side Decorations",
                    help: "When enabled, Wawona draws window decorations instead of the client."
                ) {
                    Toggle("", isOn: forceSSDBinding).labelsHidden()
                }
            }
            NativeSettingsRow("Auto Scale") {
                Toggle("", isOn: autoScaleBinding).labelsHidden()
            }
            NativeSettingsRow(
                "Wayland Display",
                summary: "Socket name",
                help: "The Wayland display socket name used by clients, such as wayland-0."
            ) {
                TextField("", text: waylandDisplayBinding)
                    .labelsHidden()
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder
    private func machineConfigurationSection(for profile: MachineProfile) -> some View {
        Section("Machine Configuration") {
            NativeSettingsRow("Name") {
                TextField("", text: nameBinding)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
            }
            NativeSettingsRow("Type") {
                Picker("", selection: typeBinding) {
                    ForEach(PlatformCapabilities.availableMachineTypes, id: \.self) { t in
                        Text(t.userFacingName).tag(t)
                    }
                    if !PlatformCapabilities.allowsMachineType(profile.type) {
                        Text(profile.type.userFacingName).tag(profile.type)
                    }
                }
                .labelsHidden()
                .nativeSettingsPickerStyle()
            }

            if profile.type == .wasm {
                NativeSettingsRow("Command", summary: "Wasm launch command") {
                    TextField("", text: Binding(
                        get: { draft?.runtimeOverrides.wasmCommand ?? "wasm hello-wasi-gui" },
                        set: { value in updateDraft { $0.runtimeOverrides.wasmCommand = value } }
                    ))
                    .labelsHidden()
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                }
                NativeSettingsRow("Package", summary: "Installed package name") {
                    TextField("", text: Binding(
                        get: { draft?.runtimeOverrides.wasmPackage ?? "" },
                        set: { value in updateDraft { $0.runtimeOverrides.wasmPackage = value } }
                    ))
                    .labelsHidden()
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                }
                #if !os(tvOS)
                NativeSettingsRow(
                    "Wasm Module",
                    summary: wasmModuleSummary,
                    help: "Choose a local .wasm module. If unset, Wawona runs the bundled hello-wasi-gui module."
                ) {
                    Button("Choose", systemImage: "doc.badge.gearshape") {
                        fileImportTarget = .wasm
                    }
                }
                #endif
            }

            if profile.type == .native {
                #if os(macOS)
                NativeSettingsRow("Wayland Client") {
                    Picker("", selection: bundledAppIDSelectionBinding) {
                        ForEach(ClientLauncher.presets) { launcher in
                            Text(launcher.displayName).tag(launcher.name)
                        }
                        if !ClientLauncher.presets.contains(where: { $0.name == resolvedBundledAppID }) {
                            Text(ClientLauncher.displayName(for: resolvedBundledAppID))
                                .tag(resolvedBundledAppID)
                        }
                    }
                    .labelsHidden()
                    .nativeSettingsPickerStyle()
                }
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
                    #if !os(tvOS)
                    NativeSettingsRow(
                        "Wasm Module",
                        summary: wasmModuleSummary,
                        help: "Choose a local .wasm module. If unset, Wawona runs bundled hello-wasi-gui."
                    ) {
                        Button("Choose", systemImage: "doc.badge.gearshape") {
                            fileImportTarget = .wasm
                        }
                    }
                    #endif
                }
            }

            if let backend = profile.type.backendEngineLabel {
                NativeSettingsRow("Backend") {
                    Text(backend).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func sshWaypipeSection() -> some View {
        Section("SSH / Waypipe") {
            NativeSettingsRow("Host", summary: "Remote address") {
                TextField("", text: sshHostBinding)
                    .labelsHidden()
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            NativeSettingsRow("User", summary: "SSH username") {
                TextField("", text: sshUserBinding)
                    .labelsHidden()
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            NativeSettingsRow(
                "Port",
                summary: "1 through 65,535",
                help: "The SSH TCP port. Wawona clamps this value to the valid port range."
            ) {
                Stepper(value: sshPortBinding, in: 1...65_535) {
                    Text(sshPortBinding.wrappedValue, format: .number)
                        .monospacedDigit()
                }
            }
            NativeSettingsRow("Password") {
                SecureField("", text: sshPasswordBinding)
                    .labelsHidden()
                    .textContentType(.password)
            }
            NativeSettingsRow(
                "Waypipe Password",
                summary: "Optional override",
                help: "Leave empty to use the global Waypipe password."
            ) {
                SecureField("", text: waypipeSSHPasswordBinding)
                    .labelsHidden()
                    .textContentType(.password)
            }
            NativeSettingsRow("Remote Command") {
                TextField("", text: remoteCommandBinding)
                    .labelsHidden()
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            NativeSettingsRow("Enable Waypipe") {
                Toggle("", isOn: waypipeEnabledBinding).labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func inputSection() -> some View {
        Section("Input") {
            if draft?.nestedCompositorDrawsOwnCursor == true {
                NativeSettingsRow(
                    "Cursor",
                    summary: "Drawn by compositor",
                    help: "Nested compositors draw their own cursor. Wawona hides the host overlay in both Multi-Touch and Touchpad modes."
                ) {
                    Image(systemName: "cursorarrow")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Drawn by compositor")
                }
            } else {
                NativeSettingsRow(
                    "Show Virtual Cursor",
                    help: "Shows the host cursor overlay for non-compositor clients."
                ) {
                    Toggle("", isOn: renderMacOSPointerBinding).labelsHidden()
                }
                #if os(macOS)
                NativeSettingsRow("Cursor Style") {
                    Picker("", selection: nestedCompositorCursorBinding) {
                        Text("Virtual Pointer").tag("virtual")
                        Text("macOS Cursor").tag("host")
                    }
                    .labelsHidden()
                    .nativeSettingsPickerStyle()
                    .disabled(!(draft?.runtimeOverrides.renderMacOSPointer ?? preferences.renderMacOSPointer))
                }
                #endif
            }
            #if os(tvOS)
            NativeSettingsRow("Touch Input") {
                Text("Touchpad").foregroundStyle(.secondary)
            }
            #else
            NativeSettingsRow(
                "Touch Input",
                help: "Multi-Touch sends native Wayland touch events. Touchpad uses a virtual pointer."
            ) {
                Picker("", selection: touchInputTypeBinding) {
                    Text("Multi-Touch").tag("Multi-Touch")
                    Text("Touchpad").tag("Touchpad")
                }
                .labelsHidden()
                .nativeSettingsPickerStyle()
            }
            #endif
            #if os(iOS)
            NativeSettingsRow(
                "Resize for Keyboard",
                help: "Shrinks and shifts the Wayland output above the software keyboard. Hardware keyboards keep the full display."
            ) {
                Toggle("", isOn: resizeDisplayForVirtualKeyboardBinding).labelsHidden()
            }
            #endif
        }
    }

    @ViewBuilder
    private func graphicsSection() -> some View {
        Section("Graphics") {
            NativeSettingsRow("Renderer") {
                Picker("", selection: rendererBinding) {
                    Text("Metal").tag("metal")
                    Text("Software").tag("software")
                }
                .labelsHidden()
                .nativeSettingsPickerStyle()
            }
            if PlatformCapabilities.allowsGpuStack {
                NativeSettingsRow("Vulkan Driver") {
                    Picker("", selection: vulkanDriverBinding) {
                        ForEach(vulkanDriverOptions, id: \.self) { value in
                            Text(vulkanDriverTitle(value)).tag(value)
                        }
                    }
                    .labelsHidden()
                    .nativeSettingsPickerStyle()
                }
                NativeSettingsRow("OpenGL Driver") {
                    Picker("", selection: openGLDriverBinding) {
                        Text("None").tag("none")
                        Text("ANGLE").tag("angle")
                    }
                    .labelsHidden()
                    .nativeSettingsPickerStyle()
                }
                NativeSettingsRow("Enable DMABUF") {
                    Toggle("", isOn: dmabufEnabledBinding).labelsHidden()
                }
            } else {
                NativeSettingsRow("GPU Stack") {
                    Text("Unavailable").foregroundStyle(.secondary)
                }
            }
            NativeSettingsRow("Enable HDR") {
                Toggle("", isOn: colorOperationsBinding).labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func advancedSection() -> some View {
        Section("Advanced") {
            NativeSettingsRow("Log Level") {
                Picker("", selection: logLevelBinding) {
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Warn").tag("warn")
                    Text("Error").tag("error")
                }
                .labelsHidden()
                .nativeSettingsPickerStyle()
            }
            NativeSettingsRow(
                "Display Backend",
                help: "Auto selects the best available path. Wayland nests the client. DRM uses the wwn-iland userspace display stack."
            ) {
                Picker("", selection: compositorBackendBinding) {
                    Text("Inherit (\(preferences.compositorBackend))").tag("")
                    Text("Auto").tag("auto")
                    Text("Wayland").tag("wayland")
                    Text("DRM").tag("drm")
                }
                .labelsHidden()
                .nativeSettingsPickerStyle()
            }
            #if os(tvOS)
            NativeSettingsRow("Menu / Shake to Exit") {
                Toggle("", isOn: shakeToCloseBinding).labelsHidden()
            }
            #else
            NativeSettingsRow("Shake to Exit") {
                Toggle("", isOn: shakeToCloseBinding).labelsHidden()
            }
            #endif
            #if !os(tvOS)
            NativeSettingsRow("Swipe Back to Exit") {
                Toggle("", isOn: swipeBackToCloseBinding).labelsHidden()
            }
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
        Section("Runtime") {
            DisclosureGroup("Resolved Values") {
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
            if resolved.machineType == .container {
                Text("Container Image: \(resolved.containerImageRef)")
                Text("Container Command: \(resolved.containerCommand)")
                Text("Container Memory: \(resolved.containerMemory.isEmpty ? "default" : resolved.containerMemory + " MiB")")
                Text("Container Rootfs: \(resolved.containerReadOnly ? "Read-Only" : "Writable")")
                Text("Container Remove: \(resolved.containerRemove ? "On exit" : "Keep")")
                Text("Container Kernel: \(resolved.containerKernelPath.isEmpty ? "auto-discover" : resolved.containerKernelPath)")
                Text("Container Initfs: \(resolved.containerInitfsPath.isEmpty ? "vminit:latest" : resolved.containerInitfsPath)")
            }
            #if os(tvOS)
            Text("Menu / Shake to Exit: \(resolved.shakeToCloseEnabled ? "Enabled" : "Disabled")")
            #else
            Text("Shake to Exit: \(resolved.shakeToCloseEnabled ? "Enabled" : "Disabled")")
            Text("Swipe Back to Exit: \(resolved.swipeBackToCloseEnabled ? "Enabled" : "Disabled")")
            #endif
            Text("Resize Display for Virtual Keyboard: \(resolved.resizeDisplayForVirtualKeyboard ? "Enabled" : "Disabled")")
            }
        }
    }

    @ViewBuilder
    private func actionsSection() -> some View {
        Section {
            Button("Save Machine Settings", systemImage: "checkmark") {
                guard let latestDraft = draft else { return }
                profileStore.upsert(latestDraft)
                profileStore.activeMachineId = latestDraft.id
                profileStore.save()
                MachineRuntimeSettingsApplicator.apply(profile: latestDraft, preferences: preferences)
            }
        }
    }

    private var resolvedSelectedID: String? {
        if let selectedID, profileStore.profiles.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return profileStore.profiles.first?.id
    }

    private func syncSelectionFromStore() {
        selectedID = machineID ?? profileStore.activeMachineId ?? profileStore.profiles.first?.id
        loadDraft()
    }

    private func loadDraft() {
        guard var profile = profileStore.profiles.first(where: { $0.id == resolvedSelectedID }) else {
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
            set: { value in
                updateDraft { profile in
                    profile.type = value
                    if value == .wasm {
                        profile.runtimeOverrides.bundledAppID = "wawona-wasm"
                    }
                }
            }
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

    private var sshPortBinding: Binding<Int> {
        Binding(
            get: {
                MachineProfileDomain.normalizeSSHPort(
                    String(draft?.sshPort ?? 22),
                    fallback: 22
                )
            },
            set: { value in
                updateDraft {
                    $0.sshPort = MachineProfileDomain.normalizeSSHPort(
                        String(value),
                        fallback: 22
                    )
                }
            }
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

    private var wasmModuleSummary: String {
        let path = wasmModulePathBinding.wrappedValue
        return path.isEmpty ? "Bundled default" : (path as NSString).lastPathComponent
    }

    private var containerKernelSummary: String {
        let path = containerKernelPathBinding.wrappedValue
        return path.isEmpty ? "Inherit global" : (path as NSString).lastPathComponent
    }

    private var containerInitfsSummary: String {
        let path = containerInitfsPathBinding.wrappedValue
        return path.isEmpty ? "Inherit global" : (path as NSString).lastPathComponent
    }

    private var vulkanDriverOptions: [String] {
        #if os(macOS)
        ["none", "moltenvk", "kosmickrisp", "swiftshader"]
        #else
        ["none", "moltenvk"]
        #endif
    }

    private func vulkanDriverTitle(_ value: String) -> String {
        switch value {
        case "moltenvk": return "MoltenVK"
        case "kosmickrisp": return "KosmicKrisp"
        case "swiftshader": return "SwiftShader"
        default: return "None"
        }
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
            get: {
                let value = draft?.runtimeOverrides.renderer ?? preferences.renderer
                return ["metal", "software"].contains(value) ? value : "metal"
            },
            set: { value in updateDraft { $0.runtimeOverrides.renderer = value } }
        )
    }

    private var vulkanDriverBinding: Binding<String> {
        Binding(
            get: {
                let value = draft?.runtimeOverrides.vulkanDriver ?? preferences.vulkanDriver
                return vulkanDriverOptions.contains(value) ? value : vulkanDriverOptions[0]
            },
            set: { value in updateDraft { $0.runtimeOverrides.vulkanDriver = value } }
        )
    }

    private var openGLDriverBinding: Binding<String> {
        Binding(
            get: {
                let value = draft?.runtimeOverrides.openGLDriver ?? "angle"
                return ["none", "angle"].contains(value) ? value : "angle"
            },
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
            get: {
                let raw = draft?.runtimeOverrides.logLevel ?? preferences.logLevel
                let allowed = ["debug", "info", "warn", "error"]
                return allowed.contains(raw) ? raw : "info"
            },
            set: { value in updateDraft { $0.runtimeOverrides.logLevel = value } }
        )
    }

    private var compositorBackendBinding: Binding<String> {
        Binding(
            get: {
                let raw = draft?.runtimeOverrides.compositorBackend ?? ""
                let allowed = ["", "auto", "wayland", "drm"]
                return allowed.contains(raw) ? raw : ""
            },
            set: { value in
                updateDraft {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    $0.runtimeOverrides.compositorBackend = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    // MARK: Container bindings (per-machine > global)

    private var containerImageRefBinding: Binding<String> {
        Binding(
            get: { draft?.containerSettings?.containerRef ?? preferences.containerDefaultImage },
            set: { value in
                updateContainerSettings { $0.containerRef = value }
            }
        )
    }

    private var containerCommandBinding: Binding<String> {
        Binding(
            get: { draft?.containerSettings?.entryCommand ?? preferences.containerDefaultCommand },
            set: { value in
                updateContainerSettings { $0.entryCommand = value }
            }
        )
    }

    private var containerMemoryMiBBinding: Binding<Int?> {
        Binding(
            get: {
                let raw = draft?.containerSettings?.memory?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !raw.isEmpty else { return nil }
                return Int(raw)
            },
            set: { value in
                updateContainerSettings {
                    guard let value else {
                        $0.memory = nil
                        return
                    }
                    $0.memory = String(min(max(value, 64), 1_048_576))
                }
            }
        )
    }

    private var containerReadOnlyBinding: Binding<Bool> {
        Binding(
            get: { draft?.containerSettings?.readOnly ?? false },
            set: { value in
                updateContainerSettings { $0.readOnly = value }
            }
        )
    }

    private var containerInitProcessBinding: Binding<Bool> {
        Binding(
            get: { draft?.containerSettings?.initProcess ?? false },
            set: { value in
                updateContainerSettings { $0.initProcess = value }
            }
        )
    }

    private var containerKernelPathBinding: Binding<String> {
        Binding(
            get: { draft?.containerSettings?.kernelPath ?? preferences.containerKernelPath },
            set: { value in
                updateContainerSettings { $0.kernelPath = value }
            }
        )
    }

    private var containerInitfsPathBinding: Binding<String> {
        Binding(
            get: { draft?.containerSettings?.initfsPath ?? preferences.containerInitfsPath },
            set: { value in
                updateContainerSettings { $0.initfsPath = value }
            }
        )
    }

    private func updateContainerSettings(_ mutate: (inout ContainerMachineSettings) -> Void) {
        updateDraft { profile in
            var cs = profile.containerSettings ?? ContainerMachineSettings()
            mutate(&cs)
            profile.containerSettings = cs
        }
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

    private var resizeDisplayForVirtualKeyboardBinding: Binding<Bool> {
        Binding(
            get: {
                draft?.runtimeOverrides.resizeDisplayForVirtualKeyboard
                    ?? preferences.resizeDisplayForVirtualKeyboard
            },
            set: { value in
                updateDraft { $0.runtimeOverrides.resizeDisplayForVirtualKeyboard = value }
            }
        )
    }

    private func updateDraft(_ mutate: (inout MachineProfile) -> Void) {
        guard draft != nil else { return }
        var copy = draft!
        mutate(&copy)
        draft = copy
    }
}

private enum MachineSettingsFileImport {
    case wasm
    case containerKernel
    case containerInitfs
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
