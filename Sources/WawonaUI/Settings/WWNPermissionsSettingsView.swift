#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
import SwiftUI
import WawonaModel
import WawonaUIContracts
#if os(macOS)
import AppKit
#endif

/// Settings → Permissions. Launch Agents / Login Item (macOS), update check
/// (all desktop hosts that show this section), Swinging Bridge TCC copy.
struct WWNPermissionsSettingsView: View {
    @ObservedObject private var updates = WWNUpdateChecker.shared
    @State private var compositorLoaded = false
    @State private var menubarLoaded = false
    @State private var loginItemLoaded = false
    @State private var agentNotice: String?
    @State private var checkUpdatesEnabled = WWNUpdateChecker.shared.checkForUpdatesEnabled

    private var accent: Color {
        WawonaSettingsHubChrome.accentColor(for: .permissions)
    }

    var body: some View {
        Form {
            #if os(macOS)
            agentsSection
            loginItemSection
            #endif
            updatesSection
            swingingBridgeSection
        }
        #if os(macOS)
        .backport.groupedForm()
        #endif
        .settingsSectionAccent(accent)
        .backport.tint(accent)
        .onAppear {
            #if os(macOS)
            refreshAgentStatus()
            #endif
            checkUpdatesEnabled = updates.checkForUpdatesEnabled
        }
        .alert(isPresented: Binding(
            get: { agentNotice != nil },
            set: { if !$0 { agentNotice = nil } }
        )) {
            Alert(
                title: Text("Permissions"),
                message: Text(agentNotice ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
        .accessibility(identifier: WWNA11y.settingsPermissions)
    }

    #if os(macOS)
    @ViewBuilder
    private var agentsSection: some View {
        Section {
            statusRow(
                title: "Compositor host",
                detail: compositorLoaded ? "Running" : "Not installed",
                systemImage: "desktopcomputer"
            )
            HStack {
                agentButton("Install") {
                    var err: NSError?
                    let ok = WWNLaunchAgentManager.sharedManager
                        .installCompositorAndMenuAgents(&err)
                    agentNotice = ok
                        ? "Compositor and menubar agents installed."
                        : (err?.localizedDescription ?? "Install failed.")
                    refreshAgentStatus()
                }
                agentButton("Start") {
                    let ok = WWNLaunchAgentManager.sharedManager.startCompositorAgent()
                    agentNotice = ok ? "Compositor agent started." : "Start failed."
                    refreshAgentStatus()
                }
                agentButton("Stop") {
                    let ok = WWNLaunchAgentManager.sharedManager.stopCompositorAgent()
                    agentNotice = ok ? "Compositor agent stopped." : "Stop failed."
                    refreshAgentStatus()
                }
                agentButton("Restart") {
                    let ok = WWNLaunchAgentManager.sharedManager.restartCompositorAgent()
                    agentNotice = ok ? "Compositor agent restarted." : "Restart failed."
                    refreshAgentStatus()
                }
            }
            statusRow(
                title: "Menubar",
                detail: menubarLoaded ? "Running" : "Not installed",
                systemImage: "menubar.rectangle"
            )
            HStack {
                agentButton("Start Menubar") {
                    var err: NSError?
                    let ok = WWNLaunchAgentManager.sharedManager.ensureMenuBarAgent(&err)
                    agentNotice = ok
                        ? "Menubar agent started."
                        : (err?.localizedDescription ?? "Menubar start failed.")
                    refreshAgentStatus()
                }
                agentButton("Stop Menubar") {
                    let ok = WWNLaunchAgentManager.sharedManager.stopMenuBarAgent()
                    agentNotice = ok ? "Menubar agent stopped." : "Stop failed."
                    refreshAgentStatus()
                }
            }
        } header: {
            Text("Launch Agents")
                .foregroundColor(accent)
        } footer: {
            Text(
                "The compositor host keeps the Wayland socket alive. The menubar "
                    + "agent shows the status item. Prefer Install from here after "
                    + "dragging Wawona.app to Applications."
            )
        }
    }

    @ViewBuilder
    private var loginItemSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { loginItemLoaded },
                set: { enabled in
                    let ok = enabled
                        ? WWNLaunchAgentManager.sharedManager.enableAppLaunchAtLogin()
                        : WWNLaunchAgentManager.sharedManager.disableAppLaunchAtLogin()
                    if !ok {
                        agentNotice = enabled
                            ? "Could not enable Login Item."
                            : "Could not disable Login Item."
                    }
                    refreshAgentStatus()
                }
            )) {
                Text("Open Wawona at login")
            }
            .accessibility(identifier: WWNA11y.settingsPermissionsLoginItem)
        } header: {
            Text("Login Item")
                .foregroundColor(accent)
        } footer: {
            Text("Starts the main UI at login. Quitting the window stays quit.")
        }
    }
    #endif

    @ViewBuilder
    private var updatesSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { checkUpdatesEnabled },
                set: { value in
                    checkUpdatesEnabled = value
                    updates.checkForUpdatesEnabled = value
                }
            )) {
                Text("Check for Updates")
            }
            .accessibility(identifier: WWNA11y.settingsPermissionsCheckUpdates)

            Text(updateStatusText)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Check Now") {
                    updates.checkNow()
                }
                .disabled(!checkUpdatesEnabled || updates.status == .checking)
                .accessibility(identifier: WWNA11y.settingsPermissionsCheckNow)

                if case .updateAvailable = updates.status {
                    Button("Download Update") {
                        updates.installOrOpenUpdate()
                    }
                    .backport.borderedButton(prominent: true)
                    .accessibility(identifier: WWNA11y.settingsPermissionsInstallUpdate)
                }
            }
        } header: {
            Text("Updates")
                .foregroundColor(accent)
        } footer: {
            Text(
                "Compares this build to the latest GitHub Release. Download opens "
                    + "the release asset (DMG on macOS) so you can install the update."
            )
        }
    }

    @ViewBuilder
    private var swingingBridgeSection: some View {
        Section {
            #if os(macOS)
            Button("Open Screen Recording settings") {
                openPrivacyPane("Privacy_ScreenCapture")
            }
            Button("Open Accessibility settings") {
                openPrivacyPane("Privacy_Accessibility")
            }
            #else
            Text(
                "Swinging Bridge needs screen capture and accessibility on hosts "
                    + "that bridge Cocoa or Android apps into Wayland. Planned."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            #endif
        } header: {
            Text("Swinging Bridge")
                .foregroundColor(accent)
        } footer: {
            Text(
                "Screen Recording / Accessibility (macOS) and MediaProjection / "
                    + "Accessibility (Android) are required when Swinging Bridge ships. "
                    + "Not Desktop Replacement."
            )
        }
    }

    private var updateStatusText: String {
        switch updates.status {
        case .idle:
            return "Current version \(updates.currentVersion)."
        case .checking:
            return "Checking GitHub Releases…"
        case .upToDate(let current):
            return "Wawona \(current) is up to date."
        case .updateAvailable(let current, let latest, _, _):
            return "Update available: \(latest) (you have \(current))."
        case .failed(let message):
            return "Check failed: \(message)"
        }
    }

    #if os(macOS)
    private func refreshAgentStatus() {
        let mgr = WWNLaunchAgentManager.sharedManager
        compositorLoaded = mgr.isCompositorAgentLoaded()
        menubarLoaded = mgr.isMenuBarAgentLoaded()
        loginItemLoaded = mgr.isAppLaunchAgentLoaded()
    }

    private func agentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .backport.controlSize(.small)
    }

    private func statusRow(title: String, detail: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(detail)
                .foregroundColor(.secondary)
        }
    }

    private func openPrivacyPane(_ pane: String) {
        let urlString =
            "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
}
#endif
