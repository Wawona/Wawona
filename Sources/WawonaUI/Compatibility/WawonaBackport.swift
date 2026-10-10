import SwiftUI

/// Wawona's single availability namespace for SwiftUI APIs newer than iOS 13.
/// Keep runtime checks here, never at feature call sites.
public struct WawonaBackport<Content> {
    let content: Content

    fileprivate init(content: Content) {
        self.content = content
    }
}

public extension View {
    var backport: WawonaBackport<Self> { WawonaBackport(content: self) }
}

public extension WawonaBackport where Content: View {
    func navigationTitle(_ title: LocalizedStringKey, inline: Bool = false) -> some View {
        navigationTitleText(Text(title), inline: inline)
    }

    func navigationTitle<S: StringProtocol>(_ title: S, inline: Bool = false) -> some View {
        navigationTitleText(Text(title), inline: inline)
    }

    @ViewBuilder
    private func navigationTitleText(_ title: Text, inline: Bool) -> some View {
        #if os(iOS)
        if inline {
            if #available(iOS 17.0, *) {
                content
                    .navigationBarTitle(title, displayMode: .inline)
                    .toolbarTitleDisplayMode(.inline)
            } else {
                content.navigationBarTitle(title, displayMode: .inline)
            }
        } else {
            content.navigationBarTitle(title, displayMode: .automatic)
        }
        #else
        content.navigationTitle(title)
        #endif
    }

    /// Keeps Settings rows visibly separated on every supported SwiftUI host.
    /// iOS 15 adds a native row-separator API; iOS 13–14 get the same visual
    /// boundary without changing the app's deployment target.
    @ViewBuilder
    func visibleRowSeparator() -> some View {
        #if os(tvOS)
        // listRowSeparator is unavailable on tvOS.
        content.overlay(Divider(), alignment: .bottom)
        #elseif os(iOS) || os(visionOS)
        if #available(iOS 15.0, *) {
            content.listRowSeparator(.visible, edges: .bottom)
        } else {
            content.overlay(Divider(), alignment: .bottom)
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

    /// Toolbar trailing controls. Prefer system automatic styling. On iOS 26+
    /// Liquid Glass already owns the bar; `.buttonStyle(.glass)` is glass-on-glass
    /// and breaks the top-trailing cluster.
    @ViewBuilder
    @MainActor
    func glassToolbarButton() -> some View {
        content.buttonStyle(.automatic)
    }

    /// Keeps the modern prominent glass button on new systems without raising the app floor.
    @ViewBuilder
    @MainActor
    func glassProminentButtonStyle() -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(DefaultButtonStyle())
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
        } else if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(DefaultButtonStyle())
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
                    WawonaBackport<Any>.frosted(Circle())
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

    /// Prominent blue circular button (Messages compose / Notes new). Opaque
    /// fill: iOS 26 toolbar `.glassProminent` often drops the bubble.
    @ViewBuilder
    @MainActor
    func blueGlassCircleButton(size: CGFloat = 46) -> some View {
        #if !os(visionOS)
        if #available(iOS 17.0, tvOS 17.0, macOS 14.0, *) {
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(Color.accentColor)
                .frame(width: size, height: size)
                .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
        } else if #available(iOS 15.0, tvOS 15.0, macOS 12.0, *) {
            content
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
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

    /// Filled blue circle for primary icon actions (Add +, editor Save checkmark).
    /// Availability lives here (Dave DeLong `Backport` namespace).
    ///
    /// iOS 26 `.glassProminent` on toolbar/sheet `Image` buttons often paints a
    /// bare accent glyph with no bubble. Use `.borderedProminent` + `.circle` +
    /// accent tint for an opaque blue fill. Pair with
    /// `sharedBackgroundVisibility(.hidden)` on the `ToolbarItem`. Prefer
    /// `Image(systemName:)` over `Label` (Label drops the circle). Force
    /// `.iconOnly`. `ButtonBorderShape.circle` is iOS 17+; older hosts clip.
    @ViewBuilder
    @MainActor
    func composeCircleButton() -> some View {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 17.0, tvOS 17.0, *) {
            content
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(Color.accentColor)
        } else if #available(iOS 15.0, tvOS 15.0, *) {
            content
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .accentColor(Color.accentColor)
        } else {
            content
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(10)
                .background(Circle().fill(Color.accentColor))
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            content
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content
        #endif
    }


    private func fallbackGlass(cornerRadius: CGFloat) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
    }

    private func fallbackGlassCapsule() -> some View {
        content.background(
            WawonaBackport<Any>.frosted(Capsule())
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
    @ViewBuilder
    static func frosted<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *) {
            shape.fill(.ultraThinMaterial)
        } else {
            shape.fill(Color.primary.opacity(0.08))
        }
    }

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
