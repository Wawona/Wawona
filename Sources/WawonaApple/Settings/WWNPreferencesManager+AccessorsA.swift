import Foundation
import WawonaModel
#if canImport(Darwin)
import Darwin
#endif

extension WWNPreferencesManager {
    // MARK: - Universal Clipboard

    @objc public func universalClipboardEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsUniversalClipboard)
    }

    @objc public func setUniversalClipboardEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsUniversalClipboard)
    }

    // MARK: - Window Decorations

    @objc public func forceServerSideDecorations() -> Bool {
        #if os(tvOS)
        return true
        #else
        return defs.bool(forKey: kWWNPrefsForceServerSideDecorations)
        #endif
    }

    @objc public func setForceServerSideDecorations(_ enabled: Bool) {
        if forceServerSideDecorations() == enabled { return }
        defs.set(enabled, forKey: kWWNPrefsForceServerSideDecorations)
        defs.set(enabled, forKey: "wawona.pref.forceSSD")
        NotificationCenter.default.post(
            name: Notification.Name(kWWNForceSSDChangedNotification),
            object: self
        )
    }

    // MARK: - Legacy display / color

    @objc public func autoRetinaScalingEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsAutoRetinaScaling)
    }

    @objc public func setAutoRetinaScalingEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsAutoRetinaScaling)
    }

    @objc public func colorSyncSupportEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsColorSyncSupport)
    }

    @objc public func setColorSyncSupportEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsColorSyncSupport)
    }

    // MARK: - Nested compositors

    @objc public func nestedCompositorsSupportEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsNestedCompositorsSupport)
    }

    @objc public func setNestedCompositorsSupportEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsNestedCompositorsSupport)
    }

    @objc public func nestedWestonBackend() -> String {
        var value = defs.string(forKey: kWWNPrefsNestedWestonBackend) ?? ""
        if value.isEmpty {
            #if os(macOS)
            return "iland-drm-gl"
            #else
            return "wayland-pixman"
            #endif
        }
        #if !os(macOS)
        if value == "iland-drm-gl" || value == "drm" {
            if compositorBackend() != "drm" {
                return "wayland-pixman"
            }
        }
        #endif
        #if targetEnvironment(simulator)
        if value == "iland-drm-gl" || value == "drm" {
            return "wayland-pixman"
        }
        #endif
        return value
    }

    @objc public func setNestedWestonBackend(_ backend: String) {
        #if os(macOS)
        let defaultBackend = "iland-drm-gl"
        #else
        let defaultBackend = "wayland-pixman"
        #endif
        let value = backend.isEmpty ? defaultBackend : backend
        defs.set(value, forKey: kWWNPrefsNestedWestonBackend)
    }

    @objc public func useMetal4ForNested() -> Bool {
        defs.bool(forKey: kWWNPrefsUseMetal4ForNested)
    }

    @objc public func setUseMetal4ForNested(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsUseMetal4ForNested)
    }

    // MARK: - Input (partial)

    @objc public func renderMacOSPointer() -> Bool {
        defs.bool(forKey: kWWNPrefsRenderMacOSPointer)
    }

    @objc public func setRenderMacOSPointer(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsRenderMacOSPointer)
    }

    @objc public func nestedCompositorCursor() -> String {
        let mode = defs.string(forKey: kWWNPrefsNestedCompositorCursor) ?? ""
        if mode == "host" || mode == "virtual" { return mode }
        return "virtual"
    }

    @objc public func setNestedCompositorCursor(_ mode: String) {
        let normalized = mode == "host" ? "host" : "virtual"
        defs.set(normalized, forKey: kWWNPrefsNestedCompositorCursor)
    }

    @objc public func swapCmdAsCtrl() -> Bool {
        defs.bool(forKey: kWWNPrefsSwapCmdAsCtrl)
    }

    @objc public func setSwapCmdAsCtrl(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsSwapCmdAsCtrl)
    }

    // MARK: - Client management

    @objc public func multipleClientsEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsMultipleClients)
    }

    @objc public func setMultipleClientsEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsMultipleClients)
    }

    @objc public func defaultStartType() -> String {
        let raw = defs.string(forKey: kWWNPrefsDefaultStartType) ?? ""
        // Canonical: prompt | newTab | newWindow. Legacy tab/window accepted.
        switch raw {
        case "newTab", "tab": return "newTab"
        case "newWindow", "window": return "newWindow"
        case "prompt": return "prompt"
        default: return "prompt"
        }
    }

    @objc public func machineSessionThumbnailsEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsMachineSessionThumbnailsEnabled)
    }

    @objc public func setMachineSessionThumbnailsEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsMachineSessionThumbnailsEnabled)
    }

    @objc public func waypipeRSSupportEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsWaypipeRSSupport)
    }

    @objc public func setWaypipeRSSupportEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsWaypipeRSSupport)
    }

    @objc public func enableTCPListener() -> Bool {
        defs.bool(forKey: kWWNPrefsEnableTCPListener)
    }

    @objc public func setEnableTCPListener(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsEnableTCPListener)
    }

    @objc public func tcpListenerPort() -> Int {
        defs.integer(forKey: kWWNPrefsTCPListenerPort)
    }

    @objc public func setTCPListenerPort(_ port: Int) {
        defs.set(port, forKey: kWWNPrefsTCPListenerPort)
    }

    @objc public func waylandSocketDir() -> String {
        #if os(iOS) || targetEnvironment(simulator)
        let preferred = Self.preferredSharedRuntimeDir()
        if !preferred.isEmpty {
            let stored = defs.string(forKey: kWWNPrefsWaylandSocketDir) ?? ""
            if stored != preferred {
                defs.set(preferred, forKey: kWWNPrefsWaylandSocketDir)
            }
            return preferred
        }
        #endif

        if let dir = defs.string(forKey: kWWNPrefsWaylandSocketDir) {
            return dir
        }
        if let envDir = getenv("XDG_RUNTIME_DIR") {
            return String(cString: envDir)
        }
        #if os(iOS) || targetEnvironment(simulator)
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("wayland-runtime")
        #else
        return "/tmp/wawona-\(getuid())"
        #endif
    }

    @objc public func setWaylandSocketDir(_ dir: String) {
        defs.set(dir, forKey: kWWNPrefsWaylandSocketDir)
    }

    @objc public func waylandDisplayNumber() -> Int {
        defs.integer(forKey: kWWNPrefsWaylandDisplayNumber)
    }

    @objc public func setWaylandDisplayNumber(_ number: Int) {
        defs.set(number, forKey: kWWNPrefsWaylandDisplayNumber)
    }

    @objc public func vulkanDriversEnabled() -> Bool {
        let driver = vulkanDriver()
        return !driver.isEmpty && driver != "none"
    }

    @objc public func setVulkanDriversEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsEnableVulkanDrivers)
        setVulkanDriver(enabled ? "moltenvk" : "none")
    }

    @objc public func dmabufEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsEnableDmabuf)
    }

    @objc public func setDmabufEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsEnableDmabuf)
    }
}
