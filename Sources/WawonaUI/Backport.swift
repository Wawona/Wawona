import SwiftUI

/// Namespace for centralized compatibility shims.
///
/// Call sites use the system API's name through `.backport`; availability
/// checks and older-system fallbacks stay here instead of spreading through
/// feature views.
public struct Backport<Content> {
    public let content: Content

    public init(_ content: Content) {
        self.content = content
    }
}

public extension View {
    var backport: Backport<Self> { Backport(self) }
}

public extension Backport where Content == Any {
    /// Liquid Glass plate on OS 26+, material plate on older systems.
    @ViewBuilder
    static func glassRoundedRectangle(cornerRadius: CGFloat) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        #elseif os(iOS)
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        #else
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
        #endif
    }
}

public extension Backport where Content: View {
    /// Liquid Glass prominent button on iOS 26+, standard prominent button
    /// elsewhere. The fallback preserves action, label, shape, and accessibility.
    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }

    /// Tahoe's transparent titlebar needs extra detail inset. Older macOS
    /// releases retain their existing layout unchanged.
    @ViewBuilder
    func macDetailTopInsetForTransparentTitlebar() -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            content.safeAreaPadding(.top, 28)
        } else {
            content
        }
        #else
        content
        #endif
    }

    /// Restore unified toolbar material only where the OS 26 window treatment
    /// requires it.
    @ViewBuilder
    func macUnifiedToolbarMaterial() -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            content
                .toolbarBackground(.regularMaterial, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
