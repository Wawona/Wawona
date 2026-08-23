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
#import "./ui/Settings/WWNWaypipeRunner.h"
#import "./ui/Machines/WWNMachineProfileStore.h"
#import "./ui/Machines/WWNMachineSessionBridge.h"
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
#import "../ios/WWNExternalDisplaySupport.h"
#import "../ios/WWNGameControllerManager.h"
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
    runtimePath = [WWNPreferencesManager preferredSharedRuntimeDir];
    setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
    WWNLog("MAIN", @"Set XDG_RUNTIME_DIR to: %@", runtimePath);
  }

  // 2. Apply the selected parallel Vulkan and GLES/ANGLE policies.
  WWNSettings_ApplyGraphicsDriverSelection();

  // 3. Initialize Rust Compositor
  WWNCompositorBridge *compositor = [WWNCompositorBridge sharedBridge];

  BOOL compositorStarted = NO;
  if (compositor) {
    // Prefer the live screen size; scene delegate refines from
    // compositorContainer.bounds once the UIWindowScene is available.
    CGSize screenSize = CGSizeMake(0, 0);
    BOOL autoScale = [[WWNPreferencesManager sharedManager] autoScale];
#if TARGET_OS_VISION
    // UIScreen is unavailable on visionOS; scene scale is applied later.
    CGFloat nativeScale = 2.0;
#else
    CGFloat nativeScale = UIScreen.mainScreen.scale;
    if (nativeScale <= 0.0) {
      nativeScale = 2.0;
    }
    screenSize = UIScreen.mainScreen.bounds.size;
#endif
    if (screenSize.width < 1.0 || screenSize.height < 1.0) {
      screenSize = CGSizeMake(390, 844);
    }
    CGFloat scale = autoScale ? nativeScale : 1.0;

    [compositor setOutputWidth:(uint32_t)screenSize.width
                        height:(uint32_t)screenSize.height
                         scale:(float)scale];

    compositorStarted = [compositor startWithSocketName:@"wayland-0"];
  }
  if (!compositorStarted) {
    WWNLog("MAIN", @"Error: Failed to start Rust compositor. Continuing so "
                   @"Machines UI can still load");
  } else {
    setenv("WAYLAND_DISPLAY", [[compositor socketName] UTF8String], 1);
  }

  // 3. Configure iOS UI -> MOVED TO SCENE DELEGATE

  // 4. Hardware input: gamepads, GCMouse, GCKeyboard presence.
  [[WWNGameControllerManager sharedManager] start];

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
#if !TARGET_OS_TV && !TARGET_OS_VISION
  if (@available(iOS 16.0, *)) {
    if ([connectingSceneSession.role
            isEqualToString:
                UIWindowSceneSessionRoleExternalDisplayNonInteractive]) {
      UISceneConfiguration *external =
          [[UISceneConfiguration alloc] initWithName:@"External Display"
                                         sessionRole:connectingSceneSession.role];
      external.delegateClass = [WWNExternalSceneDelegate class];
      return external;
    }
  }
#endif
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

    // Ignore SIGPIPE. Broken pipes from waypipe/SSH connections must not
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
#import "./ui/Machines/WWNDesktopReplacementController.h"
#import "./ui/Settings/WWNPreferences.h"
#import "WWNLaunchAgentManager.h"

// Global references for signal handler
extern volatile pid_t g_active_waypipe_pgid;

// Global cleanup for atexit
static int g_instance_lock_fd = -1;
static int g_host_lock_fd = -1;
static int g_menubar_lock_fd = -1;
static BOOL g_show_about_on_launch = NO;
static BOOL g_show_settings_on_launch = NO;
static BOOL g_service_host_mode = NO;

// Compositor-host is an agent: same Mach-O as the Machines UI, so Cocoa will
// otherwise put a second Wawona icon in the Dock when it creates client
// windows or is activated. WWNSetServiceHostMode / WWNKeepServiceHostOutOfDock
// live in WWNPlatformCallbacks.m.
/* CLI: run compositor without opening Machines / Settings. */
static BOOL g_cli_headless = NO;
static NSString *g_cli_client = nil;
static NSString *g_cli_machine = nil;
static NSString *g_cli_backend = nil;

