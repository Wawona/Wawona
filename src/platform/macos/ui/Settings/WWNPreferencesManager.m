#import "WWNPreferencesManager.h"
#import "../Machines/WWNPlatformCapabilities.h"
#import "../Machines/WWNMachineProfileStore.h"
#import <sys/sysctl.h>

static NSString *const kWWNTvosOpenGLDriverMigrated =
    @"wawona.tvosOpenGLDriverMigrated.v1";

// Preferences keys
NSString *const kWWNPrefsUniversalClipboard = @"UniversalClipboard";
NSString *const kWWNPrefsForceServerSideDecorations =
    @"ForceServerSideDecorations";
NSString *const kWWNPrefsAutoRetinaScaling = @"AutoRetinaScaling"; // Legacy
NSString *const kWWNPrefsAutoScale = @"AutoScale"; // New unified key
NSString *const kWWNPrefsColorSyncSupport = @"ColorSyncSupport"; // Legacy
NSString *const kWWNPrefsColorOperations =
    @"ColorOperations"; // New unified key
NSString *const kWWNPrefsNestedCompositorsSupport = @"NestedCompositorsSupport";
NSString *const kWWNPrefsNestedWestonBackend = @"NestedWestonBackend";
NSString *const kWWNPrefsUseMetal4ForNested =
    @"UseMetal4ForNested"; // Deprecated
NSString *const kWWNPrefsRenderMacOSPointer = @"RenderMacOSPointer";
NSString *const kWWNPrefsNestedCompositorCursor = @"NestedCompositorCursor";
NSString *const kWWNPrefsMultipleClients = @"MultipleClients";
NSString *const kWWNPrefsSwapCmdAsCtrl = @"SwapCmdAsCtrl";   // Legacy
NSString *const kWWNPrefsSwapCmdWithAlt = @"SwapCmdWithAlt"; // New unified key
NSString *const kWWNPrefsTouchInputType = @"TouchInputType";
NSString *const kWWNPrefsWaypipeRSSupport =
    @"WaypipeRSSupport"; // Deprecated - always enabled
NSString *const kWWNPrefsEnableTCPListener =
    @"EnableTCPListener"; // Deprecated - always enabled
NSString *const kWWNPrefsTCPListenerPort = @"TCPListenerPort";
NSString *const kWWNPrefsWaylandSocketDir = @"WaylandSocketDir";
NSString *const kWWNPrefsWaylandDisplayNumber = @"WaylandDisplayNumber";
NSString *const kWWNPrefsEnableVulkanDrivers = @"VulkanDriversEnabled";
NSString *const kWWNPrefsEnableDmabuf = @"DmabufEnabled";
NSString *const kWWNPrefsVulkanDriver = @"VulkanDriver";
NSString *const kWWNPrefsOpenGLDriver = @"OpenGLDriver";
NSString *const kWWNPrefsCompositorBackend = @"CompositorBackend";
NSString *const kWWNPrefsRespectSafeArea = @"RespectSafeArea";
// Matches Android prefs key (camelCase) for cross-platform sync.
NSString *const kWWNPrefsResizeDisplayForVirtualKeyboard =
    @"resizeDisplayForVirtualKeyboard";
NSString *const kWWNPrefsExternalDisplayTouchpad = @"ExternalDisplayTouchpad";
NSString *const kWWNPrefsHasSeenWelcome = @"HasSeenWelcome";
// Waypipe configuration keys
NSString *const kWWNPrefsWaypipeDisplay = @"WaypipeDisplay";
NSString *const kWWNPrefsWaypipeSocket = @"WaypipeSocket";
NSString *const kWWNPrefsWaypipeCompress = @"WaypipeCompress";
NSString *const kWWNPrefsWaypipeCompressLevel = @"WaypipeCompressLevel";
NSString *const kWWNPrefsWaypipeThreads = @"WaypipeThreads";
NSString *const kWWNPrefsWaypipeVideo = @"WaypipeVideo";
NSString *const kWWNPrefsWaypipeVideoEncoding = @"WaypipeVideoEncoding";
NSString *const kWWNPrefsWaypipeVideoDecoding = @"WaypipeVideoDecoding";
NSString *const kWWNPrefsWaypipeVideoBpf = @"WaypipeVideoBpf";
NSString *const kWWNPrefsWaypipeSSHEnabled = @"WaypipeSSHEnabled";
NSString *const kWWNPrefsWaypipeSSHHost = @"WaypipeSSHHost";
NSString *const kWWNPrefsWaypipeSSHUser = @"WaypipeSSHUser";
NSString *const kWWNPrefsWaypipeSSHBinary = @"WaypipeSSHBinary";
NSString *const kWWNPrefsWaypipeSSHAuthMethod = @"WaypipeSSHAuthMethod";
NSString *const kWWNPrefsWaypipeSSHKeyPath = @"WaypipeSSHKeyPath";
NSString *const kWWNPrefsWaypipeSSHKeyPassphrase = @"WaypipeSSHKeyPassphrase";
NSString *const kWWNPrefsWaypipeSSHPassword = @"WaypipeSSHPassword";
NSString *const kWWNPrefsWaypipeRemoteCommand = @"WaypipeRemoteCommand";
NSString *const kWWNPrefsWaypipeCustomScript = @"WaypipeCustomScript";
NSString *const kWWNPrefsWaypipeDebug = @"WaypipeDebug";
NSString *const kWWNPrefsWaypipeNoGpu = @"WaypipeNoGpu";
NSString *const kWWNPrefsWaypipeOneshot = @"WaypipeOneshot";
NSString *const kWWNPrefsWaypipeUnlinkSocket = @"WaypipeUnlinkSocket";
NSString *const kWWNPrefsWaypipeLoginShell = @"WaypipeLoginShell";
NSString *const kWWNPrefsWaypipeVsock = @"WaypipeVsock";
NSString *const kWWNPrefsWaypipeXwls = @"WaypipeXwls";
NSString *const kWWNPrefsWaypipeTitlePrefix = @"WaypipeTitlePrefix";
NSString *const kWWNPrefsWaypipeSecCtx = @"WaypipeSecCtx";
NSString *const kWWNPrefsMachineVMProvider = @"MachineVMProvider";
NSString *const kWWNPrefsMachineVMVsockPort = @"MachineVMVsockPort";
NSString *const kWWNPrefsMachineContainerRuntime = @"MachineContainerRuntime";
NSString *const kWWNPrefsMachineContainerImageStore =
    @"MachineContainerImageStore";
// Global container defaults (Settings → Containers)
NSString *const kWWNPrefsContainerDefaultImage = @"ContainerDefaultImage";
NSString *const kWWNPrefsContainerDefaultCommand = @"ContainerDefaultCommand";
NSString *const kWWNPrefsContainerMemory = @"ContainerMemory";
NSString *const kWWNPrefsContainerShmSize = @"ContainerShmSize";
NSString *const kWWNPrefsContainerKernelPath = @"ContainerKernelPath";
NSString *const kWWNPrefsContainerInitfsPath = @"ContainerInitfsPath";
NSString *const kWWNPrefsContainerVsockPort = @"ContainerVsockPort";
// SSH configuration keys (separate from Waypipe)
NSString *const kWWNPrefsSSHHost = @"SSHHost";
NSString *const kWWNPrefsSSHUser = @"SSHUser";
NSString *const kWWNPrefsSSHPort = @"SSHPort";
NSString *const kWWNPrefsSSHAuthMethod = @"SSHAuthMethod";
NSString *const kWWNPrefsSSHPassword = @"SSHPassword";
NSString *const kWWNPrefsSSHKeyPath = @"SSHKeyPath";
NSString *const kWWNPrefsSSHKeyPassphrase = @"SSHKeyPassphrase";
NSString *const kWWNPrefsWaypipeUseSSHConfig = @"WaypipeUseSSHConfig";
NSString *const kWWNForceSSDChangedNotification =
    @"WWNForceSSDChangedNotification";
