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
                    Text("Global defaults (Display, Input, Graphics, Waypipe, SSH). Values below override those settings for this machine only.")
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
                    #endif
                }
            }

            if let draft {
                machineConfigurationSection(for: draft)
                sshWaypipeSection()
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
    }

    @ViewBuilder
    private func displaySection() -> some View {
        Section("Display") {
            Toggle("Force Server-Side Decorations", isOn: forceSSDBinding)
            #if os(macOS)
            Toggle("Show macOS Cursor", isOn: renderMacOSPointerBinding)
            #else
            Toggle("Show Virtual Pointer", isOn: renderMacOSPointerBinding)
            #endif
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

            if profile.type == .native {
                NavigationLink {
                    BundledClientPickerView(selection: bundledAppIDSelectionBinding)
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
                .disabled(draft?.type == .native)
        }
    }

    @ViewBuilder
    private func inputSection() -> some View {
        Section("Input") {
            TextField("Input Profile", text: inputProfileBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
            Text("Global default: \(preferences.defaultInputProfile)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func graphicsSection() -> some View {
        Section("Graphics") {
            TextField("Renderer", text: rendererBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
            TextField("Vulkan Driver", text: vulkanDriverBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
            TextField("OpenGL Driver", text: openGLDriverBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
            Toggle("Enable DMABUF", isOn: dmabufEnabledBinding)
            Toggle("HDR / Color Operations", isOn: colorOperationsBinding)
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
            #if os(tvOS)
            Toggle("Long-press Menu to Exit Machine", isOn: shakeToCloseBinding)
            #else
            Toggle("Shake to Exit Machine", isOn: shakeToCloseBinding)
            #endif
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
            #if os(macOS)
            Text("Show macOS Cursor: \(resolved.renderMacOSPointer ? "Enabled" : "Disabled")")
            #else
            Text("Show Virtual Pointer: \(resolved.renderMacOSPointer ? "Enabled" : "Disabled")")
            #endif
            Text("Auto Scale: \(resolved.autoScale ? "Enabled" : "Disabled")")
            Text("HDR: \(resolved.colorOperations ? "Enabled" : "Disabled")")
            Text("Display: \(resolved.waylandDisplay)")
            Text("Input: \(resolved.inputProfile)")
            Text("Host: \(resolved.sshHost)")
            Text("User: \(resolved.sshUser)")
            Text("Port: \(resolved.sshPort)")
            Text("Waypipe Password: \(resolved.waypipeSSHPassword.isEmpty ? "Inherit global" : "Per-machine override")")
            Text("Waypipe: \(resolved.waypipeEnabled ? "Enabled" : "Disabled")")
            Text("Bundled App: \(resolved.bundledAppID.isEmpty ? "Off" : resolved.bundledAppID)")
            Text("Log Level: \(resolved.logLevel)")
            #if os(tvOS)
            Text("Long-press Menu to Exit: \(resolved.shakeToCloseEnabled ? "Enabled" : "Disabled")")
            #else
            Text("Shake to Exit: \(resolved.shakeToCloseEnabled ? "Enabled" : "Disabled")")
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

    private var bundledAppIDSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedBundledAppID },
            set: { value in updateDraft { $0.runtimeOverrides.bundledAppID = value } }
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
            get: { draft?.runtimeOverrides.vulkanDriver ?? "moltenvk" },
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

    private func updateDraft(_ mutate: (inout MachineProfile) -> Void) {
        guard draft != nil else { return }
        var copy = draft!
        mutate(&copy)
        draft = copy
    }
}
