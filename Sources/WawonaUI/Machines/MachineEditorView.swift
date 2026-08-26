import SwiftUI
import WawonaModel
import WawonaUIContracts
import UniformTypeIdentifiers

struct MachineEditorView: View {
    @Environment(\.dismiss) var dismiss

    @State var name: String
    @State var type: MachineType
    @State var selectedLauncherName: String
    @State var sshHost: String
    @State var sshUser: String
    @State var sshPort: Int
    @State var sshPassword: String
    @State var sshAuthMethod: Int
    @State var sshKeyPath: String
    @State var sshKeyPassphrase: String
    @State var remoteCommand: String
    @State var containerRef: String
    @State var entryCommand: String
    @State var desktopSession: Bool
    @State var imageArchivePath: String
    @State var showingImageBrowser = false
    @State var showingArchiveImporter = false
    @State var importingArchive = false
    @State var importNote: String?

    let existingProfileId: String?
    /// Snapshot for fields this form does not edit (VM/container metadata, favorites, renderer, etc.).
    let editingBaseline: MachineProfile?
    let onSave: (MachineProfile) -> Void

    init(profile: MachineProfile? = nil, onSave: @escaping (MachineProfile) -> Void) {
        self.existingProfileId = profile?.id
        self.editingBaseline = profile
        self.onSave = onSave
        let state = WawonaUIContractAdapters.machineEditorState(from: profile)
        _name = State(initialValue: state.name)
        #if os(iOS)
        let parsed = MachineType(rawValue: state.typeRawValue) ?? .native
        _type = State(initialValue: parsed == .container ? .native : parsed)
        #else
        _type = State(initialValue: MachineType(rawValue: state.typeRawValue) ?? .native)
        #endif
        _selectedLauncherName = State(initialValue: state.selectedLauncherName)
        _sshHost = State(initialValue: state.sshHost)
        _sshUser = State(initialValue: state.sshUser)
        _sshPort = State(initialValue: MachineEditorValidation.normalizedPort(from: state))
        _sshPassword = State(initialValue: state.sshPassword)
        _sshAuthMethod = State(initialValue: state.sshAuthMethod)
        _sshKeyPath = State(initialValue: state.sshKeyPath)
        _sshKeyPassphrase = State(initialValue: state.sshKeyPassphrase)
        _remoteCommand = State(initialValue: state.remoteCommand)
        _containerRef = State(initialValue: state.containerRef)
        _entryCommand = State(initialValue: state.entryCommand)
        _desktopSession = State(initialValue: state.desktopSession)
        _imageArchivePath = State(initialValue: state.imageArchivePath)
    }

    private var isNative: Bool { type == .native }
    private var isSSH:    Bool { type.isSSH }
    private var contractState: MachineEditorState {
        persistableEditorState()
    }

    private func persistableEditorState() -> MachineEditorState {
        let base = WawonaUIContractAdapters.machineEditorState(from: editingBaseline)
        let sanitizedHost = MachineEditorValidation.sanitizeSSHHost(sshHost)
        let normalizedPort = MachineEditorValidation.normalizeSSHPort(String(sshPort))
        return MachineEditorState(
            id: existingProfileId ?? base.id,
            name: name,
            typeRawValue: type.rawValue,
            selectedLauncherName: selectedLauncherName,
            sshHost: sanitizedHost,
            sshUser: sshUser,
            sshPortText: String(normalizedPort),
            sshPassword: sshPassword,
            sshAuthMethod: sshAuthMethod,
            sshKeyPath: sshKeyPath,
            sshKeyPassphrase: sshKeyPassphrase,
            remoteCommand: remoteCommand,
            inputProfile: base.inputProfile,
            bundledAppID: isNative ? selectedLauncherName : base.bundledAppID,
            waypipeEnabled: base.waypipeEnabled,
            containerRef: containerRef,
            entryCommand: entryCommand,
            desktopSession: desktopSession,
            imageArchivePath: imageArchivePath
        )
    }

