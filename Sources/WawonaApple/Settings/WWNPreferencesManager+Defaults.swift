import Foundation
import WawonaModel

extension WWNPreferencesManager {
    func setDefaultsIfNeeded() {
        let defaults = defs
        let defaultSocketDir = Self.preferredSharedRuntimeDir()
        let defaultSocket = (defaultSocketDir as NSString).appendingPathComponent("wayland-0")

        #if os(tvOS)
        let forceSSDDefault = true
        #else
        let forceSSDDefault = false
        #endif

        #if os(macOS)
        let nestedWestonDefault = "iland-drm-gl"
        let containerRuntimeDefault = "containerization"
        #else
        let nestedWestonDefault = "wayland-pixman"
        let containerRuntimeDefault = "container-in-vm"
        #endif

        defaults.register(defaults: [
            kWWNPrefsForceServerSideDecorations: forceSSDDefault,
            kWWNPrefsAutoScale: true,
            kWWNPrefsRespectSafeArea: true,
            kWWNPrefsResizeDisplayForVirtualKeyboard: true,
            kWWNPrefsExternalDisplayTouchpad: true,
            kWWNPrefsHasSeenWelcome: false,
            kWWNPrefsRenderMacOSPointer: false,
            kWWNPrefsNestedCompositorCursor: "virtual",
            kWWNPrefsTouchInputType: "Multi-Touch",
            kWWNPrefsTouchPointerEmulation: false,
            kWWNPrefsSwapCmdWithAlt: true,
            kWWNPrefsUniversalClipboard: true,
            kWWNPrefsEnableVulkanDrivers: true,
            kWWNPrefsEnableDmabuf: true,
            kWWNPrefsVulkanDriver: Self.defaultVulkanDriverForHardware(),
            kWWNPrefsOpenGLDriver: Self.defaultOpenGLDriverForHardware(),
            kWWNPrefsCompositorBackend: "auto",
            kWWNPrefsTCPListenerPort: 6000,
            kWWNPrefsWaylandSocketDir: defaultSocketDir,
            kWWNPrefsWaylandDisplayNumber: 0,
            kWWNPrefsColorOperations: true,
            kWWNPrefsNestedCompositorsSupport: true,
            kWWNPrefsNestedWestonBackend: nestedWestonDefault,
            kWWNPrefsMultipleClients: true,
            kWWNPrefsDefaultStartType: "prompt",
            kWWNPrefsMachineSessionThumbnailsEnabled: true,
            kWWNPrefsDesktopReplacementEnabled: false,
            kWWNPrefsLockscreenReplacementEnabled: false,
            kWWNPrefsDesktopReplacementMachineId: "",
            kWWNPrefsSwingingBridgeEnabled: false,
            kWWNPrefsAnowaWEnabled: false,
            kWWNPrefsWaypipeDisplay: "wayland-0",
            kWWNPrefsWaypipeSocket: defaultSocket,
            kWWNPrefsWaypipeCompress: "lz4",
            kWWNPrefsWaypipeCompressLevel: "7",
            kWWNPrefsWaypipeThreads: "0",
            kWWNPrefsWaypipeVideo: "none",
            kWWNPrefsWaypipeVideoEncoding: "hw",
            kWWNPrefsWaypipeVideoDecoding: "hw",
            kWWNPrefsWaypipeVideoBpf: "",
            kWWNPrefsWaypipeSSHEnabled: true,
            kWWNPrefsWaypipeSSHHost: "",
            kWWNPrefsWaypipeSSHUser: "",
            kWWNPrefsWaypipeSSHBinary: "ssh",
            kWWNPrefsWaypipeSSHAuthMethod: 0,
            kWWNPrefsWaypipeSSHKeyPath: "",
            kWWNPrefsWaypipeRemoteCommand: "",
            kWWNPrefsWaypipeCustomScript: "",
            kWWNPrefsWaypipeDebug: false,
            kWWNPrefsWaypipeNoGpu: false,
            kWWNPrefsWaypipeOneshot: false,
            kWWNPrefsWaypipeUnlinkSocket: false,
            kWWNPrefsWaypipeLoginShell: false,
            kWWNPrefsWaypipeVsock: false,
            kWWNPrefsWaypipeXwls: false,
            kWWNPrefsWaypipeTitlePrefix: "",
            kWWNPrefsWaypipeSecCtx: "",
            kWWNPrefsWaypipeUseSSHConfig: true,
            kWWNPrefsMachineVMProvider: "nixos-vm",
            kWWNPrefsMachineVMVsockPort: "1024",
            kWWNPrefsMachineContainerRuntime: containerRuntimeDefault,
            kWWNPrefsMachineContainerImageStore: "~/.local/share/wawona/oci",
            kWWNPrefsContainerDefaultImage: "alpine:3.20",
            kWWNPrefsContainerDefaultCommand: "/bin/sh",
            kWWNPrefsContainerMemory: "",
            kWWNPrefsContainerShmSize: "",
            kWWNPrefsContainerKernelPath: "",
            kWWNPrefsContainerInitfsPath: "",
            kWWNPrefsContainerVsockPort: "1024",
            kWWNPrefsSSHHost: "",
            kWWNPrefsSSHUser: "",
            kWWNPrefsSSHPort: 22,
            kWWNPrefsSSHAuthMethod: 0,
            kWWNPrefsSSHKeyPath: "",
            kWWNPrefsWaypipeRSSupport: false,
            kWWNPrefsEnableTCPListener: false,
            kWWNPrefsUseMetal4ForNested: false,
        ])

        migrateLegacyKeys(defaults)

        #if os(tvOS) && WWN_TVOS_GPU_BUNDLED
        if !defaults.bool(forKey: WWNPreferencesInternal.tvosOpenGLDriverMigratedKey) {
            let gl = defaults.string(forKey: kWWNPrefsOpenGLDriver) ?? ""
            if gl.isEmpty || gl == "none" {
                defaults.set("angle", forKey: kWWNPrefsOpenGLDriver)
            }
            WWNMachineProfileStore.migrateTvosGpuOpenGLDriverSnapshotsIfNeeded()
            defaults.set(true, forKey: WWNPreferencesInternal.tvosOpenGLDriverMigratedKey)
            defaults.synchronize()
        }
        #endif
    }