/// Posted by Swift `WawonaPreferences.save()` after writing canonical keys.
static NSString *const kWWNWawonaPreferencesDidSaveNotification =
    @"WawonaPreferencesDidSave";
NSString *const kWWNPrefsMachineSessionThumbnailsEnabled =
    @"MachineSessionThumbnailsEnabled";
NSString *const kWWNPrefsDesktopReplacementEnabled =
    @"DesktopReplacementEnabled";
NSString *const kWWNPrefsDesktopReplacementMachineId =
    @"DesktopReplacementMachineId";
NSString *const kWWNPrefsSwingingBridgeEnabled = @"SwingingBridgeEnabled";
NSString *const kWWNPrefsAnowaWEnabled = @"AnowaWEnabled";
NSString *const kWWNPrefsLockscreenReplacementEnabled =
    @"LockscreenReplacementEnabled";
NSString *const kWWNPrefsLockscreenReplacementMachineId =
    @"LockscreenReplacementMachineId";

static NSString *WWNPreferredSharedRuntimeDir(void) {
  return [WWNPreferencesManager preferredSharedRuntimeDir];
}

NSUserDefaults *WWNSharedUserDefaults(void) {
#ifdef WWN_PREFPANE
  static NSUserDefaults *suite;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    suite = [[NSUserDefaults alloc]
        initWithSuiteName:@"com.aspauldingcode.Wawona"];
  });
  return suite;
#else
  return [NSUserDefaults standardUserDefaults];
#endif
}

@implementation WWNPreferencesManager

+ (NSString *)preferredSharedRuntimeDir {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *dirError = nil;
#if TARGET_OS_SIMULATOR
  // Simulator: short path under host /tmp (CoreSimulator TMPDIR can be 150+).
  NSString *candidate =
      [NSString stringWithFormat:@"/tmp/wawona_sim_%u", (unsigned)getuid()];
#else
  // Device: prefer short /tmp path when writable (nested socket names fit).
  NSString *candidate =
      [NSString stringWithFormat:@"/tmp/wawona_dev_%u", (unsigned)getuid()];
#endif
  if ([fm createDirectoryAtPath:candidate
      withIntermediateDirectories:YES
                       attributes:@{NSFilePosixPermissions : @0700}
                            error:&dirError]) {
    return candidate;
  }

#if !TARGET_OS_SIMULATOR
  // Physical device: creating under /tmp is often EPERM. Fall back to the app
  // sandbox tmp (always writable). Nested sockets use +preferredNestedSocketName.
  NSString *sandbox = NSTemporaryDirectory();
  if (sandbox.length > 0) {
    if ([sandbox hasSuffix:@"/"]) {
      sandbox = [sandbox substringToIndex:sandbox.length - 1];
    }
    dirError = nil;
    if ([fm createDirectoryAtPath:sandbox
        withIntermediateDirectories:YES
                         attributes:@{NSFilePosixPermissions : @0700}
                              error:&dirError]) {
      return sandbox;
    }
  }
#endif
  (void)dirError;
  return candidate;
#else
  return [NSString stringWithFormat:@"/tmp/wawona-%u", (unsigned)getuid()];
#endif
}

+ (NSString *)preferredNestedSocketName {
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  return @"nested";
#else
  return @"wawona-nested";
#endif
}

- (BOOL)eglDriversEnabled {
  return NO;
}

- (void)setEglDriversEnabled:(BOOL)enabled {
  // No-op for now
}

+ (instancetype)sharedManager {
  static WWNPreferencesManager *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    // Set defaults if not already set
    [self setDefaultsIfNeeded];
    [self syncFromCanonicalWawonaPreferences];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleWawonaPreferencesDidSave:)
               name:kWWNWawonaPreferencesDidSaveNotification
             object:nil];
  }
  return self;
}

- (void)handleWawonaPreferencesDidSave:(NSNotification *)notification {
  (void)notification;
  [self syncFromCanonicalWawonaPreferences];
}

- (void)syncFromCanonicalWawonaPreferences {
  NSUserDefaults *defaults = WWNSharedUserDefaults();
  NSString *prefix = @"wawona.pref.";

  id forceSSD = [defaults objectForKey:[prefix stringByAppendingString:@"forceSSD"]];
  if ([forceSSD respondsToSelector:@selector(boolValue)]) {
    [self setForceServerSideDecorations:[forceSSD boolValue]];
  }

  id autoScale = [defaults objectForKey:[prefix stringByAppendingString:@"autoScale"]];
  if ([autoScale respondsToSelector:@selector(boolValue)]) {
    [self setAutoScale:[autoScale boolValue]];
  }

  NSString *waylandDisplay =
      [defaults stringForKey:[prefix stringByAppendingString:@"waylandDisplay"]];
  if (waylandDisplay.length > 0) {
    [self setWaypipeDisplay:waylandDisplay];
  }

  NSString *sshHost = [defaults stringForKey:[prefix stringByAppendingString:@"sshHost"]];
  if (sshHost.length > 0) {
    [self setWaypipeSSHHost:sshHost];
  }
  NSString *sshUser = [defaults stringForKey:[prefix stringByAppendingString:@"sshUser"]];
  if (sshUser.length > 0) {
    [self setWaypipeSSHUser:sshUser];
  }
  NSNumber *sshPort = [defaults objectForKey:[prefix stringByAppendingString:@"sshPort"]];
  if ([sshPort respondsToSelector:@selector(integerValue)]) {
    [self setSshPort:[sshPort integerValue]];
  }
  NSString *sshPassword =
      [defaults stringForKey:[prefix stringByAppendingString:@"sshPassword"]];
  if (sshPassword.length > 0) {
    [self setWaypipeSSHPassword:sshPassword];
  }

  NSString *inputProfile =
      [defaults stringForKey:[prefix stringByAppendingString:@"defaultInputProfile"]];
  if (inputProfile.length > 0) {
    NSString *lower = inputProfile.lowercaseString;
    if ([lower isEqualToString:@"touchpad"] ||
        [lower isEqualToString:@"pointer"] ||
        [lower isEqualToString:@"virtual"] ||
        [lower isEqualToString:@"trackpad"]) {
      [self setTouchInputType:@"Touchpad"];
    } else {
      /* "direct", "multi-touch", "Multi-Touch", … */
      [self setTouchInputType:@"Multi-Touch"];
    }
  }

  NSString *renderer = [defaults stringForKey:[prefix stringByAppendingString:@"renderer"]];
  if (renderer.length > 0) {
    // Canonical preferences use renderer labels, while native path selects
    // Vulkan driver implementation.
    [self setVulkanDriver:[renderer isEqualToString:@"metal"] ? @"moltenvk" : renderer];
  }

  BOOL hasWaypipeEnabled =
      [defaults objectForKey:[prefix stringByAppendingString:@"defaultWaypipeEnabled"]] != nil;
  if (hasWaypipeEnabled) {
    [self setWaypipeSSHEnabled:[defaults
                                   boolForKey:[prefix
                                                  stringByAppendingString:
                                                      @"defaultWaypipeEnabled"]]];
  }

  id xwaylandSupport =
      [defaults objectForKey:[prefix stringByAppendingString:@"xwaylandSupport"]];
  if (xwaylandSupport != nil &&
      [xwaylandSupport respondsToSelector:@selector(boolValue)]) {
    [self setWaypipeXwls:[xwaylandSupport boolValue]];
  }

  // Do not rewrite live launcher flags from canonical defaults here.
  // This sync runs during GUI machine connect; forcing a single bundled app
  // would flip other client toggles to false and terminate already-running
  // native clients via KVO observers.
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  [super observeValueForKeyPath:keyPath
                       ofObject:object
                         change:change
                        context:context];
}

