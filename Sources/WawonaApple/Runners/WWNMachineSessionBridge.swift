import Foundation
#if canImport(Darwin)
import Darwin
#endif

@objc(WWNMachineSessionBridge)
public final class WWNMachineSessionBridge: NSObject {
    private override init() {}

    @objc(profileRequiresWaypipeTransport:)
    public static func profileRequiresWaypipeTransport(_ profile: WWNMachineProfile) -> Bool {
        if profile.type == kWWNMachineTypeSSHWaypipe || profile.type == kWWNMachineTypeSSHTerminal {
            return true
        }
        guard WWNNativeShellConfiguration.isNativeShellFamily(profile.type)
          || profile.type == kWWNMachineTypeNative else { return false }
        let kind = WWNNativeShellConfiguration.kind(for: profile)
        let useSSH = WWNNativeShellConfiguration.usesSSH(for: profile)
        if kind == kWWNNativeShellKindWaypipe { return true }
        if kind == kWWNNativeShellKindTerminal && useSSH { return true }
        return false
    }

    @objc(profileUsesVirtualMachineBackend:)
    public static func profileUsesVirtualMachineBackend(_ profile: WWNMachineProfile) -> Bool {
        profile.type == kWWNMachineTypeVirtualMachine
    }

    @objc(profileUsesContainerBackend:)
    public static func profileUsesContainerBackend(_ profile: WWNMachineProfile) -> Bool {
        profile.type == kWWNMachineTypeContainer
    }

    @objc(profileUsesWasmRuntime:)
    public static func profileUsesWasmRuntime(_ profile: WWNMachineProfile) -> Bool {
        if profile.type == kWWNMachineTypeWasm { return true }
        guard profile.type == kWWNMachineTypeNative
          || WWNNativeShellConfiguration.isNativeShellFamily(profile.type) else { return false }
        return WWNNativeShellConfiguration.kind(for: profile) == kWWNNativeShellKindWasm
    }

    @objc(profileUsesNativeCompositorClient:)
    public static func profileUsesNativeCompositorClient(_ profile: WWNMachineProfile) -> Bool {
        if profileUsesWasmRuntime(profile) { return true }
        if profile.type == kWWNMachineTypeNative
          || WWNNativeShellConfiguration.isNativeShellFamily(profile.type) {
            return !profileRequiresWaypipeTransport(profile)
        }
        return false
    }

    @objc(nativeClientIdForProfile:)
    public static func nativeClientId(forProfile profile: WWNMachineProfile) -> String? {
        if profileUsesWasmRuntime(profile) { return "wawona-wasm" }
        guard profileUsesNativeCompositorClient(profile) else { return nil }

        let kind = WWNNativeShellConfiguration.kind(for: profile)
        if kind == kWWNNativeShellKindTerminal {
            return "wawona-shell"
        }

        if let runtime = profile.runtimeOverrides as? [String: Any],
           let bundled = runtime["bundledAppID"] as? String, !bundled.isEmpty {
            return bundled
        }
        if let overrides = profile.settingsOverrides as? [String: Any],
           let native = overrides["NativeClientId"] as? String, !native.isEmpty {
            return native
        }
        let legacy: [String: String] = [
            "WestonSimpleSHMEnabled": "weston-simple-shm",
            "WestonEnabled": "weston",
            "WestonTerminalEnabled": "weston-terminal",
            "FootEnabled": "foot",
        ]
        if let overrides = profile.settingsOverrides as? [String: Any] {
            for (key, client) in legacy {
                if (overrides[key] as? NSNumber)?.boolValue == true { return client }
            }
        }
        return kind == kWWNNativeShellKindWayland ? "weston-simple-shm" : nil
    }

    @objc(stopAllActiveTransports)
    public static func stopAllActiveTransports() {
        let runner = WWNWaypipeRunner.shared
        #if os(iOS)
        runner.stopActiveIOSBundledClient()
        #endif
        runner.stopAllNativeClients()
        if runner.isRunning { runner.stopWaypipe() }
        WWNRelay.sharedRelay.stopAll()
    }

