#if WWN_MODE_B
import Foundation
import UIKit

/// IOMFB host claim: digitizer steal and idle timer. Replaces `WWNModeBDisplayClaim.m`.
public enum ModeBDisplayClaim {
    /// touchId, state, x, y, force (0 when unknown).
    public typealias HidSink = @convention(c) (Int32, Int32, Double, Double, Double) -> Void

    fileprivate static var hidSink: HidSink?
    private static var hidClient: UnsafeMutableRawPointer?
    private static var iokitHandle: UnsafeMutableRawPointer?
    private static var claimed = false

    fileprivate static var hidFloat: (@convention(c) (UnsafeMutableRawPointer?, UInt32) -> Double)?
    fileprivate static var hidInt: (@convention(c) (UnsafeMutableRawPointer?, UInt32) -> CFIndex)?
    fileprivate static var hidType: (@convention(c) (UnsafeMutableRawPointer?) -> UInt32)?
    fileprivate static var hidChildren: (@convention(c) (UnsafeMutableRawPointer?) -> CFArray?)?
    private static var hidUnschedule: (
        @convention(c) (UnsafeMutableRawPointer?, CFRunLoop?, CFString?) -> Void
    )?

    fileprivate enum Hid {
        static let digitizer: UInt32 = 11
        static let fieldX: UInt32 = 0x000B0000
        static let fieldY: UInt32 = 0x000B0001
        static let fieldIndex: UInt32 = 0x000B0005
        static let fieldTouch: UInt32 = 0x000B0009
    }

    public static func setHidSink(_ sink: HidSink?) {
        hidSink = sink
    }

    public static func claimActive() -> Int32 {
        claimed ? 1 : 0
    }

    @discardableResult
    public static func claimHost() -> Int32 {
        if claimed { return 0 }
        UIApplication.shared.isIdleTimerDisabled = true
        let hid = startHid()
        claimed = true
        modebLog("claim host hid=\(hid) (no process park)")
        return 0
    }

    @discardableResult
    public static func releaseHost() -> Int32 {
        if !claimed { return 0 }
        stopHid()
        UIApplication.shared.isIdleTimerDisabled = false
        claimed = false
        modebLog("claim host released")
        return 0
    }

    fileprivate static func modebLog(_ message: String) {
        message.withCString { ptr in
            wwn_log_ring_append("MODEB", ptr)
        }
    }

    private static func mapHidPoint(rawX: Double, rawY: Double) -> (Double, Double) {
        let bounds = UIScreen.main.bounds
        let bw = bounds.size.width
        let bh = bounds.size.height
        if bw < 1 || bh < 1 {
            return (rawX, rawY)
        }
        if rawX >= 0, rawX <= 1.5, rawY >= 0, rawY <= 1.5 {
            return (rawX * bw, rawY * bh)
        }
        var dw: Int32 = 0
        var dh: Int32 = 0
        wwn_modeb_desktop_size(&dw, &dh)
        if dw > 0, dh > 0, rawX > bw * 1.5 || rawY > bh * 1.5 {
            return (rawX * bw / Double(dw), rawY * bh / Double(dh))
        }
        return (rawX, rawY)
    }

    private static var touchDown = [UInt8](repeating: 0, count: 16)
    private static var hidLogCount = 0

    private static func emitHid(
        touchId: Int32,
        state: Int32,
        rawX: Double,
        rawY: Double,
        force: Double
    ) {
        let mapped = mapHidPoint(rawX: rawX, rawY: rawY)
        if hidLogCount < 8 {
            hidLogCount += 1
            modebLog(
                "hid steal id=\(touchId) state=\(state) raw=\(rawX),\(rawY) view=\(mapped.0),\(mapped.1)"
            )
        }
        hidSink?(touchId, state, mapped.0, mapped.1, force)
    }