- (void)setDefaultsIfNeeded {
  NSUserDefaults *defaults = WWNSharedUserDefaults();

  // Register all defaults in one canonical place.
  // These values are returned by NSUserDefaults when no explicit value is set.
  NSString *defaultSocketDir = WWNPreferredSharedRuntimeDir();
  NSString *defaultSocket =
      [defaultSocketDir stringByAppendingPathComponent:@"wayland-0"];

  [defaults registerDefaults:@{
    // Display
    kWWNPrefsForceServerSideDecorations :
#if TARGET_OS_TV
        @YES,
#else
        @NO,
#endif
    kWWNPrefsAutoScale : @YES,
    kWWNPrefsRespectSafeArea : @YES,
    kWWNPrefsResizeDisplayForVirtualKeyboard : @YES,
    kWWNPrefsExternalDisplayTouchpad : @YES,
    kWWNPrefsHasSeenWelcome : @NO,
    kWWNPrefsRenderMacOSPointer : @NO,
    kWWNPrefsNestedCompositorCursor : @"virtual",
    // Input
    // Multi-Touch (wl_touch) is the reliable path for Wayland clients (Weston
    // panel, terminals, nested compositors). Touchpad/virtual-pointer is opt-in.
    kWWNPrefsTouchInputType : @"Multi-Touch",
    kWWNPrefsSwapCmdWithAlt : @YES,
    kWWNPrefsUniversalClipboard : @YES,
    // Graphics
    kWWNPrefsEnableVulkanDrivers : @YES,
    kWWNPrefsEnableDmabuf : @YES,
    kWWNPrefsVulkanDriver : [WWNPreferencesManager defaultVulkanDriverForHardware],
    kWWNPrefsOpenGLDriver :
        [WWNPreferencesManager defaultOpenGLDriverForHardware],
    kWWNPrefsCompositorBackend : @"auto",
    // Connection
    kWWNPrefsTCPListenerPort : @6000,
    kWWNPrefsWaylandSocketDir : defaultSocketDir,
    kWWNPrefsWaylandDisplayNumber : @0,
    // Advanced
    kWWNPrefsColorOperations : @YES,
    kWWNPrefsNestedCompositorsSupport : @YES,
#if TARGET_OS_OSX
    kWWNPrefsNestedWestonBackend : @"iland-drm-gl",
#else
    kWWNPrefsNestedWestonBackend : @"wayland-pixman",
#endif
    kWWNPrefsMultipleClients : @YES,
    kWWNPrefsMachineSessionThumbnailsEnabled : @YES,
    // Desktop Replacement (macOS Mode B; off by default, SIP-gated)
    kWWNPrefsDesktopReplacementEnabled : @NO,
    kWWNPrefsLockscreenReplacementEnabled : @NO,
    kWWNPrefsDesktopReplacementMachineId : @"",
    kWWNPrefsSwingingBridgeEnabled : @NO,
    kWWNPrefsAnowaWEnabled : @NO,
    // Waypipe
    kWWNPrefsWaypipeDisplay : @"wayland-0",
    kWWNPrefsWaypipeSocket : defaultSocket,
    kWWNPrefsWaypipeCompress : @"lz4",
    kWWNPrefsWaypipeCompressLevel : @"7",
    kWWNPrefsWaypipeThreads : @"0",
    kWWNPrefsWaypipeVideo : @"none",
    kWWNPrefsWaypipeVideoEncoding : @"hw",
    kWWNPrefsWaypipeVideoDecoding : @"hw",
    kWWNPrefsWaypipeVideoBpf : @"",
    kWWNPrefsWaypipeSSHEnabled : @YES,
    kWWNPrefsWaypipeSSHHost : @"",
    kWWNPrefsWaypipeSSHUser : @"",
    kWWNPrefsWaypipeSSHBinary : @"ssh",
    kWWNPrefsWaypipeSSHAuthMethod : @0,
    kWWNPrefsWaypipeSSHKeyPath : @"",
    kWWNPrefsWaypipeRemoteCommand : @"",
    kWWNPrefsWaypipeCustomScript : @"",
    kWWNPrefsWaypipeDebug : @NO,
    kWWNPrefsWaypipeNoGpu : @NO,
    kWWNPrefsWaypipeOneshot : @NO,
    kWWNPrefsWaypipeUnlinkSocket : @NO,
    kWWNPrefsWaypipeLoginShell : @NO,
    kWWNPrefsWaypipeVsock : @NO,
    kWWNPrefsWaypipeXwls : @NO,
    kWWNPrefsWaypipeTitlePrefix : @"",
    kWWNPrefsWaypipeSecCtx : @"",
    kWWNPrefsWaypipeUseSSHConfig : @YES,
    // Machine engines: wwn-vms VM provider + wwn-containers OCI runtime. The
    // container runtime default is capability-driven per target (Apple
    // Containerization on macOS; container-in-VM elsewhere).
    kWWNPrefsMachineVMProvider : @"nixos-vm",
    kWWNPrefsMachineVMVsockPort : @"1024",
#if TARGET_OS_OSX
    kWWNPrefsMachineContainerRuntime : @"containerization",
#else
    kWWNPrefsMachineContainerRuntime : @"container-in-vm",
#endif
    kWWNPrefsMachineContainerImageStore : @"~/.local/share/wawona/oci",
    // Global container defaults (empty = CLI default; image + command form the
    // one-shot `container run <image> <command>` baseline).
    kWWNPrefsContainerDefaultImage : @"alpine:3.20",
    kWWNPrefsContainerDefaultCommand : @"/bin/sh",
    kWWNPrefsContainerMemory : @"",
    kWWNPrefsContainerShmSize : @"",
    kWWNPrefsContainerKernelPath : @"",
    kWWNPrefsContainerInitfsPath : @"",
    kWWNPrefsContainerVsockPort : @"1024",
    // SSH
    kWWNPrefsSSHHost : @"",
    kWWNPrefsSSHUser : @"",
    kWWNPrefsSSHPort : @22,
    kWWNPrefsSSHAuthMethod : @0,
    kWWNPrefsSSHKeyPath : @"",
    // Legacy / deprecated (kept for migration)
    kWWNPrefsWaypipeRSSupport : @NO,
    kWWNPrefsEnableTCPListener : @NO,
    kWWNPrefsUseMetal4ForNested : @NO,
  }];

  // Migration: convert old renamed keys to new unified keys.
  // AutoRetinaScaling -> AutoScale
  if ([defaults objectForKey:kWWNPrefsAutoRetinaScaling] &&
      ![defaults objectForKey:kWWNPrefsAutoScale]) {
    [defaults setBool:[defaults boolForKey:kWWNPrefsAutoRetinaScaling]
               forKey:kWWNPrefsAutoScale];
  }
  // ColorSyncSupport -> ColorOperations
  if ([defaults objectForKey:kWWNPrefsColorSyncSupport] &&
      ![defaults objectForKey:kWWNPrefsColorOperations]) {
    [defaults setBool:[defaults boolForKey:kWWNPrefsColorSyncSupport]
               forKey:kWWNPrefsColorOperations];
  }
  // SwapCmdAsCtrl -> SwapCmdWithAlt
  if ([defaults objectForKey:kWWNPrefsSwapCmdAsCtrl] &&
      ![defaults objectForKey:kWWNPrefsSwapCmdWithAlt]) {
    [defaults setBool:[defaults boolForKey:kWWNPrefsSwapCmdAsCtrl]
               forKey:kWWNPrefsSwapCmdWithAlt];
  }
  // EnableVulkanDrivers (old) -> VulkanDriversEnabled (new)
  if ([defaults objectForKey:@"EnableVulkanDrivers"] &&
      ![defaults objectForKey:kWWNPrefsEnableVulkanDrivers]) {
    [defaults setBool:[defaults boolForKey:@"EnableVulkanDrivers"]
               forKey:kWWNPrefsEnableVulkanDrivers];
    [defaults removeObjectForKey:@"EnableVulkanDrivers"];
  }
  // EnableDmabuf (old) -> DmabufEnabled (new)
  if ([defaults objectForKey:@"EnableDmabuf"] &&
      ![defaults objectForKey:kWWNPrefsEnableDmabuf]) {
    [defaults setBool:[defaults boolForKey:@"EnableDmabuf"]
               forKey:kWWNPrefsEnableDmabuf];
    [defaults removeObjectForKey:@"EnableDmabuf"];
  }
  // VulkanDriversEnabled (bool) -> VulkanDriver (string) migration
  if (![defaults objectForKey:kWWNPrefsVulkanDriver]) {
    if ([defaults boolForKey:kWWNPrefsEnableVulkanDrivers]) {
      [defaults setObject:@"moltenvk" forKey:kWWNPrefsVulkanDriver];
    } else {
      [defaults setObject:@"none" forKey:kWWNPrefsVulkanDriver];
    }
  }

  // tvOS GPU Phase 1 shipped MoltenVK with OpenGLDriver=none. registerDefaults
  // does not overwrite an existing key, so GLES / KMS cubes stayed refused.
  // One-shot: leftover none (or a missing key) becomes ANGLE. After this,
  // Settings → Graphics None remains a real efficiency mode.
#if TARGET_OS_TV
#if defined(WWN_TVOS_GPU_BUNDLED) && WWN_TVOS_GPU_BUNDLED
  if (![defaults boolForKey:kWWNTvosOpenGLDriverMigrated]) {
    NSString *gl = [defaults stringForKey:kWWNPrefsOpenGLDriver];
    if (gl.length == 0 || [gl isEqualToString:@"none"]) {
      [defaults setObject:@"angle" forKey:kWWNPrefsOpenGLDriver];
    }
    [WWNMachineProfileStore migrateTvosGpuOpenGLDriverSnapshotsIfNeeded];
    [defaults setBool:YES forKey:kWWNTvosOpenGLDriverMigrated];
    [defaults synchronize];
  }
#endif
#endif
}

