import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import MobileCoreServices
#endif

enum WawonaFileType {
    case item, directory, filenameExtension(String)

    @available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
    var native: UTType {
        switch self {
        case .item: return .item
        case .directory: return .directory
        case .filenameExtension(let value): return UTType(filenameExtension: value) ?? .data
        }
    }

    #if os(iOS)
    var legacy: String {
        switch self {
        case .item: return "public.item"
        case .directory: return "public.folder"
        case .filenameExtension(let value):
            return UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                value as CFString, kUTTypeData)?.takeRetainedValue() as String? ?? "public.data"
        }
    }
    #endif
}

extension WawonaBackport where Content: View {
    @ViewBuilder
    func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [WawonaFileType],
                      onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
        if #available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *) {
            content.fileImporter(isPresented: isPresented,
                allowedContentTypes: allowedContentTypes.map(\.native), onCompletion: onCompletion)
        } else {
            #if os(iOS)
            // A separate presentation node avoids the pre-14.5 multiple-sheet limitation.
            content.background(Color.clear.sheet(isPresented: isPresented) {
                WawonaDocumentPicker(isPresented: isPresented,
                    identifiers: allowedContentTypes.map(\.legacy), completion: onCompletion)
            })
            #else
            content
            #endif
        }
    }
}

#if os(iOS)
private struct WawonaDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let identifiers: [String]
    let completion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(documentTypes: identifiers, in: .open)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        context.coordinator.owner = self
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var owner: WawonaDocumentPicker
        init(_ owner: WawonaDocumentPicker) { self.owner = owner }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            owner.isPresented = false
            if let url = urls.first { owner.completion(.success(url)) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            owner.isPresented = false
        }
    }
}
#endif
