import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)

/// Mirrors `WWNGraphicsDriverSelection` in `WWNSettings.h` for @_cdecl export.
public struct WWNGraphicsDriverSelection {
    public var vulkanDriver: UnsafePointer<CChar>?
    public var openGLDriver: UnsafePointer<CChar>?
    public var vulkanEnabled: Bool
    public var openGLEnabled: Bool
}

private final class WWNSettingsCStringStorage: @unchecked Sendable {
    static let shared = WWNSettingsCStringStorage()
    var vulkan = [CChar](repeating: 0, count: 32)
    var openGL = [CChar](repeating: 0, count: 32)
    var compositorBackend = [CChar](repeating: 0, count: 32)
}

private func wwnStoreCString(_ string: String, into buffer: inout [CChar]) -> UnsafePointer<CChar> {
    buffer.withUnsafeMutableBufferPointer { ptr in
        string.withCString { src in
            strncpy(ptr.baseAddress, src, ptr.count - 1)
            ptr[ptr.count - 1] = 0
        }
        return UnsafePointer(ptr.baseAddress!)
    }
}

private func wwnDriverIs(_ value: String?, _ expected: String) -> Bool {
    value == expected
}

private func wwnPrefs() -> WWNPreferencesManager {
    WWNPreferencesManager.sharedManager()
}

@_cdecl("WWNSettings_GetUniversalClipboardEnabled")
public func WWNSettings_GetUniversalClipboardEnabled() -> Bool {
    wwnPrefs().universalClipboardEnabled()
}

@_cdecl("WWNSettings_GetForceServerSideDecorations")
public func WWNSettings_GetForceServerSideDecorations() -> Bool {
    wwnPrefs().forceServerSideDecorations()
}

@_cdecl("WWNSettings_GetAutoRetinaScalingEnabled")
public func WWNSettings_GetAutoRetinaScalingEnabled() -> Bool {
    wwnPrefs().autoScale()
}

@_cdecl("WWNSettings_GetRespectSafeArea")
public func WWNSettings_GetRespectSafeArea() -> Bool {
    wwnPrefs().respectSafeArea()
}

@_cdecl("WWNSettings_GetColorSyncSupportEnabled")
public func WWNSettings_GetColorSyncSupportEnabled() -> Bool {
    wwnPrefs().colorOperations()
}

@_cdecl("WWNSettings_GetNestedCompositorsSupportEnabled")
public func WWNSettings_GetNestedCompositorsSupportEnabled() -> Bool {
    wwnPrefs().nestedCompositorsSupportEnabled()
}

@_cdecl("WWNSettings_GetUseMetal4ForNested")
public func WWNSettings_GetUseMetal4ForNested() -> Bool {
    wwnPrefs().useMetal4ForNested()
}

@_cdecl("WWNSettings_GetRenderMacOSPointer")
public func WWNSettings_GetRenderMacOSPointer() -> Bool {
    wwnPrefs().renderMacOSPointer()
}

@_cdecl("WWNSettings_GetSwapCmdAsCtrl")
public func WWNSettings_GetSwapCmdAsCtrl() -> Bool {
    wwnPrefs().swapCmdWithAlt()
}

@_cdecl("WWNSettings_GetMultipleClientsEnabled")
public func WWNSettings_GetMultipleClientsEnabled() -> Bool {
    wwnPrefs().multipleClientsEnabled()
}

@_cdecl("WWNSettings_GetWaypipeRSSupportEnabled")
public func WWNSettings_GetWaypipeRSSupportEnabled() -> Bool {
    wwnPrefs().waypipeRSSupportEnabled()
}

@_cdecl("WWNSettings_GetEnableTCPListener")
public func WWNSettings_GetEnableTCPListener() -> Bool {
    wwnPrefs().enableTCPListener()
}

@_cdecl("WWNSettings_GetTCPListenerPort")
public func WWNSettings_GetTCPListenerPort() -> Int32 {
    Int32(wwnPrefs().tcpListenerPort())
}

@_cdecl("WWNSettings_GetRenderingBackend")
public func WWNSettings_GetRenderingBackend() -> Int32 {
    0
}

@_cdecl("WWNSettings_GetDmabufEnabled")
public func WWNSettings_GetDmabufEnabled() -> Bool {
    wwnPrefs().dmabufEnabled()
}

