import Foundation
import WawonaUIContracts
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension WWNPreferencesSectionsBuilder {
    /// About detail: icon and version, then link rows, then the
    /// version / build / platform / log / copy group.
    static func aboutItems(for host: GlobalSettingsHost) -> [WWNSettingItem] {
        let fields = Set(GlobalSettingsCatalog.visibleFields(in: .about, for: host))
        var items: [WWNSettingItem] = []

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let header = WWNSettingItem.item(
            title: "Wawona",
            key: "AboutHeader",
            type: .WSettingHeader,
            default: nil,
            desc: version
        )
        items.append(header)

        if fields.contains(.aboutWebsite), let row = item(for: .aboutWebsite) {
            items.append(row)
        }
        if fields.contains(.aboutAuthor) {
            let buttons = ["Visit", "Profile", "Follow", "Connect", "Support"]
            for (linkRow, button) in zip(WawonaAboutLinks.rows.dropFirst().prefix(5), buttons) {
                items.append(aboutLink(linkRow, button: button))
            }
        }
        if fields.contains(.aboutSponsors), let row = item(for: .aboutSponsors) {
            items.append(row)
        }
        if fields.contains(.aboutSource), let row = item(for: .aboutSource) {
            items.append(row)
        }

        if fields.contains(.aboutVersion), let row = item(for: .aboutVersion) {
            items.append(row)
        }
        if fields.contains(.aboutBuild), let row = item(for: .aboutBuild) {
            items.append(row)
        }
        if fields.contains(.aboutPlatform), let row = item(for: .aboutPlatform) {
            items.append(row)
        }
        if fields.contains(.logLevel), let row = item(for: .logLevel) {
            items.append(row)
        }

        let copyLogs = button(
            "Copy Logs",
            "CopyRecentLogs",
            "Copy Wawona version, host OS, and recent logs."
        )
        copyLogs.actionBlock = {
            WWNDiagnosticReport.copyRecentLogs(machineOnly: false)
        }
        items.append(copyLogs)
        return items
    }

    /// One info row per package in the product `SettingsDependencies.json`.
    static func dependencyItems() -> [WWNSettingItem] {
        let inventory = loadSettingsDependenciesInventory()
        if inventory.isEmpty {
            return [
                info(
                    "Dependencies",
                    "DependenciesInventory",
                    "unavailable",
                    "SettingsDependencies.json missing from this build. "
                        + "Rebuild so the product inventory is embedded."
                ),
            ]
        }
        return inventory.enumerated().map { index, pkg in
            let name = (pkg["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Package"
            let version = pkg["version"] as? String ?? ""
            // Line 0 = row subtitle (role). Extra lines = info sheet only.
            let role = (pkg["role"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let url = pkg["url"] as? String ?? ""
            let license = pkg["license"] as? String ?? ""
            var lines: [String] = []
            if !role.isEmpty { lines.append(role) }
            if !license.isEmpty { lines.append("License: \(license)") }
            if !url.isEmpty { lines.append(url) }
            let key = "Dependency.\(index).\(name)"
            return info(name, key, version, lines.joined(separator: "\n"))
        }
    }

    static func desktopItems() -> [WWNSettingItem] {
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

    static func desktopMachinePickerOptions() -> (titles: [String], values: [String]) {
        return WWNMachineProfileStore.desktopReplacementMachinePickerOptions()
    }

    static func platformLabel() -> String {
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
    static func iconColor(for id: GlobalSettingsSectionID) -> NSColor {
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
    static func iconColor(for id: GlobalSettingsSectionID) -> UIColor {
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

    static func sw(_ title: String, _ key: String, _ def: Bool, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingSwitch, default: def, desc: desc)
    }

    static func text(_ title: String, _ key: String, _ def: String, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingText, default: def, desc: desc)
    }

    static func number(_ title: String, _ key: String, _ def: Int, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingNumber, default: def, desc: desc)
    }

    static func password(_ title: String, _ key: String, _ desc: String) -> WWNSettingItem {
        WWNSettingItem.item(title: title, key: key, type: .WSettingPassword, default: "", desc: desc)
    }

    static func info(
        _ title: String,
        _ key: String,
        _ value: String,
        _ desc: String,
        iconURL: String = ""
    ) -> WWNSettingItem {
        let item = WWNSettingItem.item(
            title: title,
            key: key,
            type: .WSettingInfo,
            default: value,
            desc: desc
        )
        item.iconURL = iconURL
        return item
    }

    static func button(_ title: String, _ key: String, _ desc: String) -> WWNSettingItem {
        let item = WWNSettingItem.item(title: title, key: key, type: .WSettingButton, default: nil, desc: desc)
        item.buttonTitle = title
        return item
    }

    static func link(
        _ title: String,
        _ url: String,
        _ button: String,
        iconURL: String = "",
        subtitle: String = ""
    ) -> WWNSettingItem {
        let item = WWNSettingItem.item(title: title, key: "", type: .WSettingLink, default: nil, desc: subtitle)
        item.urlString = url
        item.buttonTitle = button
        item.iconURL = iconURL
        return item
    }

    static func aboutLink(_ row: WawonaAboutLink?, button: String) -> WWNSettingItem {
        guard let row else { return link("", "", button) }
        return link(row.title, row.url, button, iconURL: row.iconURL, subtitle: row.subtitle)
    }

    static func popup(
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
