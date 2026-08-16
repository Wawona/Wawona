#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Preferences keys
extern NSString *const kWWNPrefsUniversalClipboard;
extern NSString *const kWWNPrefsForceServerSideDecorations;
extern NSString *const kWWNPrefsAutoRetinaScaling; // Legacy - use AutoScale
extern NSString *const kWWNPrefsAutoScale;         // New unified key
extern NSString
    *const kWWNPrefsColorSyncSupport;            // Legacy - use ColorOperations
extern NSString *const kWWNPrefsColorOperations; // New unified key
extern NSString *const kWWNPrefsNestedCompositorsSupport;
extern NSString *const kWWNPrefsNestedWestonBackend;
extern NSString *const kWWNPrefsUseMetal4ForNested; // Deprecated - removed
extern NSString *const kWWNPrefsRenderMacOSPointer;
/// Nested compositor cursor source when virtual cursor is enabled:
/// @"virtual" (virtual pointer) or @"host" (real macOS / host cursor).
extern NSString *const kWWNPrefsNestedCompositorCursor;
extern NSString *const kWWNPrefsMultipleClients;
extern NSString *const kWWNPrefsSwapCmdAsCtrl;  // Legacy - use SwapCmdWithAlt
extern NSString *const kWWNPrefsSwapCmdWithAlt; // New unified key
extern NSString *const kWWNPrefsTouchInputType;
extern NSString *const kWWNPrefsWaypipeRSSupport; // Deprecated - always enabled
extern NSString
    *const kWWNPrefsEnableTCPListener; // Deprecated - always enabled
