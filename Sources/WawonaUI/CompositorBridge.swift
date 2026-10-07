import SwiftUI

public struct CompositorBridge: View {
    public init() {}

    public var body: some View {
        #if os(macOS)
        #if SWIFT_PACKAGE
        MacCompositorPlaceholder()
        #else
        CompositorHostView()
        #endif
        #elseif os(iOS)
        #if SWIFT_PACKAGE
        IOSCompositorPlaceholder()
        #else
        CompositorHostView()
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