    private var editorNavigationTitle: String {
        if existingProfileId != nil {
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Edit Machine" : name
        }
        return name.isEmpty ? "New Machine" : name
    }
    private var hasValidationIssues: Bool {
        !MachineEditorValidation.validate(contractState).isEmpty
    }
    private var sshPortText: Binding<String> {
        Binding(
            get: { String(sshPort) },
            set: { sshPort = MachineEditorValidation.normalizeSSHPort($0, fallback: sshPort) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Identity + type in one compact section
                Section("Profile") {
                    TextField("Name", text: $name)
                        .wwnA11y(WawonaA11y.machinesEditorName, label: "Name")
                    Picker("Type", selection: $type) {
                        ForEach(PlatformCapabilities.availableMachineTypes, id: \.self) { t in
                            Text(t.userFacingName).tag(t)
                        }
                    }
                    .wwnMachineChoicePicker()
                    .wwnA11y(WawonaA11y.machinesEditorType, label: "Type")
                }

                // MARK: Native. Local Wayland socket, no network
                if isNative {
                    Section {
                        #if os(macOS)
                        Picker("Wayland Client", selection: $selectedLauncherName) {
                            ForEach(ClientLauncher.presets) { launcher in
                                Text(launcher.displayName).tag(launcher.name)
                            }
                        }
                        .wwnMachineChoicePicker()
                        #else
                        NavigationLink {
                            BundledClientPickerView(selection: $selectedLauncherName)
                        } label: {
                            HStack {
                                Text("Wayland Client")
                                Spacer()
                                Text(ClientLauncher.displayName(for: selectedLauncherName))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        #endif
                    } footer: {
                        Text("Connects to the compositor via local Wayland socket. No network or SSH required.")
                    }
                }

                // MARK: Container — OCI image run via wwn-containers
                if type == .container {
                    Section {
                        TextField("Image", text: $containerRef, prompt: Text("e.g. alpine:3.20"))
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                            .wwnA11y(WawonaA11y.machinesEditorContainerRef, label: "Image")
                        Button {
                            showingImageBrowser = true
                        } label: {
                            Label("Choose from library…", systemImage: "shippingbox")
                        }
                        .wwnA11y(WawonaA11y.machinesEditorContainerHub, label: "Choose from library")
                        Button {
                            showingArchiveImporter = true
                        } label: {
                            Label("Import image archive…", systemImage: "square.and.arrow.down")
                        }
                        .disabled(importingArchive)

                        if importingArchive {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Importing…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let importNote {
                            Text(importNote)
                                .font(.caption)
                                .foregroundStyle(importNote.hasPrefix("imported") ? .green : .red)
                        }
                        if !imageArchivePath.isEmpty {
                            HStack {
                                Image(systemName: "internaldrive")
                                    .foregroundStyle(.secondary)
                                Text("Archive: \(displayArchivePath)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Clear") { imageArchivePath = ""; containerRef = ""; importNote = nil }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                            }
                        }
                        TextField("Command", text: $entryCommand, prompt: Text("e.g. /bin/sh"))
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                            .wwnA11y(WawonaA11y.machinesEditorContainerCommand, label: "Command")
                        Toggle("Desktop session", isOn: $desktopSession)
                            .wwnA11y(WawonaA11y.machinesEditorContainerDesktop, label: "Desktop session")
                    } header: {
                        Text("Container")
                    } footer: {
                        Text("Empty fields inherit the global Settings → Containers defaults. "
                             + "Memory, mounts, ports and kernel paths are configured in Machine Settings.")
                            + Text("\n")
                            + Text("Desktop session attaches the container's Wayland session to Wawona via the waypipe vsock bridge — apps appear as windows (a nested desktop like GNOME/KDE shows as one window).")
                            + Text("\n")
                            + Text("Import image archive… adds a local image (docker-archive tar/tar.gz, OCI-archive, or OCI layout directory — format detected automatically) and runs the machine from it without a registry pull.")
                    }
                }

                // MARK: SSH — remote machine via network
                if isSSH {
                    Section("Remote Host") {
                        TextField("Host", text: $sshHost)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        TextField("Username", text: $sshUser)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        SecureField("Password", text: $sshPassword)
                            .textContentType(.password)
                        TextField("Port", text: sshPortText)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        Picker("Auth", selection: $sshAuthMethod) {
                            Text("Password").tag(0)
                            Text("Public Key").tag(1)
                        }
                        .wwnMachineChoicePicker()
                        TextField("Key Path", text: $sshKeyPath)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        SecureField("Key Passphrase", text: $sshKeyPassphrase)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                    }

                    Section {
                        TextField(
                            type == .sshWaypipe ? "e.g. weston-simple-shm" : "e.g. bash -l",
                            text: $remoteCommand
                        )
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                    } header: {
                        Text(type == .sshWaypipe ? "Waypipe Remote Command" : "SSH Command")
                    } footer: {
                        Text(type == .sshWaypipe
                             ? "Command to run on the remote host via waypipe."
                             : "Command to run in the remote SSH session.")
                    }
                }
            }
            .navigationTitle(editorNavigationTitle)
            .wwnA11y(WawonaA11y.machinesEditor, label: editorNavigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .wwnA11y(WawonaA11y.machinesEditorCancel, label: "Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(hasValidationIssues)
                        .wwnA11y(WawonaA11y.machinesEditorSave, label: "Save")
                }
            }
            .sheet(isPresented: $showingImageBrowser) {
                ContainerImagesView { ref in
                    containerRef = ref
                }
            }
            .fileImporter(
                isPresented: $showingArchiveImporter,
                allowedContentTypes: [.item, .directory]
            ) { result in
                handleArchiveImport(result)
            }
        }
    }

    private var displayArchivePath: String {
        (imageArchivePath as NSString).lastPathComponent
    }

    private func handleArchiveImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importNote = "Import failed: \(error.localizedDescription)"
        case .success(let url):
            let path = url.path
            importingArchive = true
            importNote = nil
            Task {
                do {
                    let imported = try await ContainerImageManager.importFromDiskResolved(path) { _ in }
                    containerRef = imported.canonical
                    imageArchivePath = imported.ociLayout
                    importNote = "imported \(imported.canonical)"
                } catch {
                    importNote = "Import failed: \(error.localizedDescription)"
                }
                importingArchive = false
            }
        }
    }

    private func save() {
        let state = persistableEditorState()
        if !MachineEditorValidation.validate(state).isEmpty {
            return
        }
        var profile = WawonaUIContractAdapters.profile(from: state)
        if profile.name.isEmpty {
            profile.name = "Unnamed"
        }
        if let baseline = editingBaseline {
            profile.favorite = baseline.favorite
            profile.runtimeOverrides.renderer = baseline.runtimeOverrides.renderer
            // The editor form only carries image ref + command; preserve the
            // advanced container fields (memory, mounts, ports, kernel paths)
            // edited in Machine Settings.
            if type == .container, let base = baseline.containerSettings {
                let ref = containerRef.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let cmd = entryCommand.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                profile.containerSettings = ContainerMachineSettings(
                    runtime: base.runtime,
                    containerRef: ref.isEmpty ? nil : ref,
                    entryCommand: cmd.isEmpty ? nil : cmd,
                    notes: base.notes,
                    memory: base.memory,
                    shmSize: base.shmSize,
                    mounts: base.mounts,
                    ports: base.ports,
                    platform: base.platform,
                    readOnly: base.readOnly,
                    remove: base.remove,
                    kernelPath: base.kernelPath,
                    initfsPath: base.initfsPath,
                    vsockPort: base.vsockPort,
                    desktopSession: desktopSession ? true : nil,
                    imageArchivePath: imageArchivePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                        ? nil
                        : imageArchivePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                )
            }
        }
        onSave(profile)
        dismiss()
    }
}

private extension View {
    @ViewBuilder
    func wwnMachineChoicePicker() -> some View {
        #if os(macOS)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.navigationLink)
        #endif
    }
}