extern NSString *const kWWNPrefsTCPListenerPort;
extern NSString *const kWWNPrefsWaylandSocketDir;
extern NSString *const kWWNPrefsWaylandDisplayNumber;
extern NSString *const kWWNPrefsEnableVulkanDrivers;
extern NSString *const kWWNPrefsEnableDmabuf;
extern NSString *const kWWNPrefsVulkanDriver;
extern NSString *const kWWNPrefsOpenGLDriver;
/// Which display backend a bundled client/nested compositor runs on:
/// `auto` | `wayland` (nested Wayland client of Wawona) | `drm`
/// (wwn-iland userspace DRM/KMS/GBM, the bare-metal-shaped path).
extern NSString *const kWWNPrefsCompositorBackend;
extern NSString *const kWWNPrefsRespectSafeArea;
extern NSString *const kWWNPrefsResizeDisplayForVirtualKeyboard;
extern NSString *const kWWNPrefsExternalDisplayTouchpad;
extern NSString *const kWWNPrefsHasSeenWelcome;
// Waypipe configuration keys
extern NSString *const kWWNPrefsWaypipeDisplay;
extern NSString *const kWWNPrefsWaypipeSocket;
extern NSString *const kWWNPrefsWaypipeCompress;
extern NSString *const kWWNPrefsWaypipeCompressLevel;
extern NSString *const kWWNPrefsWaypipeThreads;
extern NSString *const kWWNPrefsWaypipeVideo;
extern NSString *const kWWNPrefsWaypipeVideoEncoding;
extern NSString *const kWWNPrefsWaypipeVideoDecoding;
extern NSString *const kWWNPrefsWaypipeVideoBpf;
extern NSString *const kWWNPrefsWaypipeSSHEnabled;
extern NSString *const kWWNPrefsWaypipeSSHHost;
extern NSString *const kWWNPrefsWaypipeSSHUser;
extern NSString *const kWWNPrefsWaypipeSSHBinary;
extern NSString *const kWWNPrefsWaypipeSSHAuthMethod;
extern NSString *const kWWNPrefsWaypipeSSHKeyPath;
extern NSString *const kWWNPrefsWaypipeSSHKeyPassphrase;
extern NSString *const kWWNPrefsWaypipeSSHPassword;
extern NSString *const kWWNPrefsWaypipeRemoteCommand;
extern NSString *const kWWNPrefsWaypipeCustomScript;
extern NSString *const kWWNPrefsWaypipeDebug;
extern NSString *const kWWNPrefsWaypipeNoGpu;
extern NSString *const kWWNPrefsWaypipeOneshot;
extern NSString *const kWWNPrefsWaypipeUnlinkSocket;
extern NSString *const kWWNPrefsWaypipeLoginShell;
extern NSString *const kWWNPrefsWaypipeVsock;
extern NSString *const kWWNPrefsWaypipeXwls;
extern NSString *const kWWNPrefsWaypipeTitlePrefix;
extern NSString *const kWWNPrefsWaypipeSecCtx;
// Machine settings — backed by the wwn-vms (VM engine) + wwn-containers (OCI)
// dependencies. Capability-driven per target (see each dep's COMPLIANCE.md).
extern NSString *const kWWNPrefsMachineVMProvider;
extern NSString *const kWWNPrefsMachineVMVsockPort;
extern NSString *const kWWNPrefsMachineContainerRuntime;
extern NSString *const kWWNPrefsMachineContainerImageStore;
// SSH configuration keys (separate from Waypipe)
extern NSString *const kWWNPrefsSSHHost;
extern NSString *const kWWNPrefsSSHUser;
extern NSString *const kWWNPrefsSSHPort;
extern NSString *const kWWNPrefsSSHAuthMethod;
extern NSString *const kWWNPrefsSSHPassword;
extern NSString *const kWWNPrefsSSHKeyPath;
extern NSString *const kWWNPrefsSSHKeyPassphrase;
extern NSString *const kWWNPrefsWaypipeUseSSHConfig;
extern NSString *const kWWNForceSSDChangedNotification;
extern NSString *const kWWNPrefsMachineSessionThumbnailsEnabled;
// Desktop Replacement (wwn-iland Mode B): run Wawona as the desktop by replacing
// SkyLight/WindowServer. macOS-only, SIP-gated, never an App Store path. The
// chosen desktop machine MUST be a Native machine profile.
extern NSString *const kWWNPrefsDesktopReplacementEnabled;
extern NSString *const kWWNPrefsDesktopReplacementMachineId;
extern NSString *const kWWNPrefsLockscreenReplacementEnabled;
extern NSString *const kWWNPrefsLockscreenReplacementMachineId;
// Wawona Swinging Bridge (formerly anowaW): render native macOS (Cocoa/AppKit)
// apps as Wayland clients inside the nested-Weston desktop / over waypipe.
// Layered on Desktop Replacement eligibility (local-only nested-Weston).
// macOS uses Developer ID distribution (Screen Recording + Accessibility);
// never a Mac App Store path for the embedding capability.
extern NSString *const kWWNPrefsSwingingBridgeEnabled;
/// Deprecated preference key name; still read for migration.
extern NSString *const kWWNPrefsAnowaWEnabled;
@interface WWNPreferencesManager : NSObject

+ (instancetype)sharedManager;

// Universal Clipboard
- (BOOL)universalClipboardEnabled;
- (void)setUniversalClipboardEnabled:(BOOL)enabled;

// Window Decorations
- (BOOL)forceServerSideDecorations;
- (void)setForceServerSideDecorations:(BOOL)enabled;

// Display
- (BOOL)autoRetinaScalingEnabled; // Legacy - use autoScale
- (void)setAutoRetinaScalingEnabled:(BOOL)enabled;
- (BOOL)autoScale; // New unified method
- (void)setAutoScale:(BOOL)enabled;
- (BOOL)respectSafeArea;
- (void)setRespectSafeArea:(BOOL)enabled;
- (BOOL)externalDisplayTouchpad; // Device as trackpad on external displays
- (void)setExternalDisplayTouchpad:(BOOL)enabled;
- (BOOL)hasSeenWelcome;
- (void)setHasSeenWelcome:(BOOL)seen;

// Color Management
- (BOOL)colorSyncSupportEnabled; // Legacy - use colorOperations
- (void)setColorSyncSupportEnabled:(BOOL)enabled;
- (BOOL)colorOperations; // New unified method
- (void)setColorOperations:(BOOL)enabled;

