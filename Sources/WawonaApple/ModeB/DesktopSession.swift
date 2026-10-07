import Foundation

/// Thin Mode B desktop session calls into Rust. Replaces parts of
/// `WWNModeBDisplayClaim.m` / desktop ObjC. No watchdog control.
public enum DesktopSession {
    @_silgen_name("wwn_modeb_desktop_start")
    private static func wwn_modeb_desktop_start() -> Int32

    @_silgen_name("wwn_modeb_desktop_phase")
    private static func wwn_modeb_desktop_phase() -> Int32

    @_silgen_name("wwn_modeb_desktop_size")
    private static func wwn_modeb_desktop_size(
        _ width: UnsafeMutablePointer<Int32>?,
        _ height: UnsafeMutablePointer<Int32>?
    )

    @_silgen_name("wwn_modeb_desktop_recover_to_greeter")
    private static func wwn_modeb_desktop_recover_to_greeter() -> Int32

    public static func start() -> Bool {
        wwn_modeb_desktop_start() == 0
    }

    public static func phase() -> Int {
        Int(wwn_modeb_desktop_phase())
    }

    public static func size() -> (width: Int, height: Int) {
        var w: Int32 = 0
        var h: Int32 = 0
        wwn_modeb_desktop_size(&w, &h)
        return (Int(w), Int(h))
    }

    public static func recoverToGreeter() -> Bool {
        wwn_modeb_desktop_recover_to_greeter() == 0
    }
}
