import Foundation

/// Mirrors Rust `CWindowEvent` (`src/ffi/c_api.rs`).
struct WWNWindowEvent {
    var eventType: UInt64
    var windowId: UInt64
    var surfaceId: UInt32
    var title: String
    var width: UInt32
    var height: UInt32
    var parentId: UInt64
    var x: Int32
    var y: Int32
    var decorationMode: UInt8
    var fullscreenShell: UInt8
    var hostLocked: UInt8
    var edges: UInt8
    var sizeKind: UInt8
    var sizeCause: UInt8
    var fillsHost: UInt8
    var configureSerial: UInt32
    var transactionId: UInt64

    static let created: UInt64 = 0
    static let destroyed: UInt64 = 1
    static let titleChanged: UInt64 = 2
    static let sizeChanged: UInt64 = 3
    static let popupCreated: UInt64 = 4
    static let decorationsModeChanged: UInt64 = 8
    static let closeRequested: UInt64 = 16

    /// Parse a heap `CWindowEvent*` from `WWNCorePopWindowEvent`.
    static func parse(_ raw: UnsafeMutableRawPointer) -> WWNWindowEvent {
        let base = raw
        let eventType = base.load(as: UInt64.self)
        let windowId = base.advanced(by: 8).load(as: UInt64.self)
        let surfaceId = base.advanced(by: 16).load(as: UInt32.self)
        // title pointer at 24 (aligned)
        let titlePtr = base.advanced(by: 24).load(as: UnsafeMutablePointer<CChar>?.self)
        let title: String
        if let titlePtr {
            title = String(cString: titlePtr)
        } else {
            title = ""
        }
        let width = base.advanced(by: 32).load(as: UInt32.self)
        let height = base.advanced(by: 36).load(as: UInt32.self)
        let parentId = base.advanced(by: 40).load(as: UInt64.self)
        let x = base.advanced(by: 48).load(as: Int32.self)
        let y = base.advanced(by: 52).load(as: Int32.self)
        let decorationMode = base.advanced(by: 56).load(as: UInt8.self)
        let fullscreenShell = base.advanced(by: 57).load(as: UInt8.self)
        let hostLocked = base.advanced(by: 58).load(as: UInt8.self)
        let edges = base.advanced(by: 59).load(as: UInt8.self)
        let sizeKind = base.advanced(by: 60).load(as: UInt8.self)
        let sizeCause = base.advanced(by: 61).load(as: UInt8.self)
        let fillsHost = base.advanced(by: 62).load(as: UInt8.self)
        let configureSerial = base.advanced(by: 64).load(as: UInt32.self)
        let transactionId = base.advanced(by: 72).load(as: UInt64.self)
        return WWNWindowEvent(
            eventType: eventType,
            windowId: windowId,
            surfaceId: surfaceId,
            title: title,
            width: width,
            height: height,
            parentId: parentId,
            x: x,
            y: y,
            decorationMode: decorationMode,
            fullscreenShell: fullscreenShell,
            hostLocked: hostLocked,
            edges: edges,
            sizeKind: sizeKind,
            sizeCause: sizeCause,
            fillsHost: fillsHost,
            configureSerial: configureSerial,
            transactionId: transactionId
        )
    }
}
