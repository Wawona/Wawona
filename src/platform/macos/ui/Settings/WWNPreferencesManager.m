#import "WWNPreferencesManager.h"

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
NSString *const kWWNPrefsUseMetal4ForNested =
    @"UseMetal4ForNested"; // Deprecated
NSString *const kWWNPrefsRenderMacOSPointer = @"RenderMacOSPointer";
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
NSString *const kWWNPrefsRespectSafeArea = @"RespectSafeArea";
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
NSString *const kWWNPrefsMachineVMProviderStub = @"MachineVMProviderStub";
NSString *const kWWNPrefsMachineVMDefaultVsockStub =
    @"MachineVMDefaultVsockStub";
NSString *const kWWNPrefsMachineContainerRuntimeStub =
    @"MachineContainerRuntimeStub";
NSString *const kWWNPrefsMachineContainerNamespaceStub =
    @"MachineContainerNamespaceStub";
// SSH configuration keys (separate from Waypipe)
NSString *const kWWNPrefsSSHHost = @"SSHHost";
NSString *const kWWNPrefsSSHUser = @"SSHUser";
NSString *const kWWNPrefsSSHAuthMethod = @"SSHAuthMethod";
NSString *const kWWNPrefsSSHPassword = @"SSHPassword";
NSString *const kWWNPrefsSSHKeyPath = @"SSHKeyPath";
NSString *const kWWNPrefsSSHKeyPassphrase = @"SSHKeyPassphrase";
NSString *const kWWNPrefsWaypipeUseSSHConfig = @"WaypipeUseSSHConfig";
NSString *const kWWNForceSSDChangedNotification =
    @"WWNForceSSDChangedNotification";
NSString *const kWWNPrefsMachineSessionThumbnailsEnabled =
    @"MachineSessionThumbnailsEnabled";

static NSString *WWNPreferredSharedRuntimeDir(void) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#if TARGET_OS_SIMULATOR
  // Simulator: use a short path to stay within the 104-byte Unix socket
  // sun_path limit.  NSTemporaryDirectory() maps to the host's
  // CoreSimulator container path which can be 150+ chars.
  NSString *candidate =
      [NSString stringWithFormat:@"/tmp/wawona_sim_%u", (unsigned)getuid()];
#else
  // Device: NSTemporaryDirectory()/w — short enough on real hardware.
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *candidate = [tmpDir stringByAppendingPathComponent:@"w"];
#endif

  // Ensure the directory exists
  [[NSFileManager defaultManager] createDirectoryAtPath:candidate
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  return candidate;
#else
  // macOS canonical runtime path used by compositor host and launch agents.
  return [NSString stringWithFormat:@"/tmp/wawona-%u", (unsigned)getuid()];
#endif
}

@implementation WWNPreferencesManager

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
  }
  return self;
}

