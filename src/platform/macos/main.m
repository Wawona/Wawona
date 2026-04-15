#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#endif
#import <QuartzCore/QuartzCore.h>

// Rust Compositor Bridge (PRIMARY INTERFACE)
#import "WWNCompositorBridge.h"

// Platform Adapters
#import "WWNPlatformCallbacks.h"

// Logging
#import "../../util/WWNLog.h"

// Settings (for Vulkan driver configuration)
#import "./ui/Settings/WWNPreferencesManager.h"
#import "WWNSettings.h"

// C FFI for Rust Compositor window events
typedef struct CWindowInfo {
  uint64_t window_id;
  uint32_t width;
  uint32_t height;
  char *title;
} CWindowInfo;

extern uint32_t wawona_core_pending_window_count(const void *core);
extern CWindowInfo *wawona_core_pop_pending_window(void *core);
extern void wawona_window_info_free(CWindowInfo *info);

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR

//
// iOS Implementation
//

#import "./ui/Settings/WWNPreferences.h"
#import "../ios/WWNSceneDelegate.h"

@interface WWNAppDelegate : NSObject <UIApplicationDelegate>
@end

@implementation WWNAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application;
  (void)launchOptions;

  WWNLog("MAIN", @"WWN iOS starting...");

  // 1. Set up XDG_RUNTIME_DIR
  const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
  NSString *runtimePath = nil;
  NSFileManager *fm = [NSFileManager defaultManager];

  if (!runtime_dir) {
#if TARGET_OS_SIMULATOR
    runtimePath = [NSString stringWithFormat:@"/tmp/wawona_sim_%d", getuid()];
#else
    // Use NSTemporaryDirectory()/w to match WWNPreferredSharedRuntimeDir()
    // which the preferences system and waypipe runner both expect.
    runtimePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"w"];
#endif
    [fm createDirectoryAtPath:runtimePath
        withIntermediateDirectories:YES
                         attributes:@{NSFilePosixPermissions : @0700}
                              error:nil];

    setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
    WWNLog("MAIN", @"Set XDG_RUNTIME_DIR to: %@", runtimePath);
  }

  // 2. Configure Vulkan driver (statically linked on iOS)
  const char *vkDriver = WWNSettings_GetVulkanDriver();
  if (vkDriver && strcmp(vkDriver, "none") != 0) {
    WWNLog("MAIN", @"Vulkan driver: %s (static link)", vkDriver);
  } else {
    WWNLog("MAIN", @"Vulkan drivers disabled (driver selection: none)");
  }

  // 3. Initialize Rust Compositor
  WWNCompositorBridge *compositor = [WWNCompositorBridge sharedBridge];

  // Use a reasonable initial size; the scene delegate will set the
  // actual output dimensions once the UIWindowScene is available.
  CGSize screenSize = CGSizeMake(390, 844);
  BOOL autoScale = [[WWNPreferencesManager sharedManager] autoScale];
  CGFloat scale = autoScale ? 3.0 : 1.0;

  [compositor setOutputWidth:(uint32_t)screenSize.width
                      height:(uint32_t)screenSize.height
                       scale:(float)scale];

  if (![compositor startWithSocketName:@"wayland-0"]) {
    WWNLog("MAIN", @"Error: Failed to start Rust compositor");
    return NO;
  }

  setenv("WAYLAND_DISPLAY", [[compositor socketName] UTF8String], 1);

  // 3. Configure iOS UI -> MOVED TO SCENE DELEGATE
  WWNLog("MAIN", @"WWN iOS initialization complete (waiting for Scene "
                 @"connection)");
  return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:
        (UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
  (void)application;
  (void)options;
  UISceneConfiguration *config =
      [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                     sessionRole:connectingSceneSession.role];
  config.delegateClass = [WWNSceneDelegate class];
  return config;
}

- (void)applicationWillTerminate:(UIApplication *)application {
  WWNLog("MAIN", @"iOS application will terminate - shutting down gracefully");
  [[WWNCompositorBridge sharedBridge] stop];
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    // Ignore SIGPIPE — broken pipes from waypipe/SSH connections must not
    // terminate the app.  The underlying write() returns EPIPE instead.
    signal(SIGPIPE, SIG_IGN);

    return UIApplicationMain(argc, argv, nil,
                             NSStringFromClass([WWNAppDelegate class]));
  }
}

#else

//
// macOS Implementation
//