static void wwn_print_cli_help(void) {
  printf(
      "Wawona. Wayland compositor for macOS (and Apple / Android targets)\n"
      "\n"
      "Usage:\n"
      "  Wawona [options]\n"
      "\n"
      "Informational (no GUI, no instance lock):\n"
      "  -h, --help              Show this help and exit\n"
      "  -v, --version           Print version and exit\n"
      "  --list-clients          List bundled client ids and exit\n"
      "  --list-machines         List saved Machines profiles and exit\n"
      "  --mode-b-status         Desktop Replacement Mode B status and exit\n"
      "  --mode-b-ready          Classic gate: takeover-now, reboot, or blocked\n"
      "                          (prints VERDICT and REASON)\n"
      "  --mode-b-machine <id>   Select Desktop Take Over machine (id, name,\n"
      "                          or weston). Creates Weston Desktop if needed.\n"
      "                          Does not take over the screen\n"
      "  --mode-b-stage          Install helper + dylib for this build, no take-over\n"
      "  --mode-b-engage         takeover-now: take over. reboot: native Restart\n"
      "                          sheet. blocked: print exact reason\n"
      "  --mode-b-probe          Same wait as engage, keep WindowServer\n"
      "  --mode-b-disengage      Full Mode B teardown and restore WindowServer\n"
      "\n"
      "GUI vs headless:\n"
      "  (default)               Start compositor + Machines control panel\n"
      "  --headless, --no-gui    Compositor only. No Machines / Settings UI\n"
      "  --gui                   Force Machines UI (overrides --headless)\n"
      "\n"
      "Start software (after compositor is up):\n"
      "  --client <id>           Launch a bundled client (implies --headless\n"
      "                          unless --gui is also passed). Examples:\n"
      "                            weston, niri, weston-simple-egl,\n"
      "                            weston-simple-shm, opengl-cube, vkcube,\n"
      "                            weston-terminal, foot, kmscube\n"
      "  --machine <id>          Connect a saved Machines profile by id\n"
      "                          (implies --headless unless --gui)\n"
      "\n"
      "Nested compositor display backend (weston / niri):\n"
      "  --backend <mode>        auto | wayland | drm\n"
      "                            wayland. Nest as a Wayland client of Wawona\n"
      "                            drm. Wwn-iland userspace DRM/KMS/GBM\n"
      "                                      (needs OpenGLDriver ≠ none)\n"
      "                            auto. Nested wayland (safe default)\n"
      "\n"
      "Service modes (LaunchAgents):\n"
      "  --compositor-host       Compositor service without Machines\n"
      "  --menubar               Menu-bar agent\n"
      "  --show-about            Show About instead of Machines\n"
      "  --show-settings         Show Settings instead of Machines\n"
      "\n"
      "Examples:\n"
      "  # Nested Weston (Wayland backend) without the Machines GUI\n"
      "  Wawona --headless --backend wayland --client weston\n"
      "\n"
      "  # Niri on wwn-iland userspace DRM/KMS\n"
      "  Wawona --headless --backend drm --client niri\n"
      "\n"
      "  # Start a saved Machines profile from the shell\n"
      "  Wawona --machine my-niri-drm\n"
      "\n"
      "Desktop Replacement (macOS Mode B, no Machines UI):\n"
      "  Wawona --mode-b-machine weston\n"
      "  Wawona --mode-b-status\n"
      "  Wawona --mode-b-ready\n"
      "  Wawona --mode-b-probe\n"
      "  Wawona --mode-b-probe --machine <id>\n"
      "  Wawona --mode-b-engage\n"
      "  Wawona --mode-b-disengage\n"
      "  Logs: /tmp/wawona-modeb-cli.log and /tmp/wawona-modeb.log\n"
      "\n"
      "Socket: WAYLAND_DISPLAY=wayland-0 under /tmp/wawona-$UID/\n"
      "Prefs:  Settings → Advanced → Display Backend (same as --backend)\n");
}

static void wwn_print_list_clients(void) {
  static const char *kClients[] = {
      "weston",
      "niri",
      "weston-simple-egl",
      "weston-simple-shm",
      "weston-terminal",
      "foot",
      "opengl-cube",
      "vkcube",
      "kmscube",
      "neovim",
      "fastfetch",
      "phoon",
      "fuzzel",
      NULL,
  };
  printf("Bundled client ids (pass to --client):\n");
  for (const char **p = kClients; *p; p++)
    printf("  %s\n", *p);
}

static int wwn_print_list_machines(void) {
  @autoreleasepool {
    NSArray<WWNMachineProfile *> *profiles =
        [WWNMachineProfileStore loadProfiles];
    if (profiles.count == 0) {
      printf("No Machines profiles saved yet.\n");
      return 0;
    }
    printf("%-28s  %-16s  %s\n", "MACHINE ID", "TYPE", "NAME");
    for (WWNMachineProfile *p in profiles) {
      printf("%-28s  %-16s  %s\n", p.machineId.UTF8String ?: "?",
             p.type.UTF8String ?: "?", p.name.UTF8String ?: "");
    }
  }
  return 0;
}

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
  // Menubar polls this on a timer. Prefer cheap access(2) on a cached socket
  // path; only re-parse the runtime plist every few seconds (or when the
  // socket disappears) so we avoid main-thread plist I/O every tick.
  static NSString *cachedSocketPath;
  static BOOL cachedHealthy = NO;
  static CFAbsoluteTime lastPlistRead = 0;
  static const CFTimeInterval kPlistRefreshSeconds = 8.0;

  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (cachedSocketPath.length > 0 &&
      (now - lastPlistRead) < kPlistRefreshSeconds) {
    if (access(cachedSocketPath.fileSystemRepresentation, F_OK) == 0) {
      return cachedHealthy;
    }
    // Socket vanished. Fall through and re-read plist.
  }

  lastPlistRead = now;
  NSDictionary *state =
      [NSDictionary dictionaryWithContentsOfFile:wwn_runtime_state_path()];
  if (![state isKindOfClass:[NSDictionary class]]) {
    cachedSocketPath = nil;
    cachedHealthy = NO;
    return NO;
  }
  cachedHealthy = [state[@"healthy"] boolValue];
  NSString *socketPath =
      [state[@"socketPath"] isKindOfClass:[NSString class]] ? state[@"socketPath"]
                                                             : @"";
  cachedSocketPath = socketPath.length > 0 ? [socketPath copy] : nil;
  if (!cachedHealthy || cachedSocketPath.length == 0) {
    return NO;
  }
  return access(cachedSocketPath.fileSystemRepresentation, F_OK) == 0;
}

static NSString *WWNReopenPanelName(void) {
  if (g_show_settings_on_launch) {
    return @"settings";
  }
  if (g_show_about_on_launch) {
    return @"about";
  }
  return @"machines";
}

static void activate_existing_instance(void) {
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:@"WWNReopenUINotification"
                    object:nil
                  userInfo:@{@"panel" : WWNReopenPanelName()}
        deliverImmediately:YES];
}

static BOOL wwn_ui_instance_is_running(void) {
  NSString *lockPath =
      [NSString stringWithFormat:@"/tmp/wawona-%d/instance.lock", getuid()];
  int fd = open([lockPath fileSystemRepresentation], O_CREAT | O_RDWR, 0600);
  if (fd < 0) {
    return NO;
  }
  BOOL running = flock(fd, LOCK_EX | LOCK_NB) != 0;
  if (!running) {
    flock(fd, LOCK_UN);
  }
  close(fd);
  return running;
}

