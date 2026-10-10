import Foundation

/// Thin Mode B desktop session calls into Rust. Replaces parts of
/// `WWNModeBDisplayClaim.m` / desktop ObjC. No watchdog control.
///
/// Sole Swift owner of `@_silgen_name` for desktop phase/size/start.
/// Other Mode B Swift call sites use these wrappers (no duplicate silgen).
public enum DesktopSession {
    @_silgen_name("wwn_modeb_desktop_start")
    private static func wwn_modeb_desktop_start(
        _ width: UnsafeMutablePointer<UInt32>?,
        _ height: UnsafeMutablePointer<UInt32>?
    ) -> Int32

    @_silgen_name("wwn_modeb_desktop_phase")
    private static func wwn_modeb_desktop_phase() -> UInt32

    @_silgen_name("wwn_modeb_desktop_size")
    private static func wwn_modeb_desktop_size(
        _ width: UnsafeMutablePointer<UInt32>?,
        _ height: UnsafeMutablePointer<UInt32>?
    ) -> Int32

    @_silgen_name("wwn_modeb_desktop_recover_to_greeter")
    private static func wwn_modeb_desktop_recover_to_greeter() -> Int32

    public static func start() -> Bool {
        var w: UInt32 = 0
        var h: UInt32 = 0
        return wwn_modeb_desktop_start(&w, &h) == 0
    }

    public static func phase() -> Int {
        Int(wwn_modeb_desktop_phase())
    }

    /// Fills width/height from the live Mode B desktop sink. Returns 0 on success.
    @discardableResult
    public static func fillSize(
        _ width: UnsafeMutablePointer<UInt32>?,
        _ height: UnsafeMutablePointer<UInt32>?
    ) -> Int32 {
        wwn_modeb_desktop_size(width, height)
    }

    public static func size() -> (width: Int, height: Int) {
        var w: UInt32 = 0
        var h: UInt32 = 0
        _ = wwn_modeb_desktop_size(&w, &h)
        return (Int(w), Int(h))
    }

    public static func recoverToGreeter() -> Bool {
        wwn_modeb_desktop_recover_to_greeter() == 0
    }
}
