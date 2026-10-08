import Foundation

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
#if canImport(AppKit) && os(macOS)
import AppKit
#endif

/// Host pasteboard for in-process shell. Framework only.
public enum Pasteboard {
    public static func copy(_ text: String) -> Bool {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(text, forType: .string)
        #elseif canImport(UIKit) && !os(watchOS) && !os(tvOS)
        UIPasteboard.general.string = text
        return true
        #else
        _ = text
        return false
        #endif
    }

    public static func paste() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #elseif canImport(UIKit) && !os(watchOS) && !os(tvOS)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }
}
