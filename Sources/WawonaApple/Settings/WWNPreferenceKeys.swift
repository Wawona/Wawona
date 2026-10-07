import Foundation

// ObjC-visible preference key strings (declared extern in WWNPreferencesManager.h).
public let kWWNPrefsUniversalClipboard = "UniversalClipboard"
public let kWWNPrefsForceServerSideDecorations = "ForceServerSideDecorations"
public let kWWNPrefsAutoRetinaScaling = "AutoRetinaScaling"
public let kWWNPrefsAutoScale = "AutoScale"
public let kWWNPrefsColorSyncSupport = "ColorSyncSupport"
public let kWWNPrefsColorOperations = "ColorOperations"
public let kWWNPrefsNestedCompositorsSupport = "NestedCompositorsSupport"
public let kWWNPrefsNestedWestonBackend = "NestedWestonBackend"
public let kWWNPrefsUseMetal4ForNested = "UseMetal4ForNested"
public let kWWNPrefsRenderMacOSPointer = "RenderMacOSPointer"
public let kWWNPrefsNestedCompositorCursor = "NestedCompositorCursor"
public let kWWNPrefsMultipleClients = "MultipleClients"
public let kWWNPrefsDefaultStartType = "DefaultStartType"
public let kWWNPrefsSwapCmdAsCtrl = "SwapCmdAsCtrl"
public let kWWNPrefsSwapCmdWithAlt = "SwapCmdWithAlt"
public let kWWNPrefsTouchInputType = "TouchInputType"
public let kWWNPrefsTouchPointerEmulation = "TouchPointerEmulation"
public let kWWNPrefsWaypipeRSSupport = "WaypipeRSSupport"
public let kWWNPrefsEnableTCPListener = "EnableTCPListener"
public let kWWNPrefsTCPListenerPort = "TCPListenerPort"
public let kWWNPrefsWaylandSocketDir = "WaylandSocketDir"
public let kWWNPrefsWaylandDisplayNumber = "WaylandDisplayNumber"
public let kWWNPrefsEnableVulkanDrivers = "VulkanDriversEnabled"
public let kWWNPrefsEnableDmabuf = "DmabufEnabled"
public let kWWNPrefsVulkanDriver = "VulkanDriver"
public let kWWNPrefsOpenGLDriver = "OpenGLDriver"
public let kWWNPrefsCompositorBackend = "CompositorBackend"
public let kWWNPrefsRespectSafeArea = "RespectSafeArea"
public let kWWNPrefsResizeDisplayForVirtualKeyboard = "resizeDisplayForVirtualKeyboard"
public let kWWNPrefsExternalDisplayTouchpad = "ExternalDisplayTouchpad"
public let kWWNPrefsHasSeenWelcome = "HasSeenWelcome"
public let kWWNPrefsWaypipeDisplay = "WaypipeDisplay"
public let kWWNPrefsWaypipeSocket = "WaypipeSocket"
public let kWWNPrefsWaypipeCompress = "WaypipeCompress"
public let kWWNPrefsWaypipeCompressLevel = "WaypipeCompressLevel"
public let kWWNPrefsWaypipeThreads = "WaypipeThreads"
public let kWWNPrefsWaypipeVideo = "WaypipeVideo"
public let kWWNPrefsWaypipeVideoEncoding = "WaypipeVideoEncoding"
public let kWWNPrefsWaypipeVideoDecoding = "WaypipeVideoDecoding"
public let kWWNPrefsWaypipeVideoBpf = "WaypipeVideoBpf"
public let kWWNPrefsWaypipeSSHEnabled = "WaypipeSSHEnabled"
public let kWWNPrefsWaypipeSSHHost = "WaypipeSSHHost"
public let kWWNPrefsWaypipeSSHUser = "WaypipeSSHUser"
public let kWWNPrefsWaypipeSSHBinary = "WaypipeSSHBinary"
public let kWWNPrefsWaypipeSSHAuthMethod = "WaypipeSSHAuthMethod"
public let kWWNPrefsWaypipeSSHKeyPath = "WaypipeSSHKeyPath"
public let kWWNPrefsWaypipeSSHKeyPassphrase = "WaypipeSSHKeyPassphrase"
public let kWWNPrefsWaypipeSSHPassword = "WaypipeSSHPassword"
public let kWWNPrefsWaypipeRemoteCommand = "WaypipeRemoteCommand"
public let kWWNPrefsWaypipeCustomScript = "WaypipeCustomScript"
public let kWWNPrefsWaypipeDebug = "WaypipeDebug"
public let kWWNPrefsWaypipeNoGpu = "WaypipeNoGpu"
public let kWWNPrefsWaypipeOneshot = "WaypipeOneshot"
public let kWWNPrefsWaypipeUnlinkSocket = "WaypipeUnlinkSocket"
public let kWWNPrefsWaypipeLoginShell = "WaypipeLoginShell"
public let kWWNPrefsWaypipeVsock = "WaypipeVsock"
public let kWWNPrefsWaypipeXwls = "WaypipeXwls"
public let kWWNPrefsWaypipeTitlePrefix = "WaypipeTitlePrefix"
public let kWWNPrefsWaypipeSecCtx = "WaypipeSecCtx"
public let kWWNPrefsMachineVMProvider = "MachineVMProvider"
public let kWWNPrefsMachineVMVsockPort = "MachineVMVsockPort"
public let kWWNPrefsMachineContainerRuntime = "MachineContainerRuntime"
public let kWWNPrefsMachineContainerImageStore = "MachineContainerImageStore"
public let kWWNPrefsContainerDefaultImage = "ContainerDefaultImage"
public let kWWNPrefsContainerDefaultCommand = "ContainerDefaultCommand"
public let kWWNPrefsContainerMemory = "ContainerMemory"
public let kWWNPrefsContainerShmSize = "ContainerShmSize"
public let kWWNPrefsContainerKernelPath = "ContainerKernelPath"
public let kWWNPrefsContainerInitfsPath = "ContainerInitfsPath"
public let kWWNPrefsContainerVsockPort = "ContainerVsockPort"
public let kWWNPrefsSSHHost = "SSHHost"
public let kWWNPrefsSSHUser = "SSHUser"
public let kWWNPrefsSSHPort = "SSHPort"
public let kWWNPrefsSSHAuthMethod = "SSHAuthMethod"
public let kWWNPrefsSSHPassword = "SSHPassword"
public let kWWNPrefsSSHKeyPath = "SSHKeyPath"
public let kWWNPrefsSSHKeyPassphrase = "SSHKeyPassphrase"
public let kWWNPrefsWaypipeUseSSHConfig = "WaypipeUseSSHConfig"
public let kWWNForceSSDChangedNotification = "WWNForceSSDChangedNotification"
public let kWWNPrefsMachineSessionThumbnailsEnabled = "MachineSessionThumbnailsEnabled"
public let kWWNPrefsDesktopReplacementEnabled = "DesktopReplacementEnabled"
public let kWWNPrefsDesktopReplacementMachineId = "DesktopReplacementMachineId"
#if WWN_MODE_B
public let kWWNModeBDesktopReplacementChangedNotification =
    "WWNModeBDesktopReplacementChangedNotification"
