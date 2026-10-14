import SwiftUI

public struct CompositorBridge: View {
    public init() {}

    public var body: some View {
        // Product Mode A SHM needs CompositorHostView (IlandPresenter). A
        // SWIFT_PACKAGE placeholder is black UIView with no presenter; tip
        // AUTO_START then logs `no IlandPresenter` forever. Prefer Host when
        // Metal glue is in the same target; placeholder only for SPM previews.
        surface
            .accessibility(identifier: WWNA11y.compositorSurface)
            .accessibility(label: Text("Compositor surface"))
    }

    @ViewBuilder
    private var surface: some View {
        #if os(macOS)
        #if canImport(Metal) && !os(watchOS)
        CompositorHostView()
        #else
        MacCompositorPlaceholder()
        #endif
        #elseif os(iOS)
        #if canImport(Metal) && !os(watchOS)
        CompositorHostView()
        #else
        IOSCompositorPlaceholder()
        #endif
        #elseif os(Android)
        AndroidCompositorView()
        #else
        Color.black
        #endif
    }
}

#if os(macOS)
import AppKit

private struct MacCompositorPlaceholder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = nsView
        _ = context
    }
}
#endif

#if os(iOS)
import UIKit

private struct IOSCompositorPlaceholder: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        _ = uiView
        _ = context
    }
}
#endif

#if os(Android)
struct AndroidCompositorView: View {
    var body: some View {
        Color.black
    }
}
#endif