- (void)syncFromCanonicalWawonaPreferences {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
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
  NSString *sshPassword =
      [defaults stringForKey:[prefix stringByAppendingString:@"sshPassword"]];
  if (sshPassword.length > 0) {
    [self setWaypipeSSHPassword:sshPassword];
  }

  NSString *inputProfile =
      [defaults stringForKey:[prefix stringByAppendingString:@"defaultInputProfile"]];
  if (inputProfile.length > 0) {
    [self setTouchInputType:inputProfile];
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
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  // Register all defaults in one canonical place.
  // These values are returned by NSUserDefaults when no explicit value is set.
  NSString *defaultSocketDir = WWNPreferredSharedRuntimeDir();
  NSString *defaultSocket =
      [defaultSocketDir stringByAppendingPathComponent:@"wayland-0"];

  [defaults registerDefaults:@{
    // Display
    kWWNPrefsForceServerSideDecorations : @NO,
    kWWNPrefsAutoScale : @YES,
    kWWNPrefsRespectSafeArea : @YES,
    kWWNPrefsHasSeenWelcome : @NO,
    kWWNPrefsRenderMacOSPointer : @NO,
    // Input
    kWWNPrefsTouchInputType : @"Multi-Touch",
    kWWNPrefsSwapCmdWithAlt : @YES,
    kWWNPrefsUniversalClipboard : @YES,
    // Graphics
    kWWNPrefsEnableVulkanDrivers : @YES,
    kWWNPrefsEnableDmabuf : @YES,
    kWWNPrefsVulkanDriver : @"moltenvk",
    kWWNPrefsOpenGLDriver : @"angle",
    // Connection
    kWWNPrefsTCPListenerPort : @6000,
    kWWNPrefsWaylandSocketDir : defaultSocketDir,
    kWWNPrefsWaylandDisplayNumber : @0,
    // Advanced
    kWWNPrefsColorOperations : @NO,
    kWWNPrefsNestedCompositorsSupport : @YES,
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    kWWNPrefsMultipleClients : @NO,
#else
    kWWNPrefsMultipleClients : @YES,
#endif
    kWWNPrefsMachineSessionThumbnailsEnabled : @YES,
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
    // Machine stubs (v0.2.3)
    kWWNPrefsMachineVMProviderStub : @"utm-se",
    kWWNPrefsMachineVMDefaultVsockStub : @"1024",
    kWWNPrefsMachineContainerRuntimeStub : @"docker",
    kWWNPrefsMachineContainerNamespaceStub : @"default",
    // SSH
    kWWNPrefsSSHHost : @"",
    kWWNPrefsSSHUser : @"",
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
}

- (void)resetToDefaults {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  // Display
  [defaults removeObjectForKey:kWWNPrefsForceServerSideDecorations];
  [defaults removeObjectForKey:kWWNPrefsAutoScale];
  [defaults removeObjectForKey:kWWNPrefsAutoRetinaScaling];
  [defaults removeObjectForKey:kWWNPrefsRespectSafeArea];
  [defaults removeObjectForKey:kWWNPrefsHasSeenWelcome];
  [defaults removeObjectForKey:kWWNPrefsRenderMacOSPointer];
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
  [defaults removeObjectForKey:kWWNPrefsMachineVMProviderStub];
  [defaults removeObjectForKey:kWWNPrefsMachineVMDefaultVsockStub];
  [defaults removeObjectForKey:kWWNPrefsMachineContainerRuntimeStub];
  [defaults removeObjectForKey:kWWNPrefsMachineContainerNamespaceStub];
  // SSH
  [defaults removeObjectForKey:kWWNPrefsSSHHost];
  [defaults removeObjectForKey:kWWNPrefsSSHUser];
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
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsUniversalClipboard];
}

- (void)setUniversalClipboardEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsUniversalClipboard];
}

// Window Decorations
- (BOOL)forceServerSideDecorations {
#if TARGET_OS_IPHONE
  // iOS: CSD not supported; Force SSD is always on.
  return YES;
#else
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsForceServerSideDecorations];
#endif
}

- (void)setForceServerSideDecorations:(BOOL)enabled {
#if !TARGET_OS_IPHONE
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWWNPrefsForceServerSideDecorations];

  // Post notification for hot-reload
  [[NSNotificationCenter defaultCenter]
      postNotificationName:kWWNForceSSDChangedNotification
                    object:self];
#endif
}

// Display
- (BOOL)autoRetinaScalingEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsAutoRetinaScaling];
}

- (void)setAutoRetinaScalingEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsAutoRetinaScaling];
}

// Color Management
- (BOOL)colorSyncSupportEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsColorSyncSupport];
}

- (void)setColorSyncSupportEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsColorSyncSupport];
}

// Nested Compositors
- (BOOL)nestedCompositorsSupportEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsNestedCompositorsSupport];
}

- (void)setNestedCompositorsSupportEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWWNPrefsNestedCompositorsSupport];
}

- (BOOL)useMetal4ForNested {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsUseMetal4ForNested];
}

- (void)setUseMetal4ForNested:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsUseMetal4ForNested];
}

// Input
- (BOOL)renderMacOSPointer {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsRenderMacOSPointer];
}

- (void)setRenderMacOSPointer:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsRenderMacOSPointer];
}