#import "./ui/About/WWNAboutPanel.h"
#import "./ui/Machines/WWNMachinesCoordinator.h"
#import "./ui/Settings/WWNPreferences.h"
#import "WWNLaunchAgentManager.h"

// Global references for signal handler
extern volatile pid_t g_active_waypipe_pgid;

// Global cleanup for atexit
static int g_instance_lock_fd = -1;
static int g_host_lock_fd = -1;
static int g_menubar_lock_fd = -1;
static BOOL g_show_about_on_launch = NO;

static void release_instance_lock(void) {
  if (g_instance_lock_fd >= 0) {
    flock(g_instance_lock_fd, LOCK_UN);
    close(g_instance_lock_fd);
    g_instance_lock_fd = -1;
  }
}

static void release_mode_lock(int *fdRef) {
  if (!fdRef || *fdRef < 0) {
    return;
  }
  flock(*fdRef, LOCK_UN);
  close(*fdRef);
  *fdRef = -1;
}

static BOOL acquire_mode_lock(NSString *name, int *fdRef) {
  if (!name || !fdRef) {
    return NO;
  }
  NSString *lockDir = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  [[NSFileManager defaultManager] createDirectoryAtPath:lockDir
                            withIntermediateDirectories:YES
                                             attributes:@{
                                               NSFilePosixPermissions : @0700
                                             }
                                                  error:nil];
  NSString *lockPath = [lockDir stringByAppendingPathComponent:name];
  int fd = open([lockPath fileSystemRepresentation], O_CREAT | O_RDWR, 0600);
  if (fd < 0) {
    return NO;
  }
  if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
    close(fd);
    return NO;
  }
  *fdRef = fd;
  return YES;
}

