import Foundation
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
            // The detail / PrefPane chrome uses detailTitle ("Desktop Replacement").
            section.title = id.detailTitle
            section.accessibilityIdentifier = id.objcAccessibilityIdentifier
            section.icon = id.systemImage
            section.iconColor = Self.iconColor(for: id)
            if id == .environment {
                // Detail pane hosts EnvironmentVariablesView; no inventory rows.
                section.items = []
            } else if id == .desktop {
                section.items = desktopItems()
            } else {
                section.items = GlobalSettingsCatalog.visibleFields(in: id, for: host).compactMap {
                    item(for: $0)
                }
            }
            return section
        }
    }

    @objc public static func loadSettingsDependenciesInventory() -> [[AnyHashable: Any]] {
        []
    }

    @objc public static func findWaypipeBinary() -> String {
        #if WWN_PREFPANE
        return ""
        #else
        return WWNWaypipeRunner.shared.findWaypipeBinary()
        #endif
    }

    @objc(cleanVersion:)
    public static func cleanVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Field → row

    private static func item(for field: GlobalSettingsFieldID) -> WWNSettingItem? {
        switch field {
        case .forceSSD:
            return sw("Force Server-Side Decorations", kWWNPrefsForceServerSideDecorations, false,
                      "Force SSD chrome instead of client-side decorations.")
        case .respectSafeArea:
            return sw("Respect Safe Area", kWWNPrefsRespectSafeArea, true,
                      "Keep compositor content out of the notch and home indicator.")
        case .colorOperations:
            return sw("Color Operations / HDR", kWWNPrefsColorOperations, true,
                      "Allow HDR and advanced color when the client requests it.")
        case .nestedCompositors:
            return sw("Nested Compositors", kWWNPrefsNestedCompositorsSupport, true,
                      "Allow nested weston/niri sessions inside Machines.")
        case .compositorBackend:
            return popup(
                "Display Backend", kWWNPrefsCompositorBackend, "auto",
                ["Auto", "Wayland (nested)", "DRM/KMS (wwn-iland)"],
                ["auto", "wayland", "drm"],
                "How nested weston/niri attach while the host compositor is up.")
        case .multipleClients:
            return sw("Multiple Clients", kWWNPrefsMultipleClients, true,
                      "Allow more than one Wayland client per machine session.")
        case .defaultStartType:
            return popup(
                "Default Start Type", kWWNPrefsDefaultStartType, "prompt",
                ["Prompt", "New Tab", "New Window"],
                ["prompt", "tab", "window"],
                "What Start does when the app can open another window.")

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
            return sw("Shake to Close", "ShakeToCloseEnabled", true,
                      "Shake the device to close the focused client.")
        case .swipeBackToClose:
            return sw("Swipe Back to Close", "SwipeBackToCloseEnabled", true,
                      "Edge swipe closes the focused client.")

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

        case .waylandDisplay:
            return text("Wayland Display", "WaylandDisplay", "wayland-0",
                        "WAYLAND_DISPLAY name for the in-app compositor.")
        case .defaultWaylandClient:
            return text("Default Wayland Client", "DefaultBundledAppID", "",
                        "Bundled client id used when Start has no other client.")
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
            return sw("iCloud Drive Sync", WWNRootfsICloudSyncPreferenceKey, false,
                      "Keep the on-device shell HOME under iCloud Drive Documents.")
        case .iCloudSyncStatus:
            return info("iCloud Status", "ICloudSyncStatus",
                        WWNRootfsICloudSync.isEnabled() ? "Enabled" : "Disabled",
                        "Whether shell HOME sync is currently on.")

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
            return link("Website", "https://wawona.io", "Open wawona.io")
        case .aboutAuthor:
            return info("Author", "AboutAuthor", "aspauldingcode",
                        "Project author.")
        case .aboutSource:
            return link("Source", "https://github.com/Wawona/Wawona", "Open on GitHub")
        case .aboutSponsors:
            return link("Sponsors", "https://github.com/sponsors/aspauldingcode", "Sponsor")
        case .watchCompanionStatus:
            return info("Watch Companion", "WatchCompanionStatus", "See Apple Watch section",
                        "WatchConnectivity companion status.")
        case .watchSendDocument:
            return button("Send Document to Watch", "WatchCompanionSend",
                          "Pick a file to transfer via WatchConnectivity.")
        case .watchOpenDocumentsHint:
            return info("Watch Documents", "WatchOpenDocumentsHint",
                        "Open received documents from the Watch app.",
                        "Hint for Watch document transfer.")
        case .dependenciesInventory:
            return info("Dependencies", "DependenciesInventory",
                        "Bundled native ports and archives.",
                        "Inventory is filled by the packaging gate.")
        }
    }

    private static func desktopItems() -> [WWNSettingItem] {
        #if os(macOS)
        let picker = desktopMachinePickerOptions()
        let desktopMachineDesc: String
        if picker.values.count <= 1 {
            desktopMachineDesc =
                "Pick a Native Shell Wayland compositor machine (Weston or Niri). "
                + "Add one under Machine Configuration first."
        } else {
            desktopMachineDesc =
                "Preferred Native Shell Wayland compositor (Weston or Niri) for "
                + "Desktop Replacement. Terminal, Wasm, and Waypipe machines are omitted."
        }
        // Order: Desktop block first, then Lock Screen. Detail views split on
        // Lock Screen Replacement / lockscreen keys into labelled Form sections.
        return [
            sw("Enable Desktop Replacement", kWWNPrefsDesktopReplacementEnabled, false,
               "Arm Mode B Desktop Replacement when SIP is fully disabled."),
            button("Replace Now", "DesktopReplacementTakeOver",
                   "Take over the display for this login session."),
            button("SIP How-To", "DesktopReplacementSipHowTo",
                   "How to fully disable SIP for Desktop Replacement."),
            popup(
                "Desktop Machine",
                kWWNPrefsDesktopReplacementMachineId,
                "",
                picker.titles,
                picker.values,
                desktopMachineDesc
            ),
            sw("Lock Screen Replacement", kWWNPrefsLockscreenReplacementEnabled, false,
               "Replace the lock screen greeter when Desktop Replacement is available."),
        ]
        #else
        return []
        #endif
    }

    /// PrefPane and app share this: read profiles from defaults (no MachineProfileStore link).
    private static func desktopMachinePickerOptions() -> (titles: [String], values: [String]) {
        #if !WWN_PREFPANE
        return WWNMachineProfileStore.desktopReplacementMachinePickerOptions()
        #else
        var titles = ["None"]
        var values = [""]
        let raw = UserDefaults.standard.array(forKey: "WWNMachineProfiles") as? [[String: Any]] ?? []
        let eligible = raw.compactMap { dict -> (name: String, id: String, client: String)? in
            let id = dict["machineId"] as? String ?? ""
            guard !id.isEmpty else { return nil }
            let type = dict["type"] as? String ?? "native"
            let name = dict["name"] as? String ?? "Machine"
            let settings = dict["settingsOverrides"] as? [String: Any] ?? [:]
            let runtime = dict["runtimeOverrides"] as? [String: Any] ?? [:]
            let kind = (settings[kWWNPrefsNativeShellKind] as? String)
                ?? prefPaneInferredShellKind(type: type, client: prefPaneClientId(runtime: runtime, settings: settings))
            guard type == "native" || type == "wasm" || type == "ssh_waypipe" || type == "ssh_terminal"
            else { return nil }
            guard kind == kWWNNativeShellKindWayland else { return nil }
            if settings[kWWNPrefsNativeShellUseSSH] as? Bool == true { return nil }
            let client = prefPaneClientId(runtime: runtime, settings: settings)
            guard prefPaneIsCompositorClient(client) else { return nil }
            return (name, id, client)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for row in eligible {
            let lower = row.client.lowercased()
            let label: String
            if lower == "weston" || lower.hasSuffix("/weston") {
                label = "Weston"
            } else if lower == "niri" || lower.hasSuffix("/niri") {
                label = "Niri"
            } else {
                label = row.client
            }
            titles.append("\(row.name) (\(label))")
            values.append(row.id)
        }
        return (titles, values)
        #endif
    }

    #if WWN_PREFPANE
    private static func prefPaneClientId(runtime: [String: Any], settings: [String: Any]) -> String {
        if let bundled = runtime["bundledAppID"] as? String, !bundled.isEmpty { return bundled }
        if let native = settings["NativeClientId"] as? String, !native.isEmpty { return native }
        return ""
    }

    private static func prefPaneInferredShellKind(type: String, client: String) -> String {
        switch type {
        case "wasm": return kWWNNativeShellKindWasm
        case "ssh_terminal": return kWWNNativeShellKindTerminal
        case "ssh_waypipe": return kWWNNativeShellKindWaypipe
        case "native":
            if client == "wawona-shell" || client.isEmpty { return kWWNNativeShellKindTerminal }
            if client == "wawona-wasm" { return kWWNNativeShellKindWasm }
            return kWWNNativeShellKindWayland
        default:
            return kWWNNativeShellKindTerminal
        }
    }

    private static func prefPaneIsCompositorClient(_ client: String) -> Bool {
        let id = client.lowercased()
        if id.contains("weston-terminal") || id.contains("weston-simple-shm") { return false }
        if id == "foot" { return false }
        return id.contains("weston") || id.contains("niri") || id.contains("sway") || id.contains("labwc")
    }
    #endif

    private static func platformLabel() -> String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(visionOS)
        return "visionOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "Apple"
        #endif
    }

    // MARK: - Sidebar icon colors (match pre-SwiftUI Preferences)

    #if os(macOS)
    private static func iconColor(for id: GlobalSettingsSectionID) -> NSColor {
        switch id {
        case .display: return .systemBlue
        case .input: return .systemPurple
        case .graphics: return .systemRed
        case .connection: return .systemOrange
        case .environment: return .systemTeal
        case .localShell: return .systemGreen
        case .machines: return .systemIndigo
        // systemCyan is iOS 15+; keep a distinct cyan for iCloud on older hosts.
        case .iCloudSync: return NSColor(calibratedRed: 0.20, green: 0.68, blue: 0.90, alpha: 1)
        case .appleWatch: return .systemPink
        case .desktop: return .systemTeal
        case .waypipe: return .systemGreen
        case .ssh: return .systemBlue
        case .about: return .systemPurple
        case .dependencies: return .systemBrown
        }
    }
    #else
    private static func iconColor(for id: GlobalSettingsSectionID) -> UIColor {
        switch id {
        case .display: return .systemBlue
        case .input: return .systemPurple
        case .graphics: return .systemRed
        case .connection: return .systemOrange
        case .environment: return .systemTeal
        case .localShell: return .systemGreen
        case .machines: return .systemIndigo
        // systemCyan is iOS 15+; keep a distinct cyan for iCloud on older hosts.
        case .iCloudSync: return UIColor(red: 0.20, green: 0.68, blue: 0.90, alpha: 1)
        case .appleWatch: return .systemPink
        case .desktop: return .systemTeal
        case .waypipe: return .systemGreen
        case .ssh: return .systemBlue
        case .about: return .systemPurple
        case .dependencies: return .systemBrown
        }
    }
    #endif

    // MARK: - Factories

    private static func sw(_ title: String, _ key: String, _ def: Bool, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingSwitch, default: def, desc: desc)
    }

    private static func text(_ title: String, _ key: String, _ def: String, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingText, default: def, desc: desc)
    }

    private static func number(_ title: String, _ key: String, _ def: Int, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingNumber, default: def, desc: desc)
    }

    private static func password(_ title: String, _ key: String, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingPassword, default: "", desc: desc)
    }

    private static func info(_ title: String, _ key: String, _ value: String, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingInfo, default: value, desc: desc)
    }

    private static func button(_ title: String, _ key: String, _ desc: String) -> WWNSettingItem {
        let item = WWNSettingItem.item(title: title, key: key, type: .WSettingButton, default: nil, desc: desc)
        item.buttonTitle = title
        return item
    }

    private static func link(_ title: String, _ url: String, _ button: String) -> WWNSettingItem {
        let item = WWNSettingItem.item(title: title, key: "", type: .WSettingLink, default: nil, desc: "")
        item.urlString = url
        item.buttonTitle = button
        return item
    }

    private static func popup(
        _ title: String,
        _ key: String,
        _ def: Any,
        _ options: [String],
        _ values: [String]?,
        _ desc: String
    ) -> WWNSettingItem {
        let item = WWNSettingItem.item(title: title, key: key, type: .WSettingPopup, default: def, desc: desc)
        item.options = options
        item.optionValues = values ?? []
        return item
    }
}