    @objc(connectProfile:error:)
    public static func connect(_ profile: WWNMachineProfile) throws {
        #if os(iOS)
        if !profileUsesNativeCompositorClient(profile) {
            stopAllActiveTransports()
        }
        #endif

        WWNPreferencesManager.sharedManager().syncFromCanonicalWawonaPreferences()
        // Start must always have a live host compositor before launching clients.
        let bridge = WWNCompositorBridge.sharedBridge
        if !bridge.isRunning() {
            guard bridge.start(withSocketName: "wayland-0") else {
                throw NSError(
                    domain: "WWNMachineSessionBridge", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Host compositor failed to start."]
                )
            }
        }
        setenv("WAYLAND_DISPLAY", bridge.socketName(), 1)

        WWNMachineProfileStore.applyMachineToRuntimePrefs(profile)
        WWNMachineProfileStore.setActiveMachineId(profile.machineId)
        WWNSettings_ApplyGraphicsDriverSelection()

        var machineEnv: NSDictionary?
        if let runtime = profile.runtimeOverrides as? [String: Any],
           let env = runtime["environment"] as? NSDictionary {
            machineEnv = env
        }
        WWNEnvironmentOverrides.apply(machineEnv)

        if profileUsesNativeCompositorClient(profile) {
            try connectNative(profile: profile)
            return
        }
        if profileRequiresWaypipeTransport(profile) {
            WWNWaypipeRunner.shared.launchWaypipe(WWNPreferencesManager.sharedManager())
            return
        }
        if profileUsesVirtualMachineBackend(profile) {
            try connectRelayBacked(profile: profile, forbidden: "Virtual machines are not available on this platform.", code: 4)
            return
        }
        if profileUsesContainerBackend(profile) {
            try connectRelayBacked(profile: profile, forbidden: "Containers are not available on this platform.", code: 5)
            return
        }
        throw NSError(
            domain: "WWNMachineSessionBridge", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Machine type does not support connect on this platform yet."]
        )
    }

    @objc(disconnectProfile:)
    public static func disconnectProfile(_ profile: WWNMachineProfile) {
        guard profile != nil else { return }

        #if os(macOS)
        let defs = UserDefaults.standard
        let wasLockscreen =
            defs.bool(forKey: kWWNPrefsLockscreenReplacementEnabled)
            && (defs.string(forKey: kWWNPrefsLockscreenReplacementMachineId) == profile.machineId)
        #endif

        if profileUsesNativeCompositorClient(profile) {
            disconnectNative(profile: profile)
        } else if profileRequiresWaypipeTransport(profile) {
            WWNWaypipeRunner.shared.stopWaypipe()
        } else if profileUsesVirtualMachineBackend(profile) || profileUsesContainerBackend(profile) {
            WWNRelay.sharedRelay.stopProfile(withMachineId: profile.machineId ?? "")
            if WWNRelay.sharedRelay.hasOwnedSession(forMachineId: profile.machineId ?? "") {
                return
            }
        }

        if WWNMachineProfileStore.activeMachineId() == profile.machineId {
            WWNMachineProfileStore.setActiveMachineId(nil)
        }

        #if os(macOS)
        if wasLockscreen, defs.bool(forKey: kWWNPrefsDesktopReplacementEnabled),
           let desktopId = defs.string(forKey: kWWNPrefsDesktopReplacementMachineId),
           !desktopId.isEmpty,
           let desktopProfile = WWNMachineProfileStore.profile(byId: desktopId) {
            do {
                try connect(desktopProfile)
            } catch {
                NSLog("[DesktopReplacement] lockscreen handoff failed: %@", error.localizedDescription)
            }
        }
        #endif
    }

