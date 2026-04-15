import SwiftUI
import WawonaModel

struct MachineSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences
    @ObservedObject var profileStore: MachineProfileStore
    var machineID: String?

    // internal: Skip Fuse native bridging requires non-private @State for Android.
    @State var selectedID: String?
    @State var draft: MachineProfile?

    var body: some View {
        Form {
            Section("Machine") {
                if profileStore.profiles.isEmpty {
                    Text("No machine profiles available.")
                        .foregroundStyle(.secondary)
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
            }

            if let draft {
                machineConfigurationSection(for: draft)
                sshWaypipeSection()
                displaySection()
                inputSection()
                graphicsSection()
                resolvedPreviewSection(for: draft)
                actionsSection(for: draft)
            }
    @ViewBuilder
    private func displaySection() -> some View {
        Section("Display") {
            Toggle("Force Server-Side Decorations", isOn: forceSSDBinding)
            Toggle("Auto Scale", isOn: autoScaleBinding)
            TextField("Wayland Display", text: waylandDisplayBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()
        }
    }

        }
        .navigationTitle("Machine Settings")
        .onAppear {
            selectedID = machineID ?? profileStore.activeMachineId ?? profileStore.profiles.first?.id
            loadDraft()
        }
    }

    @ViewBuilder
    private func machineConfigurationSection(for profile: MachineProfile) -> some View {
        Section("Machine Configuration") {
            TextField("Name", text: nameBinding)
            Picker("Type", selection: typeBinding) {
                ForEach(MachineType.allCases, id: \.self) { t in
                    Text(t.userFacingName).tag(t)
                }
            }

            if profile.type == .native {
                TextField("Bundled App ID", text: bundledAppIDBinding)
            }

            if profile.type == .virtualMachine {
                TextField("VM Type", text: vmSubtypeBinding)
            }

            if profile.type == .container {
                TextField("Container Type", text: containerSubtypeBinding)
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
            TextField("Remote Command", text: remoteCommandBinding)
                .wawonaTextFieldNoAutocaps()
                .autocorrectionDisabled()

            Toggle("Enable Waypipe", isOn: waypipeEnabledBinding)
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
    private func resolvedPreviewSection(for profile: MachineProfile) -> some View {
        let resolved = preferences.resolvedSettings(for: profile)
        Section("Resolved Runtime (Machine > Global)") {
            Text("Renderer: \(resolved.renderer)")
            Text("Vulkan Driver: \(resolved.vulkanDriver)")
            Text("OpenGL Driver: \(resolved.openGLDriver)")
            Text("DMABUF: \(resolved.dmabufEnabled ? "Enabled" : "Disabled")")
            Text("Force SSD: \(resolved.forceSSD ? "Enabled" : "Disabled")")
            Text("Auto Scale: \(resolved.autoScale ? "Enabled" : "Disabled")")
            Text("HDR: \(resolved.colorOperations ? "Enabled" : "Disabled")")
            Text("Display: \(resolved.waylandDisplay)")
            Text("Input: \(resolved.inputProfile)")
            Text("Host: \(resolved.sshHost)")
            Text("User: \(resolved.sshUser)")
            Text("Port: \(resolved.sshPort)")
            Text("Waypipe: \(resolved.waypipeEnabled ? "Enabled" : "Disabled")")
            Text("Bundled App: \(resolved.bundledAppID.isEmpty ? "Off" : resolved.bundledAppID)")
        }
    }

    @ViewBuilder
    private func actionsSection(for profile: MachineProfile) -> some View {
        Section {
            Button("Save Machine Settings") {
                profileStore.upsert(profile)
                profileStore.activeMachineId = profile.id
                profileStore.save()
            }
        }
    }

    private func loadDraft() {
        draft = profileStore.profiles.first { $0.id == selectedID }
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

    private var vmSubtypeBinding: Binding<String> {
        Binding(
            get: { draft?.vmSubtype ?? "" },
            set: { value in updateDraft { $0.vmSubtype = value } }
        )
    }

    private var containerSubtypeBinding: Binding<String> {
        Binding(
            get: { draft?.containerSubtype ?? "" },
            set: { value in updateDraft { $0.containerSubtype = value } }
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

    private var bundledAppIDBinding: Binding<String> {
        Binding(
            get: { draft?.runtimeOverrides.bundledAppID ?? "" },
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

    private func updateDraft(_ mutate: (inout MachineProfile) -> Void) {
        guard draft != nil else { return }
        var copy = draft!
        mutate(&copy)
        draft = copy
    }
}