public let kWWNModeBDesktopReplacementReplaceNowNotification =
    "WWNModeBDesktopReplacementReplaceNowNotification"
#endif
public let kWWNPrefsLockscreenReplacementEnabled = "LockscreenReplacementEnabled"
public let kWWNPrefsLockscreenReplacementMachineId = "LockscreenReplacementMachineId"
public let kWWNPrefsSwingingBridgeEnabled = "SwingingBridgeEnabled"
public let kWWNPrefsAnowaWEnabled = "AnowaWEnabled"

private let kWWNTvosOpenGLDriverMigrated = "wawona.tvosOpenGLDriverMigrated.v1"
private let kWWNWawonaPreferencesDidSaveNotificationName = "WawonaPreferencesDidSave"

enum WWNPreferencesInternal {
    static let tvosOpenGLDriverMigratedKey = kWWNTvosOpenGLDriverMigrated
    static let wawonaPreferencesDidSave = Notification.Name(kWWNWawonaPreferencesDidSaveNotificationName)
}

public func WWNSharedUserDefaults() -> UserDefaults {
    #if WWN_PREFPANE
    struct Suite {
        static let instance: UserDefaults = {
            UserDefaults(suiteName: "com.aspauldingcode.Wawona") ?? .standard
        }()
    }
    return Suite.instance
    #else
    return .standard
    #endif
}
