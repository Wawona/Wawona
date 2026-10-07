import Foundation
import WawonaModel
#if canImport(Darwin)
import Darwin
#endif

@objc(WWNPreferencesManager)
public final class WWNPreferencesManager: NSObject {
    private static let lock = NSLock()
    private static var _shared: WWNPreferencesManager?

    @objc(sharedManager)
    public class func sharedManager() -> WWNPreferencesManager {
        lock.lock()
        defer { lock.unlock() }
        if let existing = _shared { return existing }
        let instance = WWNPreferencesManager()
        _shared = instance
        return instance
    }

    private override init() {
        super.init()
        setDefaultsIfNeeded()
        syncFromCanonicalWawonaPreferences()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWawonaPreferencesDidSave(_:)),
            name: WWNPreferencesInternal.wawonaPreferencesDidSave,
            object: nil
        )
    }

    @objc private func handleWawonaPreferencesDidSave(_ notification: Notification) {
        syncFromCanonicalWawonaPreferences()
    }

    var defs: UserDefaults { WWNSharedUserDefaults() }

    // MARK: - Runtime paths

    @objc(preferredSharedRuntimeDir)
    public class func preferredSharedRuntimeDir() -> String {
        #if os(iOS) || targetEnvironment(simulator)
        let fm = FileManager.default
        #if targetEnvironment(simulator)
        let candidate = "/tmp/wawona_sim_\(getuid())"
        #else
        let candidate = "/tmp/wawona_dev_\(getuid())"
        #endif
        do {
            try fm.createDirectory(atPath: candidate, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return candidate
        } catch {
            // fall through
        }
        #if !targetEnvironment(simulator)
        var sandbox = NSTemporaryDirectory()
        if sandbox.hasSuffix("/") {
            sandbox.removeLast()
        }
        if !sandbox.isEmpty {
            do {
                try fm.createDirectory(atPath: sandbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                return sandbox
            } catch {
                // fall through
            }
        }
        #endif
        return candidate
        #else
        return "/tmp/wawona-\(getuid())"
        #endif
    }

    @objc(preferredNestedSocketName)
    public class func preferredNestedSocketName() -> String {
        #if os(iOS) && !targetEnvironment(simulator)
        return "nested"
        #else
        return "wawona-nested"
        #endif
    }

    // MARK: - Hardware driver defaults

    @objc(defaultVulkanDriverForHardware)
    public class func defaultVulkanDriverForHardware() -> String {
        #if os(watchOS)
        return "none"
        #elseif os(tvOS)
        return PlatformCapabilities.allowsGpuStack ? "moltenvk" : "none"
        #elseif os(macOS)
        var isARM64: Int32 = 0
        var size = MemoryLayout.size(ofValue: isARM64)
        if sysctlbyname("hw.optional.arm64", &isARM64, &size, nil, 0) != 0 {
            isARM64 = 0
        }
        if isARM64 != 0 {
            if #available(macOS 26.0, *) {
                return "kosmickrisp"
            }
        }
        return "moltenvk"
        #else
        return "moltenvk"
        #endif
    }

    @objc(defaultOpenGLDriverForHardware)
    public class func defaultOpenGLDriverForHardware() -> String {
        #if os(watchOS)
        return "none"
        #elseif os(tvOS)
        return PlatformCapabilities.allowsGlesStack ? "angle" : "none"
        #else
        return "angle"
        #endif
    }

    @objc public func eglDriversEnabled() -> Bool { false }

    @objc public func setEglDriversEnabled(_ enabled: Bool) {
        _ = enabled
    }
}
