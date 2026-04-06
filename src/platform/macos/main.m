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
#import "./ui/Settings/WWNPreferences.h"

// Global references for signal handler
extern volatile pid_t g_active_waypipe_pgid;

// Global cleanup for atexit
static int g_instance_lock_fd = -1;

static void release_instance_lock(void) {
  if (g_instance_lock_fd >= 0) {
    flock(g_instance_lock_fd, LOCK_UN);
    close(g_instance_lock_fd);
    g_instance_lock_fd = -1;
  }
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
  release_instance_lock();
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
  // WWN macOS launches with no windows — the compositor runs
  // in the background and the user can open Settings from the menu bar.
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

    for (int i = 1; i < argc; i++) {
      if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-v") == 0) {
#ifdef WAWONA_VERSION
        printf("Wawona v%s\n", WAWONA_VERSION);
#else
        printf("Wawona unknown\n");
#endif
        return 0;
      }
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

    if (![rustCompositor startWithSocketName:@"wayland-0"]) {
      WWNLog("MAIN", @"Failed to start Rust compositor");
      return 1;
    }

    setenv("WAYLAND_DISPLAY", [[rustCompositor socketName] UTF8String], 1);
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
