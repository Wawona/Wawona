import Foundation
import WawonaModel

extension WWNPreferencesManager {
    @objc public func vulkanDriver() -> String {
        #if os(watchOS)
        return "none"
        #elseif os(tvOS)
        guard PlatformCapabilities.allowsGpuStack else { return "none" }
        let driver = defs.string(forKey: kWWNPrefsVulkanDriver) ?? ""
        let allowed: Set<String> = ["none", "moltenvk", "swiftshader"]
        return allowed.contains(driver) ? driver : Self.defaultVulkanDriverForHardware()
        #else
        let driver = defs.string(forKey: kWWNPrefsVulkanDriver) ?? ""
        #if os(macOS)
        let allowed: Set<String> = ["none", "moltenvk", "kosmickrisp", "swiftshader"]
        #else
        let allowed: Set<String> = ["none", "moltenvk"]
        #endif
        return allowed.contains(driver) ? driver : Self.defaultVulkanDriverForHardware()
        #endif
    }

    @objc public func setVulkanDriver(_ driver: String) {
        defs.set(driver, forKey: kWWNPrefsVulkanDriver)
    }

    @objc public func openglDriver() -> String {
        #if os(watchOS)
        return "none"
        #elseif os(tvOS)
        guard PlatformCapabilities.allowsGlesStack else { return "none" }
        let driver = defs.string(forKey: kWWNPrefsOpenGLDriver) ?? ""
        return ["none", "angle"].contains(driver) ? driver : Self.defaultOpenGLDriverForHardware()
        #else
        let driver = defs.string(forKey: kWWNPrefsOpenGLDriver) ?? ""
        return ["none", "angle"].contains(driver) ? driver : Self.defaultOpenGLDriverForHardware()
        #endif
    }

    @objc public func setOpenGLDriver(_ driver: String) {
        defs.set(driver, forKey: kWWNPrefsOpenGLDriver)
    }

    @objc public func compositorBackend() -> String {
        #if os(watchOS)
        return "wayland"
        #else
        let backend = defs.string(forKey: kWWNPrefsCompositorBackend) ?? ""
        return ["auto", "wayland", "drm"].contains(backend) ? backend : "auto"
        #endif
    }

    @objc public func setCompositorBackend(_ backend: String) {
        defs.set(backend, forKey: kWWNPrefsCompositorBackend)
    }

    @objc public func autoScale() -> Bool {
        if defs.object(forKey: kWWNPrefsAutoScale) != nil {
            return defs.bool(forKey: kWWNPrefsAutoScale)
        }
        if defs.object(forKey: kWWNPrefsAutoRetinaScaling) != nil {
            let value = defs.bool(forKey: kWWNPrefsAutoRetinaScaling)
            defs.set(value, forKey: kWWNPrefsAutoScale)
            return value
        }
        return true
    }

    @objc public func setAutoScale(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsAutoScale)
    }

    @objc public func externalDisplayTouchpad() -> Bool {
        if defs.object(forKey: kWWNPrefsExternalDisplayTouchpad) != nil {
            return defs.bool(forKey: kWWNPrefsExternalDisplayTouchpad)
        }
        return true
    }

    @objc public func setExternalDisplayTouchpad(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsExternalDisplayTouchpad)
    }

    @objc public func respectSafeArea() -> Bool {
        defs.bool(forKey: kWWNPrefsRespectSafeArea)
    }

    @objc public func setRespectSafeArea(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsRespectSafeArea)
    }

    @objc public func resizeDisplayForVirtualKeyboard() -> Bool {
        defs.bool(forKey: kWWNPrefsResizeDisplayForVirtualKeyboard)
    }

    @objc public func setResizeDisplayForVirtualKeyboard(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsResizeDisplayForVirtualKeyboard)
    }

    @objc public func hasSeenWelcome() -> Bool {
        defs.bool(forKey: kWWNPrefsHasSeenWelcome)
    }

    @objc public func setHasSeenWelcome(_ seen: Bool) {
        defs.set(seen, forKey: kWWNPrefsHasSeenWelcome)
    }

    @objc public func colorOperations() -> Bool {
        if defs.object(forKey: kWWNPrefsColorOperations) != nil {
            return defs.bool(forKey: kWWNPrefsColorOperations)
        }
        if defs.object(forKey: kWWNPrefsColorSyncSupport) != nil {
            let value = defs.bool(forKey: kWWNPrefsColorSyncSupport)
            defs.set(value, forKey: kWWNPrefsColorOperations)
            return value
        }
        return true
    }

    @objc public func setColorOperations(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsColorOperations)
    }

    @objc public func swapCmdWithAlt() -> Bool {
        if defs.object(forKey: kWWNPrefsSwapCmdWithAlt) != nil {
            return defs.bool(forKey: kWWNPrefsSwapCmdWithAlt)
        }
        if defs.object(forKey: kWWNPrefsSwapCmdAsCtrl) != nil {
            let value = defs.bool(forKey: kWWNPrefsSwapCmdAsCtrl)
            defs.set(value, forKey: kWWNPrefsSwapCmdWithAlt)
            return value
        }
        return true
    }

    @objc public func setSwapCmdWithAlt(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsSwapCmdWithAlt)
    }

    @objc public func touchInputType() -> String {
        defs.string(forKey: kWWNPrefsTouchInputType) ?? "Multi-Touch"
    }

    @objc public func setTouchInputType(_ type: String?) {
        if let type {
            defs.set(type, forKey: kWWNPrefsTouchInputType)
        } else {
            defs.removeObject(forKey: kWWNPrefsTouchInputType)
        }
    }

    @objc public func touchPointerEmulationEnabled() -> Bool {
        defs.bool(forKey: kWWNPrefsTouchPointerEmulation)
    }

    @objc public func setTouchPointerEmulationEnabled(_ enabled: Bool) {
        defs.set(enabled, forKey: kWWNPrefsTouchPointerEmulation)
    }
}
