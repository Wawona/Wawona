import Foundation
import WawonaModel
import WawonaUIContracts
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@objc(WWNPreferencesSectionsBuilder)
public final class WWNPreferencesSectionsBuilder: NSObject {
    /// Rebuilds section shells **and** row items from `GlobalSettingsCatalog`.
    /// Env Vars still uses a dedicated SwiftUI host; other sections need `items`.
    @objc public static func buildSections() -> [WWNPreferencesSection] {
        let host = GlobalSettingsCatalog.currentHost
        return GlobalSettingsCatalog.visibleSections(for: host).map { id in
            let section = WWNPreferencesSection()
            // Sidebar lists use GlobalSettingsSectionID.title ("Desktop").
            // The detail chrome uses detailTitle ("Desktop Replacement").
            section.title = id.detailTitle
            section.accessibilityIdentifier = id.objcAccessibilityIdentifier
            section.icon = id.systemImage
            section.iconColor = Self.iconColor(for: id)
            if id == .environment {
                // Detail pane hosts EnvironmentVariablesView; no inventory rows.
                section.items = []
            } else if id == .iCloudSync {
                // Detail pane hosts WWNICloudSyncSettingsView; no inventory rows.
                section.items = []
            } else if id == .appleWatch {
                // Detail pane hosts WWNAppleWatchSettingsView; no inventory rows.
                section.items = []
            } else if id == .desktop {
                section.items = desktopItems()
            } else if id == .about {
                section.items = aboutItems(for: host)
            } else if id == .dependencies {
                section.items = dependencyItems()
            } else {
                section.items = GlobalSettingsCatalog.visibleFields(in: id, for: host).compactMap {
                    item(for: $0)
                }
            }
            return section
        }
    }

