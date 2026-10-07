#if canImport(Metal) && !os(watchOS)
import Foundation
import IOSurface
import QuartzCore
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

enum IlandDrmBindings {
    typealias PresentCallback = @convention(c) (
        UInt32, UInt32, IOSurface?, UInt32, UnsafeMutableRawPointer?
    ) -> Void

    @_silgen_name("iland_drm_set_present_callback")
    static func setPresentCallback(_ cb: PresentCallback?, _ user: UnsafeMutableRawPointer?)

    @_silgen_name("iland_drm_set_preferred_mode")
    static func setPreferredMode(_ width: UInt32, _ height: UInt32, _ refreshMillihz: UInt32)

    @_silgen_name("iland_drm_complete_page_flip")
    static func completePageFlip(_ crtcID: UInt32, _ framebufferID: UInt32)

    @_silgen_name("iland_drm_prepare_virtual_fd")
    static func prepareVirtualFd() -> Int32

    static let drmVirtualFD: Int32 = 42

    @_silgen_name("g_drm_event_pipe_write")
    static var drmEventPipeWrite: Int32

    @_silgen_name("kmscube_main")
    static func kmscubeMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

    @_silgen_name("gbm_es2_demo_main")
    static func gbmEs2DemoMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

    #if os(iOS) && !os(visionOS)
    static func refreshMillihz() -> UInt32 {
        let fps = UIScreen.main.maximumFramesPerSecond
        return fps > 0 ? UInt32(fps) * 1000 : 0
    }
    #elseif os(iOS)
    static func refreshMillihz() -> UInt32 { 0 }
    #elseif os(macOS)
    static func refreshMillihz(for layer: CAMetalLayer) -> UInt32 {
        var screen: NSScreen?
        if let view = layer.delegate as? NSView {
            screen = view.window?.screen
        }
        screen = screen ?? NSScreen.main
        let fps = screen?.maximumFramesPerSecond ?? 0
        return fps > 0 ? UInt32(fps) * 1000 : 60_000
    }
    #endif
}
#endif