    private func migrateLegacyKeys(_ defaults: UserDefaults) {
        if defaults.object(forKey: kWWNPrefsAutoRetinaScaling) != nil,
           defaults.object(forKey: kWWNPrefsAutoScale) == nil {
            defaults.set(defaults.bool(forKey: kWWNPrefsAutoRetinaScaling), forKey: kWWNPrefsAutoScale)
        }
        if defaults.object(forKey: kWWNPrefsColorSyncSupport) != nil,
           defaults.object(forKey: kWWNPrefsColorOperations) == nil {
            defaults.set(defaults.bool(forKey: kWWNPrefsColorSyncSupport), forKey: kWWNPrefsColorOperations)
        }
        if defaults.object(forKey: kWWNPrefsSwapCmdAsCtrl) != nil,
           defaults.object(forKey: kWWNPrefsSwapCmdWithAlt) == nil {
            defaults.set(defaults.bool(forKey: kWWNPrefsSwapCmdAsCtrl), forKey: kWWNPrefsSwapCmdWithAlt)
        }
        if defaults.object(forKey: "EnableVulkanDrivers") != nil,
           defaults.object(forKey: kWWNPrefsEnableVulkanDrivers) == nil {
            defaults.set(defaults.bool(forKey: "EnableVulkanDrivers"), forKey: kWWNPrefsEnableVulkanDrivers)
            defaults.removeObject(forKey: "EnableVulkanDrivers")
        }
        if defaults.object(forKey: "EnableDmabuf") != nil,
           defaults.object(forKey: kWWNPrefsEnableDmabuf) == nil {
            defaults.set(defaults.bool(forKey: "EnableDmabuf"), forKey: kWWNPrefsEnableDmabuf)
            defaults.removeObject(forKey: "EnableDmabuf")
        }
        if defaults.object(forKey: kWWNPrefsVulkanDriver) == nil {
            if defaults.bool(forKey: kWWNPrefsEnableVulkanDrivers) {
                defaults.set("moltenvk", forKey: kWWNPrefsVulkanDriver)
            } else {
                defaults.set("none", forKey: kWWNPrefsVulkanDriver)
            }
        }
    }