static void wwn_launch_ui_process(NSArray<NSString *> *arguments) {
  NSString *bundlePath = WWNWawonaAppBundleRootForUI();
  NSString *exec =
      [bundlePath stringByAppendingPathComponent:@"Contents/MacOS/Wawona"];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:exec]) {
    WWNLog("MAIN", @"Wawona UI executable missing at %@", exec);
    return;
  }
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:exec];
  task.arguments = arguments.count > 0 ? arguments : @[];
  NSError *err = nil;
  if (![task launchAndReturnError:&err]) {
    WWNLog("MAIN", @"Failed to launch Wawona UI: %@", err);
  }
}

static void wwn_open_ui_panel(NSString *panel) {
  NSString *name = panel.length > 0 ? panel : @"machines";
  if (wwn_ui_instance_is_running()) {
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:@"WWNReopenUINotification"
                      object:nil
                    userInfo:@{@"panel" : name}
          deliverImmediately:YES];
    return;
  }
  NSArray<NSString *> *args = @[];
  if ([name isEqualToString:@"settings"]) {
    args = @[ @"--show-settings" ];
  } else if ([name isEqualToString:@"about"]) {
    args = @[ @"--show-about" ];
  }
  wwn_launch_ui_process(args);
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
static volatile sig_atomic_t g_shutdown_requested = 0;

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
  if (g_shutdown_requested) {
    _exit(128 + sig);
  }
  g_shutdown_requested = 1;
  dispatch_async(dispatch_get_main_queue(), ^{
    [[WWNWaypipeRunner sharedRunner] stopAllNativeClients];
    [NSApp terminate:nil];
  });
}

// Simple signal setup
static void setup_signal_sources(void) {
  signal(SIGTERM, raw_signal_handler);
  signal(SIGINT, raw_signal_handler);
}

@interface WWNMacAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation WWNMacAppDelegate

- (void)handleReopenNotification:(NSNotification *)notif {
  NSString *panel = nil;
  id raw = notif.userInfo[@"panel"];
  if ([raw isKindOfClass:[NSString class]]) {
    panel = raw;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    if ([panel isEqualToString:@"settings"]) {
      [[WWNPreferences sharedPreferences] showPreferences:NSApp];
    } else if ([panel isEqualToString:@"about"]) {
      [[WWNAboutPanel sharedAboutPanel] showAboutPanel:NSApp];
    } else {
      [[WWNMachinesCoordinator sharedCoordinator] showMachinesWindowAndActivate:YES];
    }
  });
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  if (g_service_host_mode) {
    WWNKeepServiceHostOutOfDock();
    return;
  }
  
  [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                    selector:@selector(handleReopenNotification:)
                                                        name:@"WWNReopenUINotification"
                                                      object:nil];
                                                      
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];

  if (g_cli_backend.length > 0) {
    // Session-only: do not rewrite Settings prefs from a one-shot CLI invoke.
    WWNSetCompositorBackendCLIOverride(g_cli_backend);
    WWNLog("MAIN", @"CLI --backend=%@", g_cli_backend);
  }

  // Acceptance / CLI: reach a bundled client without tapping Machines.
  NSString *autoClient = g_cli_client;
  if (autoClient.length == 0) {
    const char *autoClientEnv = getenv("WAWONA_AUTO_CLIENT");
    if (autoClientEnv && autoClientEnv[0])
      autoClient = [NSString stringWithUTF8String:autoClientEnv];
  }
  if ((autoClient.length > 0 || g_cli_machine.length > 0 || g_cli_headless) &&
      ![prefs hasSeenWelcome]) {
    // Welcome sheet is modal and would block headless / auto-client start.
    [prefs setHasSeenWelcome:YES];
  }
  if (![prefs hasSeenWelcome] && !g_cli_headless) {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Welcome to Wawona";
    alert.informativeText =
        @"A clean Wayland compositor experience for macOS, iOS, and Android.";
    [alert addButtonWithTitle:@"Continue"];
    if (alert.buttons.count > 0) {
      NSButton *continueButton = alert.buttons.firstObject;
      continueButton.accessibilityIdentifier = @"wwn.welcome.continue";
      continueButton.accessibilityLabel = @"Continue";
    }
    [alert runModal];
    [prefs setHasSeenWelcome:YES];
  }
  if (g_show_about_on_launch) {
    [[WWNAboutPanel sharedAboutPanel] showAboutPanel:NSApp];
  } else if (g_show_settings_on_launch) {
    [[WWNPreferences sharedPreferences] showPreferences:NSApp];
  } else if (!g_cli_headless) {
    [[WWNMachinesCoordinator sharedCoordinator] showMachinesWindowAndActivate:YES];
  } else {
    WWNLog("MAIN",
           @"Headless CLI. Compositor running; Machines UI suppressed "
           @"(WAYLAND_DISPLAY=wayland-0)");
    // Accessory: stay out of the Dock / Cmd-Tab unless the user opens UI later.
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
  }

  void (^startClient)(void) = ^{
    if (g_cli_machine.length > 0) {
      WWNMachineProfile *profile =
          [WWNMachineProfileStore profileById:g_cli_machine];
      if (!profile) {
        WWNLog("MAIN", @"--machine '%@' not found (try --list-machines)",
               g_cli_machine);
        return;
      }
      NSError *err = nil;
      if (![WWNMachineSessionBridge connectProfile:profile error:&err]) {
        WWNLog("MAIN", @"--machine %@ failed: %@", g_cli_machine,
               err.localizedDescription ?: @"unknown");
      } else {
        WWNLog("MAIN", @"Connected machine %@", g_cli_machine);
      }
      return;
    }
    if (autoClient.length > 0) {
      WWNLog("MAIN", @"CLI --client=%@. Starting bundled client", autoClient);
      [[WWNWaypipeRunner sharedRunner] launchBundledClientWithId:autoClient];
    }
  };

  if (autoClient.length > 0 || g_cli_machine.length > 0) {
    // Give the compositor bridge the same head start Machines Start implies.
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), startClient);
  }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  WWNLog("MAIN",
         @"macOS application will terminate - shutting down gracefully");
  cleanup_on_exit();
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  if (g_service_host_mode) {
    // Launch Services delivered the Dock / Launchpad click to the compositor
    // host (same bundle id as the Machines UI). Forward to the UI process.
    // Do not `open` the bundle: that activates this host again and can spawn
    // a second Dock tile.
    wwn_open_ui_panel(@"machines");
    return NO;
  }
  
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  if (!flag) {
    [[WWNMachinesCoordinator sharedCoordinator] showMachinesWindowAndActivate:YES];
  }
  return YES;
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

