import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
public typealias WWNTermPlatformView = NSView
#elseif canImport(UIKit)
import UIKit
public typealias WWNTermPlatformView = UIView
#endif

public typealias WWNTermReply = (Data) -> Void

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
@objc(WWNTermSurface)
public final class WWNTermSurface: WWNTermPlatformView {
    @objc public var onReply: WWNTermReply?

    @objc(feed:)
    public func feed(_ bytes: Data) {
        _ = bytes
        // Terminal screen is Rust (Wawona Terminal). Host draws via SwiftUI.
    }
}
#endif