- (BOOL)swapCmdAsCtrl {
  return
      [[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsSwapCmdAsCtrl];
}

- (void)setSwapCmdAsCtrl:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsSwapCmdAsCtrl];
}

// Client Management
- (BOOL)multipleClientsEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsMultipleClients];
}

- (void)setMultipleClientsEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsMultipleClients];
}

// Waypipe
- (BOOL)machineSessionThumbnailsEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsMachineSessionThumbnailsEnabled];
}

- (void)setMachineSessionThumbnailsEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults]
      setBool:enabled
       forKey:kWWNPrefsMachineSessionThumbnailsEnabled];
}

- (BOOL)waypipeRSSupportEnabled {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsWaypipeRSSupport];
}

- (void)setWaypipeRSSupportEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeRSSupport];
}

// Network / Remote Access
- (BOOL)enableTCPListener {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsEnableTCPListener];
}

- (void)setEnableTCPListener:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsEnableTCPListener];
}

- (NSInteger)tcpListenerPort {
  return [[NSUserDefaults standardUserDefaults]
      integerForKey:kWWNPrefsTCPListenerPort];
}

- (void)setTCPListenerPort:(NSInteger)port {
  [[NSUserDefaults standardUserDefaults] setInteger:port
                                             forKey:kWWNPrefsTCPListenerPort];
}

// Wayland Configuration
- (NSString *)waylandSocketDir {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *preferred = WWNPreferredSharedRuntimeDir();
  if (preferred.length > 0) {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
        stringForKey:kWWNPrefsWaylandSocketDir];
    if (![stored isEqualToString:preferred]) {
      [[NSUserDefaults standardUserDefaults]
          setObject:preferred
             forKey:kWWNPrefsWaylandSocketDir];
    }
    return preferred;
  }
#endif

  NSString *dir = [[NSUserDefaults standardUserDefaults]
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
  [[NSUserDefaults standardUserDefaults] setObject:dir
                                            forKey:kWWNPrefsWaylandSocketDir];
}

- (NSInteger)waylandDisplayNumber {
  return [[NSUserDefaults standardUserDefaults]
      integerForKey:kWWNPrefsWaylandDisplayNumber];
}

- (void)setWaylandDisplayNumber:(NSInteger)number {
  [[NSUserDefaults standardUserDefaults]
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
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsEnableVulkanDrivers];
  [self setVulkanDriver:enabled ? @"moltenvk" : @"none"];
}

// Dmabuf Support
- (BOOL)dmabufEnabled {
  return
      [[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsEnableDmabuf];
}

- (void)setDmabufEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsEnableDmabuf];
}

// Graphics Driver Selection
- (NSString *)vulkanDriver {
  return
      [[NSUserDefaults standardUserDefaults] stringForKey:kWWNPrefsVulkanDriver]
          ?: @"moltenvk";
}

- (void)setVulkanDriver:(NSString *)driver {
  [[NSUserDefaults standardUserDefaults] setObject:driver
                                            forKey:kWWNPrefsVulkanDriver];
}

- (NSString *)openglDriver {
  return
      [[NSUserDefaults standardUserDefaults] stringForKey:kWWNPrefsOpenGLDriver]
          ?: @"angle";
}

- (void)setOpenGLDriver:(NSString *)driver {
  [[NSUserDefaults standardUserDefaults] setObject:driver
                                            forKey:kWWNPrefsOpenGLDriver];
}

// New unified display methods
- (BOOL)autoScale {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
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
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsAutoScale];
}

- (BOOL)respectSafeArea {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsRespectSafeArea];
}

- (void)setRespectSafeArea:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsRespectSafeArea];
}

- (BOOL)hasSeenWelcome {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsHasSeenWelcome];
}

- (void)setHasSeenWelcome:(BOOL)seen {
  [[NSUserDefaults standardUserDefaults] setBool:seen
                                          forKey:kWWNPrefsHasSeenWelcome];
}

// New unified color management method
- (BOOL)colorOperations {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
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
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsColorOperations];
}