- (void)restartCompositor:(id)sender {
  (void)sender;
  [[WWNLaunchAgentManager sharedManager] restartCompositorAgent];
}

- (void)stopCompositor:(id)sender {
  (void)sender;
  [[WWNLaunchAgentManager sharedManager] stopCompositorAgent];
}

- (void)startCompositor:(id)sender {
  (void)sender;
  [[WWNLaunchAgentManager sharedManager] startCompositorAgent];
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

static void wwn_install_host_main_menu(id target) {
  NSMenu *menubar = [[NSMenu alloc] init];
  NSString *appName = @"Wawona";

  NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
  NSMenu *appMenu = [[NSMenu alloc] init];
  NSMenuItem *aboutItem = [[NSMenuItem alloc]
      initWithTitle:[NSString stringWithFormat:@"About %@", appName]
             action:@selector(showAboutPanel:)
      keyEquivalent:@""];
  aboutItem.target = target;
  [appMenu addItem:aboutItem];
  [appMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *prefsItem = [[NSMenuItem alloc] initWithTitle:@"Settings..."
                                                     action:@selector(showPreferences:)
                                              keyEquivalent:@","];
  prefsItem.target = target;
  [appMenu addItem:prefsItem];
  NSMenuItem *machinesItem = [[NSMenuItem alloc] initWithTitle:@"Machines..."
                                                         action:@selector(showMachines:)
                                                  keyEquivalent:@"m"];
  machinesItem.target = target;
  [machinesItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                           NSEventModifierFlagShift];
  [appMenu addItem:machinesItem];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Quit %@", appName]
                                              action:@selector(terminate:)
                                       keyEquivalent:@"q"]];
  [appMenuItem setSubmenu:appMenu];
  [menubar addItem:appMenuItem];

  NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
  NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  [fileMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Close Window"
                                                action:@selector(performClose:)
                                         keyEquivalent:@"w"]];
  [fileMenuItem setSubmenu:fileMenu];
  [menubar addItem:fileMenuItem];

  NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
  NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Undo"
                                                action:NSSelectorFromString(@"undo:")
                                         keyEquivalent:@"z"]];
  NSMenuItem *redoItem = [[NSMenuItem alloc] initWithTitle:@"Redo"
                                                    action:NSSelectorFromString(@"redo:")
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

  NSMenuItem *selectionMenuItem = [[NSMenuItem alloc] init];
  NSMenu *selectionMenu = [[NSMenu alloc] initWithTitle:@"Selection"];
  [selectionMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Select All"
                                                     action:@selector(selectAll:)
                                              keyEquivalent:@"a"]];
  [selectionMenuItem setSubmenu:selectionMenu];
  [menubar addItem:selectionMenuItem];

  NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
  NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
  [viewMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Enter Full Screen"
                                                action:@selector(toggleFullScreen:)
                                         keyEquivalent:@"f"]];
  [viewMenuItem setSubmenu:viewMenu];
  [menubar addItem:viewMenuItem];

  NSMenuItem *goMenuItem = [[NSMenuItem alloc] init];
  NSMenu *goMenu = [[NSMenu alloc] initWithTitle:@"Go"];
  NSMenuItem *goMachinesItem = [[NSMenuItem alloc] initWithTitle:@"Machines"
                                                           action:@selector(showMachines:)
                                                    keyEquivalent:@"m"];
  goMachinesItem.target = target;
  [goMenu addItem:goMachinesItem];
  [goMenuItem setSubmenu:goMenu];
  [menubar addItem:goMenuItem];

  NSMenuItem *runMenuItem = [[NSMenuItem alloc] init];
  NSMenu *runMenu = [[NSMenu alloc] initWithTitle:@"Run"];
  NSMenuItem *startItem = [[NSMenuItem alloc] initWithTitle:@"Start Compositor"
                                                      action:@selector(startCompositor:)
                                               keyEquivalent:@""];
  startItem.target = target;
  [runMenu addItem:startItem];
  NSMenuItem *stopItem = [[NSMenuItem alloc] initWithTitle:@"Stop Compositor"
                                                     action:@selector(stopCompositor:)
                                              keyEquivalent:@""];
  stopItem.target = target;
  [runMenu addItem:stopItem];
  NSMenuItem *restartItem = [[NSMenuItem alloc] initWithTitle:@"Restart Compositor"
                                                        action:@selector(restartCompositor:)
                                                 keyEquivalent:@"r"];
  restartItem.target = target;
  [runMenu addItem:restartItem];
  [runMenuItem setSubmenu:runMenu];
  [menubar addItem:runMenuItem];

  NSMenuItem *helpMenuItem = [[NSMenuItem alloc] init];
  NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
  NSMenuItem *helpAboutItem = [[NSMenuItem alloc] initWithTitle:@"About Wawona"
                                                          action:@selector(showAboutPanel:)
                                                   keyEquivalent:@""];
  helpAboutItem.target = target;
  [helpMenu addItem:helpAboutItem];
  [helpMenuItem setSubmenu:helpMenu];
  [menubar addItem:helpMenuItem];

  [NSApp setMainMenu:menubar];
}

@interface WWNMenuBarController : NSObject <NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSButton *startButton;
@property(nonatomic, strong) NSButton *stopButton;
@property(nonatomic, strong) NSButton *restartButton;
@property(nonatomic, strong) NSSwitch *loginAtLoginSwitch;
@property(nonatomic, strong) NSView *compositorRow;
@property(nonatomic, strong) NSView *loginRow;
@property(nonatomic, strong) NSTimer *pollTimer;
@end

