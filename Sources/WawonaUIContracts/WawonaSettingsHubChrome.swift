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
            .foregroundStyle(.white)
            .frame(width: iconTileSize, height: iconTileSize)
            .background(
                RoundedRectangle(cornerRadius: iconTileCorner, style: .continuous)
                    .fill(color)
            )
            .accessibilityHidden(true)
    }

    #if os(macOS)
    public static func color(nsColor: NSColor) -> Color { Color(nsColor: nsColor) }
    #elseif canImport(UIKit)
    public static func color(uiColor: UIColor) -> Color { Color(uiColor) }
    #endif
}