// New unified input method
- (BOOL)swapCmdWithAlt {
  // Check new key first, fallback to legacy key for migration
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
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
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsSwapCmdWithAlt];
}

- (NSString *)touchInputType {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsTouchInputType];
  return value ? value : @"Multi-Touch";
}

- (void)setTouchInputType:(NSString *)type {
  if (type) {
    [[NSUserDefaults standardUserDefaults] setObject:type
                                              forKey:kWWNPrefsTouchInputType];
  } else {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kWWNPrefsTouchInputType];
  }
}

// Waypipe Configuration Methods
- (NSString *)waypipeDisplay {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeDisplay];
  if ([value isEqualToString:@"w0"] || [value isEqualToString:@"w-0"]) {
    value = @"wayland-0";
    [[NSUserDefaults standardUserDefaults] setObject:value
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
    [[NSUserDefaults standardUserDefaults] setObject:display
                                              forKey:kWWNPrefsWaypipeDisplay];
  } else {
    [[NSUserDefaults standardUserDefaults]
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
    NSString *stored = [[NSUserDefaults standardUserDefaults]
        stringForKey:kWWNPrefsWaypipeSocket];
    if (![stored isEqualToString:preferred]) {
      [[NSUserDefaults standardUserDefaults] setObject:preferred
                                                forKey:kWWNPrefsWaypipeSocket];
    }
    return preferred;
  }
#endif

  NSString *value = [[NSUserDefaults standardUserDefaults]
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
  [[NSUserDefaults standardUserDefaults] setObject:socket
                                            forKey:kWWNPrefsWaypipeSocket];
}

- (NSString *)waypipeCompress {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeCompress];
  return value ? value : @"lz4";
}

- (void)setWaypipeCompress:(NSString *)compress {
  [[NSUserDefaults standardUserDefaults] setObject:compress
                                            forKey:kWWNPrefsWaypipeCompress];
}

- (NSString *)waypipeCompressLevel {
  id value = [[NSUserDefaults standardUserDefaults]
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
  [[NSUserDefaults standardUserDefaults]
      setObject:level
         forKey:kWWNPrefsWaypipeCompressLevel];
}

- (NSString *)waypipeThreads {
  id value = [[NSUserDefaults standardUserDefaults]
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
  [[NSUserDefaults standardUserDefaults] setObject:threads
                                            forKey:kWWNPrefsWaypipeThreads];
}

- (NSString *)waypipeVideo {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeVideo];
  return value ? value : @"none";
}

- (void)setWaypipeVideo:(NSString *)video {
  [[NSUserDefaults standardUserDefaults] setObject:video
                                            forKey:kWWNPrefsWaypipeVideo];
}

- (NSString *)waypipeVideoEncoding {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeVideoEncoding];
  return value ? value : @"hw";
}

- (void)setWaypipeVideoEncoding:(NSString *)encoding {
  [[NSUserDefaults standardUserDefaults]
      setObject:encoding
         forKey:kWWNPrefsWaypipeVideoEncoding];
}

- (NSString *)waypipeVideoDecoding {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeVideoDecoding];
  return value ? value : @"hw";
}

- (void)setWaypipeVideoDecoding:(NSString *)decoding {
  [[NSUserDefaults standardUserDefaults]
      setObject:decoding
         forKey:kWWNPrefsWaypipeVideoDecoding];
}

- (NSString *)waypipeVideoBpf {
  id value = [[NSUserDefaults standardUserDefaults]
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
  [[NSUserDefaults standardUserDefaults] setObject:bpf
                                            forKey:kWWNPrefsWaypipeVideoBpf];
}

- (BOOL)waypipeSSHEnabled {
  // SSH is always enabled on iOS/macOS
  return YES;
}

- (void)setWaypipeSSHEnabled:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeSSHEnabled];
}

- (NSString *)waypipeSSHHost {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeSSHHost];
  return value ? value : @"";
}

- (void)setWaypipeSSHHost:(NSString *)host {
  [[NSUserDefaults standardUserDefaults] setObject:host
                                            forKey:kWWNPrefsWaypipeSSHHost];
}