static NSFont *WWNMenuBarItemFont(void) {
  return [NSFont menuFontOfSize:[NSFont systemFontSize]];
}

static NSButton *WWNMenuBarSymbolButton(NSString *symbol, NSString *label,
                                        id target, SEL action) {
  NSImage *image =
      [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
  NSImageSymbolConfiguration *cfg =
      [NSImageSymbolConfiguration configurationWithPointSize:13
                                                      weight:NSFontWeightMedium];
  image = [image imageWithSymbolConfiguration:cfg];
  NSButton *btn = [NSButton buttonWithImage:image target:target action:action];
  btn.bordered = NO;
  btn.imagePosition = NSImageOnly;
  btn.imageScaling = NSImageScaleProportionallyDown;
  btn.toolTip = label;
  btn.accessibilityLabel = label;
  btn.frame = NSMakeRect(0, 0, 22, 22);
  btn.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin;
  return btn;
}

static NSImage *WWNMenuBarTemplateIcon(void) {
  NSBundle *bundle = [NSBundle mainBundle];
  NSArray<NSString *> *candidates = @[
    @"Wawona-menubar-silhouette",
    @"Wawona-iOS-Dark-1024x1024@1x",
    @"Wawona-iOS-Dark-1024x1024",
    @"AppIcon-Dark-1024",
    @"AppIcon-Light-1024",
    @"Wawona"
  ];

  NSImage *icon = nil;
  for (NSString *name in candidates) {
    NSString *path = [bundle pathForResource:name ofType:@"png"];
    if (!path) {
      NSString *resourcePath = bundle.resourcePath ?: @"";
      NSString *candidate = [resourcePath stringByAppendingPathComponent:
                                              [name stringByAppendingString:@".png"]];
      if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
        path = candidate;
      }
    }
    if (path) {
      icon = [[NSImage alloc] initWithContentsOfFile:path];
      if (icon) {
        break;
      }
    }
  }

  if (!icon) {
    return nil;
  }

  // Use template rendering so macOS draws a monochrome menu bar silhouette.
  icon.template = YES;
  icon.size = NSMakeSize(18, 18);
  return icon;
}

@implementation WWNMenuBarController

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.toolTip = @"Wawona Compositor";
    NSImage *menuIcon = WWNMenuBarTemplateIcon();
    if (menuIcon) {
      _statusItem.button.image = menuIcon;
      _statusItem.button.imagePosition = NSImageOnly;
      _statusItem.button.title = @"";
    } else {
      _statusItem.button.title = @"Wawona";
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Wawona"];
    menu.autoenablesItems = NO;
    menu.delegate = self;

    NSView *compositorRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 268, 32)];
    compositorRow.autoresizesSubviews = YES;
    NSTextField *statusLabel = [NSTextField labelWithString:@"Compositor: unknown"];
    statusLabel.font = WWNMenuBarItemFont();
    statusLabel.frame = NSMakeRect(14, 6, 150, 20);
    statusLabel.autoresizingMask =
        NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    [compositorRow addSubview:statusLabel];
    _statusLabel = statusLabel;

    NSButton *restartBtn = WWNMenuBarSymbolButton(
        @"arrow.clockwise", @"Restart Compositor", self, @selector(restartCompositor:));
    NSButton *stopBtn = WWNMenuBarSymbolButton(
        @"stop.fill", @"Stop Compositor", self, @selector(stopCompositor:));
    NSButton *startBtn = WWNMenuBarSymbolButton(
        @"play.fill", @"Start Compositor", self, @selector(startCompositor:));
    [compositorRow addSubview:restartBtn];
    [compositorRow addSubview:stopBtn];
    [compositorRow addSubview:startBtn];
    _restartButton = restartBtn;
    _stopButton = stopBtn;
    _startButton = startBtn;
    _compositorRow = compositorRow;

    NSMenuItem *compositorItem = [[NSMenuItem alloc] initWithTitle:@""
                                                            action:nil
                                                     keyEquivalent:@""];
    compositorItem.view = compositorRow;
    [menu addItem:compositorItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSView *loginRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 268, 28)];
    loginRow.autoresizesSubviews = YES;
    NSTextField *loginLabel = [NSTextField labelWithString:@"Launch at Login"];
    loginLabel.font = WWNMenuBarItemFont();
    loginLabel.frame = NSMakeRect(14, 4, 160, 20);
    loginLabel.autoresizingMask =
        NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    [loginRow addSubview:loginLabel];

    NSSwitch *loginSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    loginSwitch.controlSize = NSControlSizeMini;
    loginSwitch.target = self;
    loginSwitch.action = @selector(toggleAppLaunchAtLogin:);
    [loginSwitch sizeToFit];
    loginSwitch.autoresizingMask =
        NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    [loginRow addSubview:loginSwitch];
    _loginAtLoginSwitch = loginSwitch;
    _loginRow = loginRow;
    NSMenuItem *toggleLogin = [[NSMenuItem alloc] initWithTitle:@""
                                                         action:nil
                                                  keyEquivalent:@""];
    toggleLogin.view = loginRow;
    [menu addItem:toggleLogin];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *openMachines =
        [[NSMenuItem alloc] initWithTitle:@"Machine Configuration"
                                   action:@selector(openWawonaApp:)
                            keyEquivalent:@""];
    openMachines.target = self;
    [menu addItem:openMachines];

    NSMenuItem *openSettings =
        [[NSMenuItem alloc] initWithTitle:@"Wawona Settings"
                                   action:@selector(openWawonaSettings:)
                            keyEquivalent:@""];
    openSettings.target = self;
    [menu addItem:openSettings];

    NSMenuItem *aboutItem =
        [[NSMenuItem alloc] initWithTitle:@"About Wawona"
                                   action:@selector(openWawonaAbout:)
                            keyEquivalent:@""];
    aboutItem.target = self;
    [menu addItem:aboutItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem =
        [[NSMenuItem alloc] initWithTitle:@"Quit Wawona"
                                   action:@selector(quitMenuBar:)
                            keyEquivalent:@""];
    quitItem.target = self;
    [menu addItem:quitItem];

    [self wwn_syncCustomMenuItemWidths:menu];
    _statusItem.menu = menu;
    _pollTimer = [NSTimer timerWithTimeInterval:2.0
                                         target:self
                                       selector:@selector(refreshStatus:)
                                       userInfo:nil
                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_pollTimer forMode:NSDefaultRunLoopMode];
    [self refreshStatus:nil];
  }
  return self;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
  [self wwn_syncCustomMenuItemWidths:menu];
  [self refreshStatus:nil];
}

