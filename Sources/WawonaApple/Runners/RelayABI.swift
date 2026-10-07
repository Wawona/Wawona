import Foundation
import Darwin

/// Optional Relay ABI. Core start/stop stay hard-linked; Nix editor / host
/// waypipe helpers are resolved at runtime because older `libwawona_relay.a`
/// builds may omit them.
enum RelayABI {
    @_silgen_name("relay_resolve_backend")
    static func resolveBackend(_ spec: UnsafePointer<CChar>?, _ out: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

    @_silgen_name("relay_start")
    static func start(_ spec: UnsafePointer<CChar>?, _ handleOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

    @_silgen_name("relay_stop")
    static func stop(_ handle: UnsafePointer<CChar>?) -> Int32

    @_silgen_name("relay_copy_frame")
    static func copyFrame(
        _ handle: UnsafePointer<CChar>?,
        _ rgba: UnsafeMutablePointer<UInt8>?,
        _ len: Int,
        _ width: UnsafeMutablePointer<UInt32>?,
        _ height: UnsafeMutablePointer<UInt32>?
    ) -> Int32

    @_silgen_name("relay_copy_log")
    static func copyLog(
        _ handle: UnsafePointer<CChar>?,
        _ bytes: UnsafeMutablePointer<UInt8>?,
        _ capacity: Int,
        _ lengthOut: UnsafeMutablePointer<Int>?
    ) -> Int32

    @_silgen_name("relay_string_free")
    static func stringFree(_ s: UnsafeMutablePointer<CChar>?)

    typealias relay_host_waypipe_entry = @convention(c) (Int32) -> Int32
    private typealias NixEditorFn = @convention(c) (
        UnsafePointer<CChar>?, UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias StartHostWaypipeFn = @convention(c) (
        UnsafePointer<CChar>?, relay_host_waypipe_entry?
    ) -> Int32

    private static func dlsymFn<T>(_ name: String) -> T? {
        let handle = dlopen(nil, RTLD_LAZY)
        defer { if let handle { dlclose(handle) } }
        guard let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static func nixEditor(
        _ name: UnsafePointer<CChar>?,
        _ source: UnsafePointer<CChar>?,
        _ out: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32 {
        guard let fn: NixEditorFn = dlsymFn("relay_nix_editor") else { return -2 }
        return fn(name, source, out)
    }

    static func startHostWaypipe(
        _ handle: UnsafePointer<CChar>?,
        _ entry: relay_host_waypipe_entry?
    ) -> Int32 {
        guard let fn: StartHostWaypipeFn = dlsymFn("relay_start_host_waypipe") else { return -2 }
        return fn(handle, entry)
    }

    static func withRelayString<T>(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32,
        _ use: (String?) -> T
    ) -> T {
        var raw: UnsafeMutablePointer<CChar>?
        let rc = body(&raw)
        defer { if let raw { stringFree(raw) } }
        guard rc == 0 || rc == -1 || rc == -2, let raw else { return use(nil) }
        return use(String(cString: raw))
    }

    static func takeString(_ ptr: UnsafeMutablePointer<CChar>?) -> String? {
        guard let ptr else { return nil }
        let s = String(cString: ptr)
        stringFree(ptr)
        return s
    }
}

#if os(iOS) || os(macOS)
@_silgen_name("wwn_waypipe_client_fd")
func wwn_waypipe_client_fd(_ fd: Int32) -> Int32
#endif

@_cdecl("wwn_wasmer_webkit_available")
public func wwn_wasmer_webkit_available() -> Int32 {
    #if WWN_WASMER_IOS27
    if #available(iOS 27.0, *) {
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? 1 : 0
    }
    return 0
    #else
    return 0
    #endif
}

@_cdecl("wwn_wasmer_webkit_start")
public func wwn_wasmer_webkit_start(
    _ moduleOrPackage: UnsafePointer<CChar>?,
    _ messageOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 {
    var message =
        "iOS 27 Mode A Wasm needs WasmerSDK (hidden WKWebView, JSPI). "
        + "This binary was built without WWN_WASMER_IOS27, so Relay stays on Pulley."
    _ = moduleOrPackage
    if wwn_wasmer_webkit_available() != 0 {
        message =
            "Wasmer WASIX WKWebView host is linked but the sandbox start "
            + "is not wired in this build."
    }
    if let messageOut {
        messageOut.pointee = strdup(message)
    }
    return -2
}
