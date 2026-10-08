import Foundation
#if os(macOS)
import AppKit
#endif

@objc(WWNRootfsProvider)
public final class WWNRootfsProvider: NSObject {

    private static func platformLabel() -> String {
        #if os(visionOS)
        return "visionOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Apple"
        #endif
    }

    #if os(macOS)
    private static func hostSnapshot() -> [String: String] {
        let home = NSHomeDirectory()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let xdgRuntime = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] ?? ""
        return [
            "mode": "host",
            "filesRoot": home,
            "home": home,
            "systemRoot": xdgRuntime.isEmpty ? "(host system. No bundled rootfs)" : xdgRuntime,
            "bundleTemplateVersion": "-",
            "appliedTemplateVersion": "-",
            "filesHint": "Finder → Go → Home, or open Terminal with your login shell.",
            "platformLabel": platformLabel(),
            "shellPath": shell,
        ]
    }
    #endif

    public static func capabilities() -> WWNRootfsCapabilities {
        var caps = WWNRootfsCapabilities(rawValue: 0)
        #if os(tvOS)
        caps.insert(WWNRootfsCapabilitySettings)
        caps.insert(WWNRootfsCapabilityResetDotfiles)
        caps.insert(WWNRootfsCapabilityReinstallSystemTree)
        #elseif os(iOS)
        caps.insert(WWNRootfsCapabilitySettings)
        caps.insert(WWNRootfsCapabilityResetDotfiles)
        caps.insert(WWNRootfsCapabilityReinstallSystemTree)
        caps.insert(WWNRootfsCapabilityBrowseUserFiles)
        caps.insert(WWNRootfsCapabilityImportFile)
        #elseif os(macOS)
        caps.insert(WWNRootfsCapabilitySettings)
        caps.insert(WWNRootfsCapabilityBrowseUserFiles)
        caps.insert(WWNRootfsCapabilityImportFile)
        #endif
        #if (os(iOS) || os(macOS)) && !os(tvOS)
        if WWNRootfsICloudSync.isSupported() {
            caps.insert(WWNRootfsCapabilityICloudSync)
        }
        #endif
        return caps
    }

    @objc public static func snapshot() -> [String: String] {
        #if os(iOS)
        WWNRootfsManager.prepareFilesAppAccess()
        var snap = WWNRootfsManager.rootfsStatusSnapshot()
        snap["mode"] = "bundled"
        snap["platformLabel"] = platformLabel()
        #if os(tvOS)
        snap["filesHint"] = "tvOS has no Files app; use Reset/Reinstall below."
        #elseif os(visionOS)
        if WWNRootfsICloudSync.isEnabled(), WWNRootfsICloudSync.isContainerAvailable() {
            snap["filesHint"] = "iCloud Drive → Wawona → home/ (also in Files on Vision Pro)."
        } else {
            snap["filesHint"] = "Files → On My Vision Pro → Wawona → Wawona → home/"
        }
        #else
        if WWNRootfsICloudSync.isEnabled(), WWNRootfsICloudSync.isContainerAvailable() {
            snap["filesHint"] = "iCloud Drive → Wawona → home/ (and On My iPhone → Wawona)."
        } else {
            snap["filesHint"] = "Files → On My iPhone/iPad → Wawona → Wawona → home/"
        }
        #endif
        return snap
        #elseif os(macOS)
        var snap = hostSnapshot()
        snap["iCloudSync"] = WWNRootfsICloudSync.isEnabled() ? "On" : "Off"
        snap["iCloudStatus"] = WWNRootfsICloudSync.statusSummary()
        if WWNRootfsICloudSync.isEnabled() {
            snap["filesHint"] = "iCloud Drive → Wawona → home/ syncs with iPhone, iPad, and Vision Pro."
        }
        return snap
        #else
        return [:]
        #endif
    }

    @objc public static func prepareUserAccess() {
        #if os(iOS)
        WWNRootfsManager.prepareFilesAppAccess()
        #elseif os(macOS)
        WWNRootfsICloudSync.prepareICloudLayout()
        #endif
    }

    @objc(refreshShellDotfiles:)
    public static func refreshShellDotfiles(_ error: NSErrorPointer) -> Bool {
        #if os(iOS)
        return WWNRootfsManager.refreshShellDotfiles(error)
        #else
        error?.pointee = NSError(
            domain: "WWNRootfs",
            code: 100,
            userInfo: [NSLocalizedDescriptionKey: "Reset dotfiles is only available with a bundled shell rootfs."]
        )
        return false
        #endif
    }

    @objc(reinstallSystemTree:)
    public static func reinstallSystemTree(_ error: NSErrorPointer) -> Bool {
        #if os(iOS)
        return WWNRootfsManager.reinstallSystemTree(error)
        #else
        error?.pointee = NSError(
            domain: "WWNRootfs",
            code: 101,
            userInfo: [NSLocalizedDescriptionKey: "Reinstall system tree is only available with a bundled shell rootfs."]
        )
        return false
        #endif
    }

    @objc public static func applyShellEnvironment() {
        #if os(iOS)
        WWNRootfsManager.applyShellEnvironment()
        #endif
    }

    @objc public static func openUserFilesLocation() -> Bool {
        let snap = snapshot()
        guard let path = snap["filesRoot"], !path.isEmpty else { return false }
        #if os(macOS)
        return NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
        #else
        return false
        #endif
    }

    // iCloud Drive shell HOME: macOS / iOS / iPadOS / visionOS. Blocked on
    // tvOS and watchOS (platform-targets matrix).
    #if (os(iOS) || os(macOS) || os(visionOS)) && !os(tvOS) && !os(watchOS)
    @objc public static func isICloudSyncSupported() -> Bool {
        WWNRootfsICloudSync.isSupported()
    }

    @objc public static func isICloudSyncEnabled() -> Bool {
        WWNRootfsICloudSync.isEnabled()
    }

    @objc(setICloudSyncEnabled:error:)
    public static func setICloudSyncEnabled(_ enabled: Bool, error: NSErrorPointer) -> Bool {
        WWNRootfsICloudSync.setEnabled(enabled, error: error)
    }

    /// Throwing convenience for SwiftUI settings bindings.
    @discardableResult
    public static func setICloudSyncEnabled(_ enabled: Bool) throws -> Bool {
        var err: NSError?
        let ok = setICloudSyncEnabled(enabled, error: &err)
        if let err { throw err }
        return ok
    }
    #endif
}