- (void)wwn_syncCustomMenuItemWidths:(NSMenu *)menu {
  CGFloat width = 268.0;
  NSDictionary *attrs = @{NSFontAttributeName : WWNMenuBarItemFont()};
  for (NSMenuItem *item in menu.itemArray) {
    if (item.view || item.isSeparatorItem || item.title.length == 0) {
      continue;
    }
    CGFloat text = [item.title sizeWithAttributes:attrs].width;
    width = MAX(width, text + 48.0);
  }
  const CGFloat kTrailing = 12.0;
  const CGFloat kBtn = 22.0;
  const CGFloat kGap = 4.0;
  if (self.compositorRow) {
    NSRect frame = self.compositorRow.frame;
    frame.size.width = width;
    self.compositorRow.frame = frame;
    CGFloat x = width - kTrailing;
    self.startButton.frame =
        NSMakeRect(x - kBtn, 5, kBtn, kBtn);
    x -= (kBtn + kGap);
    self.stopButton.frame =
        NSMakeRect(x - kBtn, 5, kBtn, kBtn);
    x -= (kBtn + kGap);
    self.restartButton.frame =
        NSMakeRect(x - kBtn, 5, kBtn, kBtn);
    NSRect status = self.statusLabel.frame;
    status.size.width = MAX(80.0, x - kBtn - 8.0 - 14.0);
    self.statusLabel.frame = status;
  }
  if (self.loginRow && self.loginAtLoginSwitch) {
    NSRect frame = self.loginRow.frame;
    frame.size.width = width;
    self.loginRow.frame = frame;
    [self.loginAtLoginSwitch sizeToFit];
    NSSize sw = self.loginAtLoginSwitch.frame.size;
    CGFloat y = (frame.size.height - sw.height) / 2.0;
    self.loginAtLoginSwitch.frame =
        NSMakeRect(width - kTrailing - sw.width, y, sw.width, sw.height);
  }
}

- (void)refreshStatus:(id)sender {
  (void)sender;
  BOOL running = wwn_is_compositor_socket_ready();
  NSString *title =
      running ? @"Compositor: running" : @"Compositor: stopped";
  if (![self.statusLabel.stringValue isEqualToString:title]) {
    self.statusLabel.stringValue = title;
  }
  self.startButton.enabled = !running;
  self.stopButton.enabled = running;
  self.restartButton.enabled = running;
  BOOL loginOn = [[WWNLaunchAgentManager sharedManager] isAppLaunchAgentLoaded];
  self.loginAtLoginSwitch.state =
      loginOn ? NSControlStateValueOn : NSControlStateValueOff;
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
  BOOL wantOn = (self.loginAtLoginSwitch.state == NSControlStateValueOn);
  if (wantOn) {
    [manager enableAppLaunchAtLogin];
  } else {
    [manager disableAppLaunchAtLogin];
  }
  [self refreshStatus:nil];
}

- (void)openWawonaApp:(id)sender {
  (void)sender;
  wwn_open_ui_panel(@"machines");
}

- (void)openWawonaSettings:(id)sender {
  (void)sender;
  wwn_open_ui_panel(@"settings");
}

- (void)openWawonaAbout:(id)sender {
  (void)sender;
  wwn_open_ui_panel(@"about");
}

- (void)quitMenuBar:(id)sender {
  (void)sender;
  // Boot out KeepAlive agents and remove plists before exit so launchd
  // cannot reopen the menubar / compositor host.
  [[WWNLaunchAgentManager sharedManager] stopCompositorAndMenuAgents];
  [NSApp terminate:nil];
}

@end

/// Xcode / AppKit / Launch Services inject single-dash Cocoa keys (e.g.
/// `-NSDocumentRevisionsDebugMode YES`). Those are not Wawona CLI flags.
static BOOL wwn_is_cocoa_passthrough_arg(const char *arg) {
  if (arg == NULL || arg[0] != '-') {
    return NO;
  }
  // Double-dash is always our CLI surface.
  if (arg[1] == '-') {
    return NO;
  }
  if (strncmp(arg, "-NS", 3) == 0 || strncmp(arg, "-_NS", 4) == 0 ||
      strncmp(arg, "-Apple", 6) == 0 || strncmp(arg, "-psn_", 5) == 0) {
    return YES;
  }
  return NO;
}