    @objc public func resetToDefaults() {
        let keys = [
            kWWNPrefsForceServerSideDecorations, kWWNPrefsAutoScale, kWWNPrefsAutoRetinaScaling,
            kWWNPrefsRespectSafeArea, kWWNPrefsResizeDisplayForVirtualKeyboard, kWWNPrefsHasSeenWelcome,
            kWWNPrefsRenderMacOSPointer, kWWNPrefsNestedCompositorCursor, kWWNPrefsTouchInputType,
            kWWNPrefsTouchPointerEmulation, kWWNPrefsSwapCmdWithAlt, kWWNPrefsSwapCmdAsCtrl,
            kWWNPrefsUniversalClipboard, kWWNPrefsEnableVulkanDrivers, kWWNPrefsEnableDmabuf,
            kWWNPrefsVulkanDriver, kWWNPrefsOpenGLDriver, kWWNPrefsCompositorBackend,
            kWWNPrefsTCPListenerPort, kWWNPrefsWaylandSocketDir, kWWNPrefsWaylandDisplayNumber,
            kWWNPrefsColorOperations, kWWNPrefsColorSyncSupport, kWWNPrefsNestedCompositorsSupport,
            kWWNPrefsUseMetal4ForNested, kWWNPrefsMultipleClients, kWWNPrefsDefaultStartType,
            kWWNPrefsMachineSessionThumbnailsEnabled, kWWNPrefsWaypipeDisplay, kWWNPrefsWaypipeSocket,
            kWWNPrefsWaypipeCompress, kWWNPrefsWaypipeCompressLevel, kWWNPrefsWaypipeThreads,
            kWWNPrefsWaypipeVideo, kWWNPrefsWaypipeVideoEncoding, kWWNPrefsWaypipeVideoDecoding,
            kWWNPrefsWaypipeVideoBpf, kWWNPrefsWaypipeUseSSHConfig, kWWNPrefsWaypipeRemoteCommand,
            kWWNPrefsWaypipeDebug, kWWNPrefsWaypipeNoGpu, kWWNPrefsWaypipeOneshot,
            kWWNPrefsWaypipeUnlinkSocket, kWWNPrefsWaypipeLoginShell, kWWNPrefsWaypipeVsock,
            kWWNPrefsWaypipeXwls, kWWNPrefsWaypipeTitlePrefix, kWWNPrefsWaypipeSecCtx,
            kWWNPrefsWaypipeCustomScript, kWWNPrefsMachineVMProvider, kWWNPrefsMachineVMVsockPort,
            kWWNPrefsMachineContainerRuntime, kWWNPrefsMachineContainerImageStore,
            kWWNPrefsContainerDefaultImage, kWWNPrefsContainerDefaultCommand, kWWNPrefsContainerMemory,
            kWWNPrefsContainerShmSize, kWWNPrefsContainerKernelPath, kWWNPrefsContainerInitfsPath,
            kWWNPrefsContainerVsockPort, kWWNPrefsSSHHost, kWWNPrefsSSHUser, kWWNPrefsSSHPort,
            kWWNPrefsSSHAuthMethod, kWWNPrefsSSHKeyPath, kWWNPrefsWaypipeRSSupport,
            kWWNPrefsEnableTCPListener,
        ]
        for key in keys {
            defs.removeObject(forKey: key)
        }
        setDefaultsIfNeeded()
    }
}