// Nested Compositors
- (BOOL)nestedCompositorsSupportEnabled;
- (void)setNestedCompositorsSupportEnabled:(BOOL)enabled;
- (NSString *)nestedWestonBackend;
- (void)setNestedWestonBackend:(NSString *)backend;
- (BOOL)useMetal4ForNested;
- (void)setUseMetal4ForNested:(BOOL)enabled;

// Input
- (BOOL)renderMacOSPointer;
- (void)setRenderMacOSPointer:(BOOL)enabled;
/// @"virtual" or @"host". Only meaningful when renderMacOSPointer is YES.
- (NSString *)nestedCompositorCursor;
- (void)setNestedCompositorCursor:(NSString *)mode;
- (BOOL)resizeDisplayForVirtualKeyboard;
- (void)setResizeDisplayForVirtualKeyboard:(BOOL)enabled;
- (BOOL)swapCmdAsCtrl; // Legacy - use swapCmdWithAlt
- (void)setSwapCmdAsCtrl:(BOOL)enabled;
- (BOOL)swapCmdWithAlt; // New unified method
- (void)setSwapCmdWithAlt:(BOOL)enabled;
- (NSString *)touchInputType;
- (void)setTouchInputType:(NSString *)type;

// Client Management
- (BOOL)multipleClientsEnabled;
- (void)setMultipleClientsEnabled:(BOOL)enabled;

- (BOOL)machineSessionThumbnailsEnabled;
- (void)setMachineSessionThumbnailsEnabled:(BOOL)enabled;

// Waypipe
- (BOOL)waypipeRSSupportEnabled;
- (void)setWaypipeRSSupportEnabled:(BOOL)enabled;

// Network / Remote Access
- (BOOL)enableTCPListener;
- (void)setEnableTCPListener:(BOOL)enabled;
- (NSInteger)tcpListenerPort;
- (void)setTCPListenerPort:(NSInteger)port;

// Wayland Configuration
- (NSString *)waylandSocketDir;
- (void)setWaylandSocketDir:(NSString *)dir;
- (NSInteger)waylandDisplayNumber;
- (void)setWaylandDisplayNumber:(NSInteger)number;

// Rendering Backend Flags
- (BOOL)vulkanDriversEnabled;
- (void)setVulkanDriversEnabled:(BOOL)enabled;
- (BOOL)eglDriversEnabled;
- (void)setEglDriversEnabled:(BOOL)enabled;

// Dmabuf Support (IOSurface-backed)
- (BOOL)dmabufEnabled;
- (void)setDmabufEnabled:(BOOL)enabled;

// Graphics Driver Selection (Settings > Graphics > Drivers)
- (NSString *)vulkanDriver;
- (void)setVulkanDriver:(NSString *)driver;
// Short XDG_RUNTIME_DIR for Wayland sockets (Darwin sun_path is 104 bytes).
+ (NSString *)preferredSharedRuntimeDir;
// Nested Weston socket name; shorter on physical iOS (container paths are long).
+ (NSString *)preferredNestedSocketName;

// Capability-tiered default ICD: KosmicKrisp on Apple Silicon + macOS 26+,
// MoltenVK otherwise. Used when the user has not made an explicit choice.
+ (NSString *)defaultVulkanDriverForHardware;
- (NSString *)openglDriver;
- (void)setOpenGLDriver:(NSString *)driver;

// Display backend for bundled clients / nested compositors.
// Stored as `auto` | `wayland` | `drm`; `auto` resolves per client (see
// WWNResolveCompositorBackend in WWNWaypipeRunner.m). A client that supports
// both must never hardcode one — niri and weston each have a real DRM backend,
// which is the whole reason wwn-iland's userspace KMS exists.
- (NSString *)compositorBackend;
- (void)setCompositorBackend:(NSString *)backend;

