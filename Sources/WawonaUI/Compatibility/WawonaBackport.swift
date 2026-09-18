import SwiftUI

/// Wawona's single availability namespace for SwiftUI APIs newer than iOS 13.
/// Keep runtime checks here, never at feature call sites.
public struct WawonaBackport<Content> {
    fileprivate let content: Content

    fileprivate init(content: Content) {
        self.content = content
    }
}

public extension View {
    var backport: WawonaBackport<Self> { WawonaBackport(content: self) }
}

public extension WawonaBackport where Content: View {
    /// Keeps Settings rows visibly separated on every supported SwiftUI host.
    /// iOS 15 adds a native row-separator API; iOS 13–14 get the same visual
    /// boundary without changing the app's deployment target.
    @ViewBuilder
    func visibleRowSeparator() -> some View {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            content.listRowSeparator(.visible, edges: .bottom)
        } else {
            content.overlay(alignment: .bottom) {
                Divider()
            }
        }
        #else
        content
        #endif
    }

    /// Uses system Liquid Glass where it exists and a stable translucent card elsewhere.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 20) -> some View {
        #if os(visionOS)
        fallbackGlass(cornerRadius: cornerRadius)
        #elseif os(macOS)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            fallbackGlass(cornerRadius: cornerRadius)
        }
        #else
        if #available(iOS 26.0, tvOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            fallbackGlass(cornerRadius: cornerRadius)
        }
        #endif
    }

    /// Uses system Liquid Glass in a capsule shape where it exists, and a stable translucent capsule elsewhere.
    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        #if os(visionOS)
        fallbackGlassCapsule()
        #elseif os(macOS)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            fallbackGlassCapsule()
        }
        #else
        if #available(iOS 26.0, tvOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            fallbackGlassCapsule()
        }
        #endif
    }

    /// Keeps the modern glass button on new systems without raising the app floor.
    @ViewBuilder
    @MainActor
    func glassButtonStyle() -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.automatic)
        }
        #else
        content.buttonStyle(.automatic)
        #endif
    }

    /// Native liquid glass toolbar button on modern OS, with standard toolbar button fallback.
    /// On macOS, toolbar items use native toolbar styling to avoid glass-on-glass over window material.
    @ViewBuilder
    @MainActor
    func glassToolbarButton() -> some View {
        #if os(macOS)
        content.buttonStyle(.automatic)
        #elseif !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.automatic)
        }
        #else
        content.buttonStyle(.automatic)
        #endif
    }

    /// Keeps the modern prominent glass button on new systems without raising the app floor.
    @ViewBuilder
    @MainActor
    func glassProminentButtonStyle() -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }

    /// Native prominent liquid glass toolbar button on modern OS, with prominent fallback.
    /// On macOS, toolbar items use native borderedProminent to avoid glass-on-glass.
    @ViewBuilder
    @MainActor
    func glassProminentToolbarButton() -> some View {
        #if os(macOS)
        content.buttonStyle(.borderedProminent)
        #elseif !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }

    /// Prominent circular glass button style on modern OS, with frosted circular fallback on older OS.
    @ViewBuilder
    @MainActor
    func prominentGlassCircleButton() -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            content
                .buttonStyle(DefaultButtonStyle())
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                )
        }
        #else
        content
            .buttonStyle(DefaultButtonStyle())
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
            )
        #endif
    }

    /// Prominent blue circular glass button (matching iOS 26 Messages compose / Notes new button).
    @ViewBuilder
    @MainActor
    func blueGlassCircleButton(size: CGFloat = 46) -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Color.accentColor)
                .frame(width: size, height: size)
                .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
        } else {
            content
                .buttonStyle(.plain)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
                )
        }
        #else
        content
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(Color.accentColor)
            .frame(width: size, height: size)
        #endif
    }

    @ViewBuilder
    @MainActor
    func blueGlassCircleButton(diameter: CGFloat) -> some View {
        blueGlassCircleButton(size: diameter)
    }

    private func fallbackGlass(cornerRadius: CGFloat) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
    }

    private func fallbackGlassCapsule() -> some View {
        content.background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.10),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
        )
    }
}

public extension WawonaBackport where Content == Any {
    /// `NavigationStack` on iOS 16+, with `NavigationView` as the iOS 13-15 host.
    @ViewBuilder
    @MainActor
    static func navigation<Inner: View>(@ViewBuilder content: () -> Inner) -> some View {
        if #available(iOS 16.0, tvOS 16.0, watchOS 9.0, macOS 13.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }
        }
    }

    /// Groups toolbar / chrome views in a native iOS 26 Liquid Glass container for unified refraction.
    @ViewBuilder
    @MainActor
    static func glassContainer<Inner: View>(spacing: CGFloat? = 10, @ViewBuilder content: () -> Inner) -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, macOS 26.0, watchOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