    private static func connectNative(profile: WWNMachineProfile) throws {
        guard let clientId = nativeClientId(forProfile: profile), !clientId.isEmpty else {
            throw NSError(domain: "WWNMachineSessionBridge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Native machine has no bundled client configured."])
        }
        if !WWNPlatformAllowsGpuStack(),
           ["kmscube", "gbm-es2-demo", "opengl-cube", "vkcube", "weston-simple-egl"].contains(clientId) {
            throw NSError(
                domain: "WWNMachineSessionBridge", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "\(clientId) requires a GPU stack unavailable on this platform."]
            )
        }
        if clientId == "wawona-wasm" {
            try validateWasmBundle(profile: profile)
        }
        if clientId == "wawona-shell" { return }

        WWNWaypipeRunner.shared.launchBundledClient(withId: clientId, machineId: profile.machineId)
        #if os(macOS)
        if WWNPlatformAllowsSwingingBridge(), clientId == "weston" {
            WWNSwingingBridgeController.sharedController.attach(forProfile: profile)
        }
        #endif
    }

    private static func validateWasmBundle(profile: WWNMachineProfile) throws {
        let runtime = profile.runtimeOverrides as? [String: Any] ?? [:]
        let wasmPath = (((runtime["wasmModulePath"] as? String) ?? "") as NSString).expandingTildeInPath
        let haveExplicit = !wasmPath.isEmpty && FileManager.default.fileExists(atPath: wasmPath)
        let pkg = runtime["wasmPackage"] as? String ?? ""
        let cmd = runtime["wasmCommand"] as? String ?? ""
        let haveName = !pkg.isEmpty || !cmd.isEmpty
        let bundled = Bundle.main.path(forResource: "hello-wasi-gui", ofType: "wasm") ?? ""
        let haveBundled = !bundled.isEmpty && FileManager.default.fileExists(atPath: bundled)
        if !haveExplicit, !haveName, !haveBundled {
            throw NSError(
                domain: "WWNMachineSessionBridge", code: 6,
                userInfo: [NSLocalizedDescriptionKey:
                    "Bundled hello-wasi-gui.wasm is missing. Pick a Wayland .wasm or type wasm hello-wasi-gui."]
            )
        }
    }

    private static func connectRelayBacked(profile: WWNMachineProfile, forbidden: String, code: Int) throws {
        let allowed: Bool
        if profileUsesVirtualMachineBackend(profile) {
            allowed = WWNPlatformAllowsVirtualMachine()
        } else {
            allowed = WWNPlatformAllowsContainer()
        }
        if !allowed {
            throw NSError(domain: "WWNMachineSessionBridge", code: code,
                          userInfo: [NSLocalizedDescriptionKey: forbidden])
        }
        var err: NSError?
        let ok = WWNRelay.sharedRelay.startProfile(profile, error: &err)
        if !ok { throw err ?? NSError(domain: "WWNMachineSessionBridge", code: code, userInfo: nil) }
    }

    private static func disconnectNative(profile: WWNMachineProfile) {
        let runner = WWNWaypipeRunner.shared
        let clientId = nativeClientId(forProfile: profile)
        #if os(macOS)
        if WWNDesktopReplacementController.sharedController.isDesktopMachine(profile) {
            WWNDesktopReplacementController.sharedController.disengage()
        }
        if WWNPlatformAllowsSwingingBridge(), clientId == "weston" {
            WWNSwingingBridgeController.sharedController.detach()
        }
        #endif
        runner.stopBundledClient(forMachineId: profile.machineId)
        #if os(iOS)
        if !runner.isAnyNativeClientRunning {
            runner.stopActiveIOSBundledClient()
        }
        #endif
    }
}

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
@inline(__always)
private func WWNPlatformAllowsVirtualMachine() -> Bool {
    #if os(tvOS)
    return false
    #else
    return true
    #endif
}

@inline(__always)
private func WWNPlatformAllowsContainer() -> Bool {
    #if os(tvOS)
    return false
    #else
    return true
    #endif
}

@inline(__always)
private func WWNPlatformAllowsGpuStack() -> Bool {
    #if os(tvOS)
    #if WWN_TVOS_GPU_BUNDLED
    return true
    #else
    return false
    #endif
    #else
    return true
    #endif
}

@inline(__always)
private func WWNPlatformAllowsSwingingBridge() -> Bool {
    #if os(macOS)
    return true
    #else
    return false
    #endif
}
#else
@inline(__always)
private func WWNPlatformAllowsVirtualMachine() -> Bool { false }
@inline(__always)
private func WWNPlatformAllowsContainer() -> Bool { false }
@inline(__always)
private func WWNPlatformAllowsGpuStack() -> Bool { false }
@inline(__always)
private func WWNPlatformAllowsSwingingBridge() -> Bool { false }
#endif