- (void)resetToDefaults {
  NSUserDefaults *defaults = WWNSharedUserDefaults();
  // Display
  [defaults removeObjectForKey:kWWNPrefsForceServerSideDecorations];
  [defaults removeObjectForKey:kWWNPrefsAutoScale];
  [defaults removeObjectForKey:kWWNPrefsAutoRetinaScaling];
  [defaults removeObjectForKey:kWWNPrefsRespectSafeArea];
  [defaults removeObjectForKey:kWWNPrefsResizeDisplayForVirtualKeyboard];
  [defaults removeObjectForKey:kWWNPrefsHasSeenWelcome];
  [defaults removeObjectForKey:kWWNPrefsRenderMacOSPointer];
  [defaults removeObjectForKey:kWWNPrefsNestedCompositorCursor];
  // Input
  [defaults removeObjectForKey:kWWNPrefsTouchInputType];
  [defaults removeObjectForKey:kWWNPrefsSwapCmdWithAlt];
  [defaults removeObjectForKey:kWWNPrefsSwapCmdAsCtrl];
  [defaults removeObjectForKey:kWWNPrefsUniversalClipboard];
  // Graphics
  [defaults removeObjectForKey:kWWNPrefsEnableVulkanDrivers];
  [defaults removeObjectForKey:kWWNPrefsEnableDmabuf];
  [defaults removeObjectForKey:kWWNPrefsVulkanDriver];
  [defaults removeObjectForKey:kWWNPrefsOpenGLDriver];
  [defaults removeObjectForKey:kWWNPrefsCompositorBackend];
  // Connection
  [defaults removeObjectForKey:kWWNPrefsTCPListenerPort];
  [defaults removeObjectForKey:kWWNPrefsWaylandSocketDir];
  [defaults removeObjectForKey:kWWNPrefsWaylandDisplayNumber];
  // Advanced
  [defaults removeObjectForKey:kWWNPrefsColorOperations];
  [defaults removeObjectForKey:kWWNPrefsColorSyncSupport];
  [defaults removeObjectForKey:kWWNPrefsNestedCompositorsSupport];
  [defaults removeObjectForKey:kWWNPrefsUseMetal4ForNested];
  [defaults removeObjectForKey:kWWNPrefsMultipleClients];
  [defaults removeObjectForKey:kWWNPrefsMachineSessionThumbnailsEnabled];
  // Waypipe
  [defaults removeObjectForKey:kWWNPrefsWaypipeDisplay];
  [defaults removeObjectForKey:kWWNPrefsWaypipeSocket];
  [defaults removeObjectForKey:kWWNPrefsWaypipeCompress];
  [defaults removeObjectForKey:kWWNPrefsWaypipeCompressLevel];
  [defaults removeObjectForKey:kWWNPrefsWaypipeThreads];
  [defaults removeObjectForKey:kWWNPrefsWaypipeVideo];
  [defaults removeObjectForKey:kWWNPrefsWaypipeVideoEncoding];
  [defaults removeObjectForKey:kWWNPrefsWaypipeVideoDecoding];
  [defaults removeObjectForKey:kWWNPrefsWaypipeVideoBpf];
  [defaults removeObjectForKey:kWWNPrefsWaypipeUseSSHConfig];
  [defaults removeObjectForKey:kWWNPrefsWaypipeRemoteCommand];
  [defaults removeObjectForKey:kWWNPrefsWaypipeDebug];
  [defaults removeObjectForKey:kWWNPrefsWaypipeNoGpu];
  [defaults removeObjectForKey:kWWNPrefsWaypipeOneshot];
  [defaults removeObjectForKey:kWWNPrefsWaypipeUnlinkSocket];
  [defaults removeObjectForKey:kWWNPrefsWaypipeLoginShell];
  [defaults removeObjectForKey:kWWNPrefsWaypipeVsock];
  [defaults removeObjectForKey:kWWNPrefsWaypipeXwls];
  [defaults removeObjectForKey:kWWNPrefsWaypipeTitlePrefix];
  [defaults removeObjectForKey:kWWNPrefsWaypipeSecCtx];
  [defaults removeObjectForKey:kWWNPrefsWaypipeCustomScript];
  [defaults removeObjectForKey:kWWNPrefsMachineVMProvider];
  [defaults removeObjectForKey:kWWNPrefsMachineVMVsockPort];
  [defaults removeObjectForKey:kWWNPrefsMachineContainerRuntime];
  [defaults removeObjectForKey:kWWNPrefsMachineContainerImageStore];
  [defaults removeObjectForKey:kWWNPrefsContainerDefaultImage];
  [defaults removeObjectForKey:kWWNPrefsContainerDefaultCommand];
  [defaults removeObjectForKey:kWWNPrefsContainerMemory];
  [defaults removeObjectForKey:kWWNPrefsContainerShmSize];
  [defaults removeObjectForKey:kWWNPrefsContainerKernelPath];
  [defaults removeObjectForKey:kWWNPrefsContainerInitfsPath];
  [defaults removeObjectForKey:kWWNPrefsContainerVsockPort];
  // SSH
  [defaults removeObjectForKey:kWWNPrefsSSHHost];
  [defaults removeObjectForKey:kWWNPrefsSSHUser];
  [defaults removeObjectForKey:kWWNPrefsSSHPort];
  [defaults removeObjectForKey:kWWNPrefsSSHAuthMethod];
  [defaults removeObjectForKey:kWWNPrefsSSHKeyPath];
  // Deprecated / legacy
  [defaults removeObjectForKey:kWWNPrefsWaypipeRSSupport];
  [defaults removeObjectForKey:kWWNPrefsEnableTCPListener];
  // Re-register defaults
  [self setDefaultsIfNeeded];
}

// Universal Clipboard
- (BOOL)universalClipboardEnabled {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsUniversalClipboard];
}

- (void)setUniversalClipboardEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsUniversalClipboard];
}

// Window Decorations
- (BOOL)forceServerSideDecorations {
#if TARGET_OS_TV
  return YES;
#else
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsForceServerSideDecorations];
#endif
}

- (void)setForceServerSideDecorations:(BOOL)enabled {
  if ([self forceServerSideDecorations] == enabled) {
    return;
  }
  [WWNSharedUserDefaults()
      setBool:enabled
       forKey:kWWNPrefsForceServerSideDecorations];
  // Keep the Swift mirror key in sync so MachineSettings / WawonaPreferences
  // and the ObjC compositor path never disagree.
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:@"wawona.pref.forceSSD"];

  // Post notification for hot-reload (bridge + any UI observers).
  [[NSNotificationCenter defaultCenter]
      postNotificationName:kWWNForceSSDChangedNotification
                    object:self];
}

