import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Native text editing only. Relay supplies file templates and syntax ranges.
public struct NixConfigurationEditor: View {
    @Binding private var files: [String: String]
    @State private var selectedFile = "configuration.nix"
    public init(files: Binding<[String: String]>) { _files = files }
    private var source: Binding<String> {
        Binding(get: {
            files[selectedFile] ?? NixEditorDocument.load(selectedFile, source: nil)?.source ?? ""
        }, set: { files[selectedFile] = $0 })
    }
    public var body: some View {
        WawonaDisclosureGroup("NixOS configuration") { editor }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Configuration file", selection: $selectedFile) {
                Text("configuration.nix").tag("configuration.nix")
                Text("flake.nix").tag("flake.nix")
                Text("relay.nix").tag("relay.nix")
            }.pickerStyle(SegmentedPickerStyle())
            #if os(iOS) || os(macOS)
            NixNativeTextView(source: source, filename: selectedFile)
                .frame(minHeight: 360, idealHeight: 480)
                .accessibility(label: Text(selectedFile))
                .accessibility(identifier: "wwn.vm.nix.source")
            #else
            Text(source.wrappedValue).font(.system(.body, design: .monospaced))
            #endif
            Text("Save the machine to keep these configuration drafts. Applying them to the guest is not available yet.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

private struct NixEditorDocument: Decodable {
    struct Highlight: Decodable { let location: Int; let length: Int; let kind: String }
    let source: String
    let highlights: [Highlight]
    static func load(_ filename: String, source: String?) -> NixEditorDocument? {
        #if canImport(Darwin)
        typealias Editor = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
        typealias Free = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(handle, "relay_nix_editor"),
              let freeSymbol = dlsym(handle, "relay_string_free") else { return nil }
        let editor = unsafeBitCast(symbol, to: Editor.self)
        let release = unsafeBitCast(freeSymbol, to: Free.self)
        var output: UnsafeMutablePointer<CChar>?
        let result = filename.withCString { name in
            if let source = source { return source.withCString { editor(name, $0, &output) } }
            return editor(name, nil, &output)
        }
        guard result == 0, let output = output else { return nil }
        defer { release(output) }
        return try? JSONDecoder().decode(Self.self, from: Data(String(cString: output).utf8))
        #else
        return nil
        #endif
    }
}

#if os(iOS)
private struct NixNativeTextView: UIViewRepresentable {
    @Binding var source: String
    let filename: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        view.backgroundColor = .secondarySystemBackground
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != source { view.text = source }
        if view.markedTextRange == nil { highlight(view) }
    }
    func highlight(_ view: UITextView) {
        let selection = view.selectedRange
        let range = NSRange(location: 0, length: view.textStorage.length)
        view.textStorage.beginEditing()
        view.textStorage.addAttributes([.foregroundColor: UIColor.label, .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)], range: range)
        if let document = NixEditorDocument.load(filename, source: view.text) {
            for span in document.highlights {
                let color: UIColor
                switch span.kind {
                case "comment": color = .secondaryLabel
                case "keyword": color = .systemPurple
                case "string": color = .systemGreen
                case "number": color = .systemOrange
                case "punctuation": color = .systemBlue
                default: color = .label
                }
                guard span.location >= 0, span.length > 0, span.location + span.length <= range.length else { continue }
                view.textStorage.addAttribute(.foregroundColor, value: color, range: NSRange(location: span.location, length: span.length))
            }
        }
        view.textStorage.endEditing()
        view.selectedRange = selection
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NixNativeTextView
        init(_ parent: NixNativeTextView) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) {
            parent.source = view.text
            if view.markedTextRange == nil { parent.highlight(view) }
        }
    }
}
#elseif os(macOS)
private struct NixNativeTextView: NSViewRepresentable {
    @Binding var source: String
    let filename: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.delegate = context.coordinator
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != source { view.string = source }
        if !view.hasMarkedText() { highlight(view) }
    }
    func highlight(_ view: NSTextView) {
        guard let storage = view.textStorage else { return }
        let selection = view.selectedRange()
        storage.beginEditing()
        storage.addAttributes([.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)], range: NSRange(location: 0, length: storage.length))
        if let document = NixEditorDocument.load(filename, source: view.string) {
            for span in document.highlights {
                let color: NSColor
                switch span.kind {
                case "comment": color = .secondaryLabelColor
                case "keyword": color = .systemPurple
                case "string": color = .systemGreen
                case "number": color = .systemOrange
                case "punctuation": color = .systemBlue
                default: color = .labelColor
                }
                guard span.location >= 0, span.length > 0, span.location + span.length <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: span.location, length: span.length))
            }
        }
        storage.endEditing()
        view.setSelectedRange(selection)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NixNativeTextView
        init(_ parent: NixNativeTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.source = view.string
            if !view.hasMarkedText() { parent.highlight(view) }
        }
    }
}
#endif
