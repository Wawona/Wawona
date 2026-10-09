import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(WawonaModel)
import WawonaModel
#endif

/// Aqua vs Classic / own-display backend resolution.
/// Policy: Rust `launch_resolve`. Swift applies the string to env/argv.

#if os(macOS)
private func appleWindowServerIsRunning() -> Bool {
    // Classic is WindowServer gone. Aqua Machines Start has NSScreen.
    // A censored proc list must not be treated as Classic.
    if !NSScreen.screens.isEmpty {
        return true
    }
    // Fallback: positive name match only. Sparse listings stay Aqua.
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "WindowServer"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return true
    }
}
#endif

/// YES when Classic Desktop Replacement owns the panel (no host Wayland).
@_cdecl("WWNHostSessionUsesOwnDisplayDRM")
public func WWNHostSessionUsesOwnDisplayDRM() -> Bool {
    #if os(macOS)
    return !appleWindowServerIsRunning()
    #else
    return false
    #endif
}

private var cliCompositorBackendOverride: String?

@_cdecl("WWNSetCompositorBackendCLIOverride")
public func WWNSetCompositorBackendCLIOverride(_ backend: NSString?) {
    let value = backend as String?
    cliCompositorBackendOverride = (value?.isEmpty == false) ? value : nil
}

@_cdecl("WWNCompositorBackendCLIOverride")
public func WWNCompositorBackendCLIOverride() -> NSString? {
    cliCompositorBackendOverride as NSString?
}

/// Resolves `auto`|`wayland`|`drm`. Own-display always returns `drm`.
@_cdecl("WWNResolveCompositorBackend")
public func WWNResolveCompositorBackend(_ overrideValue: NSString?) -> NSString {
    let classic = WWNHostSessionUsesOwnDisplayDRM()
    var pref = UserDefaults.standard.string(forKey: "CompositorBackend") ?? "auto"
    var cli = overrideValue as String?
    if cli?.isEmpty != false {
        cli = cliCompositorBackendOverride
    }
    #if canImport(WawonaModel)
    if let json = WawonaDomainBridge.resolveBackend(
        pref: pref,
        classicOwnDisplay: classic,
        cliOverride: cli
    ),
       let data = json.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let backend = obj["backend"] as? String
    {
        return backend as NSString
    }
    #endif
    if classic {
        return "drm" as NSString
    }
    var choice = cli
    if choice?.isEmpty != false {
        choice = pref
    }
    switch choice {
    case "drm":
        return "drm" as NSString
    case "wayland":
        return "wayland" as NSString
    default:
        return "wayland" as NSString
    }
}
