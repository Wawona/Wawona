#if canImport(Metal) && os(iOS) && WWN_MODE_B
import Foundation
import IOSurface

enum IlandModeBPresent {
    @_silgen_name("wwn_modeb_desktop_present_iosurface")
    static func presentIOSurface(_ surface: IOSurface?, _ width: UInt32, _ height: UInt32) -> Int32

    @_silgen_name("wwn_modeb_desktop_size")
    static func desktopSize(_ width: UnsafeMutablePointer<UInt32>?, _ height: UnsafeMutablePointer<UInt32>?) -> Int32

    @_silgen_name("wwn_modeb_desktop_phase")
    static func desktopPhase() -> UInt32

    static func routeIfActive(surface: IOSurface, crtcID: UInt32, framebufferID: UInt32) -> Bool {
        guard desktopPhase() != 0 else { return false }
        let width = UInt32(IOSurfaceGetWidth(surface))
        let height = UInt32(IOSurfaceGetHeight(surface))
        _ = presentIOSurface(surface, width, height)
        IlandDrmBindings.completePageFlip(crtcID, framebufferID)
        return true
    }

    static func presentCompositorOnly(surface: IOSurface) -> Bool {
        guard desktopPhase() != 0 else { return false }
        let width = UInt32(IOSurfaceGetWidth(surface))
        let height = UInt32(IOSurfaceGetHeight(surface))
        return presentIOSurface(surface, width, height) == 0
    }
}

@_cdecl("wwn_modeb_desktop_bind_iland_present")
public func wwn_modeb_desktop_bind_iland_present() -> Int32 {
    var width: UInt32 = 0
    var height: UInt32 = 0
    guard IlandModeBPresent.desktopSize(&width, &height) == 0 else { return -1 }
    IlandDrmBindings.setPreferredMode(width, height, IlandDrmBindings.refreshMillihz())
    guard IlandDrmBindings.prepareVirtualFd() == 0 else { return -1 }
    IlandDrmBindings.setPresentCallback(modeBPresentTrampoline, nil)
    return 0
}

private func modeBPresentTrampoline(
    crtcID: UInt32,
    framebufferID: UInt32,
    surface: IOSurface?,
    flags: UInt32,
    user: UnsafeMutableRawPointer?
) {
    _ = flags
    _ = user
    if let surface {
        let width = UInt32(IOSurfaceGetWidth(surface))
        let height = UInt32(IOSurfaceGetHeight(surface))
        _ = IlandModeBPresent.presentIOSurface(surface, width, height)
    }
    IlandDrmBindings.completePageFlip(crtcID, framebufferID)
}
#endif
