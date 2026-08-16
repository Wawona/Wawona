#if os(watchOS)
import SwiftUI
import WatchKit
import WawonaModel
import WawonaUIContracts

/// Presents global Wawona Settings via WatchKit (preferred), with SwiftUI fallback
/// when no WKInterfaceController host is available (pure SwiftUI `@main` lifecycle).
/// Both hosts must render `GlobalSettingsCatalog` for `.watchOS`.
enum WatchKitGlobalSettings {
    /// Posted when WatchKit presentation fails so SwiftUI can show a fallback sheet.
    static let fallbackPresentationNeeded = Notification.Name("WWNWatchSettingsFallbackNeeded")

    static func registerHost() {
        if let controller = WKExtension.shared().visibleInterfaceController {
            WWNWatchPreferencesCoordinator.setHostInterfaceController(controller)
        }
    }

    @discardableResult
    static func open() -> Bool {
        registerHost()
        let presented = WWNWatchPreferencesCoordinator.shared().showSettings()
        if !presented {
            NotificationCenter.default.post(name: fallbackPresentationNeeded, object: nil)
        }
        return presented
    }
}

/// Global Wawona Settings for watchOS — same section catalog as iOS/macOS
/// (`GlobalSettingsCatalog`), minus Desktop (forbidden) and Local Shell.
struct WatchGlobalSettingsView: View {
    @ObservedObject private var preferences = WawonaPreferences.shared
    @Environment(\.dismiss) private var dismiss

    private let sections = GlobalSettingsCatalog.visibleSections(for: .watchOS)

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.self) { section in
                    NavigationLink {
                        WatchGlobalSettingsSectionHost(section: section, preferences: preferences)
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                    .accessibilityIdentifier("wwn.settings.\(section.rawValue)")
                }
            }
            .navigationTitle("Wawona Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        preferences.save()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                preferences.save()
            }
        }
    }
}