@_cdecl("WWNSettings_GetVulkanDriver")
public func WWNSettings_GetVulkanDriver() -> UnsafePointer<CChar>? {
    let s = wwnPrefs().vulkanDriver()
    let trimmed = s.isEmpty ? "moltenvk" : s
    return wwnStoreCString(trimmed, into: &WWNSettingsCStringStorage.shared.vulkan)
}

@_cdecl("WWNSettings_GetOpenGLDriver")
public func WWNSettings_GetOpenGLDriver() -> UnsafePointer<CChar>? {
    let s = wwnPrefs().openglDriver()
    let trimmed = s.isEmpty ? "angle" : s
    return wwnStoreCString(trimmed, into: &WWNSettingsCStringStorage.shared.openGL)
}

@_cdecl("WWNSettings_GetCompositorBackend")
public func WWNSettings_GetCompositorBackend() -> UnsafePointer<CChar>? {
    let s = wwnPrefs().compositorBackend()
    let trimmed = s.isEmpty ? "auto" : s
    return wwnStoreCString(trimmed, into: &WWNSettingsCStringStorage.shared.compositorBackend)
}

@_cdecl("WWNSettings_ResolveCompositorBackend")
public func WWNSettings_ResolveCompositorBackend() -> UnsafePointer<CChar>? {
    guard let backendPtr = WWNSettings_GetCompositorBackend() else {
        return wwnStoreCString("wayland", into: &WWNSettingsCStringStorage.shared.compositorBackend)
    }
    let choice = String(cString: backendPtr)
    if wwnDriverIs(choice, "drm") {
        guard let glPtr = WWNSettings_GetOpenGLDriver() else {
            return wwnStoreCString("wayland", into: &WWNSettingsCStringStorage.shared.compositorBackend)
        }
        let gl = String(cString: glPtr)
        if wwnDriverIs(gl, "none") {
            return wwnStoreCString("wayland", into: &WWNSettingsCStringStorage.shared.compositorBackend)
        }
        return wwnStoreCString("drm", into: &WWNSettingsCStringStorage.shared.compositorBackend)
    }
    if wwnDriverIs(choice, "wayland") {
        return wwnStoreCString("wayland", into: &WWNSettingsCStringStorage.shared.compositorBackend)
    }
    return wwnStoreCString("wayland", into: &WWNSettingsCStringStorage.shared.compositorBackend)
}

@_cdecl("WWNSettings_GetVulkanDriversEnabled")
public func WWNSettings_GetVulkanDriversEnabled() -> Bool {
    WWNSettings_ResolveGraphicsDriverSelection().vulkanEnabled
}

@_cdecl("WWNSettings_GetEGLDriversEnabled")
public func WWNSettings_GetEGLDriversEnabled() -> Bool {
    WWNSettings_ResolveGraphicsDriverSelection().openGLEnabled
}

public func WWNSettings_ResolveGraphicsDriverSelection() -> WWNGraphicsDriverSelection {
    var vulkan = "none"
    if let p = WWNSettings_GetVulkanDriver() { vulkan = String(cString: p) }
    var openGL = "none"
    if let p = WWNSettings_GetOpenGLDriver() { openGL = String(cString: p) }

    #if os(watchOS)
    vulkan = "none"
    openGL = "none"
    #elseif os(tvOS)
    #if WWN_TVOS_GPU_BUNDLED
    if !wwnDriverIs(vulkan, "none"), !wwnDriverIs(vulkan, "moltenvk") { vulkan = "moltenvk" }
    if !wwnDriverIs(openGL, "none"), !wwnDriverIs(openGL, "angle") { openGL = "angle" }
    #else
    vulkan = "none"
    openGL = "none"
    #endif
    #elseif os(macOS)
    if !wwnDriverIs(vulkan, "none"), !wwnDriverIs(vulkan, "moltenvk"),
       !wwnDriverIs(vulkan, "kosmickrisp"), !wwnDriverIs(vulkan, "swiftshader") {
        vulkan = "moltenvk"
    }
    if !wwnDriverIs(openGL, "none"), !wwnDriverIs(openGL, "angle") { openGL = "angle" }
    #elseif targetEnvironment(simulator)
    if wwnDriverIs(vulkan, "moltenvk")
        || (!wwnDriverIs(vulkan, "none") && !wwnDriverIs(vulkan, "swiftshader")) {
        vulkan = "swiftshader"
    }
    if !wwnDriverIs(openGL, "none"), !wwnDriverIs(openGL, "angle") { openGL = "angle" }
    #else
    if !wwnDriverIs(vulkan, "none"), !wwnDriverIs(vulkan, "moltenvk") { vulkan = "moltenvk" }
    if !wwnDriverIs(openGL, "none"), !wwnDriverIs(openGL, "angle") { openGL = "angle" }
    #endif

    let vkPtr = wwnStoreCString(vulkan, into: &WWNSettingsCStringStorage.shared.vulkan)
    let glPtr = wwnStoreCString(openGL, into: &WWNSettingsCStringStorage.shared.openGL)
    return WWNGraphicsDriverSelection(
        vulkanDriver: vkPtr,
        openGLDriver: glPtr,
        vulkanEnabled: !wwnDriverIs(vulkan, "none"),
        openGLEnabled: !wwnDriverIs(openGL, "none")
    )
}