// Display
- (BOOL)autoRetinaScalingEnabled {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsAutoRetinaScaling];
}

- (void)setAutoRetinaScalingEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsAutoRetinaScaling];
}

// Color Management
- (BOOL)colorSyncSupportEnabled {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsColorSyncSupport];
}

- (void)setColorSyncSupportEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsColorSyncSupport];
}

// Nested Compositors
- (BOOL)nestedCompositorsSupportEnabled {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsNestedCompositorsSupport];
}

- (void)setNestedCompositorsSupportEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults()
      setBool:enabled
       forKey:kWWNPrefsNestedCompositorsSupport];
}

- (NSString *)nestedWestonBackend {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsNestedWestonBackend];
  if (value.length == 0) {
#if TARGET_OS_OSX
    return @"iland-drm-gl";
#else
    return @"wayland-pixman";
#endif
  }
#if !TARGET_OS_OSX
  // Stored iland-drm-gl (old iOS-device default) must not keep launching
  // blank DRM Weston. Honour drm only via Display Backend = drm.
  if ([value isEqualToString:@"iland-drm-gl"] ||
      [value isEqualToString:@"drm"]) {
    NSString *cb = [self compositorBackend];
    if (![cb isEqualToString:@"drm"]) {
      return @"wayland-pixman";
    }
  }
#endif
#if TARGET_OS_SIMULATOR
  if ([value isEqualToString:@"iland-drm-gl"] ||
      [value isEqualToString:@"drm"]) {
    return @"wayland-pixman";
  }
#endif
  return value;
}

- (void)setNestedWestonBackend:(NSString *)backend {
#if TARGET_OS_OSX
  NSString *defaultBackend = @"iland-drm-gl";
#else
  NSString *defaultBackend = @"wayland-pixman";
#endif
  NSString *value =
      (backend.length > 0) ? backend : defaultBackend;
  [WWNSharedUserDefaults() setObject:value
                                            forKey:kWWNPrefsNestedWestonBackend];
}

- (BOOL)useMetal4ForNested {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsUseMetal4ForNested];
}

- (void)setUseMetal4ForNested:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsUseMetal4ForNested];
}

// Input
- (BOOL)renderMacOSPointer {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsRenderMacOSPointer];
}

- (void)setRenderMacOSPointer:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsRenderMacOSPointer];
}

- (NSString *)nestedCompositorCursor {
  NSString *mode = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsNestedCompositorCursor];
  if ([mode isEqualToString:@"host"] || [mode isEqualToString:@"virtual"]) {
    return mode;
  }
  return @"virtual";
}

- (void)setNestedCompositorCursor:(NSString *)mode {
  NSString *normalized =
      [mode isEqualToString:@"host"] ? @"host" : @"virtual";
  [WWNSharedUserDefaults() setObject:normalized
                                            forKey:kWWNPrefsNestedCompositorCursor];
}

- (BOOL)swapCmdAsCtrl {
  return
      [WWNSharedUserDefaults() boolForKey:kWWNPrefsSwapCmdAsCtrl];
}

- (void)setSwapCmdAsCtrl:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsSwapCmdAsCtrl];
}

// Client Management
- (BOOL)multipleClientsEnabled {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsMultipleClients];
}

- (void)setMultipleClientsEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsMultipleClients];
}

// Waypipe
- (BOOL)machineSessionThumbnailsEnabled {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsMachineSessionThumbnailsEnabled];
}

- (void)setMachineSessionThumbnailsEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults()
      setBool:enabled
       forKey:kWWNPrefsMachineSessionThumbnailsEnabled];
}

- (BOOL)waypipeRSSupportEnabled {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsWaypipeRSSupport];
}

- (void)setWaypipeRSSupportEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeRSSupport];
}

// Network / Remote Access
- (BOOL)enableTCPListener {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsEnableTCPListener];
}

- (void)setEnableTCPListener:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsEnableTCPListener];
}

- (NSInteger)tcpListenerPort {
  return [WWNSharedUserDefaults()
      integerForKey:kWWNPrefsTCPListenerPort];
}

- (void)setTCPListenerPort:(NSInteger)port {
  [WWNSharedUserDefaults() setInteger:port
                                             forKey:kWWNPrefsTCPListenerPort];
}

// Wayland Configuration
- (NSString *)waylandSocketDir {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *preferred = WWNPreferredSharedRuntimeDir();
  if (preferred.length > 0) {
    NSString *stored = [WWNSharedUserDefaults()
        stringForKey:kWWNPrefsWaylandSocketDir];
    if (![stored isEqualToString:preferred]) {
      [WWNSharedUserDefaults()
          setObject:preferred
             forKey:kWWNPrefsWaylandSocketDir];
    }
    return preferred;
  }
#endif

  NSString *dir = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaylandSocketDir];
  if (!dir) {
    const char *envDir = getenv("XDG_RUNTIME_DIR");
    if (envDir) {
      dir = [NSString stringWithUTF8String:envDir];
    } else {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      NSString *tmpDir = NSTemporaryDirectory();
      dir = [tmpDir stringByAppendingPathComponent:@"wayland-runtime"];
#else
      dir = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
#endif
    }
  }
  return dir;
}

- (void)setWaylandSocketDir:(NSString *)dir {
  [WWNSharedUserDefaults() setObject:dir
                                            forKey:kWWNPrefsWaylandSocketDir];
}

- (NSInteger)waylandDisplayNumber {
  return [WWNSharedUserDefaults()
      integerForKey:kWWNPrefsWaylandDisplayNumber];
}

- (void)setWaylandDisplayNumber:(NSInteger)number {
  [WWNSharedUserDefaults()
      setInteger:number
          forKey:kWWNPrefsWaylandDisplayNumber];
}

// Rendering Backend Flags (vulkanDriversEnabled derived from VulkanDriver for
// compatibility)
- (BOOL)vulkanDriversEnabled {
  NSString *driver = [self vulkanDriver];
  return driver && ![driver isEqualToString:@"none"];
}

- (void)setVulkanDriversEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsEnableVulkanDrivers];
  [self setVulkanDriver:enabled ? @"moltenvk" : @"none"];
}

// Dmabuf Support
- (BOOL)dmabufEnabled {
  return
      [WWNSharedUserDefaults() boolForKey:kWWNPrefsEnableDmabuf];
}

- (void)setDmabufEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsEnableDmabuf];
}

// Graphics Driver Selection
//
// ICD tiering (p9): KosmicKrisp is a native-Metal Vulkan driver that only
// exists for Apple Silicon on macOS 26+ (Tahoe). Everywhere else. Intel Macs,
// older macOS. MoltenVK is the only viable ICD. Pick KosmicKrisp as the
// default when the hardware supports it so users get the faster path, and fall
// back to MoltenVK otherwise. An explicit user choice always wins.
+ (NSString *)defaultVulkanDriverForHardware {
#if TARGET_OS_WATCH
  return @"none";
#elif TARGET_OS_TV
  return WWNPlatformAllowsGpuStack() ? @"moltenvk" : @"none";
#elif TARGET_OS_OSX
  int isARM64 = 0;
  size_t sz = sizeof(isARM64);
  if (sysctlbyname("hw.optional.arm64", &isARM64, &sz, NULL, 0) != 0) {
    isARM64 = 0;
  }
  BOOL macos26 = NO;
  if (@available(macOS 26.0, *)) {
    macos26 = YES;
  }
  if (isARM64 && macos26) {
    return @"kosmickrisp";
  }
#endif
  return @"moltenvk";
}

+ (NSString *)defaultOpenGLDriverForHardware {
#if TARGET_OS_WATCH
  return @"none";
#elif TARGET_OS_TV
  return WWNPlatformAllowsGlesStack() ? @"angle" : @"none";
#else
  return @"angle";
#endif
}

