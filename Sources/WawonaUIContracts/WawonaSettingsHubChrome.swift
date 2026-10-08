import SwiftUI
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Shared System Settings look for Wawona Global Settings hubs.
///
/// Targets the same visual language as:
/// - iOS Settings.app rows (colored rounded icon tile + title + caption)
/// - macOS System Settings → General hub (`GeneralSettings.appex` subpane list)
///
/// Used by the macOS PrefPane and the tvOS/visionOS in-app Global Settings
/// panel. iOS/iPadOS Global Settings use Settings.bundle (Apple plist chrome).
/// Never ship PrefPane or Settings.bundle beside a second in-app Global
/// Settings hub (`wawona-global-settings-exclusive`).
public enum WawonaSettingsHubChrome {
    public static let iconTileSize: CGFloat = 29
    public static let iconTileCorner: CGFloat = 7

    /// Settings.app / General-style glyph tile.
    @ViewBuilder
    public static func iconTile(systemName: String, color: Color) -> some View {
        Image(systemName: systemName.isEmpty ? "gearshape.fill" : systemName)
            .font(.body.weight(.semibold))
            // iOS 13 floor: avoid foregroundStyle (15+) / accessibilityHidden (14+).
            .foregroundColor(.white)
            .frame(width: iconTileSize, height: iconTileSize)
            .background(
                RoundedRectangle(cornerRadius: iconTileCorner, style: .continuous)
                    .fill(color)
            )
            .accessibility(hidden: true)
    }

    /// Hub list row: colored SF Symbol tile + section title.
    @ViewBuilder
    public static func hubRow(
        title: String,
        systemImage: String,
        iconColor: Color
    ) -> some View {
        Label {
            Text(title)
        } icon: {
            iconTile(systemName: systemImage, color: iconColor)
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
        default: return "gearshape.fill"
        }
    }

    #if os(macOS)
    public static func color(nsColor: NSColor) -> Color { Color(nsColor: nsColor) }
    #elseif canImport(UIKit)
    public static func color(uiColor: UIColor) -> Color { Color(uiColor) }
    #endif
}