private func wwnVulkanDylibName(_ driver: String) -> String? {
    switch driver {
    case "kosmickrisp": return "libvulkan_kosmickrisp.dylib"
    case "moltenvk": return "libMoltenVK.dylib"
    case "swiftshader": return "libvk_swiftshader.dylib"
    default: return nil
    }
}

private func wwnVulkanDylibPath(driver: String, bundle: Bundle) -> String? {
    guard let name = wwnVulkanDylibName(driver) else { return nil }
    guard let frameworks = bundle.privateFrameworksPath else { return nil }
    let candidate = frameworks.appending("/\(name)")
    return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
}

@_cdecl("WWNSettings_ApplyGraphicsDriverSelection")
public func WWNSettings_ApplyGraphicsDriverSelection() {
    let selection = WWNSettings_ResolveGraphicsDriverSelection()
    let vkDriver = selection.vulkanDriver.map { String(cString: $0) } ?? "none"
    let bundle = Bundle.main

    let icdName: String? = switch vkDriver {
    case "kosmickrisp": "kosmickrisp_icd"
    case "moltenvk": "MoltenVK_icd"
    case "swiftshader": "vk_swiftshader_icd"
    default: nil
    }

    var icd = icdName.flatMap {
        bundle.path(forResource: $0, ofType: "json", inDirectory: "vulkan/icd.d")
    }
    if icd == nil, vkDriver == "kosmickrisp" {
        icd = bundle.path(forResource: "MoltenVK_icd", ofType: "json", inDirectory: "vulkan/icd.d")
    }

    if let icd {
        setenv("VK_DRIVER_FILES", icd, 1)
        setenv("VK_ICD_FILENAMES", icd, 1)
    } else {
        unsetenv("VK_DRIVER_FILES")
        unsetenv("VK_ICD_FILENAMES")
    }

    let icdPath = wwnVulkanDylibPath(driver: vkDriver, bundle: bundle)
    if let icdPath {
        setenv("WWN_VULKAN_LIBRARY", icdPath, 1)
    } else {
        unsetenv("WWN_VULKAN_LIBRARY")
    }

    let fallbackOrder = ["moltenvk", "swiftshader"]
    var fallbacks: [String] = []
    for name in fallbackOrder where name != vkDriver {
        if let path = wwnVulkanDylibPath(driver: name, bundle: bundle),
           path != icdPath {
            fallbacks.append(path)
        }
    }
    if fallbacks.isEmpty {
        unsetenv("WWN_VULKAN_LIBRARY_FALLBACKS")
    } else {
        setenv("WWN_VULKAN_LIBRARY_FALLBACKS", fallbacks.joined(separator: ":"), 1)
    }

    let glDriver = selection.openGLDriver.map { String(cString: $0) } ?? "none"
    setenv("WWN_OPENGL_DRIVER", glDriver, 1)
    if glDriver == "angle" {
        setenv("ANGLE_DEFAULT_PLATFORM", "metal", 1)
        unsetenv("WWN_DISABLE_EGL")
    } else if glDriver == "none" {
        setenv("WWN_DISABLE_EGL", "1", 1)
        unsetenv("ANGLE_DEFAULT_PLATFORM")
    } else {
        unsetenv("WWN_DISABLE_EGL")
        unsetenv("ANGLE_DEFAULT_PLATFORM")
    }
}

#endif
