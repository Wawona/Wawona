#if os(watchOS)
import SwiftUI
import WawonaModel

/// SSH defaults. Captions match iOS `PreferencesSectionsBuilder`.
struct WatchSSHSettingsPage: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        List {
            Section("Connection") {
                watchCaption("SSH hostname or address.") {
                    TextField("Host", text: $preferences.sshHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: preferences.sshHost) { _, _ in preferences.save() }
                }
                watchCaption("SSH username.") {
                    TextField("User", text: $preferences.sshUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: preferences.sshUser) { _, _ in preferences.save() }
                }
                watchCaption("SSH port.") {
                    Stepper("Port: \(preferences.sshPort)", value: $preferences.sshPort, in: 1...65535)
                        .onChange(of: preferences.sshPort) { _, _ in preferences.save() }
                }
                watchCaption("How SSH authenticates.") {
                    Picker("Auth Method", selection: $preferences.sshAuthMethod) {
                        Text("Password").tag(0)
                        Text("Key").tag(1)
                    }
                    .onChange(of: preferences.sshAuthMethod) { _, _ in preferences.save() }
                }
                watchCaption("SSH password.") {
                    SecureField("Password", text: $preferences.sshPassword)
                        .onChange(of: preferences.sshPassword) { _, _ in preferences.save() }
                }
            }
            Section("Key") {
                watchCaption("Type used when generating a key.") {
                    Picker("Key Type", selection: $preferences.sshKeyType) {
                        Text("ed25519").tag("ed25519")
                        Text("rsa").tag("rsa")
                        Text("ecdsa").tag("ecdsa")
                    }
                    .onChange(of: preferences.sshKeyType) { _, _ in preferences.save() }
                }
                watchCaption("Path to the private key.") {
                    TextField("Key Path", text: $preferences.sshKeyPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: preferences.sshKeyPath) { _, _ in preferences.save() }
                }
                watchCaption("Passphrase for the private key.") {
                    SecureField("Key Passphrase", text: $preferences.sshKeyPassphrase)
                        .onChange(of: preferences.sshKeyPassphrase) { _, _ in preferences.save() }
                }
                watchCaption("Create a new SSH keypair for Wawona.") {
                    Button("Generate Key") {
                        do {
                            let path = try WWNSSHKeygen.generateKeyType(
                                preferences.sshKeyType,
                                passphrase: preferences.sshKeyPassphrase
                            )
                            preferences.sshKeyPath = path
                            preferences.sshAuthMethod = 1
                            preferences.save()
                        } catch {
                            preferences.sshKeyPath = error.localizedDescription
                            preferences.save()
                        }
                    }
                }
            }
        }
        .navigationTitle("SSH")
    }
}

/// Waypipe defaults. Captions match iOS.
struct WatchWaypipeSettingsPage: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        List {
            Section("Session") {
                watchCaption("Prefer waypipe for remote machine connections.") {
                    Toggle("Waypipe by Default", isOn: $preferences.defaultWaypipeEnabled)
                        .onChange(of: preferences.defaultWaypipeEnabled) { _, _ in preferences.save() }
                }
                watchCaption("Allow X11 clients through XWayland when available.") {
                    Toggle("XWayland", isOn: $preferences.xwaylandSupport)
                        .onChange(of: preferences.xwaylandSupport) { _, _ in preferences.save() }
                }
                watchCaption("Password for waypipe SSH when key auth is not used.") {
                    SecureField("Waypipe SSH Password", text: $preferences.waypipeSSHPassword)
                        .onChange(of: preferences.waypipeSSHPassword) { _, _ in preferences.save() }
                }
                watchCaption("waypipe compression algorithm.") {
                    Picker("Compression", selection: $preferences.waypipeCompress) {
                        Text("none").tag("none")
                        Text("lz4").tag("lz4")
                        Text("zstd").tag("zstd")
                    }
                    .onChange(of: preferences.waypipeCompress) { _, _ in preferences.save() }
                }
                watchCaption("Optional video encode path for waypipe.") {
                    Picker("Video Codec", selection: $preferences.waypipeVideo) {
                        ForEach(["none", "h264", "vp9", "av1"], id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: preferences.waypipeVideo) { _, _ in preferences.save() }
                }
                watchCaption("Command run on the remote after waypipe SSH.") {
                    TextField("Remote Command", text: $preferences.waypipeRemoteCommand)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: preferences.waypipeRemoteCommand) { _, _ in preferences.save() }
                }
            }
            Section("Diagnostics") {
                watchCaption("Verbose waypipe logging.") {
                    Toggle("Debug Mode", isOn: $preferences.waypipeDebug)
                        .onChange(of: preferences.waypipeDebug) { _, _ in preferences.save() }
                }
                watchCaption("Force SHM / no-gpu waypipe transport.") {
                    Toggle("Disable GPU", isOn: $preferences.waypipeNoGpu)
                        .onChange(of: preferences.waypipeNoGpu) { _, _ in preferences.save() }
                }
            }
        }
        .navigationTitle("Waypipe")
    }
}

@ViewBuilder
func watchCaption<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        content()
        Text(caption)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
#endif
