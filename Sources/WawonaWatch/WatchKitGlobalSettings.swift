#if os(watchOS)
import SwiftUI
import WatchKit
import WawonaModel

/// Presents global Wawona Settings via WatchKit (preferred), with SwiftUI fallback
/// when no WKInterfaceController host is available (pure SwiftUI `@main` lifecycle).
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

/// Global Wawona Settings for watchOS — section list → drill-in detail (macOS
/// sidebar equivalent). Each section opens its own view; About is full-screen.
struct WatchGlobalSettingsView: View {
    @ObservedObject private var preferences = WawonaPreferences.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WatchSettingsDisplaySection(preferences: preferences)
                } label: {
                    settingsRow(title: "Display", systemImage: "display")
                }
                NavigationLink {
                    WatchSettingsGraphicsSection(preferences: preferences)
                } label: {
                    settingsRow(title: "Graphics", systemImage: "cpu")
                }
                NavigationLink {
                    WatchSettingsConnectionSection(preferences: preferences)
                } label: {
                    settingsRow(title: "Connection", systemImage: "network")
                }
                NavigationLink {
                    WatchSettingsSSHSection(preferences: preferences)
                } label: {
                    settingsRow(title: "SSH Defaults", systemImage: "lock.shield")
                }
                NavigationLink {
                    WatchSettingsAdvancedSection(preferences: preferences)
                } label: {
                    settingsRow(title: "Advanced", systemImage: "gearshape.2")
                }
                NavigationLink {
                    WatchSettingsAboutSection()
                } label: {
                    settingsRow(title: "About", systemImage: "info.circle")
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

    @ViewBuilder
    private func settingsRow(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }
}

// MARK: - Section detail views

private struct WatchSettingsDisplaySection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            Toggle("Auto Scale", isOn: $preferences.autoScale)
            // Force SSD is macOS-only (#120): watchOS always draws SSD.
            if PlatformCapabilities.supportsClientSideDecorations {
                Toggle("Force SSD", isOn: $preferences.forceSSD)
            }
            Toggle("Color Operations (HDR)", isOn: $preferences.colorOperations)
        }
        .navigationTitle("Display")
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsGraphicsSection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            Picker("Renderer", selection: $preferences.renderer) {
                Text("metal").tag("metal")
                Text("software").tag("software")
            }
            Text("watchOS has no Metal GPU stack — compositor presents via SHM/CPU. GPU clients (EGL cubes, kmscube, vkcube) stay unavailable.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Graphics")
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsConnectionSection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            TextField("Wayland Display", text: $preferences.waylandDisplay)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Input Profile", text: $preferences.defaultInputProfile)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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
            Toggle("Waypipe by Default", isOn: $preferences.defaultWaypipeEnabled)
        }
        .navigationTitle("Connection")
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsSSHSection: View {
    @ObservedObject var preferences: WawonaPreferences
    @State private var keygenMessage: String?

    var body: some View {
        Form {
            TextField("Host", text: $preferences.sshHost)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("User", text: $preferences.sshUser)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Port", text: Binding(
                get: { String(preferences.sshPort) },
                set: { preferences.sshPort = Int($0) ?? preferences.sshPort }
            ))
            Picker("Auth", selection: $preferences.sshAuthMethod) {
                Text("Password").tag(0)
                Text("Public Key").tag(1)
            }
            if preferences.sshAuthMethod == 0 {
                SecureField("Password", text: $preferences.sshPassword)
            } else {
                Picker("Key Type", selection: $preferences.sshKeyType) {
                    Text("ed25519").tag("ed25519")
                    Text("ecdsa").tag("ecdsa")
                    Text("rsa").tag("rsa")
                }
                TextField("Key Path", text: $preferences.sshKeyPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Key Passphrase", text: $preferences.sshKeyPassphrase)
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
            if let keygenMessage {
                Text(keygenMessage).font(.caption2)
            }
        }
        .navigationTitle("SSH Defaults")
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsAdvancedSection: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        Form {
            Picker("Log Level", selection: $preferences.logLevel) {
                Text("Debug").tag("debug")
                Text("Info").tag("info")
                Text("Warn").tag("warn")
                Text("Error").tag("error")
            }
            Toggle("Shake to Close", isOn: $preferences.shakeToCloseEnabled)
            Toggle("Swipe Back to Close", isOn: $preferences.swipeBackToCloseEnabled)
        }
        .navigationTitle("Advanced")
        .onDisappear { preferences.save() }
    }
}

private struct WatchSettingsAboutSection: View {
    var body: some View {
        Form {
            LabeledContent("Version", value: watchAboutVersion)
            LabeledContent("Platform", value: "watchOS")
            LabeledContent("Author", value: "Alex Spaulding")
            Link("Source Code", destination: URL(string: "https://github.com/wawona/wawona")!)
            Link("GitHub Sponsors", destination: URL(string: "https://github.com/sponsors/aspauldingcode")!)
            Link("Portfolio", destination: URL(string: "https://aspauldingcode.com")!)
        }
        .navigationTitle("About")
    }

    private var watchAboutVersion: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let version = (raw?.isEmpty == false) ? raw! : "0.0.0"
        return version.hasPrefix("v") ? version : "v\(version)"
    }
}
#endif
