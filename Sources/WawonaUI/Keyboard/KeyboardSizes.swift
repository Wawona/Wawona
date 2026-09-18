#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  KeyboardSizes.swift
//  Wawona
//
//  Device-specific sizing for keyboard toolbar (ported 1:1 from rootshell).
//

import UIKit

public struct KeyboardSizes: Sendable {
    // MARK: - Nested Types

    public struct Toolbar: Sendable {
        public let height: CGFloat
        public let padding: CGFloat  // Vertical padding
        public let spacing: CGFloat  // Horizontal spacing between buttons
        public let cornerRadius: CGFloat
        public let drawerHeight: CGFloat  // Height of expandable drawer row (0 on iPad)

        public init(height: CGFloat, padding: CGFloat, spacing: CGFloat, cornerRadius: CGFloat, drawerHeight: CGFloat) {
            self.height = height
            self.padding = padding
            self.spacing = spacing
            self.cornerRadius = cornerRadius
            self.drawerHeight = drawerHeight
        }
    }

    public struct Button: Sendable {
        public let height: CGFloat
        public let iconWidth: CGFloat    // For arrow cluster, copy/paste icons
        public let normalWidth: CGFloat  // For Tab, symbols
        public let wideWidth: CGFloat    // For Esc, Ctrl, Alt, Cmd
        public let cornerRadius: CGFloat
        public let fontSize: CGFloat
        public let symbolSize: CGFloat

        public init(height: CGFloat, iconWidth: CGFloat, normalWidth: CGFloat, wideWidth: CGFloat, cornerRadius: CGFloat, fontSize: CGFloat, symbolSize: CGFloat) {
            self.height = height
            self.iconWidth = iconWidth
            self.normalWidth = normalWidth
            self.wideWidth = wideWidth
            self.cornerRadius = cornerRadius
            self.fontSize = fontSize
            self.symbolSize = symbolSize
        }
    }

    // MARK: - Properties

    public let toolbar: Toolbar
    public let button: Button

    public init(toolbar: Toolbar, button: Button) {
        self.toolbar = toolbar
        self.button = button
    }

    // MARK: - Device Presets

    /// iPhone portrait (small)
    public static let iPhonePortrait = KeyboardSizes(
        toolbar: Toolbar(height: 44, padding: 0, spacing: 0, cornerRadius: 16, drawerHeight: 44),
        button: Button(
            height: 38,
            iconWidth: 48,
            normalWidth: 33,
            wideWidth: 48,
            cornerRadius: 10,
            fontSize: 15,
            symbolSize: 16
        )
    )

    /// iPhone landscape (compact)
    public static let iPhoneLandscape = KeyboardSizes(
        toolbar: Toolbar(height: 38, padding: 0, spacing: 0, cornerRadius: 14, drawerHeight: 38),
        button: Button(
            height: 32,
            iconWidth: 44,
            normalWidth: 30,
            wideWidth: 44,
            cornerRadius: 9,
            fontSize: 14,
            symbolSize: 15
        )
    )

    /// iPad (all orientations)
    public static let iPad = KeyboardSizes(
        toolbar: Toolbar(height: 55, padding: 6, spacing: 0, cornerRadius: 18, drawerHeight: 55),
        button: Button(
            height: 43,
            iconWidth: 58,
            normalWidth: 48,
            wideWidth: 68,
            cornerRadius: 12,
            fontSize: 17,
            symbolSize: 18
        )
    )

    // MARK: - Device Detection

    public static func current(traitCollection: UITraitCollection? = nil) -> KeyboardSizes {
        let idiom = traitCollection?.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom

        #if os(visionOS)
        // visionOS doesn't have device orientation, use iPad sizes
        return .iPad
        #else
        switch idiom {
        case .pad:
            return .iPad
        case .phone:
            return isPhoneLandscape(traitCollection: traitCollection) ? .iPhoneLandscape : .iPhonePortrait
        default:
            return .iPhonePortrait
        }
        #endif
    }

    #if !os(visionOS)
    private static func isPhoneLandscape(traitCollection: UITraitCollection?) -> Bool {
        if let traitCollection {
            if traitCollection.verticalSizeClass == .compact {
                return true
            }
            if traitCollection.verticalSizeClass == .regular {
                return false
            }
        }

        let orientation = UIDevice.current.orientation
        if orientation.isValidInterfaceOrientation {
            return orientation.isLandscape
        }

        let screenBounds = UIScreen.main.bounds
        return screenBounds.width > screenBounds.height
    }
    #endif
}
#endif
