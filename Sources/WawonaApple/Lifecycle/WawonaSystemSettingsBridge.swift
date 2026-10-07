#if os(macOS)
import AppKit
import Foundation

/// ObjC trampoline into System Settings → Wawona PrefPane.
/// PrefPane is the sole Global Settings host (no in-app catalog fallback).
@objc(WawonaSystemSettings)
public final class WawonaSystemSettingsBridge: NSObject {
    @objc public static func openPreferencePane() {
        if let url = URL(string: "x-apple.systempreferences:com.aspauldingcode.Wawona.prefPane") {
            _ = NSWorkspace.shared.open(url)
        }
    }
}
#endif