    fileprivate static func handleHidEvent(_ event: UnsafeMutableRawPointer) {
        guard let hidType, let hidFloat else { return }
        let type = hidType(event)
        if type != Hid.digitizer {
            if let kids = hidChildren?(event) {
                let n = CFArrayGetCount(kids)
                for i in 0..<n {
                    guard let child = CFArrayGetValueAtIndex(kids, i) else { continue }
                    handleHidEvent(UnsafeMutableRawPointer(mutating: child))
                }
            }
            return
        }
        var touchId: Int32 = 1
        if let hidInt {
            let idx = hidInt(event, Hid.fieldIndex)
            if idx > 0 { touchId = Int32(idx) }
        }
        let x = hidFloat(event, Hid.fieldX)
        let y = hidFloat(event, Hid.fieldY)
        var touching = true
        if let hidInt {
            touching = hidInt(event, Hid.fieldTouch) != 0
        }
        let slot = Int(touchId & 15)
        var state: Int32 = 2
        if touching, touchDown[slot] == 0 {
            state = 1
            touchDown[slot] = 1
        } else if !touching, touchDown[slot] != 0 {
            state = 0
            touchDown[slot] = 0
        } else if !touching {
            return
        }
        emitHid(
            touchId: touchId,
            state: state,
            rawX: x,
            rawY: y,
            force: touching ? 1.0 : 0.0
        )
    }

    private static func startHid() -> Int32 {
        if iokitHandle == nil {
            iokitHandle = dlopen(
                "/System/Library/Frameworks/IOKit.framework/IOKit",
                RTLD_NOW | RTLD_LOCAL
            )
        }
        guard let iokit = iokitHandle else {
            modebLog("claim HID: IOKit missing")
            return Int32(ENOENT)
        }

        typealias CreateType = @convention(c) (CFAllocator?, UInt32, CFDictionary?) -> UnsafeMutableRawPointer?
        typealias Create = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
        typealias Register = @convention(c) (
            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
        ) -> Void
        typealias RegisterFilter = @convention(c) (
            UnsafeMutableRawPointer?,
            (@convention(c) (
                UnsafeMutableRawPointer?,
                UnsafeMutableRawPointer?,
                UnsafeMutableRawPointer?,
                UnsafeMutableRawPointer?
            ) -> DarwinBoolean)?,
            UnsafeMutableRawPointer?,
            UnsafeMutableRawPointer?
        ) -> Void
        typealias Schedule = @convention(c) (UnsafeMutableRawPointer?, CFRunLoop?, CFString?) -> Void

        guard let createType = unsafeBitCast(
            dlsym(iokit, "IOHIDEventSystemClientCreateWithType"),
            to: CreateType?.self
        ), let create = unsafeBitCast(
            dlsym(iokit, "IOHIDEventSystemClientCreate"),
            to: Create?.self
        ), let registerCb = unsafeBitCast(
            dlsym(iokit, "IOHIDEventSystemClientRegisterEventCallback"),
            to: Register?.self
        ), let schedule = unsafeBitCast(
            dlsym(iokit, "IOHIDEventSystemClientScheduleWithRunLoop"),
            to: Schedule?.self
        ) else {
            modebLog("claim HID: symbols missing")
            return Int32(ENOSYS)
        }

        hidUnschedule = unsafeBitCast(
            dlsym(iokit, "IOHIDEventSystemClientUnscheduleFromRunLoop"),
            to: (@convention(c) (UnsafeMutableRawPointer?, CFRunLoop?, CFString?) -> Void)?.self
        )
        hidFloat = unsafeBitCast(
            dlsym(iokit, "IOHIDEventGetFloatValue"),
            to: (@convention(c) (UnsafeMutableRawPointer?, UInt32) -> Double)?.self
        )
        hidInt = unsafeBitCast(
            dlsym(iokit, "IOHIDEventGetIntegerValue"),
            to: (@convention(c) (UnsafeMutableRawPointer?, UInt32) -> CFIndex)?.self
        )
        hidType = unsafeBitCast(
            dlsym(iokit, "IOHIDEventGetType"),
            to: (@convention(c) (UnsafeMutableRawPointer?) -> UInt32)?.self
        )
        hidChildren = unsafeBitCast(
            dlsym(iokit, "IOHIDEventGetChildren"),
            to: (@convention(c) (UnsafeMutableRawPointer?) -> CFArray?)?.self
        )

        var client = createType(kCFAllocatorDefault, 0, nil)
        if client == nil {
            client = create(kCFAllocatorDefault)
        }
        guard let client else {
            modebLog("claim HID: client create failed")
            return Int32(EPERM)
        }
        hidClient = client

        let registerFilter = unsafeBitCast(
            dlsym(iokit, "IOHIDEventSystemClientRegisterEventFilter"),
            to: RegisterFilter?.self
        )

        // Free @convention(c) entry points only (not nested enum methods).
        registerCb(
            client,
            unsafeBitCast(
                modebHidEventCallback as @convention(c) (
                    UnsafeMutableRawPointer?,
                    UnsafeMutableRawPointer?,
                    UnsafeMutableRawPointer?,
                    UnsafeMutableRawPointer?
                ) -> Void,
                to: UnsafeMutableRawPointer.self
            ),
            nil,
            nil
        )
        if let registerFilter {
            registerFilter(client, modebHidEventFilter, nil, nil)
        }
        let mode = CFRunLoopMode.commonModes.rawValue as CFString
        schedule(client, CFRunLoopGetMain(), mode)
        modebLog("claim HID: digitizer steal armed filter=\(registerFilter != nil ? 1 : 0)")
        return 0
    }

