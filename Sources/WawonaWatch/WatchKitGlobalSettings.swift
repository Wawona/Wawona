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

/// Global Wawona Settings for watchOS (SwiftUI).
/// Same sections/keys as `WWNWatchSettings.storyboard` + `WWNWatchSettingsBridge`.
struct WatchGlobalSettingsView: View {
    @ObservedObject private var preferences = WawonaPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var keygenMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Auto Scale", isOn: $preferences.autoScale)
                    Toggle("Force SSD", isOn: $preferences.forceSSD)
                    Toggle("Color Operations (HDR)", isOn: $preferences.colorOperations)
                }
                Section("Graphics") {
                    Picker("Renderer", selection: $preferences.renderer) {
                        Text("metal").tag("metal")
                        Text("software").tag("software")
                    }
                }
                Section("Connection") {
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
                Section("SSH Defaults") {
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
                            var err: NSError?
                            if let path = WWNSSHKeygen.generateKeyType(
                                preferences.sshKeyType,
                                passphrase: preferences.sshKeyPassphrase,
                                error: &err
                            ) {
                                preferences.sshKeyPath = path
                                preferences.sshAuthMethod = 1
                                preferences.save()
                                keygenMessage = "Created \(path)"
                            } else {
                                keygenMessage = err?.localizedDescription ?? "Keygen failed"
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
                Section("Advanced") {
                    Picker("Log Level", selection: $preferences.logLevel) {
                        Text("Debug").tag("debug")
                        Text("Info").tag("info")
                        Text("Warn").tag("warn")
                        Text("Error").tag("error")
                    }
                    Toggle("Shake to Close", isOn: $preferences.shakeToCloseEnabled)
                    Toggle("Swipe Back to Close", isOn: $preferences.swipeBackToCloseEnabled)
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
#endif
