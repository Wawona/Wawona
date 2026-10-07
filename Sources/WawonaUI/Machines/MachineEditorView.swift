import SwiftUI
import WawonaModel
import WawonaUIContracts
import UniformTypeIdentifiers

struct MachineEditorView: View {
    @Environment(\.presentationMode) private var presentationMode
    private func dismiss() { presentationMode.wrappedValue.dismiss() }

    @State var name: String
    @State var type: MachineType
    @State var nativeShellKind: NativeShellKind
    @State var nativeShellUseSSH: Bool
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
    @State var vmIdentifier: String
    @State var vmVsockPort: String
    @State var vmGuestVariant: String
    @State var vmMemoryMB: Int
    @State var vmDiskGiB: Int
    @State var vmNotes: String
    @State var vmNixFiles: [String: String]
    @State var vmNixosGeneration: Int?
    @State var wasmCommand: String
    @State var wasmModulePath: String
    @State var wasmPackage: String
    @State var wasmCatalogResults: [WasmCatalogPackage] = []
    @State var wasmCatalogNote: String?
    @State var wasmCatalogLoading = false
    @State var showingImageBrowser = false
    @State var fileImportKind: MachineEditorFileImport?
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
        let state = MachineEditorDomain.machineEditorState(from: profile)
        _name = State(initialValue: state.name)
        _type = State(initialValue: MachineType(rawValue: state.typeRawValue) ?? .native)
        _nativeShellKind = State(
            initialValue: NativeShellKind(rawValue: state.nativeShellKindRawValue) ?? .terminal
        )
        _nativeShellUseSSH = State(initialValue: state.nativeShellUseSSH)
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
        _vmIdentifier = State(initialValue: state.vmIdentifier)
        _vmVsockPort = State(initialValue: state.vmVsockPort)
        _vmGuestVariant = State(initialValue: state.vmGuestVariant)
        _vmMemoryMB = State(initialValue: state.vmMemoryMB)
        _vmDiskGiB = State(initialValue: state.vmDiskGiB)
        _vmNotes = State(initialValue: state.vmNotes)
        _vmNixFiles = State(initialValue: profile?.vmSettings?.nixFiles ?? [:])
        _vmNixosGeneration = State(initialValue: profile?.vmSettings?.nixosGeneration)
        _wasmCommand = State(initialValue: state.wasmCommand)
        _wasmModulePath = State(initialValue: state.wasmModulePath)
        _wasmPackage = State(initialValue: state.wasmPackage)
    }

    private var fileImporterPresented: Binding<Bool> {
        Binding(
            get: { fileImportKind != nil },
            set: { presented in
                if !presented {
                    fileImportKind = nil
                }
            }
        )
    }

    private var isNative: Bool { type == .native }
    private var session: NativeShellSession {
        NativeShellSession(kind: nativeShellKind, useSSH: nativeShellUseSSH)
    }
    private var isWasm: Bool { isNative && nativeShellKind == .wasm }
    private var isSSH: Bool { isNative && session.needsSSHFields }
    private var contractState: MachineEditorState {
        persistableEditorState()
    }

    private func persistableEditorState() -> MachineEditorState {
        let base = MachineEditorDomain.machineEditorState(from: editingBaseline)
        let sanitizedHost = MachineProfileDomain.sanitizeSSHHost(sshHost)
        let normalizedPort = MachineProfileDomain.normalizeSSHPort(String(sshPort))
        let bundled = session.resolvedBundledAppID(selectedLauncher: selectedLauncherName) ?? ""
        return MachineEditorState(
            id: existingProfileId ?? base.id,
            name: name,
            typeRawValue: type.rawValue,
            nativeShellKindRawValue: nativeShellKind.rawValue,
            nativeShellUseSSH: nativeShellUseSSH,
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
            bundledAppID: isNative ? bundled : base.bundledAppID,
            waypipeEnabled: isNative ? session.waypipeEnabled : base.waypipeEnabled,
            containerRef: containerRef,
            entryCommand: entryCommand,
            desktopSession: desktopSession,
            imageArchivePath: imageArchivePath,
            vmIdentifier: vmIdentifier,
            vmVsockPort: vmVsockPort,
            vmGuestVariant: vmGuestVariant,
            vmMemoryMB: vmMemoryMB,
            vmDiskGiB: vmDiskGiB,
            vmNotes: vmNotes,
            wasmCommand: wasmCommand,
            wasmModulePath: wasmModulePath,
            wasmPackage: wasmPackage
        )
    }

    private var editorNavigationTitle: String {
        if existingProfileId != nil {
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Edit Machine" : name
        }
        return name.isEmpty ? "New Machine" : name
    }
    private var hasValidationIssues: Bool {
        !MachineProfileDomain.validate(contractState).isEmpty
    }
    var body: some View {
        WawonaBackport<Any>.navigation {
            Form {
                // MARK: Identity + type in one compact section
                Section(header: Text("Profile")) {
                    WawonaTextField("Name", text: $name)
                        .wwnA11y(WawonaA11y.machinesEditorName, label: "Name")
                    Picker("Type", selection: $type) {
                        ForEach(PlatformCapabilities.creatableMachineTypes, id: \.self) { t in
                            Text(t.userFacingName).tag(t)
                        }
                    }
                    .wwnMachineChoicePicker()
                    .wwnA11y(WawonaA11y.machinesEditorType, label: "Type")
                }

                if isNative {
                    Section {
                        Picker("Session", selection: $nativeShellKind) {
                            ForEach(NativeShellKind.allCases, id: \.self) { kind in
                                Text(kind.userFacingName).tag(kind)
                            }
                        }
                        .wwnMachineChoicePicker()
                        .wwnA11y("wwn.machines.editor.nativeShell.kind", label: "Native Shell Session")
                        if nativeShellKind.allowsSSH {
                            Toggle("Use SSH", isOn: $nativeShellUseSSH)
                        }
                        if nativeShellKind == .terminal {
                            WawonaTextField(
                                "Custom Command",
                                text: $remoteCommand,
                                prompt: Text(
                                    nativeShellUseSSH
                                        ? "e.g. bash -l"
                                        : "e.g. htop (empty = interactive shell)"
                                )
                            )
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        }
                    } header: {
                        Text("Native Shell Session")
                    } footer: {
                        Text(
                            nativeShellKind == .terminal
                                ? (nativeShellUseSSH
                                    ? "Custom Command runs in the remote SSH session. Empty defaults to bash -l."
                                    : "Optional Custom Command for Wawona Terminal. Empty opens an interactive shell.")
                                : nativeShellKind == .wayland
                                    ? "Bundled Wayland client on the local compositor socket."
                                    : nativeShellKind == .wasm
                                        ? "Relay WASI package (same bytecode as /wasm/v1)."
                                        : "Waypipe stream, with optional SSH to a remote host."
                        )
                    }

                    if nativeShellKind == .wasm {
                        Section {
                            WawonaTextField("Command", text: $wasmCommand, prompt: Text("wasm hello-wasi-gui"))
                                .wawonaTextFieldNoAutocaps()
                                .autocorrectionDisabled()
                            WawonaTextField("Package", text: $wasmPackage, prompt: Text("hello-wasi-gui"))
                                .wawonaTextFieldNoAutocaps()
                                .autocorrectionDisabled()
                            WawonaButton(
                                wasmCatalogLoading ? "Searching…" : "Search Catalog",
                                systemImage: "magnifyingglass"
                            ) {
                                searchWasmCatalog()
                            }
                            .disabled(wasmCatalogLoading)
                            ForEach(wasmCatalogResults) { pkg in
                                WawonaButton {
                                    wasmPackage = pkg.name
                                    wasmCommand = "wasm \(pkg.name)"
                                    downloadWasmPackage(pkg)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pkg.name)
                                        if !pkg.summary.isEmpty {
                                            Text(pkg.summary)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            WawonaTextField("Local .wasm", text: $wasmModulePath)
                                .wawonaTextFieldNoAutocaps()
                                .autocorrectionDisabled()
                            #if !os(tvOS)
                            WawonaButton("Choose File", systemImage: "folder") {
                                fileImportKind = .wasm
                            }
                            #endif
                            ForEach(WasmLaunch.listLocalModules(), id: \.path) { url in
                                WawonaButton(url.lastPathComponent, systemImage: "doc.badge.gearshape") {
                                    wasmModulePath = url.path
                                    wasmCommand = "wasm \(url.path)"
                                }
                            }
                            if let wasmCatalogNote {
                                Text(wasmCatalogNote).font(.caption)
                            }
                        } footer: {
                            Text("Search /wasm/v1, pick a local module, or type wasm hello-wasi-gui.")
                        }
                    }

                    if nativeShellKind == .wayland {
                        Section {
                            #if os(macOS)
                            Picker("Wayland Software", selection: $selectedLauncherName) {
                                ForEach(
                                    ClientLauncher.presets.waylandPickerGrouped(),
                                    id: \.kind
                                ) { group in
                                    Section(group.kind.sectionTitle) {
                                        ForEach(group.clients) { launcher in
                                            Text(launcher.displayName).tag(launcher.name)
                                        }
                                    }
                                }
                            }
                            .wwnMachineChoicePicker()
                            #else
                            NavigationLink {
                                BundledClientPickerView(selection: $selectedLauncherName)
                            } label: {
                                HStack {
                                    Text("Wayland Software")
                                    Spacer()
                                    Text(ClientLauncher.displayName(for: selectedLauncherName))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            #endif
                        } footer: {
                            Text("Compositors, then clients by type. Custom commands belong under Terminal. Connects on the local Wayland socket.")
                        }
                    }
                }

                // MARK: Container - OCI image run via wwn-containers
                if type == .container {
                    Section {
                        WawonaTextField("Image", text: $containerRef, prompt: Text("e.g. alpine:3.20"))
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                            .wwnA11y(WawonaA11y.machinesEditorContainerRef, label: "Image")
                        WawonaButton {
                            showingImageBrowser = true
                        } label: {
                            WawonaLabel("Choose from library…", systemImage: "shippingbox")
                        }
                        .wwnA11y(WawonaA11y.machinesEditorContainerHub, label: "Choose from library")
                        WawonaButton {
                            fileImportKind = .archive
                        } label: {
                            WawonaLabel("Import image archive…", systemImage: "square.and.arrow.down")
                        }
                        .disabled(importingArchive)

                        if importingArchive {
                            HStack(spacing: 6) {
                                WawonaProgressView().backport.controlSize(.small)
                                Text("Importing…").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        if let importNote {
                            Text(importNote)
                                .font(.caption)
                                .foregroundColor(importNote.hasPrefix("imported") ? .green : .red)
                        }
                        if !imageArchivePath.isEmpty {
                            HStack {
                                Image(systemName: "internaldrive")
                                    .foregroundColor(.secondary)
                                Text("Archive: \(displayArchivePath)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                WawonaButton("Clear") { imageArchivePath = ""; containerRef = ""; importNote = nil }
                                    .buttonStyle(.borderless)
                                    .backport.controlSize(.small)
                            }
                        }
                        WawonaTextField("Command", text: $entryCommand, prompt: Text("e.g. /bin/sh"))
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
                            + Text("Desktop session attaches the container's Wayland session to Wawona via the waypipe vsock bridge: apps appear as windows (a nested desktop like GNOME/KDE shows as one window).")
                            + Text("\n")
                            + Text("Import image archive… adds a local image (docker-archive tar/tar.gz, OCI-archive, or OCI layout directory; format detected automatically) and runs the machine from it without a registry pull.")
                    }
                }

                if type == .virtualMachine {
                    Section {
                        HStack {
                            Text("Backend")
                            Spacer()
                            Text("Wawona Relay")
                                .foregroundColor(.secondary)
                        }
                        WawonaTextField("VM Identifier", text: $vmIdentifier, prompt: Text("e.g. studio-linux"))
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        Picker("NixOS guest", selection: $vmGuestVariant) {
                            Text("NixOS 4K pages").tag("4k")
                            Text("NixOS 16K pages").tag("16k")
                        }
                        .wwnMachineChoicePicker()
                        NixGenerationPicker(
                            machineId: existingProfileId ?? "",
                            vmIdentifier: vmIdentifier,
                            generation: $vmNixosGeneration
                        )
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Memory")
                                Spacer()
                                Text("\(vmMemoryMB) MiB")
                                    .foregroundColor(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(vmMemoryMB) },
                                    set: { vmMemoryMB = Int($0.rounded()) }
                                ),
                                in: 256...4096,
                                step: 256
                            )
                            .accessibility(label: Text("Virtual machine memory"))
                            .accessibility(identifier: "wwn.vm.memory")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Storage")
                                Spacer()
                                Text("\(vmDiskGiB) GiB")
                                    .foregroundColor(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(vmDiskGiB) },
                                    set: { vmDiskGiB = Int($0.rounded()) }
                                ),
                                in: Double(max(4, min(editingBaseline?.vmSettings?.diskGiB ?? 4, 64)))...64,
                                step: 1
                            )
                            .accessibility(label: Text("Virtual machine storage"))
                            .accessibility(identifier: "wwn.vm.storage")
                            HStack {
                                Text("\(max(4, min(editingBaseline?.vmSettings?.diskGiB ?? 4, 64))) GiB")
                                Spacer()
                                Text("64 GiB")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        WawonaLabeledContent("Connection", value: "Automatic")
                        NixConfigurationEditor(files: $vmNixFiles)
                        WawonaTextField("Notes", text: $vmNotes)
                    } header: {
                        Text("Virtual Machine")
                    } footer: {
                        Text("Memory and storage changes apply after stopping and starting the machine. Storage can grow but cannot shrink. Changing the VM Identifier selects a different disk.")
                    }
                }

                // MARK: SSH - Terminal or Waypipe with Use SSH
                if isSSH {
                    Section(header: Text("Remote Host")) {
                        WawonaTextField("Host", text: $sshHost, prompt: Text("e.g. 192.168.1.100 or host.local"))
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        WawonaTextField("Username", text: $sshUser, prompt: Text("e.g. user or root"))
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        SecureField("Password", text: $sshPassword)
                            .textContentType(.password)
                        WawonaLabeledContent("Port") {
                            NativeBoundedIntegerField(
                                title: "Port",
                                value: $sshPort,
                                range: 1...65_535,
                                step: 1,
                                prompt: "22"
                            )
                            .frame(width: 170)
                        }
                        Picker("Auth", selection: $sshAuthMethod) {
                            Text("Password").tag(0)
                            Text("Public Key").tag(1)
                        }
                        .wwnMachineChoicePicker()
                        WawonaTextField("Key Path", text: $sshKeyPath, prompt: Text("e.g. ~/.ssh/id_ed25519"))
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        SecureField("Key Passphrase", text: $sshKeyPassphrase)
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                    }

                    if nativeShellKind == .waypipe {
                        Section {
                            WawonaTextField(
                                "e.g. weston-simple-shm",
                                text: $remoteCommand
                            )
                            .wawonaTextFieldNoAutocaps()
                            .autocorrectionDisabled()
                        } header: {
                            Text("Waypipe Remote Command")
                        } footer: {
                            Text("Command to run on the remote host via waypipe.")
                        }
                    }
                }
            }
            .backport.navigationTitle(editorNavigationTitle)
            #if os(iOS)
            .backport.dismissKeyboardOnScroll()
            #endif
            .wwnA11y(WawonaA11y.machinesEditor, label: editorNavigationTitle)
            .backport.navigationActions(trailingIsPrimary: false, leading: {
                    WawonaButton { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                        .backport.glassToolbarButton()
                        .wwnA11y(WawonaA11y.machinesEditorCancel, label: "Cancel")
                }, trailing: {
                    WawonaButton(action: save) {
                        Image(systemName: "checkmark").font(.body.weight(.semibold))
                    }
                        .backport.blueGlassCircleButton(size: 44)
                        .disabled(hasValidationIssues)
                        .wwnA11y(WawonaA11y.machinesEditorSave, label: "Save")
                })
            .sheet(isPresented: $showingImageBrowser) {
                ContainerImagesView { ref in
                    containerRef = ref
                }
            }
            #if !os(tvOS)
            .backport.fileImporter(
                isPresented: fileImporterPresented,
                allowedContentTypes: fileImportKind == .wasm
                    ? [.filenameExtension("wasm")]
                    : [.item, .directory]
            ) { result in
                let kind = fileImportKind
                fileImportKind = nil
                switch kind {
                case .wasm:
                    if case .success(let url) = result {
                        wasmModulePath = url.path
                        wasmCommand = "wasm \(url.path)"
                    }
                case .archive:
                    handleArchiveImport(result)
                case .none:
                    break
                }
            }
            #endif
        }
    }

    private var displayArchivePath: String {
        (imageArchivePath as NSString).lastPathComponent
    }

    private func searchWasmCatalog() {
        wasmCatalogLoading = true
        wasmCatalogNote = nil
        let query = wasmPackage
        Task {
            do {
                wasmCatalogResults = try await Task.detached {
                    try WasmLaunch.searchCatalog(query)
                }.value
                if wasmCatalogResults.isEmpty {
                    wasmCatalogNote = "No packages in /wasm/v1 match."
                }
            } catch {
                wasmCatalogNote = error.localizedDescription
            }
            wasmCatalogLoading = false
        }
    }

    private func downloadWasmPackage(_ pkg: WasmCatalogPackage) {
        wasmCatalogLoading = true
        Task {
            do {
                wasmModulePath = try await Task.detached {
                    try WasmLaunch.downloadPackage(pkg)
                }.value
                wasmCatalogNote = "Saved \(pkg.name) to the Wawona folder."
            } catch {
                wasmCatalogNote = error.localizedDescription
            }
            wasmCatalogLoading = false
        }
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
        if !MachineProfileDomain.validate(state).isEmpty {
            return
        }
        var profile = MachineEditorDomain.profile(from: state)
        if profile.name.isEmpty {
            profile.name = "Unnamed"
        }
        if let baseline = editingBaseline {
            profile.favorite = baseline.favorite
            profile.runtimeOverrides.renderer = baseline.runtimeOverrides.renderer
            profile.runtimeOverrides.resizeDisplayForVirtualKeyboard =
                baseline.runtimeOverrides.resizeDisplayForVirtualKeyboard
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
                    desktopSession: desktopSession,
                    imageArchivePath: imageArchivePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                        ? nil
                        : imageArchivePath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                )
            }
        }
        if type == .virtualMachine {
            profile.vmSettings?.nixFiles = vmNixFiles
            profile.vmSettings?.nixosGeneration = vmNixosGeneration
        }
        onSave(profile)
        dismiss()
    }
}

enum MachineEditorFileImport {
    case archive
    case wasm
}

private extension View {
    @ViewBuilder
    func wwnMachineChoicePicker() -> some View {
        #if os(macOS)
        self.pickerStyle(.menu)
        #else
        if #available(iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            self.pickerStyle(.navigationLink)
        } else {
            self.pickerStyle(DefaultPickerStyle())
        }
        #endif
    }
}
