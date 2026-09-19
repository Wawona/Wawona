import SwiftUI
#if os(iOS)
import UIKit
#endif

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
        } else if #available(iOS 15.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        }
        #else
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
        #endif
    }

    /// `NavigationStack` on iOS 16+, `NavigationView` with stack behavior on
    /// iOS 13–15.
    @ViewBuilder
    static func NavigationContainer<Body: View>(
        @ViewBuilder content: () -> Body
    ) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            NavigationStack(content: content)
        } else {
            NavigationView(content: content)
                .navigationViewStyle(StackNavigationViewStyle())
        }
        #else
        content()
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
        } else if #available(iOS 15.0, *) {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(DefaultButtonStyle())
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }

    /// Native searchable chrome on iOS 15+, inline search field on iOS 13–14.
    @ViewBuilder
    func searchable(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        if #available(iOS 15.0, *) {
            content.searchable(text: text, placement: .toolbar, prompt: prompt)
        } else {
            VStack(spacing: 0) {
                TextField(prompt, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("wwn.search")
                content
            }
        }
        #else
        content
        #endif
    }

    /// Native foreground styles on iOS 15+, equivalent color on iOS 13–14.
    @ViewBuilder
    func foregroundStyle(_ color: Color) -> some View {
        #if os(iOS)
        if #available(iOS 15.0, *) {
            content.foregroundStyle(color)
        } else {
            content.foregroundColor(color)
        }
        #else
        content.foregroundStyle(color)
        #endif
    }

    /// Menu picker on iOS 14+, wheel picker on iOS 13.
    @ViewBuilder
    func menuPickerStyle() -> some View {
        #if os(iOS)
        if #available(iOS 14.0, *) {
            content.pickerStyle(MenuPickerStyle())
        } else {
            content.pickerStyle(WheelPickerStyle())
        }
        #else
        content.pickerStyle(MenuPickerStyle())
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