static NSString *wwn_runtime_dir(void) {
  const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
  if (runtime_dir && strlen(runtime_dir) > 0) {
    return [NSString stringWithUTF8String:runtime_dir];
  }
  return [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
}

static NSString *wwn_runtime_state_path(void) {
  return [wwn_runtime_dir() stringByAppendingPathComponent:@"wawona-runtime-state.plist"];
}

static NSString *wwn_runtime_env_path(void) {
  return [wwn_runtime_dir() stringByAppendingPathComponent:@"wawona-env.sh"];
}

static void wwn_write_runtime_state(BOOL healthy, NSString *socketName,
                                    NSString *socketPath, NSString *mode,
                                    NSString *error) {
  NSString *runtimeDir = wwn_runtime_dir();
  [[NSFileManager defaultManager] createDirectoryAtPath:runtimeDir
                            withIntermediateDirectories:YES
                                             attributes:@{
                                               NSFilePosixPermissions : @0700
                                             }
                                                  error:nil];
  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  state[@"healthy"] = @(healthy);
  state[@"pid"] = @((NSInteger)getpid());
  state[@"mode"] = mode ?: @"unknown";
  state[@"xdgRuntimeDir"] = runtimeDir;
  state[@"waylandDisplay"] = socketName ?: @"wayland-0";
  state[@"socketPath"] = socketPath ?: [runtimeDir stringByAppendingPathComponent:(socketName ?: @"wayland-0")];
  state[@"startedAt"] = @([[NSDate date] timeIntervalSince1970]);
  if (error.length > 0) {
    state[@"lastError"] = error;
  }
  [state writeToFile:wwn_runtime_state_path() atomically:YES];
}

static void wwn_write_runtime_exports(NSString *socketName) {
  NSString *runtimeDir = wwn_runtime_dir();
  NSString *display = socketName.length > 0 ? socketName : @"wayland-0";
  NSString *contents = [NSString stringWithFormat:
      @"#!/bin/sh\nexport XDG_RUNTIME_DIR=\"%@\"\nexport WAYLAND_DISPLAY=\"%@\"\n",
      runtimeDir, display];
  NSString *path = wwn_runtime_env_path();
  [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  chmod([path fileSystemRepresentation], 0700);
}

static BOOL wwn_is_compositor_socket_ready(void) {
  NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:wwn_runtime_state_path()];
  if (![state isKindOfClass:[NSDictionary class]]) {
    return NO;
  }
  if (![state[@"healthy"] boolValue]) {
    return NO;
  }
  NSString *socketPath = [state[@"socketPath"] isKindOfClass:[NSString class]] ? state[@"socketPath"] : @"";
  if (socketPath.length == 0) {
    return NO;
  }
  return [[NSFileManager defaultManager] fileExistsAtPath:socketPath];
}

static void activate_existing_instance(void) {
  NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
  if (!bundleID || bundleID.length == 0) {
    bundleID = @"com.aspauldingcode.Wawona";
  }
  pid_t currentPID = [[NSProcessInfo processInfo] processIdentifier];
  NSArray<NSRunningApplication *> *runningApps =
      [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID];
  for (NSRunningApplication *app in runningApps) {
    if (app.processIdentifier != currentPID && !app.terminated) {
      [app activateWithOptions:NSApplicationActivateAllWindows];
      break;
    }
  }
}

static BOOL acquire_single_instance_lock(void) {
  NSString *lockDir = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  [[NSFileManager defaultManager] createDirectoryAtPath:lockDir
                            withIntermediateDirectories:YES
                                             attributes:@{
                                               NSFilePosixPermissions : @0700
                                             }
                                                  error:nil];
  NSString *lockPath =
      [lockDir stringByAppendingPathComponent:@"instance.lock"];

  g_instance_lock_fd =
      open([lockPath fileSystemRepresentation], O_CREAT | O_RDWR, 0600);
  if (g_instance_lock_fd < 0) {
    // If lock setup fails, do not block startup.
    WWNLog("MAIN", @"Warning: failed to open single-instance lock file");
    return YES;
  }

  if (flock(g_instance_lock_fd, LOCK_EX | LOCK_NB) != 0) {
    close(g_instance_lock_fd);
    g_instance_lock_fd = -1;
    return NO;
  }
  return YES;
}

static void cleanup_on_exit(void) {
  static int cleaning_up = 0;
  if (cleaning_up) {
    return;
  }
  cleaning_up = 1;

  WWNLog("MAIN", @"Performing final cleanup on exit...");

  // Stop Rust compositor
  [[WWNCompositorBridge sharedBridge] stop];
  wwn_write_runtime_state(NO, @"wayland-0", nil, @"shutdown", @"process exiting");
  release_instance_lock();
  release_mode_lock(&g_host_lock_fd);
  release_mode_lock(&g_menubar_lock_fd);
}

// Emergency crash handler - must be strictly async-signal-safe
static void crash_handler(int sig) {
  // Use write() directly for safety
  const char *msg = "\nCRITICAL: WWN crashed. Emergency cleanup...\n";
  write(STDERR_FILENO, msg, strlen(msg));

  // Kill waypipe process group if active
  pid_t pgid = g_active_waypipe_pgid;
  if (pgid > 0) {
    kill(-pgid, SIGKILL);
  }

  _exit(128 + sig);
}

// Raw signal handler for graceful termination
static void raw_signal_handler(int sig) {
  const char *msg;
  if (sig == SIGINT) {
    msg = "\n\nReceived SIGINT (Ctrl+C), shutting down gracefully...\n";
  } else if (sig == SIGTERM) {
    msg = "\n\nReceived SIGTERM, shutting down gracefully...\n";
  } else {
    msg = "\n\nReceived signal, shutting down...\n";
  }
  write(STDERR_FILENO, msg, strlen(msg));
  _exit(0);
}

// Simple signal setup
static void setup_signal_sources(void) {
  signal(SIGTERM, raw_signal_handler);
  signal(SIGINT, raw_signal_handler);
}

@interface WWNMacAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation WWNMacAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSError *agentError = nil;
  (void)[[WWNLaunchAgentManager sharedManager]
      ensureCompositorAndMenuAgents:&agentError];
  (void)agentError;

  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  if (![prefs hasSeenWelcome]) {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Welcome to Wawona";
    alert.informativeText =
        @"A clean Wayland compositor experience for macOS, iOS, and Android.";
    [alert addButtonWithTitle:@"Continue"];
    [alert runModal];
    [prefs setHasSeenWelcome:YES];
  }
  if (g_show_about_on_launch) {
    [[WWNAboutPanel sharedAboutPanel] showAboutPanel:nil];
  } else {
    [[WWNMachinesCoordinator sharedCoordinator] showMachinesWindowAndActivate:YES];
  }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  WWNLog("MAIN",
         @"macOS application will terminate - shutting down gracefully");
  cleanup_on_exit();
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication *)sender {
  return NSTerminateNow;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)sender {
  (void)sender;
  WWNLog("MAIN", @"Window closed, but compositor will continue running");
  return NO;
}

