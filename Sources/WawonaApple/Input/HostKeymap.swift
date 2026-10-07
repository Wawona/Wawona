import Foundation
#if os(macOS)
import Carbon
import CoreFoundation
#endif

/// Host keyboard layout bridge. Replaces `WWNHostKeymap.m`.
public enum HostKeymap {
    public static let hostKeyKindMacVK: Int32 = 1

    /// Dump TIS / UCKeyTranslate (macOS) and push levels into Rust.
    public static func dumpAndApply(core: UnsafeMutableRawPointer?) {
        #if os(macOS)
        macDumpAndApply(core: core)
        #else
        _ = core
        #endif
    }

    /// Observe layout changes (macOS only).
    public static func startObserving(core: UnsafeMutableRawPointer?) {
        #if os(macOS)
        MacKeymapObserver.shared.start(core: core)
        #else
        _ = core
        #endif
    }
}

#if os(macOS)
import Carbon

private enum MacKeymapObserver {
    static let shared = Observer()
    final class Observer {
        private var core: UnsafeMutableRawPointer?
        private var installed = false

        func start(core: UnsafeMutableRawPointer?) {
            self.core = core
            guard !installed else { return }
            installed = true
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDistributedCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    let obs = Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue()
                    HostKeymap.dumpAndApply(core: obs.core)
                },
                kTISNotifySelectedKeyboardInputSourceChanged,
                nil,
                .deliverImmediately
            )
        }
    }
}

private func macDumpAndApply(core: UnsafeMutableRawPointer?) {
    guard let held = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let dataRef = TISGetInputSourceProperty(held, kTISPropertyUnicodeKeyLayoutData)
    else { return }
    let data = dataRef as! CFData
    guard let base = CFDataGetBytePtr(data) else { return }
    let layout = UnsafeRawPointer(base).assumingMemoryBound(to: UCKeyboardLayout.self)
    let mods: [UInt32] = [
        0,
        UInt32(shiftKey >> 8),
        UInt32(optionKey >> 8),
        UInt32((shiftKey | optionKey) >> 8),
    ]
    var ids: [Int32] = []
    var levels: [UInt32] = []
    for kvk: UInt16 in 0..<128 {
        var lv = [UInt32](repeating: 0, count: 4)
        var ok = true
        for i in 0..<4 {
            if !translateKvk(layout: layout, kvk: kvk, modifierKeyState: mods[i], out: &lv[i]) {
                ok = false
                break
            }
        }
        if !ok || (lv[0] == 0 && lv[1] == 0) { continue }
        ids.append(Int32(kvk))
        levels.append(contentsOf: lv)
    }
    guard !ids.isEmpty else { return }
    ids.withUnsafeBufferPointer { idBuf in
        levels.withUnsafeBufferPointer { lvBuf in
            WWNApplyHostKeyLevels(
                HostKeymap.hostKeyKindMacVK,
                idBuf.baseAddress,
                lvBuf.baseAddress,
                ids.count
            )
        }
    }
    if let core {
        WWNCoreReloadHostKeymap(core)
    }
}

private func translateKvk(
    layout: UnsafePointer<UCKeyboardLayout>,
    kvk: UInt16,
    modifierKeyState: UInt32,
    out: inout UInt32
) -> Bool {
    var dead: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var count: Int = 0
    let st = UCKeyTranslate(
        layout,
        kvk,
        UInt16(kUCKeyActionDisplay),
        modifierKeyState,
        UInt32(LMGetKbdType()),
        UInt32(kUCKeyTranslateNoDeadKeysBit),
        &dead,
        4,
        &count,
        &chars
    )
    if st != noErr || count == 0 {
        out = 0
        return true
    }
    out = UInt32(chars[0])
    return true
}

@_silgen_name("WWNApplyHostKeyLevels")
private func WWNApplyHostKeyLevels(
    _ kind: Int32,
    _ ids: UnsafePointer<Int32>?,
    _ levels4: UnsafePointer<UInt32>?,
    _ count: Int
)

@_silgen_name("WWNCoreReloadHostKeymap")
private func WWNCoreReloadHostKeymap(_ core: UnsafeMutableRawPointer)
#endif

@_cdecl("WWNHostKeymapDumpAndApply")
public func WWNHostKeymapDumpAndApply(_ core: UnsafeMutableRawPointer?) {
    HostKeymap.dumpAndApply(core: core)
}

@_cdecl("WWNHostKeymapStartObserving")
public func WWNHostKeymapStartObserving(_ core: UnsafeMutableRawPointer?) {
    HostKeymap.startObserving(core: core)
}