- (NSString *)waypipeSSHUser {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeSSHUser];
  return value ? value : @"";
}

- (void)setWaypipeSSHUser:(NSString *)user {
  [[NSUserDefaults standardUserDefaults] setObject:user
                                            forKey:kWWNPrefsWaypipeSSHUser];
}

- (NSString *)waypipeSSHBinary {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeSSHBinary];
  return value ? value : @"ssh";
}

- (void)setWaypipeSSHBinary:(NSString *)binary {
  [[NSUserDefaults standardUserDefaults] setObject:binary
                                            forKey:kWWNPrefsWaypipeSSHBinary];
}

- (NSInteger)waypipeSSHAuthMethod {
  NSInteger method = [[NSUserDefaults standardUserDefaults]
      integerForKey:kWWNPrefsWaypipeSSHAuthMethod];
  return method; // 0 = password (default), 1 = public key
}

- (void)setWaypipeSSHAuthMethod:(NSInteger)method {
  [[NSUserDefaults standardUserDefaults]
      setInteger:method
          forKey:kWWNPrefsWaypipeSSHAuthMethod];
}

- (NSString *)waypipeSSHKeyPath {
  return [[NSUserDefaults standardUserDefaults]
             stringForKey:kWWNPrefsWaypipeSSHKeyPath]
             ?: @"";
}

- (void)setWaypipeSSHKeyPath:(NSString *)keyPath {
  [[NSUserDefaults standardUserDefaults] setObject:keyPath
                                            forKey:kWWNPrefsWaypipeSSHKeyPath];
}

- (NSString *)waypipeSSHKeyPassphrase {
  return [[NSUserDefaults standardUserDefaults]
             stringForKey:kWWNPrefsWaypipeSSHKeyPassphrase]
             ?: @"";
}

- (void)setWaypipeSSHKeyPassphrase:(NSString *)passphrase {
  if (passphrase && passphrase.length > 0) {
    [[NSUserDefaults standardUserDefaults]
        setObject:passphrase
           forKey:kWWNPrefsWaypipeSSHKeyPassphrase];
  } else {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kWWNPrefsWaypipeSSHKeyPassphrase];
  }
}

- (NSString *)waypipeSSHPassword {
  return [[NSUserDefaults standardUserDefaults]
             stringForKey:kWWNPrefsWaypipeSSHPassword]
             ?: @"";
}

- (void)setWaypipeSSHPassword:(NSString *)password {
  if (password && password.length > 0) {
    [[NSUserDefaults standardUserDefaults]
        setObject:password
           forKey:kWWNPrefsWaypipeSSHPassword];
  } else {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kWWNPrefsWaypipeSSHPassword];
  }
}

- (NSString *)waypipeRemoteCommand {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeRemoteCommand];
  return value ? value : @"";
}

- (void)setWaypipeRemoteCommand:(NSString *)command {
  [[NSUserDefaults standardUserDefaults]
      setObject:command
         forKey:kWWNPrefsWaypipeRemoteCommand];
}

- (NSString *)waypipeCustomScript {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeCustomScript];
  return value ? value : @"";
}

- (void)setWaypipeCustomScript:(NSString *)script {
  [[NSUserDefaults standardUserDefaults]
      setObject:script
         forKey:kWWNPrefsWaypipeCustomScript];
}

- (BOOL)waypipeDebug {
  return
      [[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsWaypipeDebug];
}

- (void)setWaypipeDebug:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeDebug];
}

- (BOOL)waypipeNoGpu {
  return
      [[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsWaypipeNoGpu];
}

- (void)setWaypipeNoGpu:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeNoGpu];
}

- (BOOL)waypipeOneshot {
#if TARGET_OS_IPHONE
  // iOS App Store: SSH uses in-process libssh2 only; oneshot is always on.
  return YES;
#else
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsWaypipeOneshot];
#endif
}

- (void)setWaypipeOneshot:(BOOL)enabled {
#if !TARGET_OS_IPHONE
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeOneshot];
#endif
  // On iOS the getter always returns YES; no-op setter keeps UI from persisting
  // off.
}