    /// Bundled Okular-style inventory from `SettingsDependencies.json`
    /// (`settings-deps.nix` / `settingsDepsResource` in xcodegen).
    @objc public static func loadSettingsDependenciesInventory() -> [[AnyHashable: Any]] {
        guard let url = Bundle.main.url(
            forResource: "SettingsDependencies",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let packages = json["packages"] as? [[AnyHashable: Any]]
        else {
            return []
        }
        return packages
    }

    @objc public static func findWaypipeBinary() -> String {
        return WWNWaypipeRunner.shared.findWaypipeBinary()
    }

    @objc(cleanVersion:)
    public static func cleanVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Field → row

    static func item(for field: GlobalSettingsFieldID) -> WWNSettingItem? {
        switch field {
        case .forceSSD:
            return sw("Force Server-Side Decorations", kWWNPrefsForceServerSideDecorations, false,
                      "Force SSD chrome instead of client-side decorations.")
        case .respectSafeArea:
            return sw("Respect Safe Area", kWWNPrefsRespectSafeArea, true,
                      "Keep compositor content out of the notch and home indicator.")
        case .colorOperations:
            return sw("Color Operations / HDR", kWWNPrefsColorOperations, true,
                      "Allow HDR when a client negotiates color management or presents an HDR buffer. Does not force EDR for SDR clients.")
        case .nestedCompositors:
            return sw("Nested Compositors", kWWNPrefsNestedCompositorsSupport, true,
                      "Allow nested weston/niri sessions inside Machines.")
        case .compositorBackend:
            return popup(
                "Display Backend", kWWNPrefsCompositorBackend, "auto",
                ["Auto", "Wayland (nested)", "DRM/KMS (iLand)"],
                ["auto", "wayland", "drm"],
                "How nested weston/niri attach while the host compositor is up.")
        case .multipleClients:
            return sw("Multiple Clients", kWWNPrefsMultipleClients, true,
                      "Allow more than one Wayland client per machine session.")
        case .defaultStartType:
            return popup(
                "Default Start Type", kWWNPrefsDefaultStartType, "prompt",
                ["Prompt", "New Tab", "New Window"],
                ["prompt", "newTab", "newWindow"],
                "What Start does when the app can open another window. Hidden on hosts that only support tabs.")

        case .toolbarKeysCustomize:
            return button("Customize Toolbar Keys", "ToolbarKeysCustomize",
                          "Reorder, hide, and add custom Toolbar Keys (Rootshell layout).")
        case .persistentToolbar:
            return sw("Persistent Toolbar", kWWNPrefsPersistentToolbar, false,
                      "Keep the toolbar visible when the software keyboard is dismissed.")
        case .showToolbarWithHardwareKeyboard:
            return sw("Show Toolbar with Hardware Keyboard",
                      kWWNPrefsShowToolbarWithHardwareKeyboard, false,
                      "Keep the toolbar docked while an external keyboard is connected.")
        case .toolbarThemeAware:
            return sw("Toolbar Follow Theme", kWWNPrefsToolbarThemeAware, true,
                      "Tint toolbar glass from the host light/dark appearance.")
        case .toolbarChromeStyle:
            return popup(
                "Toolbar Style", kWWNPrefsToolbarChromeStyle, "flat",
                ["Flat", "Sculpted", "Steampunk", "Phosphor", "Beige Box", "Neon Grid", "Circuit Board"],
                ["flat", "sculpted", "steampunk", "phosphor", "beige-box", "neon-grid", "circuit-board"],
                "Rootshell keyboard chrome styles applied to Toolbar Keys.")
        case .toolbarArrowJoystickMode:
            return popup(
                "Arrow Key Mode", kWWNPrefsToolbarArrowJoystickMode, "joystick",
                ["Joystick", "Cluster"],
                ["joystick", "cluster"],
                "How the arrow-key control behaves on the toolbar.")
        case .virtualCursor:
            return sw("Show Virtual Cursor", kWWNPrefsRenderMacOSPointer, false,
                      "Draw a host/virtual pointer for non-compositor clients.")
        case .nestedCompositorCursor:
            return popup(
                "Nested Compositor Cursor", kWWNPrefsNestedCompositorCursor, "virtual",
                ["Virtual Pointer", "Host Cursor"],
                ["virtual", "host"],
                "Nested weston/niri hide the host cursor regardless of this setting.")
        case .touchInputType:
            return popup(
                "Touch Input Type", kWWNPrefsTouchInputType, "Multi-Touch",
                ["Multi-Touch", "Touchpad"],
                ["Multi-Touch", "Touchpad"],
                "Multi-Touch injects wl_touch. Touchpad uses a virtual pointer.")
        case .touchPointerEmulation:
            return sw("Pointer Emulation for Touch", kWWNPrefsTouchPointerEmulation, false,
                      "Map some touch gestures to pointer buttons.")
        case .resizeDisplayForVirtualKeyboard:
            return sw("Resize Display for Virtual Keyboard",
                      kWWNPrefsResizeDisplayForVirtualKeyboard, true,
                      "Shrink the compositor when the software keyboard is shown.")
        case .swapCmdWithAlt:
            return sw("Swap CMD with ALT", kWWNPrefsSwapCmdWithAlt, true,
                      "Swap Command and Alt for Linux clients.")
        case .universalClipboard:
            return sw("Universal Clipboard", kWWNPrefsUniversalClipboard, true,
                      "Share clipboard with the host pasteboard.")
        case .shakeToClose:
            return sw("Shake to Exit Machine", "wawona.pref.shakeToCloseEnabled", true,
                      "Shake the device to leave the compositor and return to Machines. Session stays running until Stop.")
        case .swipeBackToClose:
            // iOS/iPadOS: edge swipe opens the sidebar (not exit). watchOS keeps exit.
            return sw("Swipe Back to Exit Machine", "wawona.pref.swipeBackToCloseEnabled", true,
                      "On Apple Watch, swipe back leaves the active session.")

        case .renderer:
            return popup("Renderer", "Renderer", "metal",
                         ["Metal", "Software"], ["metal", "software"],
                         "Present path on platforms without a full GPU stack.")
        case .vulkanDriver:
            return popup(
                "Vulkan Driver", kWWNPrefsVulkanDriver, "MoltenVK",
                ["MoltenVK", "KosmicKrisp", "SwiftShader"],
                ["MoltenVK", "KosmicKrisp", "SwiftShader"],
                "ICD used when a Vulkan client starts.")
        case .openGLDriver:
            return popup(
                "OpenGL Driver", kWWNPrefsOpenGLDriver, "ANGLE",
                ["ANGLE", "SwiftShader"],
                ["ANGLE", "SwiftShader"],
                "GL ES provider for ANGLE-backed clients.")
        case .sessionThumbnails:
            return sw("Session Thumbnails", kWWNPrefsMachineSessionThumbnailsEnabled, true,
                      "Capture machine thumbnails while a session is running.")
        case .spritePresentAccelerator:
            return sw(
                "SpriteKit Present Accelerator",
                "SpritePresentAccelerator",
                true,
                "Software rendering draws the frame. SpriteKit composites it onto the watch."
            )

        case .waylandDisplay:
            return text("Wayland Display", "WaylandDisplay", "wayland-0",
                        "WAYLAND_DISPLAY name for the in-app compositor.")
        case .defaultWaylandClient:
            // Bundled Wayland clients removed. Default Start is Wawona Terminal.
            return text("Default Native Client", "DefaultBundledAppID", "wawona-shell",
                        "Keep-set id only: wawona-shell or wawona-wasm. Optional software installs via wpm.")
        case .environmentTable:
            return nil
        case .resetShellDotfiles:
            return button("Reset Shell Dotfiles", "RootfsResetDotfiles",
                          "Copy bundled shell config into HOME again.")
        case .resetSystemTree:
            return button("Reset System Tree", "RootfsReinstallSystem",
                          "Reinstall the bundled system rootfs tree.")
        case .importFileToHome:
            return button("Import File to Home", "RootfsImportFile",
                          "Pick a file and copy it into the shell HOME.")

        case .iCloudSyncEnabled:
            return sw("iCloud Sync", WWNCloudSync.enabledKey, true,
                      "Sync machines, preferences, and shell HOME through CloudKit.")
        case .iCloudSyncStatus:
            return info("iCloud Status", "ICloudSyncStatus",
                        WWNCloudSync.shared.status.summary,
                        "CloudKit sync state for this device.")
        case .iCloudSyncNow:
            return button("Sync Now", "ICloudSyncNow", "Fetch and upload changes now.")
        case .iCloudDriveHome:
            return sw("Keep HOME in iCloud Drive", WWNRootfsICloudSyncPreferenceKey, false,
                      "Keep the on-device shell HOME under iCloud Drive Documents.")

        case .waypipeByDefault:
            return sw("Waypipe by Default", "DefaultWaypipeEnabled", true,
                      "Prefer waypipe for remote machine connections.")
        case .waypipeXwayland:
            return sw("XWayland", "XwaylandSupport", false,
                      "Allow X11 clients through XWayland when available.")
        case .waypipePassword:
            return password("Waypipe SSH Password", kWWNPrefsWaypipeSSHPassword,
                            "Password for waypipe SSH when key auth is not used.")
        case .waypipeCompress:
            return popup("Compression", kWWNPrefsWaypipeCompress, "lz4",
                         ["none", "lz4", "zstd"], ["none", "lz4", "zstd"],
                         "waypipe compression algorithm.")
        case .waypipeVideo:
            return popup("Video Codec", kWWNPrefsWaypipeVideo, "none",
                         ["none", "h264", "vp9", "av1"],
                         ["none", "h264", "vp9", "av1"],
                         "Optional video encode path for waypipe.")
        case .waypipeRemoteCommand:
            return text("Remote Command", kWWNPrefsWaypipeRemoteCommand, "",
                        "Command run on the remote after waypipe SSH.")
        case .waypipeDebug:
            return sw("Debug Mode", kWWNPrefsWaypipeDebug, false,
                      "Verbose waypipe logging.")
        case .waypipeNoGpu:
            return sw("Disable GPU", kWWNPrefsWaypipeNoGpu, false,
                      "Force SHM / no-gpu waypipe transport.")

        case .sshHost:
            return text("Host", kWWNPrefsSSHHost, "", "SSH hostname or address.")
        case .sshUser:
            return text("User", kWWNPrefsSSHUser, "", "SSH username.")
        case .sshPort:
            return number("Port", kWWNPrefsSSHPort, 22, "SSH port.")
        case .sshAuthMethod:
            return popup("Auth Method", kWWNPrefsSSHAuthMethod, 0,
                         ["Password", "Key", "Agent"], nil,
                         "How SSH authenticates.")
        case .sshPassword:
            return password("Password", kWWNPrefsSSHPassword, "SSH password.")
        case .sshKeyType:
            return popup("Key Type", "SSHKeyType", "ed25519",
                         ["ed25519", "rsa", "ecdsa"],
                         ["ed25519", "rsa", "ecdsa"],
                         "Type used when generating a key.")
        case .sshKeyPath:
            return text("Key Path", kWWNPrefsSSHKeyPath, "", "Path to the private key.")
        case .sshKeyPassphrase:
            return password("Key Passphrase", kWWNPrefsSSHKeyPassphrase,
                            "Passphrase for the private key.")
        case .sshGenerateKey:
            return button("Generate Key", "SSHGenerateKey",
                          "Create a new SSH keypair for Wawona.")

        case .vmEngine:
            return text("VM Engine", kWWNPrefsMachineVMProvider, "",
                        "Preferred virtual machine engine label.")
        case .vmVsockPort:
            return number("VM vsock Port", kWWNPrefsMachineVMVsockPort, 1024,
                          "Default vsock port for Relay guests.")
        case .containerRuntime:
            return text("Container Runtime", kWWNPrefsMachineContainerRuntime, "",
                        "Preferred container runtime label.")
        case .containerImageStore:
            return text("Container Image Store", kWWNPrefsMachineContainerImageStore, "",
                        "Where pulled OCI images are kept.")
        case .machinesStatus:
            return info("Machines Status", "MachinesStatus", "Ready",
                        "High-level Machines subsystem status.")

        case .logLevel:
            return popup("Log Level", "LogLevel", "info",
                         ["error", "warn", "info", "debug", "trace"],
                         ["error", "warn", "info", "debug", "trace"],
                         "Compositor and host log verbosity.")
        case .aboutVersion:
            return info("Version", "AboutVersion",
                        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                        "Marketing version.")
        case .aboutBuild:
            return info("Build", "AboutBuild",
                        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                        "Build number.")
        case .aboutPlatform:
            return info("Platform", "AboutPlatform", platformLabel(),
                        "Host product target.")
        case .aboutWebsite:
            return aboutLink(WawonaAboutLinks.row(url: "https://wawona.io"), button: "Visit")
        case .aboutAuthor:
            return aboutLink(WawonaAboutLinks.row(url: "https://aspauldingcode.com"), button: "Visit")
        case .aboutSource:
            return aboutLink(WawonaAboutLinks.row(url: "https://github.com/Wawona/Wawona"), button: "Contribute")
        case .aboutSponsors:
            return aboutLink(WawonaAboutLinks.row(url: "https://github.com/sponsors/aspauldingcode"), button: "Sponsor")
        case .watchCompanionStatus:
            return info("Watch Companion", "WatchCompanionStatus", "Pairing, Watch app, and reachability.",
                        "WatchConnectivity companion status.")
        case .watchSendDocument:
            return button("Send Document to Watch", "WatchCompanionSend",
                          "Pick a file to transfer via WatchConnectivity.")
        case .watchOpenDocumentsHint:
            return info("Watch Documents", "WatchOpenDocumentsHint",
                        "Open received documents from the Watch app.",
                        "Hint for Watch document transfer.")
        case .dependenciesInventory:
            // Expanded by `dependencyItems()`; keep a fallback for callers that
            // ask for this field alone.
            return info(
                "Dependencies",
                "DependenciesInventory",
                "Bundled native ports and archives.",
                "Inventory is filled by SettingsDependencies.json."
            )
        }
    }
}
