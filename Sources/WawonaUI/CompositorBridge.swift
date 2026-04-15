import SwiftUI

public struct CompositorBridge: View {
    public init() {}

    public var body: some View {
        #if os(macOS)
        MacCompositorView()
        #elseif os(iOS)
        IOSCompositorView()
        #elseif os(Android)
        AndroidCompositorView()
        #else
        Color.black
        #endif
    }
}

#if os(macOS)
import AppKit

private struct MacCompositorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // The ObjC compositor host is injected by the app target at runtime.
        // During SwiftPM-only previews/tests, use a placeholder view.
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

private struct IOSCompositorView: UIViewRepresentable {
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