- (void)showAboutPanel:(id)sender {
  [[WWNAboutPanel sharedAboutPanel] showAboutPanel:sender];
}

- (void)showPreferences:(id)sender {
  [[WWNPreferences sharedPreferences] showPreferences:sender];
}

- (void)showMachines:(id)sender {
  [[WWNMachinesCoordinator sharedCoordinator] showMachinesWindowFromMenu:sender];
}

- (BOOL)applicationShouldSaveApplicationState:(NSApplication *)sender {
  (void)sender;
  return NO;
}

- (BOOL)applicationShouldRestoreApplicationState:(NSApplication *)sender {
  (void)sender;
  return NO;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
  (void)app;
  return NO;
}

@end

@interface WWNMenuBarController : NSObject
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *statusLineItem;
@property(nonatomic, strong) NSTimer *pollTimer;
@end

@implementation WWNMenuBarController

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.title = @"Wawona";
    _statusItem.button.toolTip = @"Wawona Compositor";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Wawona"];
    _statusLineItem = [[NSMenuItem alloc] initWithTitle:@"Compositor: unknown"
                                                  action:nil
                                           keyEquivalent:@""];
    [_statusLineItem setEnabled:NO];
    [menu addItem:_statusLineItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *restartItem =
        [[NSMenuItem alloc] initWithTitle:@"Restart Compositor"
                                   action:@selector(restartCompositor:)
                            keyEquivalent:@"r"];
    restartItem.target = self;
    [menu addItem:restartItem];

    NSMenuItem *stopItem = [[NSMenuItem alloc] initWithTitle:@"Stop Compositor"
                                                       action:@selector(stopCompositor:)
                                                keyEquivalent:@"s"];
    stopItem.target = self;
    [menu addItem:stopItem];

    NSMenuItem *startItem = [[NSMenuItem alloc] initWithTitle:@"Start Compositor"
                                                        action:@selector(startCompositor:)
                                                 keyEquivalent:@""];
    startItem.target = self;
    [menu addItem:startItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *toggleLogin =
        [[NSMenuItem alloc] initWithTitle:@"Toggle Launch Wawona.app at Login"
                                   action:@selector(toggleAppLaunchAtLogin:)
                            keyEquivalent:@"l"];
    toggleLogin.target = self;
    [menu addItem:toggleLogin];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *openApp =
        [[NSMenuItem alloc] initWithTitle:@"Open Wawona"
                                   action:@selector(openWawonaApp:)
                            keyEquivalent:@"o"];
    openApp.target = self;
    [menu addItem:openApp];

    NSMenuItem *aboutItem =
        [[NSMenuItem alloc] initWithTitle:@"About Wawona"
                                   action:@selector(openWawonaAbout:)
                            keyEquivalent:@""];
    aboutItem.target = self;
    [menu addItem:aboutItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem =
        [[NSMenuItem alloc] initWithTitle:@"Quit Menu Bar"
                                   action:@selector(quitMenuBar:)
                            keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    _statusItem.menu = menu;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                   target:self
                                                 selector:@selector(refreshStatus:)
                                                 userInfo:nil
                                                  repeats:YES];
    [self refreshStatus:nil];
  }
  return self;
}

- (void)refreshStatus:(id)sender {
  (void)sender;
  BOOL running = wwn_is_compositor_socket_ready();
  self.statusLineItem.title =
      running ? @"Compositor: running" : @"Compositor: stopped";
}

- (void)restartCompositor:(id)sender {
  (void)sender;
  [[WWNLaunchAgentManager sharedManager] restartCompositorAgent];
  [self refreshStatus:nil];
}

- (void)stopCompositor:(id)sender {
  (void)sender;
  [[WWNLaunchAgentManager sharedManager] stopCompositorAgent];
  [self refreshStatus:nil];
}

- (void)startCompositor:(id)sender {
  (void)sender;
  [[WWNLaunchAgentManager sharedManager] startCompositorAgent];
  [self refreshStatus:nil];
}

- (void)toggleAppLaunchAtLogin:(id)sender {
  (void)sender;
  WWNLaunchAgentManager *manager = [WWNLaunchAgentManager sharedManager];
  if ([manager isAppLaunchAgentLoaded]) {
    [manager disableAppLaunchAtLogin];
  } else {
    [manager enableAppLaunchAtLogin];
  }
}

- (void)openWawonaApp:(id)sender {
  (void)sender;
  NSURL *bundleURL = [NSBundle mainBundle].bundleURL;
  NSString *bundlePath = bundleURL.path;
  if (![bundlePath hasSuffix:@".app"]) {
    bundlePath =
        [[bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
  }
  NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
  [NSWorkspace.sharedWorkspace openApplicationAtURL:[NSURL fileURLWithPath:bundlePath]
                                      configuration:config
                                  completionHandler:nil];
}

- (void)openWawonaAbout:(id)sender {
  (void)sender;
  NSURL *bundleURL = [NSBundle mainBundle].bundleURL;
  NSString *bundlePath = bundleURL.path;
  if (![bundlePath hasSuffix:@".app"]) {
    bundlePath =
        [[bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
  }
  NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
  config.arguments = @[ @"--show-about" ];
  [NSWorkspace.sharedWorkspace openApplicationAtURL:[NSURL fileURLWithPath:bundlePath]
                                      configuration:config
                                  completionHandler:nil];
}

- (void)quitMenuBar:(id)sender {
  (void)sender;
  [NSApp terminate:nil];
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    // Overwrite argv[0] so macOS menu bar shows "Wawona" instead of the binary
    // name
    const char *desiredName = "Wawona";
    size_t maxLen = strlen(argv[0]);
    memset(argv[0], 0, maxLen);
    strncpy(argv[0], desiredName, maxLen);

    [[NSProcessInfo processInfo] setProcessName:@"Wawona"];
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    BOOL compositorHostMode = NO;
    BOOL menuBarMode = NO;
    for (int i = 1; i < argc; i++) {
      if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-v") == 0) {
#ifdef WAWONA_VERSION
        printf("Wawona v%s\n", WAWONA_VERSION);
#else
        printf("Wawona unknown\n");
#endif
        return 0;
      }
      if (strcmp(argv[i], "--compositor-host") == 0) {
        compositorHostMode = YES;
      } else if (strcmp(argv[i], "--menubar") == 0) {
        menuBarMode = YES;
      } else if (strcmp(argv[i], "--show-about") == 0) {
        g_show_about_on_launch = YES;
      }
    }

    if (compositorHostMode && menuBarMode) {
      WWNLog("MAIN", @"Invalid startup flags: --compositor-host and --menubar are mutually exclusive");
      return 2;
    }

    if (compositorHostMode) {
      if (!acquire_mode_lock(@"compositor-host.lock", &g_host_lock_fd)) {
        WWNLog("MAIN", @"Compositor host already running; exiting host mode.");
        return 0;
      }
      [[NSProcessInfo processInfo] setProcessName:@"WawonaCompositorHost"];
      [NSApplication sharedApplication];
      [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];

      NSString *runtimePath = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
      setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
      [[NSFileManager defaultManager] createDirectoryAtPath:runtimePath
                                withIntermediateDirectories:YES
                                                 attributes:@{
                                                   NSFilePosixPermissions : @0700
                                                 }
                                                      error:nil];

      WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
      [bridge setOutputWidth:1024 height:768 scale:1.0f];
      [bridge setForceSSD:WWNSettings_GetForceServerSideDecorations()];
      if (![bridge startWithSocketName:@"wayland-0"]) {
        wwn_write_runtime_state(NO, @"wayland-0", nil, @"compositor-host",
                                @"failed to start compositor");
        return 1;
      }
      setenv("WAYLAND_DISPLAY", "wayland-0", 1);
      wwn_write_runtime_exports(@"wayland-0");
      wwn_write_runtime_state(YES, @"wayland-0", [bridge socketPath],
                              @"compositor-host", nil);
      setup_signal_sources();
      signal(SIGPIPE, SIG_IGN);
      signal(SIGSEGV, crash_handler);
      signal(SIGABRT, crash_handler);
      signal(SIGBUS, crash_handler);
      signal(SIGILL, crash_handler);
      [[NSRunLoop mainRunLoop] run];
      [bridge stop];
      release_mode_lock(&g_host_lock_fd);
      return 0;
    }

    if (menuBarMode) {
      if (!acquire_mode_lock(@"menubar.lock", &g_menubar_lock_fd)) {
        return 0;
      }
      [[NSProcessInfo processInfo] setProcessName:@"WawonaMenuBar"];
      [NSApplication sharedApplication];
      [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
      NSError *agentError = nil;
      (void)[[WWNLaunchAgentManager sharedManager]
          ensureCompositorAndMenuAgents:&agentError];
      __unused WWNMenuBarController *controller = [[WWNMenuBarController alloc] init];
      [NSApp run];
      release_mode_lock(&g_menubar_lock_fd);
      return 0;
    }

    WWNLog("MAIN", @"WWN - Wayland Compositor for macOS");

    if (!acquire_single_instance_lock()) {
      WWNLog("MAIN", @"Another Wawona instance is already running; exiting.");
      activate_existing_instance();
      return 0;
    }

    [[NSProcessInfo processInfo] disableAutomaticTermination:@"KeepAlive"];
    [[NSProcessInfo processInfo] disableSuddenTermination];

    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    WWNMacAppDelegate *delegate = [[WWNMacAppDelegate alloc] init];
    [NSApp setDelegate:delegate];

    // === Build Menu Bar ===
    NSMenu *menubar = [[NSMenu alloc] init];
    NSString *appName = [[NSProcessInfo processInfo] processName];

    // -- App Menu --
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];

    [appMenu addItem:[[NSMenuItem alloc]
                         initWithTitle:[NSString stringWithFormat:@"About %@",
                                                                  appName]
                                action:@selector(showAboutPanel:)
                         keyEquivalent:@""]];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *prefsItem =
        [[NSMenuItem alloc] initWithTitle:@"Settings..."
                                   action:@selector(showPreferences:)
                            keyEquivalent:@","];
    [appMenu addItem:prefsItem];
    NSMenuItem *machinesItem =
        [[NSMenuItem alloc] initWithTitle:@"Machines..."
                                   action:@selector(showMachines:)
                            keyEquivalent:@"m"];
    [machinesItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                             NSEventModifierFlagShift];
    [appMenu addItem:machinesItem];
    [appMenu addItem:[NSMenuItem separatorItem]];

    [appMenu addItem:[[NSMenuItem alloc]
                         initWithTitle:[NSString
                                           stringWithFormat:@"Hide %@", appName]
                                action:@selector(hide:)
                         keyEquivalent:@"h"]];

    NSMenuItem *hideOthers =
        [[NSMenuItem alloc] initWithTitle:@"Hide Others"
                                   action:@selector(hideOtherApplications:)
                            keyEquivalent:@"h"];
    [hideOthers setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                             NSEventModifierFlagOption];
    [appMenu addItem:hideOthers];

    [appMenu addItem:[[NSMenuItem alloc]
                         initWithTitle:@"Show All"
                                action:@selector(unhideAllApplications:)
                         keyEquivalent:@""]];
    [appMenu addItem:[NSMenuItem separatorItem]];

    [appMenu addItem:[[NSMenuItem alloc]
                         initWithTitle:[NSString
                                           stringWithFormat:@"Quit %@", appName]
                                action:@selector(terminate:)
                         keyEquivalent:@"q"]];
    [appMenuItem setSubmenu:appMenu];
    [menubar addItem:appMenuItem];

    // -- Edit Menu --
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Undo"
                                                  action:@selector(undo:)
                                           keyEquivalent:@"z"]];
    NSMenuItem *redoItem =
        [[NSMenuItem alloc] initWithTitle:@"Redo"
                                   action:@selector(redo:)
                            keyEquivalent:@"z"];
    [redoItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                             NSEventModifierFlagShift];
    [editMenu addItem:redoItem];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Cut"
                                                  action:@selector(cut:)
                                           keyEquivalent:@"x"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Copy"
                                                  action:@selector(copy:)
                                           keyEquivalent:@"c"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Paste"
                                                  action:@selector(paste:)
                                           keyEquivalent:@"v"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Select All"
                                                  action:@selector(selectAll:)
                                           keyEquivalent:@"a"]];
    [editMenuItem setSubmenu:editMenu];
    [menubar addItem:editMenuItem];

    // -- Window Menu --
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu
        addItem:[[NSMenuItem alloc] initWithTitle:@"Minimize"
                                           action:@selector(performMiniaturize:)
                                    keyEquivalent:@"m"]];
    [windowMenu
        addItem:[[NSMenuItem alloc] initWithTitle:@"Zoom"
                                           action:@selector(performZoom:)
                                    keyEquivalent:@""]];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu
        addItem:[[NSMenuItem alloc] initWithTitle:@"Bring All to Front"
                                           action:@selector(arrangeInFront:)
                                    keyEquivalent:@""]];
    [windowMenuItem setSubmenu:windowMenu];
    [menubar addItem:windowMenuItem];
    [NSApp setWindowsMenu:windowMenu];

    [NSApp setMainMenu:menubar];

    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    NSString *runtimePath = nil;
    if (runtime_dir) {
      runtimePath = [NSString stringWithUTF8String:runtime_dir];
    } else {
      runtimePath = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
      setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
    }

    [[NSFileManager defaultManager] createDirectoryAtPath:runtimePath
                              withIntermediateDirectories:YES
                                               attributes:@{
                                                 NSFilePosixPermissions : @0700
                                               }
                                                    error:nil];

    // Configure Vulkan ICD based on user-selected driver
    const char *vkDriver = WWNSettings_GetVulkanDriver();
    if (vkDriver && strcmp(vkDriver, "none") != 0) {
      NSBundle *mainBundle = [NSBundle mainBundle];
      NSString *icdName = nil;

      if (strcmp(vkDriver, "kosmickrisp") == 0) {
        icdName = @"kosmickrisp_icd";
      } else if (strcmp(vkDriver, "moltenvk") == 0) {
        icdName = @"MoltenVK_icd";
      }

      if (icdName) {
        NSString *bundleICD = [mainBundle pathForResource:icdName
                                                   ofType:@"json"
                                              inDirectory:@"vulkan/icd.d"];
        if (bundleICD) {
          setenv("VK_DRIVER_FILES", [bundleICD UTF8String], 1);
          WWNLog("MAIN", @"Vulkan: %s ICD from bundle: %@", vkDriver,
                 bundleICD);
        } else {
          WWNLog("MAIN",
                 @"Vulkan: %s ICD not found in bundle, using loader defaults",
                 vkDriver);
        }
      } else {
        WWNLog("MAIN", @"Vulkan: Unknown driver '%s', using loader defaults",
               vkDriver);
      }
    } else {
      WWNLog("MAIN", @"Vulkan drivers disabled (driver selection: none)");
      unsetenv("VK_DRIVER_FILES");
    }

    WWNLog("MAIN", @"Starting Rust-based WWN compositor (macOS)...");

    NSScreen *mainScreen = [NSScreen mainScreen];
    CGFloat scale = mainScreen.backingScaleFactor;

    // Initial output dimensions = the default window content size that
    // handleWindowCreated: will use for nested compositors and large
    // clients.  Using the macOS display size here would make Wayland
    // clients (especially nested compositors like Weston) render at the
    // full screen resolution even though they're in a windowed frame.
    CGFloat screenW = mainScreen.frame.size.width;
    CGFloat screenH = mainScreen.frame.size.height;
    uint32_t outputW = (uint32_t)fmin(1024, screenW * 0.75);
    uint32_t outputH = (uint32_t)fmin(768, screenH * 0.75);

    WWNCompositorBridge *rustCompositor = [WWNCompositorBridge sharedBridge];
    [rustCompositor setOutputWidth:outputW height:outputH scale:(float)scale];

    // Set initial SSD state
    BOOL forceSSD = WWNSettings_GetForceServerSideDecorations();
    [rustCompositor setForceSSD:forceSSD];
    WWNLog("MAIN", @"Initial Force SSD state: %d", forceSSD);

    BOOL compositorStarted = [rustCompositor startWithSocketName:@"wayland-0"];
    if (!compositorStarted) {
      if (wwn_is_compositor_socket_ready()) {
        WWNLog("MAIN", @"Compositor host already running; app will attach to shared runtime environment");
        setenv("WAYLAND_DISPLAY", "wayland-0", 1);
      } else {
        WWNLog("MAIN", @"Failed to start Rust compositor");
        return 1;
      }
    } else {
      setenv("WAYLAND_DISPLAY", [[rustCompositor socketName] UTF8String], 1);
      wwn_write_runtime_exports([rustCompositor socketName]);
      wwn_write_runtime_state(YES, [rustCompositor socketName],
                              [rustCompositor socketPath], @"app", nil);
    }
    setup_signal_sources();
    signal(SIGPIPE,
           SIG_IGN); // broken pipes from waypipe/SSH → EPIPE, not crash
    signal(SIGSEGV, crash_handler);
    signal(SIGABRT, crash_handler);
    signal(SIGBUS, crash_handler);
    signal(SIGILL, crash_handler);

    WWNLog("MAIN", @"Rust Compositor running!");
    [NSApp run];
    [rustCompositor stop];
  }
  return 0;
}

#endif
