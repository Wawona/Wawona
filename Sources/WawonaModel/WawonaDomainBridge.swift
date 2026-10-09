import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Shared dlsym bridge for `src/domain` C trampolines.
///
/// Generated UniFFI Swift (`namespace wawona`, Nix `$out/uniffi/swift`) is
/// the preferred import when staged into `.nix-deps/uniffi` / product
/// `macos-dependencies/uniffi` and linked. Until every Apple target compiles
/// that module, callers use these trampolines. Do not hand-edit UniFFI output.
public enum WawonaDomainBridge {
    public static var rustLinked: Bool {
        symbol("wawona_domain_string_free") != nil
    }

    /// True when Nix-staged UniFFI Swift is on the include path this build.
    /// Compile with `SWIFT_INCLUDE_PATHS` containing `.nix-deps/uniffi`.
    public static var uniffiStaged: Bool {
        #if canImport(wawona)
        return true
        #else
        return false
        #endif
    }

    public static func callNoArg(_ name: String) -> String? {
        typealias Fn = @convention(c) () -> UnsafeMutablePointer<CChar>?
        guard let sym = symbol(name), let freeSym = symbol("wawona_domain_string_free") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
        guard let raw = fn() else { return nil }
        defer { freeFn(raw) }
        return String(cString: raw)
    }

    public static func callString1(_ name: String, _ arg: String) -> String? {
        typealias Fn = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
        guard let sym = symbol(name), let freeSym = symbol("wawona_domain_string_free") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
        return arg.withCString { cArg in
            guard let raw = fn(cArg) else { return nil }
            defer { freeFn(raw) }
            return String(cString: raw)
        }
    }

    public static func callString2(_ name: String, _ a: String, _ b: String) -> String? {
        typealias Fn = @convention(c) (
            UnsafePointer<CChar>?, UnsafePointer<CChar>?
        ) -> UnsafeMutablePointer<CChar>?
        guard let sym = symbol(name), let freeSym = symbol("wawona_domain_string_free") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
        return a.withCString { cA in
            b.withCString { cB in
                guard let raw = fn(cA, cB) else { return nil }
                defer { freeFn(raw) }
                return String(cString: raw)
            }
        }
    }

    public static func clientCatalogJSON() -> String? {
        callNoArg("wawona_client_catalog_json")
    }

    public static func prefsDefaultsJSON() -> String? {
        callNoArg("wawona_prefs_defaults_json")
    }

    public static func prefsKeysCSV() -> String? {
        callNoArg("wawona_prefs_keys_csv")
    }

    public static func resolveBackend(
        pref: String,
        classicOwnDisplay: Bool,
        cliOverride: String?
    ) -> String? {
        typealias Fn = @convention(c) (
            UnsafePointer<CChar>?, Int32, UnsafePointer<CChar>?
        ) -> UnsafeMutablePointer<CChar>?
        guard let sym = symbol("wawona_launch_resolve_backend"),
              let freeSym = symbol("wawona_domain_string_free")
        else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
        return pref.withCString { cPref in
            let invoke: (UnsafePointer<CChar>?) -> String? = { cCli in
                guard let raw = fn(cPref, classicOwnDisplay ? 1 : 0, cCli) else { return nil }
                defer { freeFn(raw) }
                return String(cString: raw)
            }
            if let cliOverride {
                return cliOverride.withCString { invoke($0) }
            }
            return invoke(nil)
        }
    }

    public static func nestedCursorPolicy(
        isNestedCompositor: Bool,
        showVirtualCursor: Bool
    ) -> (hideHost: Bool, showVirtual: Bool)? {
        typealias Fn = @convention(c) (Int32, Int32) -> UnsafeMutablePointer<CChar>?
        guard let sym = symbol("wawona_launch_nested_cursor_policy"),
              let freeSym = symbol("wawona_domain_string_free")
        else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
        guard let raw = fn(isNestedCompositor ? 1 : 0, showVirtualCursor ? 1 : 0) else {
            return nil
        }
        defer { freeFn(raw) }
        let json = String(cString: raw)
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return (
            hideHost: (obj["hide_host_cursor"] as? Bool) ?? false,
            showVirtual: (obj["show_virtual_pointer"] as? Bool) ?? false
        )
    }

    private typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        name.withCString { dlsym(UnsafeMutableRawPointer(bitPattern: -2), $0) }
    }
}