- (NSString *)vulkanDriver {
#if TARGET_OS_WATCH
  return @"none";
#elif TARGET_OS_TV
  if (!WWNPlatformAllowsGpuStack()) {
    return @"none";
  }
  NSString *driver =
      [WWNSharedUserDefaults() stringForKey:kWWNPrefsVulkanDriver];
  NSSet *allowed = [NSSet setWithArray:@[ @"none", @"moltenvk" ]];
  return [allowed containsObject:driver]
             ? driver
             : [WWNPreferencesManager defaultVulkanDriverForHardware];
#else
  NSString *driver =
      [WWNSharedUserDefaults() stringForKey:kWWNPrefsVulkanDriver];
#if TARGET_OS_OSX
  NSSet *allowed =
      [NSSet setWithArray:@[ @"none", @"moltenvk", @"kosmickrisp", @"swiftshader" ]];
#else
  NSSet *allowed = [NSSet setWithArray:@[ @"none", @"moltenvk" ]];
#endif
  return [allowed containsObject:driver]
             ? driver
             : [WWNPreferencesManager defaultVulkanDriverForHardware];
#endif
}

- (void)setVulkanDriver:(NSString *)driver {
  [WWNSharedUserDefaults() setObject:driver
                                            forKey:kWWNPrefsVulkanDriver];
}

- (NSString *)openglDriver {
#if TARGET_OS_WATCH
  return @"none";
#elif TARGET_OS_TV
  if (!WWNPlatformAllowsGlesStack()) {
    return @"none";
  }
  NSString *driver =
      [WWNSharedUserDefaults() stringForKey:kWWNPrefsOpenGLDriver];
  return [@[ @"none", @"angle" ] containsObject:driver]
             ? driver
             : [WWNPreferencesManager defaultOpenGLDriverForHardware];
#else
  NSString *driver =
      [WWNSharedUserDefaults() stringForKey:kWWNPrefsOpenGLDriver];
  return [@[ @"none", @"angle" ] containsObject:driver]
             ? driver
             : [WWNPreferencesManager defaultOpenGLDriverForHardware];
#endif
}

- (void)setOpenGLDriver:(NSString *)driver {
  [WWNSharedUserDefaults() setObject:driver
                                            forKey:kWWNPrefsOpenGLDriver];
}

- (NSString *)compositorBackend {
#if TARGET_OS_WATCH
  // watchOS GPU is blocked (no Metal). Nested Wayland only.
  return @"wayland";
#else
  NSString *backend = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsCompositorBackend];
  return [@[ @"auto", @"wayland", @"drm" ] containsObject:backend] ? backend
                                                                   : @"auto";
#endif
}

- (void)setCompositorBackend:(NSString *)backend {
  [WWNSharedUserDefaults()
      setObject:backend
         forKey:kWWNPrefsCompositorBackend];
}

// New unified display methods
- (BOOL)autoScale {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = WWNSharedUserDefaults();
  if ([defaults objectForKey:kWWNPrefsAutoScale]) {
    return [defaults boolForKey:kWWNPrefsAutoScale];
  }
  // Migrate from legacy key
  if ([defaults objectForKey:kWWNPrefsAutoRetinaScaling]) {
    BOOL value = [defaults boolForKey:kWWNPrefsAutoRetinaScaling];
    [defaults setBool:value forKey:kWWNPrefsAutoScale];
    return value;
  }
  return YES; // Default
}

- (void)setAutoScale:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsAutoScale];
}

- (BOOL)externalDisplayTouchpad {
  NSUserDefaults *defaults = WWNSharedUserDefaults();
  if ([defaults objectForKey:kWWNPrefsExternalDisplayTouchpad]) {
    return [defaults boolForKey:kWWNPrefsExternalDisplayTouchpad];
  }
  return YES; // Default: device becomes a trackpad on external displays
}

- (void)setExternalDisplayTouchpad:(BOOL)enabled {
  [WWNSharedUserDefaults()
      setBool:enabled
       forKey:kWWNPrefsExternalDisplayTouchpad];
}

- (BOOL)respectSafeArea {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsRespectSafeArea];
}

- (void)setRespectSafeArea:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsRespectSafeArea];
}

- (BOOL)resizeDisplayForVirtualKeyboard {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsResizeDisplayForVirtualKeyboard];
}

- (void)setResizeDisplayForVirtualKeyboard:(BOOL)enabled {
  [WWNSharedUserDefaults()
      setBool:enabled
       forKey:kWWNPrefsResizeDisplayForVirtualKeyboard];
}

- (BOOL)hasSeenWelcome {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsHasSeenWelcome];
}

- (void)setHasSeenWelcome:(BOOL)seen {
  [WWNSharedUserDefaults() setBool:seen
                                          forKey:kWWNPrefsHasSeenWelcome];
}

// New unified color management method
- (BOOL)colorOperations {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = WWNSharedUserDefaults();
  if ([defaults objectForKey:kWWNPrefsColorOperations]) {
    return [defaults boolForKey:kWWNPrefsColorOperations];
  }
  // Migrate from legacy key
  if ([defaults objectForKey:kWWNPrefsColorSyncSupport]) {
    BOOL value = [defaults boolForKey:kWWNPrefsColorSyncSupport];
    [defaults setBool:value forKey:kWWNPrefsColorOperations];
    return value;
  }
  return YES; // Default
}

- (void)setColorOperations:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsColorOperations];
}

// New unified input method
- (BOOL)swapCmdWithAlt {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = WWNSharedUserDefaults();
  if ([defaults objectForKey:kWWNPrefsSwapCmdWithAlt]) {
    return [defaults boolForKey:kWWNPrefsSwapCmdWithAlt];
  }
  // Migrate from legacy key
  if ([defaults objectForKey:kWWNPrefsSwapCmdAsCtrl]) {
    BOOL value = [defaults boolForKey:kWWNPrefsSwapCmdAsCtrl];
    [defaults setBool:value forKey:kWWNPrefsSwapCmdWithAlt];
    return value;
  }
  return YES; // Default on for macOS/iOS
}

- (void)setSwapCmdWithAlt:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsSwapCmdWithAlt];
}

- (NSString *)touchInputType {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsTouchInputType];
  return value ? value : @"Multi-Touch";
}

- (void)setTouchInputType:(NSString *)type {
  if (type) {
    [WWNSharedUserDefaults() setObject:type
                                              forKey:kWWNPrefsTouchInputType];
  } else {
    [WWNSharedUserDefaults()
        removeObjectForKey:kWWNPrefsTouchInputType];
  }
}

// Waypipe Configuration Methods
- (NSString *)waypipeDisplay {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeDisplay];
  if ([value isEqualToString:@"w0"] || [value isEqualToString:@"w-0"]) {
    value = @"wayland-0";
    [WWNSharedUserDefaults() setObject:value
                                              forKey:kWWNPrefsWaypipeDisplay];
  }
  return value.length > 0 ? value : @"wayland-0";
#else
  NSInteger displayNumber = [self waylandDisplayNumber];
  return [NSString stringWithFormat:@"wayland-%ld", (long)displayNumber];
#endif
}

- (void)setWaypipeDisplay:(NSString *)display {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if ([display isEqualToString:@"w0"] || [display isEqualToString:@"w-0"]) {
    display = @"wayland-0";
  }
  if (display.length > 0) {
    [WWNSharedUserDefaults() setObject:display
                                              forKey:kWWNPrefsWaypipeDisplay];
  } else {
    [WWNSharedUserDefaults()
        removeObjectForKey:kWWNPrefsWaypipeDisplay];
  }
#else
  if (display && display.length > 0) {
    NSInteger number = 0;
    if ([display hasPrefix:@"wayland-"]) {
      NSString *numberStr = [display substringFromIndex:8];
      number = [numberStr integerValue];
    } else {
      number = [display integerValue];
    }
    [self setWaylandDisplayNumber:number];
  }
#endif
}