- (BOOL)waypipeUnlinkSocket {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsWaypipeUnlinkSocket];
}

- (void)setWaypipeUnlinkSocket:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeUnlinkSocket];
}

- (BOOL)waypipeLoginShell {
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsWaypipeLoginShell];
}

- (void)setWaypipeLoginShell:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeLoginShell];
}

- (BOOL)waypipeVsock {
  return
      [[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsWaypipeVsock];
}

- (void)setWaypipeVsock:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeVsock];
}

- (BOOL)waypipeXwls {
  return
      [[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsWaypipeXwls];
}

- (void)setWaypipeXwls:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeXwls];
}

- (NSString *)waypipeTitlePrefix {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeTitlePrefix];
  return value ? value : @"";
}

- (void)setWaypipeTitlePrefix:(NSString *)prefix {
  [[NSUserDefaults standardUserDefaults] setObject:prefix
                                            forKey:kWWNPrefsWaypipeTitlePrefix];
}

- (NSString *)waypipeSecCtx {
  NSString *value = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsWaypipeSecCtx];
  return value ? value : @"";
}

- (void)setWaypipeSecCtx:(NSString *)secCtx {
  [[NSUserDefaults standardUserDefaults] setObject:secCtx
                                            forKey:kWWNPrefsWaypipeSecCtx];
}

- (BOOL)waypipeUseSSHConfig {
  // Default to YES if not set (use SSH config from OpenSSH section by default)
  if (![[NSUserDefaults standardUserDefaults]
          objectForKey:kWWNPrefsWaypipeUseSSHConfig]) {
    return YES;
  }
  return [[NSUserDefaults standardUserDefaults]
      boolForKey:kWWNPrefsWaypipeUseSSHConfig];
}

- (void)setWaypipeUseSSHConfig:(BOOL)enabled {
  [[NSUserDefaults standardUserDefaults] setBool:enabled
                                          forKey:kWWNPrefsWaypipeUseSSHConfig];
}

// SSH Configuration (separate from Waypipe)
- (NSString *)sshHost {
  NSString *value =
      [[NSUserDefaults standardUserDefaults] stringForKey:kWWNPrefsSSHHost];
  return value ? value : @"";
}

- (void)setSshHost:(NSString *)host {
  [[NSUserDefaults standardUserDefaults] setObject:host
                                            forKey:kWWNPrefsSSHHost];
}

- (NSString *)sshUser {
  NSString *value =
      [[NSUserDefaults standardUserDefaults] stringForKey:kWWNPrefsSSHUser];
  return value ? value : @"";
}

- (void)setSshUser:(NSString *)user {
  [[NSUserDefaults standardUserDefaults] setObject:user
                                            forKey:kWWNPrefsSSHUser];
}

- (NSInteger)sshAuthMethod {
  return [[NSUserDefaults standardUserDefaults]
      integerForKey:kWWNPrefsSSHAuthMethod];
}

- (void)setSshAuthMethod:(NSInteger)method {
  [[NSUserDefaults standardUserDefaults] setInteger:method
                                             forKey:kWWNPrefsSSHAuthMethod];
}

// Helper methods for preference storage
- (NSString *)getSecureValueForKey:(NSString *)key {
  NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:key];
  return value ?: @"";
}

- (void)setSecureValue:(NSString *)value forKey:(NSString *)key {
  if (value && value.length > 0) {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
  } else {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
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
      [[NSUserDefaults standardUserDefaults] stringForKey:kWWNPrefsSSHKeyPath];
  return value ? value : @"";
}

- (void)setSshKeyPath:(NSString *)keyPath {
  [[NSUserDefaults standardUserDefaults] setObject:keyPath
                                            forKey:kWWNPrefsSSHKeyPath];
}

- (NSString *)sshKeyPassphrase {
  return [self getSecureValueForKey:kWWNPrefsSSHKeyPassphrase];
}

- (void)setSshKeyPassphrase:(NSString *)passphrase {
  [self setSecureValue:passphrase forKey:kWWNPrefsSSHKeyPassphrase];
}

@end
