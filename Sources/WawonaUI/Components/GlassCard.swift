import SwiftUI
#if os(macOS)
import AppKit
#endif

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    #if !os(macOS)
    @Environment(\.colorScheme) private var colorScheme
    #endif

    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if #available(macOS 26, iOS 26, *) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(outlineColor, lineWidth: 1)
            }
    }

    private var outlineColor: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.16)
        #endif
    }
}
