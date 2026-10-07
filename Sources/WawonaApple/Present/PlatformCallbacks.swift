import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@objc(WWNPlatformCallbacks)
public final class WWNPlatformCallbacks: NSObject {
    @objc public static let sharedCallbacks = WWNPlatformCallbacks()

    #if os(macOS)
    @objc public var windowRegistry: NSMutableDictionary = NSMutableDictionary()
    #else
    @objc public var windowRegistry: NSMutableDictionary = NSMutableDictionary()
    #endif

    @objc(registerWindow:forId:)
    public func registerWindow(_ window: AnyObject, forId windowId: UInt64) {
        windowRegistry[NSNumber(value: windowId)] = window
    }

    @objc(unregisterWindowId:)
    public func unregisterWindowId(_ windowId: UInt64) {
        windowRegistry.removeObject(forKey: NSNumber(value: windowId))
    }

    @objc(windowForId:)
    public func window(forId windowId: UInt64) -> AnyObject? {
        windowRegistry[NSNumber(value: windowId)] as AnyObject?
    }
}
