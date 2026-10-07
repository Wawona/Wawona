import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@objc(WWNImageLoader)
public final class WWNImageLoader: NSObject {
    @objc public static let sharedLoader = WWNImageLoader()
    private override init() { super.init() }

    #if os(macOS)
    @objc public func loadImage(from url: URL, completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async { completion(image) }
        }
    }
    #elseif canImport(UIKit)
    @objc public func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let image = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
            DispatchQueue.main.async { completion(image) }
        }
    }
    #endif
}