int main(int argc, char *argv[]) {
  @autoreleasepool {
    // Overwrite argv[0] so macOS menu bar shows "Wawona" instead of the binary
    // name
    const char *desiredName = "Wawona";
    size_t maxLen = strlen(argv[0]);
    memset(argv[0], 0, maxLen);
    strncpy(argv[0], desiredName, maxLen);

    [[NSProcessInfo processInfo] setProcessName:@"Wawona"];
    // Do not restore prior AppKit window frames for Wayland client windows.
    [[NSUserDefaults standardUserDefaults] setBool:NO
                                              forKey:@"NSQuitAlwaysKeepsWindows"];
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    // --- Early CLI: --help / --version / list before any bundle env logging ---
    BOOL forceGui = NO;
    for (int i = 1; i < argc; i++) {
      const char *arg = argv[i];
      if (wwn_is_cocoa_passthrough_arg(arg)) {
        continue;
      }
      if (strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0) {
        wwn_print_cli_help();
        return 0;
      }
      if (strcmp(arg, "--version") == 0 || strcmp(arg, "-v") == 0) {
#ifdef WAWONA_VERSION
        printf("Wawona v%s\n", WAWONA_VERSION);
#else
        printf("Wawona unknown\n");
#endif
        return 0;
      }
      if (strcmp(arg, "--list-clients") == 0) {
        wwn_print_list_clients();
        return 0;
      }
      if (strcmp(arg, "--list-machines") == 0) {
        return wwn_print_list_machines();
      }
      /*
       * Mode B CLI: scan once for --mode-b-* and optional --machine /
       * --mode-b-machine, then select Desktop machine before the action.
       */
      if (strcmp(arg, "--mode-b-status") == 0 ||
          strcmp(arg, "--mode-b-ready") == 0 ||
          strcmp(arg, "--mode-b-stage") == 0 ||
          strcmp(arg, "--mode-b-probe") == 0 ||
          strcmp(arg, "--mode-b-engage") == 0 ||
          strcmp(arg, "--mode-b-disengage") == 0 ||
          strcmp(arg, "--mode-b-machine") == 0 ||
          strncmp(arg, "--mode-b-machine=", 17) == 0) {
        WWNLogSetQuiet(1);
        NSString *modeBSelect = nil;
        const char *modeBAction = NULL;
        for (int j = 1; j < argc; j++) {
          const char *a = argv[j];
          if (strcmp(a, "--mode-b-status") == 0) {
            modeBAction = "status";
          } else if (strcmp(a, "--mode-b-ready") == 0) {
            modeBAction = "ready";
          } else if (strcmp(a, "--mode-b-stage") == 0) {
            modeBAction = "stage";
          } else if (strcmp(a, "--mode-b-probe") == 0) {
            modeBAction = "probe";
          } else if (strcmp(a, "--mode-b-engage") == 0) {
            modeBAction = "engage";
          } else if (strcmp(a, "--mode-b-disengage") == 0) {
            modeBAction = "disengage";
          } else if (strcmp(a, "--mode-b-machine") == 0) {
            if (j + 1 >= argc) {
              fprintf(stderr,
                      "Wawona: --mode-b-machine requires an id/name "
                      "(or weston)\n");
              return 2;
            }
            modeBSelect = [NSString stringWithUTF8String:argv[++j]];
            if (!modeBAction) {
              modeBAction = "select";
            }
          } else if (strncmp(a, "--mode-b-machine=", 17) == 0) {
            modeBSelect = [NSString stringWithUTF8String:a + 17];
            if (!modeBAction) {
              modeBAction = "select";
            }
          } else if (strcmp(a, "--machine") == 0) {
            if (j + 1 >= argc) {
              fprintf(stderr,
                      "Wawona: --machine requires an id "
                      "(see --list-machines)\n");
              return 2;
            }
            if (!modeBSelect) {
              modeBSelect = [NSString stringWithUTF8String:argv[++j]];
            } else {
              ++j;
            }
          } else if (strncmp(a, "--machine=", 10) == 0) {
            if (!modeBSelect) {
              modeBSelect = [NSString stringWithUTF8String:a + 10];
            }
          }
        }
        WWNDesktopReplacementController *ctl =
            [WWNDesktopReplacementController sharedController];
        if (modeBSelect.length > 0) {
          int sel = [ctl cliSelectDesktopMachine:modeBSelect];
          if (sel != 0) {
            return sel;
          }
          if (modeBAction && strcmp(modeBAction, "select") == 0) {
            return 0;
          }
        } else if (modeBAction && strcmp(modeBAction, "select") == 0) {
          fprintf(stderr,
                  "Wawona: --mode-b-machine requires an id/name "
                  "(or weston)\n");
          return 2;
        }
        if (modeBAction && strcmp(modeBAction, "status") == 0) {
          return [ctl cliStatus];
        }
        if (modeBAction && strcmp(modeBAction, "ready") == 0) {
          return [ctl cliReady];
        }
        if (modeBAction && strcmp(modeBAction, "stage") == 0) {
          return [ctl cliStage];
        }
        if (modeBAction && strcmp(modeBAction, "probe") == 0) {
          return [ctl cliEngageKeepWindowServer:YES];
        }
        if (modeBAction && strcmp(modeBAction, "engage") == 0) {
          return [ctl cliEngageKeepWindowServer:NO];
        }
        if (modeBAction && strcmp(modeBAction, "disengage") == 0) {
          return [ctl cliDisengage];
        }
      }
    }

    WWNConfigureBundledRuntimeEnvIfNeeded();

    BOOL compositorHostMode = NO;
    BOOL menuBarMode = NO;
    for (int i = 1; i < argc; i++) {
      const char *arg = argv[i];
      if (wwn_is_cocoa_passthrough_arg(arg)) {
        continue;
      }
      if (strcmp(arg, "--compositor-host") == 0) {
        compositorHostMode = YES;
      } else if (strcmp(arg, "--menubar") == 0) {
        menuBarMode = YES;
      } else if (strcmp(arg, "--show-about") == 0) {
        g_show_about_on_launch = YES;
      } else if (strcmp(arg, "--show-settings") == 0) {
        g_show_settings_on_launch = YES;
      } else if (strcmp(arg, "--headless") == 0 ||
                 strcmp(arg, "--no-gui") == 0) {
        g_cli_headless = YES;
      } else if (strcmp(arg, "--gui") == 0) {
        forceGui = YES;
      } else if (strcmp(arg, "--client") == 0) {
        if (i + 1 >= argc) {
          fprintf(stderr, "Wawona: --client requires an id (see --list-clients)\n");
          return 2;
        }
        g_cli_client = [NSString stringWithUTF8String:argv[++i]];
      } else if (strncmp(arg, "--client=", 9) == 0) {
        g_cli_client = [NSString stringWithUTF8String:arg + 9];
      } else if (strcmp(arg, "--machine") == 0) {
        if (i + 1 >= argc) {
          fprintf(stderr,
                  "Wawona: --machine requires an id (see --list-machines)\n");
          return 2;
        }
        g_cli_machine = [NSString stringWithUTF8String:argv[++i]];
      } else if (strncmp(arg, "--machine=", 10) == 0) {
        g_cli_machine = [NSString stringWithUTF8String:arg + 10];
      } else if (strcmp(arg, "--backend") == 0) {
        if (i + 1 >= argc) {
          fprintf(stderr,
                  "Wawona: --backend requires auto|wayland|drm\n");
          return 2;
        }
        g_cli_backend = [NSString stringWithUTF8String:argv[++i]];
      } else if (strncmp(arg, "--backend=", 10) == 0) {
        g_cli_backend = [NSString stringWithUTF8String:arg + 10];
      } else if (strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0 ||
                 strcmp(arg, "--version") == 0 || strcmp(arg, "-v") == 0 ||
                 strcmp(arg, "--list-clients") == 0 ||
                 strcmp(arg, "--list-machines") == 0 ||
                 strcmp(arg, "--mode-b-status") == 0 ||
                 strcmp(arg, "--mode-b-ready") == 0 ||
                 strcmp(arg, "--mode-b-stage") == 0 ||
                 strcmp(arg, "--mode-b-probe") == 0 ||
                 strcmp(arg, "--mode-b-engage") == 0 ||
                 strcmp(arg, "--mode-b-disengage") == 0 ||
                 strcmp(arg, "--mode-b-machine") == 0 ||
                 strncmp(arg, "--mode-b-machine=", 17) == 0) {
        // Already handled above.
      } else if (arg[0] == '-') {
        fprintf(stderr, "Wawona: unknown option '%s' (try --help)\n", arg);
        return 2;
      }
    }

    if (g_cli_backend.length > 0) {
      NSString *b = [g_cli_backend lowercaseString];
      if (!([b isEqualToString:@"auto"] || [b isEqualToString:@"wayland"] ||
            [b isEqualToString:@"drm"])) {
        fprintf(stderr,
                "Wawona: --backend must be auto, wayland, or drm (got '%s')\n",
                g_cli_backend.UTF8String);
        return 2;
      }
      g_cli_backend = b;
    }

    // --client / --machine imply headless unless the user asked for --gui.
    if (!forceGui && (g_cli_client.length > 0 || g_cli_machine.length > 0)) {
      g_cli_headless = YES;
    }
    if (forceGui) {
      g_cli_headless = NO;
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
      [[NSProcessInfo processInfo] setProcessName:@"WawonaCompositor"];
      [NSApplication sharedApplication];
      g_service_host_mode = YES;
      WWNSetServiceHostMode(YES);
      [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      void (^keepOut)(NSNotification *) = ^(__unused NSNotification *note) {
        WWNKeepServiceHostOutOfDock();
      };
      [nc addObserverForName:NSWindowDidBecomeKeyNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:keepOut];
      [nc addObserverForName:NSWindowDidBecomeMainNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:keepOut];
      [nc addObserverForName:NSApplicationDidBecomeActiveNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:keepOut];
      WWNMacAppDelegate *hostDelegate = [[WWNMacAppDelegate alloc] init];
      [NSApp setDelegate:hostDelegate];
      wwn_install_host_main_menu(hostDelegate);
      NSError *agentError = nil;
      (void)[[WWNLaunchAgentManager sharedManager] ensureMenuBarAgent:&agentError];

      NSString *runtimePath = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
      setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
      [[NSFileManager defaultManager] createDirectoryAtPath:runtimePath
                                withIntermediateDirectories:YES
                                                 attributes:@{
                                                   NSFilePosixPermissions : @0700
                                                 }
                                                      error:nil];

      WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
      // wl_output mirrors the real display; per-window geometry overrides
      // handle nested-compositor host windows.
      NSScreen *hostScreen = [NSScreen mainScreen];
      NSSize hostScreenSize = hostScreen ? hostScreen.frame.size
                                         : NSMakeSize(1024, 768);
      CGFloat hostScale = hostScreen ? hostScreen.backingScaleFactor : 1.0;
      [bridge setOutputWidth:(uint32_t)hostScreenSize.width
                      height:(uint32_t)hostScreenSize.height
                       scale:(float)hostScale];
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
      WWNLog("MAIN", @"Rust Compositor running!");
      
      if ([[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsDesktopReplacementEnabled]) {
        NSString *desktopMachineId = [[NSUserDefaults standardUserDefaults] stringForKey:kWWNPrefsDesktopReplacementMachineId];
        if (desktopMachineId.length > 0) {
          WWNLog("MAIN", @"Compositor daemon: Desktop Replacement enabled. Auto-starting machine %@.", desktopMachineId);
          dispatch_async(dispatch_get_main_queue(), ^{
            WWNMachineProfile *profile = [WWNMachineProfileStore profileById:desktopMachineId];
            if (profile) {
              NSError *err = nil;
              if (![WWNMachineSessionBridge connectProfile:profile error:&err]) {
                WWNLog("MAIN", @"Failed to auto-start desktop replacement: %@", err);
              }
            }
          });
        }
      }

      WWNKeepServiceHostOutOfDock();
      [NSApp run];
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
          ensureCompositorAgent:&agentError];
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
    if (g_cli_headless) {
      [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    } else {
      [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    }

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
                                                  action:NSSelectorFromString(@"undo:")
                                           keyEquivalent:@"z"]];
    NSMenuItem *redoItem =
        [[NSMenuItem alloc] initWithTitle:@"Redo"
                                   action:NSSelectorFromString(@"redo:")
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

    WWNSettings_ApplyGraphicsDriverSelection();

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
