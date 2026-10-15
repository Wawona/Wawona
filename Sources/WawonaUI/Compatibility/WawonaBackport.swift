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

    /// Section accent for Toggle / Button / Link / Picker.
    /// `.tint` on iOS 15+; `.accentColor` on the iOS 13–14 floor.
    @ViewBuilder
    func tint(_ color: Color) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            content.tint(color)
        } else {
            content.accentColor(color)
        }
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

    /// Full-screen cover on iOS 14+; sheet fallback on iOS 13.
    @ViewBuilder
    func fullScreenCover<Cover: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content cover: @escaping () -> Cover
    ) -> some View {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 14.0, tvOS 14.0, *) {
            self.content.fullScreenCover(isPresented: isPresented, content: cover)
        } else {
            self.content.sheet(isPresented: isPresented, content: cover)
        }
        #else
        self.content.sheet(isPresented: isPresented, content: cover)
        #endif
    }

    /// Item-driven full-screen cover on iOS 14+; sheet fallback on iOS 13.
    /// Prefer this over bare `.fullScreenCover(item:)` so the iOS 13 floor compiles.
    @ViewBuilder
    func fullScreenCover<Item: Identifiable, Cover: View>(
        item: Binding<Item?>,
        @ViewBuilder content cover: @escaping (Item) -> Cover
    ) -> some View {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 14.0, tvOS 14.0, *) {
            self.content.fullScreenCover(item: item, content: cover)
        } else {
            self.content.sheet(item: item, content: cover)
        }
        #else
        self.content.sheet(item: item, content: cover)
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

    /// Dave DeLong namespace: `ScrollViewReader` (iOS 14+) with an iOS 13
    /// plain-`ScrollView` host. Call sites must not use bare `ScrollViewReader`.
    /// Wawona Terminal uses this for end-of-buffer scroll.
    @ViewBuilder
    @MainActor
    static func scrollViewReader<Inner: View>(
        @ViewBuilder content: @escaping (WawonaScrollViewProxy) -> Inner
    ) -> some View {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 14.0, tvOS 14.0, *) {
            WawonaNativeScrollViewReader(content: content)
        } else {
            content(WawonaScrollViewProxy())
        }
        #elseif os(watchOS)
        if #available(watchOS 7.0, *) {
            WawonaNativeScrollViewReader(content: content)
        } else {
            content(WawonaScrollViewProxy())
        }
        #elseif os(macOS)
        if #available(macOS 11.0, *) {
            WawonaNativeScrollViewReader(content: content)
        } else {
            content(WawonaScrollViewProxy())
        }
        #else
        content(WawonaScrollViewProxy())
        #endif
    }
}

/// Programmatic scroll proxy for `WawonaBackport.scrollViewReader`.
/// iOS 14+ wraps `ScrollViewProxy`. iOS 13: `scrollTo` is a no-op.
public struct WawonaScrollViewProxy {
    private let scrollToImpl: ((AnyHashable, UnitPoint?) -> Void)?

    fileprivate init(
        scrollToImpl: ((AnyHashable, UnitPoint?) -> Void)? = nil
    ) {
        self.scrollToImpl = scrollToImpl
    }

    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        scrollToImpl?(AnyHashable(id), anchor)
    }
}

#if os(iOS) || os(tvOS) || os(visionOS)
@available(iOS 14.0, tvOS 14.0, *)
private struct WawonaNativeScrollViewReader<Inner: View>: View {
    let content: (WawonaScrollViewProxy) -> Inner

    var body: some View {
        ScrollViewReader { proxy in
            content(
                WawonaScrollViewProxy(scrollToImpl: { id, anchor in
                    if let anchor {
                        proxy.scrollTo(id, anchor: anchor)
                    } else {
                        proxy.scrollTo(id)
                    }
                })
            )
        }
    }
}
#elseif os(watchOS)
@available(watchOS 7.0, *)
private struct WawonaNativeScrollViewReader<Inner: View>: View {
    let content: (WawonaScrollViewProxy) -> Inner

    var body: some View {
        ScrollViewReader { proxy in
            content(
                WawonaScrollViewProxy(scrollToImpl: { id, anchor in
                    if let anchor {
                        proxy.scrollTo(id, anchor: anchor)
                    } else {
                        proxy.scrollTo(id)
                    }
                })
            )
        }
    }
}
#elseif os(macOS)
@available(macOS 11.0, *)
private struct WawonaNativeScrollViewReader<Inner: View>: View {
    let content: (WawonaScrollViewProxy) -> Inner

    var body: some View {
        ScrollViewReader { proxy in
            content(
                WawonaScrollViewProxy(scrollToImpl: { id, anchor in
                    if let anchor {
                        proxy.scrollTo(id, anchor: anchor)
                    } else {
                        proxy.scrollTo(id)
                    }
                })
            )
        }
    }
}
#endif