    private static func stopHid() {
        guard let client = hidClient else { return }
        let mode = CFRunLoopMode.commonModes.rawValue as CFString
        hidUnschedule?(client, CFRunLoopGetMain(), mode)
        Unmanaged<AnyObject>.fromOpaque(client).release()
        hidClient = nil
        modebLog("claim HID: released")
    }

    @_silgen_name("wwn_modeb_desktop_size")
    private static func wwn_modeb_desktop_size(
        _ width: UnsafeMutablePointer<Int32>?,
        _ height: UnsafeMutablePointer<Int32>?
    )

    @_silgen_name("wwn_log_ring_append")
    private static func wwn_log_ring_append(_ module: UnsafePointer<CChar>, _ msg: UnsafePointer<CChar>)
}

private func modebHidEventCallback(
    _ target: UnsafeMutableRawPointer?,
    _ refcon: UnsafeMutableRawPointer?,
    _ client: UnsafeMutableRawPointer?,
    _ event: UnsafeMutableRawPointer?
) {
    _ = target
    _ = refcon
    _ = client
    guard let event else { return }
    ModeBDisplayClaim.handleHidEvent(event)
}

private func modebHidEventFilter(
    _ target: UnsafeMutableRawPointer?,
    _ refcon: UnsafeMutableRawPointer?,
    _ service: UnsafeMutableRawPointer?,
    _ event: UnsafeMutableRawPointer?
) -> DarwinBoolean {
    _ = target
    _ = refcon
    _ = service
    guard let event, let hidType = ModeBDisplayClaim.hidType else { return false }
    let type = hidType(event)
    var digitizer = type == ModeBDisplayClaim.Hid.digitizer
    if !digitizer, let kids = ModeBDisplayClaim.hidChildren?(event) {
        let n = CFArrayGetCount(kids)
        for i in 0..<n {
            guard let child = CFArrayGetValueAtIndex(kids, i) else { continue }
            if hidType(UnsafeMutableRawPointer(mutating: child)) == ModeBDisplayClaim.Hid.digitizer {
                digitizer = true
                break
            }
        }
    }
    if digitizer {
        ModeBDisplayClaim.handleHidEvent(event)
        return true
    }
    return false
}

@_cdecl("wwn_modeb_set_hid_sink")
public func wwn_modeb_set_hid_sink(_ sink: ModeBDisplayClaim.HidSink?) {
    ModeBDisplayClaim.setHidSink(sink)
}

@_cdecl("wwn_modeb_claim_active")
public func wwn_modeb_claim_active() -> Int32 {
    ModeBDisplayClaim.claimActive()
}

@_cdecl("wwn_modeb_claim_host")
public func wwn_modeb_claim_host() -> Int32 {
    ModeBDisplayClaim.claimHost()
}

@_cdecl("wwn_modeb_release_host")
public func wwn_modeb_release_host() -> Int32 {
    ModeBDisplayClaim.releaseHost()
}
#endif