- (NSString *)waypipeSocket {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *runtimeDir = WWNPreferredSharedRuntimeDir();
  if (runtimeDir.length > 0) {
    NSString *display = [self waypipeDisplay];
    if (display.length == 0) {
      display = @"wayland-0";
    }
    NSString *preferred = [runtimeDir stringByAppendingPathComponent:display];
    NSString *stored = [WWNSharedUserDefaults()
        stringForKey:kWWNPrefsWaypipeSocket];
    if (![stored isEqualToString:preferred]) {
      [WWNSharedUserDefaults() setObject:preferred
                                                forKey:kWWNPrefsWaypipeSocket];
    }
    return preferred;
  }
#endif

  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeSocket];
  if (!value) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    NSString *tmpDir = NSTemporaryDirectory();
    value = [tmpDir stringByAppendingPathComponent:@"waypipe"];
#else
    value =
        [NSString stringWithFormat:@"/tmp/wawona-waypipe-%d.sock", getuid()];
#endif
  }
  return value;
}

- (void)setWaypipeSocket:(NSString *)socket {
  [WWNSharedUserDefaults() setObject:socket
                                            forKey:kWWNPrefsWaypipeSocket];
}

- (NSString *)waypipeCompress {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeCompress];
  return value ? value : @"lz4";
}

- (void)setWaypipeCompress:(NSString *)compress {
  [WWNSharedUserDefaults() setObject:compress
                                            forKey:kWWNPrefsWaypipeCompress];
}

- (NSString *)waypipeCompressLevel {
  id value = [WWNSharedUserDefaults()
      objectForKey:kWWNPrefsWaypipeCompressLevel];
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    return [(NSNumber *)value stringValue];
  }
  return @"7";
}

- (void)setWaypipeCompressLevel:(NSString *)level {
  [WWNSharedUserDefaults()
      setObject:level
         forKey:kWWNPrefsWaypipeCompressLevel];
}

- (NSString *)waypipeThreads {
  id value = [WWNSharedUserDefaults()
      objectForKey:kWWNPrefsWaypipeThreads];
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    return [(NSNumber *)value stringValue];
  }
  return @"0";
}

- (void)setWaypipeThreads:(NSString *)threads {
  [WWNSharedUserDefaults() setObject:threads
                                            forKey:kWWNPrefsWaypipeThreads];
}

- (NSString *)waypipeVideo {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeVideo];
  return value ? value : @"none";
}

- (void)setWaypipeVideo:(NSString *)video {
  [WWNSharedUserDefaults() setObject:video
                                            forKey:kWWNPrefsWaypipeVideo];
}

- (NSString *)waypipeVideoEncoding {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeVideoEncoding];
  return value ? value : @"hw";
}

- (void)setWaypipeVideoEncoding:(NSString *)encoding {
  [WWNSharedUserDefaults()
      setObject:encoding
         forKey:kWWNPrefsWaypipeVideoEncoding];
}

- (NSString *)waypipeVideoDecoding {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeVideoDecoding];
  return value ? value : @"hw";
}

- (void)setWaypipeVideoDecoding:(NSString *)decoding {
  [WWNSharedUserDefaults()
      setObject:decoding
         forKey:kWWNPrefsWaypipeVideoDecoding];
}

- (NSString *)waypipeVideoBpf {
  id value = [WWNSharedUserDefaults()
      objectForKey:kWWNPrefsWaypipeVideoBpf];
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    double number = [(NSNumber *)value doubleValue];
    if (number > 0) {
      return [(NSNumber *)value stringValue];
    }
  }
  return @"";
}

- (void)setWaypipeVideoBpf:(NSString *)bpf {
  [WWNSharedUserDefaults() setObject:bpf
                                            forKey:kWWNPrefsWaypipeVideoBpf];
}

- (BOOL)waypipeSSHEnabled {
  // SSH is always enabled on iOS/macOS
  return YES;
}

- (void)setWaypipeSSHEnabled:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeSSHEnabled];
}

- (NSString *)waypipeSSHHost {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeSSHHost];
  return value ? value : @"";
}

- (void)setWaypipeSSHHost:(NSString *)host {
  [WWNSharedUserDefaults() setObject:host
                                            forKey:kWWNPrefsWaypipeSSHHost];
}

- (NSString *)waypipeSSHUser {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeSSHUser];
  return value ? value : @"";
}

- (void)setWaypipeSSHUser:(NSString *)user {
  [WWNSharedUserDefaults() setObject:user
                                            forKey:kWWNPrefsWaypipeSSHUser];
}

- (NSString *)waypipeSSHBinary {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeSSHBinary];
  return value ? value : @"ssh";
}

- (void)setWaypipeSSHBinary:(NSString *)binary {
  [WWNSharedUserDefaults() setObject:binary
                                            forKey:kWWNPrefsWaypipeSSHBinary];
}

- (NSInteger)waypipeSSHAuthMethod {
  NSInteger method = [WWNSharedUserDefaults()
      integerForKey:kWWNPrefsWaypipeSSHAuthMethod];
  return method; // 0 = password (default), 1 = public key
}

- (void)setWaypipeSSHAuthMethod:(NSInteger)method {
  [WWNSharedUserDefaults()
      setInteger:method
          forKey:kWWNPrefsWaypipeSSHAuthMethod];
}

- (NSString *)waypipeSSHKeyPath {
  return [WWNSharedUserDefaults()
             stringForKey:kWWNPrefsWaypipeSSHKeyPath]
             ?: @"";
}

- (void)setWaypipeSSHKeyPath:(NSString *)keyPath {
  [WWNSharedUserDefaults() setObject:keyPath
                                            forKey:kWWNPrefsWaypipeSSHKeyPath];
}

- (NSString *)waypipeSSHKeyPassphrase {
  return [WWNSharedUserDefaults()
             stringForKey:kWWNPrefsWaypipeSSHKeyPassphrase]
             ?: @"";
}

- (void)setWaypipeSSHKeyPassphrase:(NSString *)passphrase {
  if (passphrase && passphrase.length > 0) {
    [WWNSharedUserDefaults()
        setObject:passphrase
           forKey:kWWNPrefsWaypipeSSHKeyPassphrase];
  } else {
    [WWNSharedUserDefaults()
        removeObjectForKey:kWWNPrefsWaypipeSSHKeyPassphrase];
  }
}

- (NSString *)waypipeSSHPassword {
  return [WWNSharedUserDefaults()
             stringForKey:kWWNPrefsWaypipeSSHPassword]
             ?: @"";
}

- (void)setWaypipeSSHPassword:(NSString *)password {
  if (password && password.length > 0) {
    [WWNSharedUserDefaults()
        setObject:password
           forKey:kWWNPrefsWaypipeSSHPassword];
  } else {
    [WWNSharedUserDefaults()
        removeObjectForKey:kWWNPrefsWaypipeSSHPassword];
  }
}

- (NSString *)waypipeRemoteCommand {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeRemoteCommand];
  return value ? value : @"";
}

- (void)setWaypipeRemoteCommand:(NSString *)command {
  [WWNSharedUserDefaults()
      setObject:command
         forKey:kWWNPrefsWaypipeRemoteCommand];
}

// Container defaults (Settings → Containers). Per-machine containerSettings
// override these; empty strings pass through to the CLI's own defaults.
- (NSString *)containerDefaultImage {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsContainerDefaultImage];
  return value ? value : @"alpine:3.20";
}

- (void)setContainerDefaultImage:(NSString *)image {
  [[NSUserDefaults standardUserDefaults]
      setObject:image ?: @""
         forKey:kWWNPrefsContainerDefaultImage];
}

- (NSString *)containerDefaultCommand {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsContainerDefaultCommand];
  return value ? value : @"/bin/sh";
}

- (void)setContainerDefaultCommand:(NSString *)command {
  [[NSUserDefaults standardUserDefaults]
      setObject:command ?: @""
         forKey:kWWNPrefsContainerDefaultCommand];
}

- (NSString *)containerMemory {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsContainerMemory];
  return value ? value : @"";
}

- (void)setContainerMemory:(NSString *)memory {
  [[NSUserDefaults standardUserDefaults]
      setObject:memory ?: @""
         forKey:kWWNPrefsContainerMemory];
}