// Waypipe Configuration
- (NSString *)waypipeDisplay;
- (void)setWaypipeDisplay:(NSString *)display;
- (NSString *)waypipeSocket;
- (void)setWaypipeSocket:(NSString *)socket;
- (NSString *)waypipeCompress;
- (void)setWaypipeCompress:(NSString *)compress;
- (NSString *)waypipeCompressLevel;
- (void)setWaypipeCompressLevel:(NSString *)level;
- (NSString *)waypipeThreads;
- (void)setWaypipeThreads:(NSString *)threads;
- (NSString *)waypipeVideo;
- (void)setWaypipeVideo:(NSString *)video;
- (NSString *)waypipeVideoEncoding;
- (void)setWaypipeVideoEncoding:(NSString *)encoding;
- (NSString *)waypipeVideoDecoding;
- (void)setWaypipeVideoDecoding:(NSString *)decoding;
- (NSString *)waypipeVideoBpf;
- (void)setWaypipeVideoBpf:(NSString *)bpf;
- (BOOL)waypipeSSHEnabled;
- (void)setWaypipeSSHEnabled:(BOOL)enabled;
- (NSString *)waypipeSSHHost;
- (void)setWaypipeSSHHost:(NSString *)host;
- (NSString *)waypipeSSHUser;
- (void)setWaypipeSSHUser:(NSString *)user;
- (NSString *)waypipeSSHBinary;
- (void)setWaypipeSSHBinary:(NSString *)binary;
- (NSInteger)waypipeSSHAuthMethod; // 0 = password, 1 = public key
- (void)setWaypipeSSHAuthMethod:(NSInteger)method;
- (NSString *)waypipeSSHKeyPath;
- (void)setWaypipeSSHKeyPath:(NSString *)keyPath;
- (NSString *)waypipeSSHKeyPassphrase;
- (void)setWaypipeSSHKeyPassphrase:(NSString *)passphrase;
- (NSString *)waypipeSSHPassword;
- (void)setWaypipeSSHPassword:(NSString *)password;
- (NSString *)waypipeRemoteCommand;
- (void)setWaypipeRemoteCommand:(NSString *)command;
- (NSString *)waypipeCustomScript;
- (void)setWaypipeCustomScript:(NSString *)script;
- (BOOL)waypipeDebug;
- (void)setWaypipeDebug:(BOOL)enabled;
- (BOOL)waypipeNoGpu;
- (void)setWaypipeNoGpu:(BOOL)enabled;
- (BOOL)waypipeOneshot;
- (void)setWaypipeOneshot:(BOOL)enabled;
- (BOOL)waypipeUnlinkSocket;
- (void)setWaypipeUnlinkSocket:(BOOL)enabled;
- (BOOL)waypipeLoginShell;
- (void)setWaypipeLoginShell:(BOOL)enabled;
- (BOOL)waypipeVsock;
- (void)setWaypipeVsock:(BOOL)enabled;
- (BOOL)waypipeXwls;
- (void)setWaypipeXwls:(BOOL)enabled;
- (NSString *)waypipeTitlePrefix;
- (void)setWaypipeTitlePrefix:(NSString *)prefix;
- (NSString *)waypipeSecCtx;
- (void)setWaypipeSecCtx:(NSString *)secCtx;
- (BOOL)waypipeUseSSHConfig;
- (void)setWaypipeUseSSHConfig:(BOOL)enabled;

// SSH Configuration (separate from Waypipe)
- (NSString *)sshHost;
- (void)setSshHost:(NSString *)host;
- (NSString *)sshUser;
- (void)setSshUser:(NSString *)user;
- (NSInteger)sshPort;
- (void)setSshPort:(NSInteger)port;
- (NSInteger)sshAuthMethod; // 0 = password, 1 = public key
- (void)setSshAuthMethod:(NSInteger)method;
- (NSString *)sshPassword;
- (void)setSshPassword:(NSString *)password;
- (NSString *)sshKeyPath;
- (void)setSshKeyPath:(NSString *)keyPath;
- (NSString *)sshKeyPassphrase;
- (void)setSshKeyPassphrase:(NSString *)passphrase;

// Reset to defaults
- (void)resetToDefaults;
- (void)syncFromCanonicalWawonaPreferences;

@end

NS_ASSUME_NONNULL_END