private struct WatchGlobalSettingsSectionHost: View {
    let section: GlobalSettingsSectionID
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Group {
            switch section {
            case .display:
                WatchSettingsDisplaySection(preferences: preferences)
            case .input:
                WatchSettingsInputSection(preferences: preferences)
            case .graphics:
                WatchSettingsGraphicsSection(preferences: preferences)
            case .connection:
                WatchSettingsConnectionSection(preferences: preferences)
            case .environment:
                WatchEnvironmentVariablesSection(preferences: preferences)
            case .waypipe:
                WatchSettingsWaypipeSection(preferences: preferences)
            case .ssh:
                WatchSettingsSSHSection(preferences: preferences)
            case .advanced:
                WatchSettingsAdvancedSection(preferences: preferences)
            case .about:
                WatchSettingsAboutSection()
            case .localShell, .desktop, .appleWatch:
                Text("Unavailable on watchOS")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func watchShows(_ field: GlobalSettingsFieldID, in section: GlobalSettingsSectionID) -> Bool {
    GlobalSettingsCatalog.visibleFields(in: section, for: .watchOS).contains(field)
}

// MARK: - Section detail views

private struct WatchSettingsDisplaySection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            if watchShows(.autoScale, in: .display) {
                Toggle("Auto Scale", isOn: $preferences.autoScale)
            }
            if watchShows(.forceSSD, in: .display), PlatformCapabilities.supportsClientSideDecorations {
                Toggle("Force SSD", isOn: $preferences.forceSSD)
            }
            if watchShows(.respectSafeArea, in: .display) {
                Text("Respect Safe Area is iPhone-only.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(GlobalSettingsSectionID.display.title)
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsInputSection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            if watchShows(.virtualCursor, in: .input) {
                Toggle("Show Virtual Cursor", isOn: $preferences.renderMacOSPointer)
            }
            if watchShows(.nestedCompositorCursor, in: .input) {
                Picker("Nested Compositor Cursor", selection: $preferences.nestedCompositorCursor) {
                    Text("Virtual Pointer").tag("virtual")
                    Text("Host Cursor").tag("host")
                }
                .disabled(!preferences.renderMacOSPointer)
            }
            if watchShows(.touchInputType, in: .input) {
                Picker("Touch Input Type", selection: $preferences.defaultInputProfile) {
                    Text("Multi-Touch").tag("Multi-Touch")
                    Text("Touchpad").tag("Touchpad")
                }
                Text("Multi-Touch is finger→wl_touch. Touchpad is the iOS virtual pointer (relative drag, tap=click). Crown scrolls in Touchpad mode.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if watchShows(.resizeDisplayForVirtualKeyboard, in: .input) {
                Toggle("Resize Display for Virtual Keyboard", isOn: $preferences.resizeDisplayForVirtualKeyboard)
            }
            if watchShows(.swapCmdWithAlt, in: .input) {
                Toggle("Swap CMD with ALT", isOn: $preferences.swapCmdWithAlt)
            }
            if watchShows(.universalClipboard, in: .input) {
                Toggle("Universal Clipboard", isOn: $preferences.universalClipboard)
            }
        }
        .navigationTitle(GlobalSettingsSectionID.input.title)
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsGraphicsSection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            if watchShows(.renderer, in: .graphics) {
                Picker("Renderer", selection: $preferences.renderer) {
                    Text("metal").tag("metal")
                    Text("software").tag("software")
                }
            }
            if watchShows(.vulkanDriver, in: .graphics) {
                LabeledContent("Vulkan Driver", value: "None")
            }
            if watchShows(.openGLDriver, in: .graphics) {
                LabeledContent("OpenGL Driver", value: "None")
            }
            if watchShows(.dmabufEnabled, in: .graphics) {
                LabeledContent("Enable DMABUF", value: "Off")
            }
            Text("watchOS has no Metal GPU stack — compositor presents via SHM/CPU. GPU clients stay unavailable.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(GlobalSettingsSectionID.graphics.title)
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsConnectionSection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            if watchShows(.waylandDisplay, in: .connection) {
                TextField("Wayland Display", text: $preferences.waylandDisplay)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if watchShows(.defaultWaylandClient, in: .connection) {
                NavigationLink {
                    WatchBundledClientPickerView(selection: $preferences.defaultBundledAppID)
                } label: {
                    HStack {
                        Text("Default Wayland Client")
                        Spacer()
                        Text(ClientLauncher.displayName(for: preferences.defaultBundledAppID))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(GlobalSettingsSectionID.connection.title)
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsWaypipeSection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            if watchShows(.waypipeByDefault, in: .waypipe) {
                Toggle("Waypipe by Default", isOn: $preferences.defaultWaypipeEnabled)
            }
            if watchShows(.waypipeXwayland, in: .waypipe) {
                Toggle("XWayland", isOn: $preferences.xwaylandSupport)
            }
            if watchShows(.waypipePassword, in: .waypipe) {
                SecureField("Waypipe Password", text: $preferences.waypipeSSHPassword)
            }
            if watchShows(.waypipeCompress, in: .waypipe) {
                Picker("Compression", selection: $preferences.waypipeCompress) {
                    Text("none").tag("none")
                    Text("lz4").tag("lz4")
                    Text("zstd").tag("zstd")
                }
            }
            if watchShows(.waypipeVideo, in: .waypipe) {
                Picker("Video Codec", selection: $preferences.waypipeVideo) {
                    Text("none").tag("none")
                    Text("h264").tag("h264")
                    Text("vp9").tag("vp9")
                    Text("av1").tag("av1")
                }
            }
            if watchShows(.waypipeRemoteCommand, in: .waypipe) {
                TextField("Remote Command", text: $preferences.waypipeRemoteCommand)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if watchShows(.waypipeDebug, in: .waypipe) {
                Toggle("Debug Mode", isOn: $preferences.waypipeDebug)
            }
            if watchShows(.waypipeNoGpu, in: .waypipe) {
                Toggle("Disable GPU", isOn: $preferences.waypipeNoGpu)
            }
            Text("Global defaults for all machines. Per-machine Waypipe settings override these values.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(GlobalSettingsSectionID.waypipe.title)
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsSSHSection: View {
    @ObservedObject var preferences: WawonaPreferences
    @State private var keygenMessage: String?

    var body: some View {
        Form {
            if watchShows(.sshHost, in: .ssh) {
                TextField("Host", text: $preferences.sshHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if watchShows(.sshUser, in: .ssh) {
                TextField("User", text: $preferences.sshUser)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if watchShows(.sshPort, in: .ssh) {
                TextField("Port", text: Binding(
                    get: { String(preferences.sshPort) },
                    set: { preferences.sshPort = Int($0) ?? preferences.sshPort }
                ))
            }
            if watchShows(.sshAuthMethod, in: .ssh) {
                Picker("Auth", selection: $preferences.sshAuthMethod) {
                    Text("Password").tag(0)
                    Text("Public Key").tag(1)
                }
            }
            if preferences.sshAuthMethod == 0 {
                if watchShows(.sshPassword, in: .ssh) {
                    SecureField("Password", text: $preferences.sshPassword)
                }
            } else {
                if watchShows(.sshKeyType, in: .ssh) {
                    Picker("Key Type", selection: $preferences.sshKeyType) {
                        Text("ed25519").tag("ed25519")
                        Text("ecdsa").tag("ecdsa")
                        Text("rsa").tag("rsa")
                    }
                }
                if watchShows(.sshKeyPath, in: .ssh) {
                    TextField("Key Path", text: $preferences.sshKeyPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if watchShows(.sshKeyPassphrase, in: .ssh) {
                    SecureField("Key Passphrase", text: $preferences.sshKeyPassphrase)
                }
                if watchShows(.sshGenerateKey, in: .ssh) {
                    Button("Generate Key") {
                        do {
                            let path = try WWNSSHKeygen.generateKeyType(
                                preferences.sshKeyType,
                                passphrase: preferences.sshKeyPassphrase
                            )
                            preferences.sshKeyPath = path
                            preferences.sshAuthMethod = 1
                            preferences.save()
                            keygenMessage = "Created \(path)"
                        } catch {
                            keygenMessage = error.localizedDescription
                        }
                    }
                    Text("GPG: copy gpg --export-ssh-key into Documents/ssh and set Key Path.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let keygenMessage {
                Text(keygenMessage).font(.caption2)
            }
        }
        .navigationTitle(GlobalSettingsSectionID.ssh.title)
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsAdvancedSection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            if watchShows(.colorOperations, in: .advanced) {
                Toggle("Color Operations (HDR)", isOn: $preferences.colorOperations)
            }
            if watchShows(.nestedCompositors, in: .advanced) {
                Toggle("Nested Compositors", isOn: $preferences.nestedCompositorsSupport)
            }
            if watchShows(.compositorBackend, in: .advanced) {
                Picker("Display Backend", selection: $preferences.compositorBackend) {
                    Text("Auto").tag("auto")
                    Text("Wayland (nested)").tag("wayland")
                    Text("DRM/KMS (wwn-iland)").tag("drm")
                }
            }
            if watchShows(.multipleClients, in: .advanced) {
                Toggle("Multiple Clients", isOn: $preferences.multipleClients)
            }
            if watchShows(.logLevel, in: .advanced) {
                Picker("Log Level", selection: $preferences.logLevel) {
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Warn").tag("warn")
                    Text("Error").tag("error")
                }
            }
            if watchShows(.shakeToClose, in: .advanced) {
                Toggle("Shake to Close", isOn: $preferences.shakeToCloseEnabled)
            }
            if watchShows(.swipeBackToClose, in: .advanced) {
                Toggle("Swipe Back to Close", isOn: $preferences.swipeBackToCloseEnabled)
            }
        }
        .navigationTitle(GlobalSettingsSectionID.advanced.title)
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsAboutSection: View {
    var body: some View {
        Form {
            if watchShows(.aboutVersion, in: .about) {
                LabeledContent("Version", value: watchAboutVersion)
            }
            if watchShows(.aboutPlatform, in: .about) {
                LabeledContent("Platform", value: "watchOS")
            }
            if watchShows(.aboutAuthor, in: .about) {
                LabeledContent("Author", value: "Alex Spaulding")
            }
            if watchShows(.aboutSource, in: .about) {
                Link("Source Code", destination: URL(string: "https://github.com/wawona/wawona")!)
            }
            if watchShows(.aboutSponsors, in: .about) {
                Link("GitHub Sponsors", destination: URL(string: "https://github.com/sponsors/aspauldingcode")!)
            }
            if watchShows(.aboutPortfolio, in: .about) {
                Link("Portfolio", destination: URL(string: "https://aspauldingcode.com")!)
            }
        }
        .navigationTitle(GlobalSettingsSectionID.about.title)
    }

    private var watchAboutVersion: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let version = (raw?.isEmpty == false) ? raw! : "0.0.0"
        return version.hasPrefix("v") ? version : "v\(version)"
    }
}

/// Compact Environment Variables list for watchOS (#157 / #159).
private struct WatchEnvironmentVariablesSection: View {
    @ObservedObject var preferences: WawonaPreferences
    @State private var confirmReset = false

    private var rows: [ResolvedEnvironmentEntry] {
        preferences.resolvedEnvironment(for: nil).filter { !$0.isSecret }
    }

    var body: some View {
        List {
            ForEach(rows.prefix(40)) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.caption.monospaced())
                    Text(row.displayValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(row.source.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .accessibilityIdentifier("wwn.settings.environment.row.\(row.name)")
            }
            Section {
                Button("Reset Wawona-managed") {
                    preferences.resetEnvironmentManaged()
                }
                .accessibilityIdentifier("wwn.settings.environment.resetManaged")
                Button("Reset All", role: .destructive) {
                    confirmReset = true
                }
                .accessibilityIdentifier("wwn.settings.environment.resetAll")
            }
        }
        .navigationTitle(GlobalSettingsSectionID.environment.title)
        .accessibilityIdentifier("wwn.settings.environment")
        .confirmationDialog("Reset all overrides?", isPresented: $confirmReset) {
            Button("Reset All", role: .destructive) {
                preferences.resetEnvironmentAll()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
#endif
