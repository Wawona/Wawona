import SwiftUI
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Sidebar row helpers for in-app Global Settings and Machines Configuration.
///
/// Sidebars use **section-tinted SF Symbols** (glyph color = section accent).
/// Never colored rounded-square tiles with white glyphs. The same accents tint
/// Settings **detail** controls (`settingsSectionAccent` / `.backport.tint`).
/// OS PrefPane / Settings.bundle hosts are retired
/// (`wawona-global-settings-exclusive`).
public enum WawonaSettingsHubChrome {
    /// Column width so sidebar titles align under tinted glyphs.
    public static let sidebarIconColumn: CGFloat = 20

    /// Section-tinted SF Symbol for a sidebar row. No tile background.
    @ViewBuilder
    public static func sidebarIcon(systemName: String, color: Color) -> some View {
        Image(systemName: systemName.isEmpty ? "gearshape" : systemName)
            .font(.body)
            // iOS 13 floor: avoid foregroundStyle (15+) / accessibilityHidden (14+).
            .foregroundColor(color)
            .frame(width: sidebarIconColumn, alignment: .center)
            .accessibility(hidden: true)
    }

    /// Hub list row: section-tinted SF Symbol + section title.
    /// iOS 13 floor: avoid `Label { } icon:` (iOS 14+).
    /// `iconColor` tints the glyph only. Never a colored rounded-square tile.
    public static func hubRow(
        title: String,
        systemImage: String,
        iconColor: Color
    ) -> some View {
        HStack(spacing: 8) {
            sidebarIcon(systemName: systemImage, color: iconColor)
            Text(title)
            Spacer(minLength: 0)
        }
    }

    /// Fallback glyph when a preferences section has no `icon` set.
    public static func systemImage(forSectionTitle title: String) -> String {
        switch title.lowercased() {
        case let t where t.contains("display"): return "display"
        case let t where t.contains("input") || t.contains("keyboard"):
            return "keyboard"
        case let t where t.contains("graphics"): return "cube"
        case let t where t.contains("environment"): return "terminal"
        case let t where t.contains("desktop"): return "desktopcomputer"
        case let t where t.contains("about"): return "info.circle"
        default: return "gearshape"
        }
    }

    #if os(macOS)
    public static func color(nsColor: NSColor) -> Color { Color(nsColor: nsColor) }
    #elseif canImport(UIKit)
    public static func color(uiColor: UIColor) -> Color { Color(uiColor) }
    #endif

    /// Section accent for sidebar glyphs and Settings **detail** controls.
    /// Matches `PreferencesSectionsBuilder.iconColor` and Android
    /// `SettingsTab.accentColor`. Never use this as a sidebar icon tile fill.
    /// Uses system UIColors so teal/indigo/brown stay valid on the iOS 13 floor
    /// (SwiftUI `.teal` / `.indigo` / `.brown` are iOS 15+).
    public static func accentColor(for id: GlobalSettingsSectionID) -> Color {
        #if os(macOS)
        switch id {
        case .display, .ssh: return Color(nsColor: .systemBlue)
        case .input, .about: return Color(nsColor: .systemPurple)
        case .graphics: return Color(nsColor: .systemRed)
        case .connection: return Color(nsColor: .systemOrange)
        case .environment, .desktop: return Color(nsColor: .systemTeal)
        case .localShell, .waypipe: return Color(nsColor: .systemGreen)
        case .machines: return Color(nsColor: .systemIndigo)
        case .iCloudSync:
            return Color(
                nsColor: NSColor(calibratedRed: 0.20, green: 0.68, blue: 0.90, alpha: 1)
            )
        case .appleWatch: return Color(nsColor: .systemPink)
        case .dependencies: return Color(nsColor: .systemBrown)
        }
        #elseif os(watchOS)
        // watchOS: UIColor.systemBlue / systemTeal / … unavailable.
        switch id {
        case .display, .ssh: return .blue
        case .input, .about: return .purple
        case .graphics: return .red
        case .connection: return .orange
        case .environment, .desktop:
            return Color(red: 0.35, green: 0.78, blue: 0.78)
        case .localShell, .waypipe: return .green
        case .machines:
            return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .iCloudSync:
            return Color(red: 0.20, green: 0.68, blue: 0.90)
        case .appleWatch: return .pink
        case .dependencies:
            return Color(red: 0.67, green: 0.45, blue: 0.20)
        }
        #elseif canImport(UIKit)
        switch id {
        case .display, .ssh: return Color(UIColor.systemBlue)
        case .input, .about: return Color(UIColor.systemPurple)
        case .graphics: return Color(UIColor.systemRed)
        case .connection: return Color(UIColor.systemOrange)
        case .environment, .desktop: return Color(UIColor.systemTeal)
        case .localShell, .waypipe: return Color(UIColor.systemGreen)
        case .machines: return Color(UIColor.systemIndigo)
        case .iCloudSync:
            return Color(UIColor(red: 0.20, green: 0.68, blue: 0.90, alpha: 1))
        case .appleWatch: return Color(UIColor.systemPink)
        case .dependencies: return Color(UIColor.systemBrown)
        }
        #else
        switch id {
        case .display, .ssh: return .blue
        case .input, .about: return .purple
        case .graphics: return .red
        case .connection: return .orange
        case .environment, .desktop:
            return Color(red: 0.35, green: 0.78, blue: 0.78)
        case .localShell, .waypipe: return .green
        case .machines:
            return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .iCloudSync:
            return Color(red: 0.20, green: 0.68, blue: 0.90)
        case .appleWatch: return .pink
        case .dependencies:
            return Color(red: 0.67, green: 0.45, blue: 0.20)
        }
        #endif
    }
}

// MARK: - Section accent (Settings detail controls)

/// Accent for the open Settings section's detail pane (toggles, pickers,
/// buttons, links, section headers). Default is the system accent.
/// Do **not** paint this onto sidebar icon backgrounds.
private enum SettingsSectionAccentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

public extension EnvironmentValues {
    var settingsSectionAccent: Color {
        get { self[SettingsSectionAccentKey.self] }
        set { self[SettingsSectionAccentKey.self] = newValue }
    }
}

public extension View {
    /// Propagate section accent into Settings detail. Pair with
    /// `.backport.tint(color)` so Toggle / Picker / Button / Link use it.
    func settingsSectionAccent(_ color: Color) -> some View {
        environment(\.settingsSectionAccent, color)
    }
}

// MARK: - Settings detail toolbar chrome

/// Optional Add action for Global Settings detail trailing chrome.
/// Env Vars registers `onAdd` so the host can place `[+][x]` in one group.
public final class WawonaSettingsChromeBridge: ObservableObject {
    @Published public var onAdd: (() -> Void)?

    public init() {}
}