- (NSString *)containerShmSize {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsContainerShmSize];
  return value ? value : @"";
}

- (void)setContainerShmSize:(NSString *)shmSize {
  [[NSUserDefaults standardUserDefaults]
      setObject:shmSize ?: @""
         forKey:kWWNPrefsContainerShmSize];
}

- (NSString *)containerKernelPath {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsContainerKernelPath];
  return value ? value : @"";
}

- (void)setContainerKernelPath:(NSString *)path {
  [[NSUserDefaults standardUserDefaults]
      setObject:path ?: @""
         forKey:kWWNPrefsContainerKernelPath];
}

- (NSString *)containerInitfsPath {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsContainerInitfsPath];
  return value ? value : @"";
}

- (void)setContainerInitfsPath:(NSString *)path {
  [[NSUserDefaults standardUserDefaults]
      setObject:path ?: @""
         forKey:kWWNPrefsContainerInitfsPath];
}

- (NSString *)containerVsockPort {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsContainerVsockPort];
  return value ? value : @"1024";
}

- (void)setContainerVsockPort:(NSString *)port {
  [[NSUserDefaults standardUserDefaults]
      setObject:port ?: @"1024"
         forKey:kWWNPrefsContainerVsockPort];
}

- (NSString *)waypipeCustomScript {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeCustomScript];
  return value ? value : @"";
}

- (void)setWaypipeCustomScript:(NSString *)script {
  [WWNSharedUserDefaults()
      setObject:script
         forKey:kWWNPrefsWaypipeCustomScript];
}

- (BOOL)waypipeDebug {
  return
      [WWNSharedUserDefaults() boolForKey:kWWNPrefsWaypipeDebug];
}

- (void)setWaypipeDebug:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeDebug];
}

- (BOOL)waypipeNoGpu {
  return
      [WWNSharedUserDefaults() boolForKey:kWWNPrefsWaypipeNoGpu];
}

- (void)setWaypipeNoGpu:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeNoGpu];
}

- (BOOL)waypipeOneshot {
#if TARGET_OS_IPHONE
  // iOS App Store: SSH uses in-process libssh2 only; oneshot is always on.
  return YES;
#else
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsWaypipeOneshot];
#endif
}

- (void)setWaypipeOneshot:(BOOL)enabled {
#if !TARGET_OS_IPHONE
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeOneshot];
#endif
  // On iOS the getter always returns YES; no-op setter keeps UI from persisting
  // off.
}

- (BOOL)waypipeUnlinkSocket {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsWaypipeUnlinkSocket];
}

- (void)setWaypipeUnlinkSocket:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeUnlinkSocket];
}

- (BOOL)waypipeLoginShell {
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsWaypipeLoginShell];
}

- (void)setWaypipeLoginShell:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeLoginShell];
}

- (BOOL)waypipeVsock {
  return
      [WWNSharedUserDefaults() boolForKey:kWWNPrefsWaypipeVsock];
}

- (void)setWaypipeVsock:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeVsock];
}

- (BOOL)waypipeXwls {
  return
      [WWNSharedUserDefaults() boolForKey:kWWNPrefsWaypipeXwls];
}

- (void)setWaypipeXwls:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeXwls];
}

- (NSString *)waypipeTitlePrefix {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeTitlePrefix];
  return value ? value : @"";
}

- (void)setWaypipeTitlePrefix:(NSString *)prefix {
  [WWNSharedUserDefaults() setObject:prefix
                                            forKey:kWWNPrefsWaypipeTitlePrefix];
}

- (NSString *)waypipeSecCtx {
  NSString *value = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsWaypipeSecCtx];
  return value ? value : @"";
}

- (void)setWaypipeSecCtx:(NSString *)secCtx {
  [WWNSharedUserDefaults() setObject:secCtx
                                            forKey:kWWNPrefsWaypipeSecCtx];
}

- (BOOL)waypipeUseSSHConfig {
  // Default to YES if not set (use SSH config from OpenSSH section by default)
  if (![WWNSharedUserDefaults()
          objectForKey:kWWNPrefsWaypipeUseSSHConfig]) {
    return YES;
  }
  return [WWNSharedUserDefaults()
      boolForKey:kWWNPrefsWaypipeUseSSHConfig];
}

- (void)setWaypipeUseSSHConfig:(BOOL)enabled {
  [WWNSharedUserDefaults() setBool:enabled
                                          forKey:kWWNPrefsWaypipeUseSSHConfig];
}

// SSH Configuration (separate from Waypipe)
- (NSString *)sshHost {
  NSString *value =
      [WWNSharedUserDefaults() stringForKey:kWWNPrefsSSHHost];
  return value ? value : @"";
}

- (void)setSshHost:(NSString *)host {
  [WWNSharedUserDefaults() setObject:host
                                            forKey:kWWNPrefsSSHHost];
}

- (NSString *)sshUser {
  NSString *value =
      [WWNSharedUserDefaults() stringForKey:kWWNPrefsSSHUser];
  return value ? value : @"";
}

- (void)setSshUser:(NSString *)user {
  [WWNSharedUserDefaults() setObject:user
                                            forKey:kWWNPrefsSSHUser];
}

- (NSInteger)sshPort {
  NSInteger port = [WWNSharedUserDefaults() integerForKey:kWWNPrefsSSHPort];
  if (port <= 0) {
    return 22;
  }
  return port;
}

- (void)setSshPort:(NSInteger)port {
  NSInteger clamped = port;
  if (clamped < 1 || clamped > 65535) {
    clamped = 22;
  }
  [WWNSharedUserDefaults() setInteger:clamped
                                             forKey:kWWNPrefsSSHPort];
  // Keep waypipe port string in sync for Android/JNI host:port paths.
  [WWNSharedUserDefaults()
      setObject:[NSString stringWithFormat:@"%ld", (long)clamped]
         forKey:@"WaypipeSSHPort"];
}

- (NSInteger)sshAuthMethod {
  return [WWNSharedUserDefaults()
      integerForKey:kWWNPrefsSSHAuthMethod];
}

- (void)setSshAuthMethod:(NSInteger)method {
  [WWNSharedUserDefaults() setInteger:method
                                             forKey:kWWNPrefsSSHAuthMethod];
  // Keep WaypipeSSH* namespace in sync (Settings + Machines runtime).
  [WWNSharedUserDefaults()
      setInteger:method
          forKey:kWWNPrefsWaypipeSSHAuthMethod];
}

// Helper methods for preference storage
- (NSString *)getSecureValueForKey:(NSString *)key {
  NSString *value = [WWNSharedUserDefaults() stringForKey:key];
  return value ?: @"";
}

- (void)setSecureValue:(NSString *)value forKey:(NSString *)key {
  if (value && value.length > 0) {
    [WWNSharedUserDefaults() setObject:value forKey:key];
  } else {
    [WWNSharedUserDefaults() removeObjectForKey:key];
  }
}

- (NSString *)sshPassword {
  return [self getSecureValueForKey:kWWNPrefsSSHPassword];
}

- (void)setSshPassword:(NSString *)password {
  [self setSecureValue:password forKey:kWWNPrefsSSHPassword];
}

- (NSString *)sshKeyPath {
  NSString *value =
      [WWNSharedUserDefaults() stringForKey:kWWNPrefsSSHKeyPath];
  return value ? value : @"";
}

- (void)setSshKeyPath:(NSString *)keyPath {
  [WWNSharedUserDefaults() setObject:keyPath
                                            forKey:kWWNPrefsSSHKeyPath];
  [WWNSharedUserDefaults()
      setObject:keyPath ?: @""
         forKey:kWWNPrefsWaypipeSSHKeyPath];
}

- (NSString *)sshKeyPassphrase {
  return [self getSecureValueForKey:kWWNPrefsSSHKeyPassphrase];
}

- (void)setSshKeyPassphrase:(NSString *)passphrase {
  [self setSecureValue:passphrase forKey:kWWNPrefsSSHKeyPassphrase];
  [self setWaypipeSSHKeyPassphrase:passphrase];
}

@end
