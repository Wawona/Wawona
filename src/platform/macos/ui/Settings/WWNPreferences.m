#import "WWNPreferences.h"
#import "../Machines/WWNMachinesCoordinator.h"
#import "../Machines/WWNMachineProfileStore.h"
#if TARGET_OS_OSX
#import "WWNSipStatus.h"
#import "../Machines/WWNDesktopReplacementController.h"
#endif
#import "../../platform/macos/WWNCompositorBridge.h"
#import "../../../../util/WWNLog.h"
#import "../../WWNPlatformCallbacks.h"
#import "../Helpers/WWNImageLoader.h"
#import "WWNPreferencesManager.h"
#import "WWNSettingsModel.h"
#import "WWNWaypipeRunner.h"
// #if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
// #import <HIAHKernel/HIAHKernel.h>
// #endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import "WWNSettingsSplitViewController.h"
#endif
//  #import "../../core/WWNKernel.h" // Removed
#import <Network/Network.h>
#import <objc/runtime.h>

// System headers removed as they are now used in WWNWaypipeRunner or unused
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif
#import <arpa/inet.h>
#import <errno.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <spawn.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <unistd.h>
#if TARGET_OS_IPHONE
#import "../../platform/ios/WWNIOSVersions.h"
#import "../../platform/macos/WWNRootfsProvider.h"
#if !TARGET_OS_TV && !TARGET_OS_WATCH
#import "../../platform/ios/WWNWatchCompanionBridge.h"
#endif
#if !TARGET_OS_TV
#import "../../platform/macos/WWNRootfsICloudSync.h"
#endif
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <libssh2.h>
#import "WWNSSHKeygen.h"
#else
#import "../../platform/macos/WWNRootfsProvider.h"
#import "WWNSSHKeygen.h"
#if !TARGET_OS_TV
#import "../../platform/macos/WWNRootfsICloudSync.h"
#endif
#endif

#ifndef WAWONA_VERSION
#if TARGET_OS_IPHONE && defined(WAWONA_VERSION_STRING)
#define WAWONA_VERSION WAWONA_VERSION_STRING
#else
#define WAWONA_VERSION "0.0.0-unknown"
#endif
#endif

#ifndef WAWONA_WAYLAND_VERSION
#if TARGET_OS_IPHONE && defined(WAWONA_WAYLAND_VERSION_STRING)
#define WAWONA_WAYLAND_VERSION WAWONA_WAYLAND_VERSION_STRING
#else
#define WAWONA_WAYLAND_VERSION "Bundled"
#endif
#endif

// Similar logic for other versions...
#ifndef WAWONA_WAYPIPE_VERSION
#if TARGET_OS_IPHONE && defined(WAWONA_WAYPIPE_VERSION_STRING)
#define WAWONA_WAYPIPE_VERSION WAWONA_WAYPIPE_VERSION_STRING
#else
#define WAWONA_WAYPIPE_VERSION "unknown"
#endif
#endif

#ifndef WAWONA_MESA_VERSION
#if TARGET_OS_IPHONE && defined(WAWONA_MESA_VERSION_STRING)
#define WAWONA_MESA_VERSION WAWONA_MESA_VERSION_STRING
#else
#define WAWONA_MESA_VERSION "Bundled"
#endif
#endif

#ifndef WAWONA_EPOLL_SHIM_VERSION
#if TARGET_OS_IPHONE && defined(WAWONA_EPOLL_SHIM_VERSION_STRING)
#define WAWONA_EPOLL_SHIM_VERSION WAWONA_EPOLL_SHIM_VERSION_STRING
#else
#define WAWONA_EPOLL_SHIM_VERSION "Bundled"
#endif
#endif

#ifndef WAWONA_LIBSSH2_VERSION
#define WAWONA_LIBSSH2_VERSION "Bundled"
#endif

#ifndef WAWONA_LIBFFI_VERSION
#define WAWONA_LIBFFI_VERSION "Bundled"
#endif

#ifndef WAWONA_LZ4_VERSION
#define WAWONA_LZ4_VERSION "Bundled"
#endif

#ifndef WAWONA_ZSTD_VERSION
#define WAWONA_ZSTD_VERSION "Bundled"
#endif

#ifndef WAWONA_XKBCOMMON_VERSION
#define WAWONA_XKBCOMMON_VERSION "Bundled"
#endif

#ifndef WAWONA_SSHPASS_VERSION
#define WAWONA_SSHPASS_VERSION "Bundled"
#endif

// MARK: - Helper Class Interfaces

#if !TARGET_OS_IPHONE
@interface WWNPreferencesSidebar
    : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property(nonatomic, weak) WWNPreferences *parent;
@property(nonatomic, strong) NSOutlineView *outlineView;
@end

@interface WWNPreferencesContent
    : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) WWNPreferencesSection *section;
@property(nonatomic, strong) NSTableView *tableView;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) NSView *environmentHostView;
- (void)reloadForCurrentSection;
@end
#endif

// MARK: - Main Class Extension

@interface WWNPreferences () <WWNWaypipeRunnerDelegate
#if TARGET_OS_IPHONE && !TARGET_OS_TV
                              ,
                              UITextFieldDelegate, UIDocumentPickerDelegate
#elif TARGET_OS_IPHONE
                              ,
                              UITextFieldDelegate
#else
                              ,
                              NSTextFieldDelegate, NSToolbarDelegate
#endif
                              >
@property(nonatomic, strong, readwrite)
    NSArray<WWNPreferencesSection *> *sections;
@property(nonatomic, strong) NSMutableString *waypipeStatusText;
@property(nonatomic, assign) BOOL waypipeMarkedConnected;
#if TARGET_OS_IPHONE
@property(nonatomic, strong) UIAlertController *waypipeStatusAlert;
// Which import a presented UIDocumentPicker is servicing (both the GPG/OpenSSH
// key import and the shell-home file import share this VC as delegate).
@property(nonatomic, assign) BOOL documentPickerImportsSSHKey;
@property(nonatomic, assign) BOOL documentPickerSendsToAppleWatch;
#if !TARGET_OS_TV
- (void)importPickedFileToShellHome:(NSArray<NSURL *> *)urls;
#endif
#else
@property(nonatomic, strong) NSSplitViewController *splitVC;
@property(nonatomic, strong) WWNPreferencesSidebar *sidebar;
@property(nonatomic, strong) WWNPreferencesContent *content;
@property(nonatomic, strong) NSWindowController *winController;
@property(nonatomic, strong) NSPanel *waypipeStatusPanel;
@property(nonatomic, strong) NSTextView *waypipeStatusTextView;
@property(nonatomic, strong) NSButton *waypipeStopButton;
#endif
- (NSArray<WWNPreferencesSection *> *)buildSections;
- (void)runWaypipe;
- (NSString *)localIPAddress;
- (NSString *)getLibSSH2Version;
- (NSString *)getSocketPath;
- (void)pingHost;
- (void)pingSSHHost;
- (void)testSSHConnection;
- (void)generateSSHKey;
- (void)importGPGSSHKey;
- (void)syncSSHKeyPrefsFromUI;
- (void)debouncedReloadData;
#if (TARGET_OS_IPHONE || TARGET_OS_OSX)
- (void)showLocalShellHelp;
#endif
#if TARGET_OS_OSX
- (void)showDesktopReplacementSipHowTo;
#endif
#if TARGET_OS_IPHONE
- (void)confirmResetShellDotfiles;
- (void)confirmReinstallSystemTree;
#endif
#if TARGET_OS_IPHONE && !TARGET_OS_TV
- (void)importFileToShellHome;
- (void)sendDocumentToAppleWatch;
- (void)sendPickedFileToAppleWatch:(NSArray<NSURL *> *)urls;
#endif
#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
- (void)handleLocalShellICloudSyncToggle:(BOOL)enabled;
#endif
#if !TARGET_OS_IPHONE
- (void)showSection:(NSInteger)idx;
- (void)toggleMacOSPasswordVisibility:(NSButton *)sender;
#endif
#if TARGET_OS_TV
- (void)tvSwitchButtonPressed:(UIButton *)button;
#endif
@end

// MARK: - Main Implementation

@implementation WWNPreferences

#if TARGET_OS_IPHONE
/// Load the About-header logo using the same cascading strategy as macOS:
/// always prefer the dark variant, with direct bundle-path fallback to
/// bypass iOS's @1x scale-suffix interpretation.
static UIImage *WWNAboutLogo(void) {
  NSBundle *bundle = [NSBundle mainBundle];
  NSFileManager *fm = [NSFileManager defaultManager];
  UIImage *img = nil;

  img = [UIImage imageNamed:@"Wawona-iOS-Dark-1024x1024@1x.png"];
  if (img)
    return img;

  NSString *path =
      [bundle pathForResource:@"Wawona-iOS-Dark-1024x1024@1x" ofType:@"png"];
  if (path) {
    img = [UIImage imageWithContentsOfFile:path];
    if (img)
      return img;
  }

  path = [bundle pathForResource:@"Wawona-iOS-Dark-1024x1024" ofType:@"png"];
  if (path) {
    img = [UIImage imageWithContentsOfFile:path];
    if (img)
      return img;
  }

  NSString *bundleRoot = [bundle bundlePath];
  NSString *direct = [bundleRoot
      stringByAppendingPathComponent:@"Wawona-iOS-Dark-1024x1024@1x.png"];
  if ([fm fileExistsAtPath:direct]) {
    img = [UIImage imageWithContentsOfFile:direct];
    if (img)
      return img;
  }

  direct = [bundleRoot
      stringByAppendingPathComponent:@"Wawona-iOS-Dark-1024x1024.png"];
  if ([fm fileExistsAtPath:direct]) {
    img = [UIImage imageWithContentsOfFile:direct];
    if (img)
      return img;
  }

  img = [UIImage imageNamed:@"Wawona"];
  if (img)
    return img;

  path = [bundle pathForResource:@"Wawona" ofType:@"png"];
  if (path) {
    img = [UIImage imageWithContentsOfFile:path];
    if (img)
      return img;
  }

  img = [UIImage imageNamed:@"Wawona-iOS-Light-1024x1024@1x.png"];
  if (img)
    return img;

  return nil;
}
#endif

+ (instancetype)sharedPreferences {
  static WWNPreferences *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

#if TARGET_OS_IPHONE
/// Safely present an alert, avoiding "presentation in progress" errors.
/// If another view controller is already being presented, dismiss it first.
- (void)presentSafeAlertWithTitle:(NSString *)title
                          message:(NSString *)message {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:title
                                          message:message
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];

  UIViewController *presenter = self;
  if (presenter.presentedViewController) {
    [presenter.presentedViewController
        dismissViewControllerAnimated:NO
                           completion:^{
                             [presenter presentViewController:alert
                                                     animated:YES
                                                   completion:nil];
                           }];
  } else {
    [presenter presentViewController:alert animated:YES completion:nil];
  }
}
#endif

#if !TARGET_OS_IPHONE
- (instancetype)init {
  self = [super init];
  if (self) {
    [WWNWaypipeRunner sharedRunner].delegate = self;
    self.sections = [self buildSections];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(defaultsChanged:)
               name:NSUserDefaultsDidChangeNotification
             object:nil];
  }
  return self;
}
#else
- (instancetype)init {
#if TARGET_OS_TV
  self = [super initWithStyle:UITableViewStyleGrouped];
#else
  self = [super initWithStyle:UITableViewStyleInsetGrouped];
#endif
  if (self) {
    self.title = @"Settings";
    [WWNWaypipeRunner sharedRunner].delegate = self;
    self.sections = [self buildSections];
    if (self.sections.count > 0) {
      self.activeSection = self.sections[0];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(dismissSelf)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier =
        @"wwn.settings.done";
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Done";
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(defaultsChanged:)
               name:NSUserDefaultsDidChangeNotification
             object:nil];
  }
  return self;
}
#endif

- (void)defaultsChanged:(NSNotification *)notification {
  static BOOL sLastForceSSD = NO;
  static BOOL sHasCheckedForceSSD = NO;

  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  BOOL enabled = [defs boolForKey:@"ForceServerSideDecorations"];
  if ([defs objectForKey:@"ForceServerSideDecorations"] || enabled) {
    if (!sHasCheckedForceSSD || sLastForceSSD != enabled) {
      sLastForceSSD = enabled;
      sHasCheckedForceSSD = YES;
      [[WWNCompositorBridge sharedBridge] setForceSSD:enabled];
      WWNLog("PREFS", @"Force SSD changed to: %d", enabled);
    }
  }

  [NSObject
      cancelPreviousPerformRequestsWithTarget:self
                                     selector:@selector(debouncedReloadData)
                                       object:nil];
  [self performSelector:@selector(debouncedReloadData)
             withObject:nil
             afterDelay:0.1];
}

- (void)debouncedReloadData {
  dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
    if (self.tableView) {
      [self.tableView reloadData];
    }
#else
    if (self.sidebar.outlineView) {
      [self.sidebar.outlineView reloadData];
    }
#endif
  });
}

#if TARGET_OS_IPHONE

- (void)viewDidLoad {
  [super viewDidLoad];

  self.view.accessibilityIdentifier = @"wwn.settings.root";
  self.view.accessibilityLabel = @"Settings";

  // Remove extra top padding
  self.tableView.tableHeaderView =
      [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1.0, 1.0)];

  __weak typeof(self) weakSelf = self;
  [self registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                    withHandler:^(
                        id<UITraitEnvironment> _Nonnull traitEnvironment,
                        UITraitCollection *_Nonnull previousCollection) {

                      __strong typeof(weakSelf) strongSelf = weakSelf;
                      if (!strongSelf) return;

                      [strongSelf.tableView reloadData];
                    }];
}

#endif

#define ITEM(t, k, ty, def, d)                                                 \
  [WWNSettingItem itemWithTitle:t key:k type:ty default:(def)desc:(d)]

#if TARGET_OS_IPHONE
- (void)setActiveSection:(WWNPreferencesSection *)activeSection {
  _activeSection = activeSection;
  if (activeSection.accessibilityIdentifier.length > 0) {
    self.tableView.accessibilityIdentifier = activeSection.accessibilityIdentifier;
    self.tableView.accessibilityLabel = activeSection.title;
  }
  if (self.isViewLoaded) {
    [self.tableView reloadData];
  }
}
#endif

- (NSArray<WWNPreferencesSection *> *)buildSections {
  NSMutableArray *sects = [NSMutableArray array];
  __weak typeof(self) weakSelf = self;

  // DISPLAY
  WWNPreferencesSection *display = [[WWNPreferencesSection alloc] init];
  display.title = @"Display";
  display.accessibilityIdentifier = @"wwn.settings.display";
  display.icon = @"display";
#if TARGET_OS_IPHONE
  display.iconColor = [UIColor systemBlueColor];
#else
  display.iconColor = [NSColor systemBlueColor];
#endif
  NSMutableArray *displayItems = [NSMutableArray arrayWithArray:@[
    ITEM(@"Force Server-Side Decorations", @"ForceServerSideDecorations",
         WSettingSwitch, @NO,
         @"When off, weston-family clients draw their own window frames."),
    ITEM(@"Auto Scale", @"AutoScale", WSettingSwitch, @YES,
         @"Matches macOS UI Scaling.")
  ]];

#if TARGET_OS_IPHONE
  // Respect Safe Area only makes sense on iOS (notch, Dynamic Island, etc.)
  [displayItems addObject:ITEM(@"Respect Safe Area", @"RespectSafeArea",
                               WSettingSwitch, @YES, @"Avoids notch areas.")];
#endif

  display.items = displayItems;
  [sects addObject:display];

  // INPUT
  WWNPreferencesSection *input = [[WWNPreferencesSection alloc] init];
  input.title = @"Input";
  input.accessibilityIdentifier = @"wwn.settings.input";
  input.icon = @"keyboard";
#if TARGET_OS_IPHONE
  input.iconColor = [UIColor systemPurpleColor];
#else
  input.iconColor = [NSColor systemPurpleColor];
#endif
  WWNSettingItem *touchInputItem =
      ITEM(@"Touch Input Type", @"TouchInputType", WSettingPopup,
           @"Multi-Touch", @"Input method for touch interactions.");
  touchInputItem.options = @[ @"Multi-Touch", @"Touchpad" ];

  BOOL showVirtualCursor =
      [[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsRenderMacOSPointer];
  WWNSettingItem *showVirtualCursorItem =
#if TARGET_OS_IPHONE
      ITEM(@"Show Virtual Cursor", @"RenderMacOSPointer", WSettingSwitch, @NO,
           @"Draws a host overlay pointer in touchpad mode.");
#else
      ITEM(@"Show Virtual Cursor", @"RenderMacOSPointer", WSettingSwitch, @NO,
           @"Enables virtual cursor control (host overlay or real macOS cursor).");
#endif
  WWNSettingItem *nestedCursorItem = ITEM(
      @"Nested Compositor Cursor", kWWNPrefsNestedCompositorCursor,
      WSettingPopup, @"virtual",
      @"When using nested compositors, grab the virtual pointer or the real "
      @"macOS / host cursor. Requires Show Virtual Cursor.");
  nestedCursorItem.options =
#if TARGET_OS_IPHONE
      @[ @"Virtual Pointer", @"Host Cursor" ];
#else
      @[ @"Virtual Pointer", @"macOS Cursor" ];
#endif
  nestedCursorItem.optionValues = @[ @"virtual", @"host" ];
  nestedCursorItem.interactive = showVirtualCursor;

  input.items = @[
    showVirtualCursorItem,
    nestedCursorItem,
    touchInputItem,
    ITEM(@"Resize Display for Virtual Keyboard",
         @"resizeDisplayForVirtualKeyboard", WSettingSwitch, @YES,
         @"host IME + Wawona extra keyboard."),
    ITEM(@"Swap CMD with ALT", @"SwapCmdWithAlt", WSettingSwitch, @YES,
         @"Swaps Command and Alt keys."),
    ITEM(@"Universal Clipboard", @"UniversalClipboard", WSettingSwitch, @YES,
         @"Syncs clipboard with macOS.")
  ];
  [sects addObject:input];

  // GRAPHICS
  WWNPreferencesSection *graphics = [[WWNPreferencesSection alloc] init];
  graphics.title = @"Graphics";
  graphics.accessibilityIdentifier = @"wwn.settings.graphics";
  graphics.icon = @"cpu";
#if TARGET_OS_IPHONE
  graphics.iconColor = [UIColor systemRedColor];
#else
  graphics.iconColor = [NSColor systemRedColor];
#endif
  WWNSettingItem *vulkanDriverItem =
#if TARGET_OS_TV || TARGET_OS_WATCH
      ITEM(@"Vulkan Driver", @"VulkanDriver", WSettingPopup, @"none",
           @"Vulkan is unavailable on this platform.");
#else
      ITEM(@"Vulkan Driver", @"VulkanDriver", WSettingPopup, @"moltenvk",
           @"Select the Vulkan ICD used by newly launched machine sessions.");
#endif
#if TARGET_OS_OSX
  vulkanDriverItem.options = @[ @"None", @"MoltenVK", @"KosmicKrisp", @"SwiftShader" ];
  vulkanDriverItem.optionValues =
      @[ @"none", @"moltenvk", @"kosmickrisp", @"swiftshader" ];
#elif TARGET_OS_TV || TARGET_OS_WATCH
  vulkanDriverItem.options = @[ @"None" ];
  vulkanDriverItem.optionValues = @[ @"none" ];
#else
  vulkanDriverItem.options = @[ @"None", @"MoltenVK" ];
  vulkanDriverItem.optionValues = @[ @"none", @"moltenvk" ];
#endif

  WWNSettingItem *openGLDriverItem =
#if TARGET_OS_TV || TARGET_OS_WATCH
      ITEM(@"OpenGL Driver", @"OpenGLDriver", WSettingPopup, @"none",
           @"OpenGL ES is unavailable on this platform.");
#else
      ITEM(@"OpenGL Driver", @"OpenGLDriver", WSettingPopup, @"angle",
           @"Select the OpenGL ES implementation used by newly launched machine sessions.");
#endif
#if TARGET_OS_TV || TARGET_OS_WATCH
  openGLDriverItem.options = @[ @"None" ];
  openGLDriverItem.optionValues = @[ @"none" ];
#elif TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  openGLDriverItem.options = @[ @"None", @"ANGLE" ];
  openGLDriverItem.optionValues = @[ @"none", @"angle" ];
#else
  openGLDriverItem.options = @[ @"None", @"ANGLE" ];
  openGLDriverItem.optionValues = @[ @"none", @"angle" ];
#endif

  graphics.items = @[
    vulkanDriverItem, openGLDriverItem,
    ITEM(@"Enable DMABUF", @"DmabufEnabled", WSettingSwitch, @YES,
         @"Zero-copy texture sharing.")
  ];
  [sects addObject:graphics];

  // CONNECTION — networking only. Wayland socket / XDG / TERM live in
  // Environment Variables (#157), not duplicated here.
  WWNPreferencesSection *connection = [[WWNPreferencesSection alloc] init];
  connection.title = @"Connection";
  connection.accessibilityIdentifier = @"wwn.settings.connection";
  connection.icon = @"network";
#if TARGET_OS_IPHONE
  connection.iconColor = [UIColor systemOrangeColor];
#else
  connection.iconColor = [NSColor systemOrangeColor];
#endif

  connection.items = @[
    ITEM(@"TCP Port", @"TCPListenerPort", WSettingInfo, @6000,
         @"Port for TCP listener. Wayland socket variables "
         @"(XDG_RUNTIME_DIR, WAYLAND_DISPLAY, …) are under "
         @"Environment Variables."),
  ];
  [sects addObject:connection];

  // ENVIRONMENT VARIABLES (#157) — single inventory + edit/reset surface.
  {
    WWNPreferencesSection *environment = [[WWNPreferencesSection alloc] init];
    environment.title = @"Environment Variables";
    environment.accessibilityIdentifier = @"wwn.settings.environment";
    environment.icon = @"list.bullet.rectangle";
#if TARGET_OS_IPHONE
    environment.iconColor = [UIColor systemTealColor];
#else
    environment.iconColor = [NSColor systemTealColor];
#endif
    // Detail pane embeds the full SwiftUI table (see showSection / selectSection).
    // Keep a fallback button for hosts that cannot embed yet.
    WWNSettingItem *manageBtn =
        ITEM(@"Open Environment Variables…", @"EnvironmentManage", WSettingButton,
             nil,
             @"View every variable Wawona injects. Edit, add, or Reset each "
             @"row to its catalog default. Per-machine overrides live in "
             @"Edit Machine → Environment Variables.");
    manageBtn.actionBlock = ^{
      [weakSelf openEnvironmentVariablesManager];
    };
    environment.items = @[ manageBtn ];
    [sects addObject:environment];
  }

  // LOCAL SHELL (WWN-ROOTFS — all platforms via WWNRootfsProvider)
  if ([WWNRootfsProvider capabilities] & WWNRootfsCapabilitySettings) {
    [WWNRootfsProvider prepareUserAccess];
    NSDictionary *rootfs = [WWNRootfsProvider snapshot];
    NSString *mode = rootfs[@"mode"] ?: @"host";
    NSString *bundleVersion = rootfs[@"bundleTemplateVersion"];
    NSString *appliedVersion = rootfs[@"appliedTemplateVersion"];
    NSString *templateStatus =
        [mode isEqualToString:@"host"]
            ? @"host shell"
            : [NSString
                  stringWithFormat:@"bundle v%@ / installed v%@", bundleVersion,
                                   appliedVersion.length ? appliedVersion
                                                         : @"—"];

    WWNPreferencesSection *localShell = [[WWNPreferencesSection alloc] init];
    localShell.title = @"Local Shell";
    localShell.accessibilityIdentifier = @"wwn.settings.local.shell";
    localShell.icon = @"terminal";
#if TARGET_OS_IPHONE
    localShell.iconColor = [UIColor systemGreenColor];
#else
    localShell.iconColor = [NSColor systemGreenColor];
#endif

    WWNRootfsCapabilities caps = [WWNRootfsProvider capabilities];
    NSMutableArray *localItems = [NSMutableArray arrayWithArray:@[
      ITEM(@"Platform", nil, WSettingInfo, rootfs[@"platformLabel"],
           @"Operating system for this Wawona build."),
      ITEM(@"Browse Hint", nil, WSettingInfo, rootfs[@"filesHint"],
           @"How to open shell files with the platform file manager."),
      ITEM(@"Shell HOME", nil, WSettingInfo, rootfs[@"home"],
           @"$HOME for the local / nested shell."),
      ITEM(@"System Root", nil, WSettingInfo, rootfs[@"systemRoot"],
           @"WAWONA_ROOTFS (bundled) or host runtime directory."),
      ITEM(@"Template Version", nil, WSettingInfo, templateStatus,
           @"Bundled vs installed rootfs template (mobile only)."),
    ]];

#if !TARGET_OS_TV
    if (caps & WWNRootfsCapabilityICloudSync) {
      BOOL iCloudOn = [WWNRootfsProvider isICloudSyncEnabled];
      [localItems addObject:
          ITEM(@"Sync Shell HOME via iCloud",
               WWNRootfsICloudSyncPreferenceKey, WSettingSwitch, @(iCloudOn),
               @"Optional. Syncs shell dotfiles and scripts across your Apple "
               @"devices via iCloud Drive. Requires iCloud sign-in.")];
      [localItems
          addObject:ITEM(@"iCloud Status", nil, WSettingInfo,
                         rootfs[@"iCloudStatus"] ?: @"", @"Current iCloud sync state.")];
    }
#endif

    if (caps & WWNRootfsCapabilityBrowseUserFiles) {
#if TARGET_OS_OSX
      WWNSettingItem *finderBtn =
          ITEM(@"Open HOME in Finder", @"RootfsOpenFinder", WSettingButton, nil,
               @"Reveal shell HOME in Finder.");
      finderBtn.actionBlock = ^{
        [weakSelf openLocalShellInFinder];
      };
      [localItems addObject:finderBtn];
#else
      WWNSettingItem *filesHelpBtn =
          ITEM(@"Browse User Files", @"RootfsFilesHelp", WSettingButton, nil,
               rootfs[@"filesHint"]);
      filesHelpBtn.actionBlock = ^{
        [weakSelf showLocalShellHelp];
      };
      [localItems addObject:filesHelpBtn];
#endif
    }

#if TARGET_OS_IPHONE && !TARGET_OS_TV
    if (caps & WWNRootfsCapabilityImportFile) {
      WWNSettingItem *importBtn =
          ITEM(@"Import File to Home", @"RootfsImportFile", WSettingButton, nil,
               @"Copy a file into shell HOME.");
      importBtn.actionBlock = ^{
        [weakSelf importFileToShellHome];
      };
      [localItems addObject:importBtn];
    }
#endif

    if (caps & WWNRootfsCapabilityResetDotfiles) {
      WWNSettingItem *resetDotfilesBtn =
          ITEM(@"Reset Shell Dotfiles", @"RootfsResetDotfiles", WSettingButton,
               nil,
               @"Restore .zshenv, .zshrc, and .zlogin from bundled templates.");
      resetDotfilesBtn.actionBlock = ^{
#if TARGET_OS_IPHONE
        [weakSelf confirmResetShellDotfiles];
#endif
      };
      [localItems addObject:resetDotfilesBtn];
    }

    if (caps & WWNRootfsCapabilityReinstallSystemTree) {
      WWNSettingItem *reinstallBtn = ITEM(@"Reinstall System Tree",
                                           @"RootfsReinstallSystem",
                                           WSettingButton, nil,
                                           @"Re-copy etc/ and usr/ from the app bundle.");
      reinstallBtn.actionBlock = ^{
#if TARGET_OS_IPHONE
        [weakSelf confirmReinstallSystemTree];
#endif
      };
      [localItems addObject:reinstallBtn];
    }

    localShell.items = localItems;
    [sects addObject:localShell];
  }

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST && !TARGET_OS_TV && !TARGET_OS_WATCH && !TARGET_OS_VISION
  // APPLE WATCH companion documents (WatchConnectivity — #151)
  {
    [[WWNWatchCompanionBridge sharedBridge] activate];
    WWNPreferencesSection *appleWatch = [[WWNPreferencesSection alloc] init];
    appleWatch.title = @"Apple Watch";
    appleWatch.accessibilityIdentifier = @"wwn.settings.appleWatch";
    appleWatch.icon = @"applewatch";
    appleWatch.iconColor = [UIColor systemPinkColor];

    WWNSettingItem *sendBtn =
        ITEM(@"Send Document to Watch", @"WatchCompanionSend", WSettingButton, nil,
             @"Copy a file (including .wasm) into the paired Watch Documents "
             @"inbox via WatchConnectivity. Does not require an app update. "
             @"Watch WASM runtime may still be off for size.");
    sendBtn.actionBlock = ^{
      [weakSelf sendDocumentToAppleWatch];
    };
    appleWatch.items = @[
      ITEM(@"Companion Status", nil, WSettingInfo,
           [[WWNWatchCompanionBridge sharedBridge] statusSummary],
           @"Paired Watch / Wawona Watch app / reachability."),
      ITEM(@"Last Transfer", nil, WSettingInfo,
           [[WWNWatchCompanionBridge sharedBridge] lastTransferSummary],
           @"Most recent send attempt from this iPhone."),
      sendBtn,
      ITEM(@"On the Watch", nil, WSettingInfo,
           @"Files land in Documents/Wawona/inbox. Open Files on iPhone → "
           @"On My iPhone → Wawona for local copies; Watch receives via "
           @"WatchConnectivity (not iCloud Drive).",
           @"Landing path and sync model."),
    ];
    [sects addObject:appleWatch];
  }
#endif

  // ADVANCED
  WWNPreferencesSection *advanced = [[WWNPreferencesSection alloc] init];
  advanced.title = @"Advanced";
  advanced.accessibilityIdentifier = @"wwn.settings.advanced";
  advanced.icon = @"gearshape.2";
#if TARGET_OS_IPHONE
  advanced.iconColor = [UIColor systemGrayColor];
#else
  advanced.iconColor = [NSColor systemGrayColor];
#endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  WWNSettingItem *nestedWestonBackendItem =
      ITEM(@"Nested Weston Backend", @"NestedWestonBackend", WSettingPopup,
           @"wayland-pixman",
           @"Wayland (Pixman) nests in a Wawona window. iland DRM (GL) presents "
           @"via Metal overlay (WWNIlandPresenter).");
  nestedWestonBackendItem.options =
      @[ @"Wayland (Pixman)", @"iland DRM (GL)" ];
  nestedWestonBackendItem.optionValues =
      @[ @"wayland-pixman", @"iland-drm-gl" ];
#endif
  // General per-client backend choice. niri and weston both have real DRM
  // backends; pinning them to nested Wayland discards the userspace DRM/KMS/GBM
  // path wwn-iland exists to provide. Per-machine profiles override this.
  WWNSettingItem *compositorBackendItem =
      ITEM(@"Display Backend", @"CompositorBackend", WSettingPopup, @"auto",
           @"How bundled clients and nested compositors present. Wayland runs "
           @"them nested inside Wawona; DRM/KMS runs them against wwn-iland's "
           @"userspace display stack, as they would on bare metal.");
  compositorBackendItem.options =
      @[ @"Auto", @"Wayland (nested)", @"DRM/KMS (wwn-iland)" ];
  compositorBackendItem.optionValues = @[ @"auto", @"wayland", @"drm" ];

  NSMutableArray *advancedItems = [NSMutableArray arrayWithArray:@[
    ITEM(@"Color Operations", @"ColorOperations", WSettingSwitch, @NO,
         @"Color profiles and HDR."),
    ITEM(@"Nested Compositors", @"NestedCompositorsSupport", WSettingSwitch,
         @YES, @"Support for nested compositors."),
  ]];
  [advancedItems addObject:compositorBackendItem];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [advancedItems addObject:nestedWestonBackendItem];
#endif
  [advancedItems addObject:ITEM(@"Multiple Clients", @"MultipleClients", WSettingSwitch,
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
         @NO,
#else
         @YES,
#endif
         @"Allow multiple Wayland clients to connect simultaneously.")];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#if TARGET_OS_TV
  [advancedItems addObject:ITEM(@"Long-press Menu to Exit Machine",
                                @"wawona.pref.shakeToCloseEnabled", WSettingSwitch, @YES,
                                @"Hold Menu/Back on the Siri Remote (~1s) to confirm closing the "
                                @"active machine session. Short Menu sends Escape to the client. "
                                @"(tvOS has no shake API.)")];
#else
  [advancedItems addObject:ITEM(@"Shake to Exit Machine", @"wawona.pref.shakeToCloseEnabled",
                                WSettingSwitch, @YES,
                                @"Shake the device to confirm closing the active machine session.")];
  [advancedItems addObject:ITEM(@"Swipe Back to Exit Machine",
                                @"wawona.pref.swipeBackToCloseEnabled", WSettingSwitch, @YES,
                                @"When enabled, edge swipe back asks before closing the active "
                                @"machine session. When off, swipe back closes immediately.")];
#endif
#endif
  advanced.items = advancedItems;
  [sects addObject:advanced];

#if TARGET_OS_OSX
  // DESKTOP REPLACEMENT (macOS only; wwn-iland Mode B; SIP-gated stretch).
  // Mirrors the Android Launcher desktop-replacement flow: the user picks a
  // single Native machine to become the Wayland desktop. On macOS this
  // corresponds to iland Mode B replacing SkyLight/WindowServer (requires SIP
  // disabled + root; never an App Store path). Non-native machines (VM,
  // container, waypipe/SSH) are intentionally not selectable.
  {
    WWNPreferencesSection *desktop = [[WWNPreferencesSection alloc] init];
    desktop.title = @"Desktop";
    desktop.accessibilityIdentifier = @"wwn.settings.desktop";
    desktop.icon = @"macwindow.on.rectangle";
    desktop.iconColor = [NSColor systemTealColor];

    NSMutableArray *desktopItems = [NSMutableArray array];

    // If the user previously enabled Desktop but SIP was re-enabled, clear the
    // pref so Mode B cannot engage until they fix SIP again.
    BOOL clearedForSip = [[WWNDesktopReplacementController sharedController]
        reconcilePrefsWithCurrentSip];

    // System Integrity Protection status — Mode B requires SIP disabled or
    // partially disabled (`csrutil enable --without debug`). Surface the current
    // state so the user knows whether desktop replacement can actually engage.
    WWNSipStatusType sipStatus = [WWNSipStatus current];
    BOOL sipAllowsDesktop = [WWNSipStatus allowsDesktopReplacement:sipStatus];
    if (clearedForSip) {
      sipAllowsDesktop = NO;
    }
    [desktopItems
        addObject:ITEM(@"System Integrity Protection", nil, WSettingInfo,
                       [WWNSipStatus describe:sipStatus],
                       sipAllowsDesktop
                           ? @"SIP permits wwn-iland Mode B (debugging and "
                             @"library injection). Desktop replacement can "
                             @"engage."
                           : @"SIP is blocking wwn-iland Mode B. Partially "
                             @"disable SIP before enabling desktop replacement "
                             @"(see SIP Requirements & How-To below).")];

    WWNSettingItem *sipHowToBtn =
        ITEM(@"SIP Requirements & How-To", @"DesktopReplacementSipHowTo",
             WSettingButton, nil,
             @"Why SIP must change, Recovery steps, and how this differs from "
             @"Android Desktop Replacement.");
    sipHowToBtn.actionBlock = ^{
      [weakSelf showDesktopReplacementSipHowTo];
    };
    [desktopItems addObject:sipHowToBtn];

    [desktopItems
        addObject:ITEM(@"Enable Desktop Replacement",
                       @"DesktopReplacementEnabled", WSettingSwitch, @NO,
                       @"Run Wawona as the macOS desktop by replacing "
                       @"SkyLight/WindowServer via wwn-iland Mode B. Requires "
                       @"SIP partially disabled (not App Store). Pick one "
                       @"nested-Weston machine below.")];

    // Machine picker, populated from the machine profile store. Only local
    // nested-Weston native machines qualify (App Bridge shares this selection),
    // so plain Weston demo clients / VM / container / SSH machines are excluded.
    NSArray<WWNMachineProfile *> *allProfiles =
        [WWNMachineProfileStore loadProfiles];
    NSMutableArray<NSString *> *nativeNames = [NSMutableArray array];
    NSMutableArray<NSString *> *nativeIds = [NSMutableArray array];
    for (WWNMachineProfile *p in allProfiles) {
      if ([WWNMachineProfileStore profileEligibleForAppBridge:p]) {
        NSString *label = p.name.length ? p.name : @"Unnamed Machine";
        [nativeNames addObject:label];
        [nativeIds addObject:p.machineId ?: @""];
      }
    }
    if (nativeIds.count > 0) {
      WWNSettingItem *machineItem =
          ITEM(@"Desktop Machine (nested Weston only)",
               @"DesktopReplacementMachineId", WSettingPopup,
               nativeIds.firstObject,
               @"The local Native machine whose nested Weston compositor "
               @"becomes the desktop. Plain Weston clients (weston-terminal, "
               @"simple-shm, foot) and remote/VM/container machines are not "
               @"eligible.");
      machineItem.options = nativeNames;
      machineItem.optionValues = nativeIds;
      [desktopItems addObject:machineItem];
    } else {
      [desktopItems
          addObject:ITEM(@"Desktop Machine", nil, WSettingInfo, @"None",
                         @"No eligible machine found. Create a Native machine "
                         @"running the nested Weston compositor "
                         @"(weston --backend=wayland) in Machine "
                         @"Configuration, then select it here.")];
    }

    // ── Wawona Swinging Bridge ──────────────────────────────────────────────
    [desktopItems
        addObject:ITEM(@"Wawona Swinging Bridge", @"SwingingBridgeEnabled", WSettingSwitch,
                       @NO,
                       @"Render native macOS apps as windows inside the nested "
                       @"Wayland desktop. Uses ScreenCaptureKit per-window "
                       @"capture plus CGEvent/Accessibility input injection, so "
                       @"it needs Screen Recording and Accessibility "
                       @"permissions (Developer ID, not the Mac App Store). "
                       @"Requires the desktop machine above to be a nested "
                       @"Weston compositor.")];

    // ── Lockscreen Replacement (#103) — macOS + Android only ─────────────
    [desktopItems
        addObject:ITEM(@"Enable Lockscreen Replacement",
                       @"LockscreenReplacementEnabled", WSettingSwitch, @NO,
                       @"Run a local greeter/lock machine (gtkgreet, gtklock, …) "
                       @"before the Desktop Replacement session. Never available "
                       @"on iOS/iPadOS/tvOS/watchOS/visionOS.")];
    NSMutableArray<NSString *> *lockNames = [NSMutableArray array];
    NSMutableArray<NSString *> *lockIds = [NSMutableArray array];
    for (WWNMachineProfile *p in allProfiles) {
      if (![p.type isEqualToString:kWWNMachineTypeNative])
        continue;
      NSDictionary *so =
          [p.settingsOverrides isKindOfClass:[NSDictionary class]]
              ? p.settingsOverrides
              : @{};
      NSString *cid = [so[@"NativeClientId"] isKindOfClass:[NSString class]]
                          ? so[@"NativeClientId"]
                          : @"";
      NSString *cmd = [so[@"NativeCustomCommand"] isKindOfClass:[NSString class]]
                          ? so[@"NativeCustomCommand"]
                          : @"";
      NSString *script =
          [p.customScript isKindOfClass:[NSString class]] ? p.customScript : @"";
      NSString *launcher =
          [[NSString stringWithFormat:@"%@ %@ %@", cid, cmd, script]
              lowercaseString];
      BOOL greeter = [launcher containsString:@"gtkgreet"] ||
                     [launcher containsString:@"gtklock"] ||
                     [launcher containsString:@"greetd"] ||
                     [launcher containsString:@"wlgreet"] ||
                     [launcher containsString:@"lock"];
      if (!greeter)
        continue;
      [lockNames addObject:p.name.length ? p.name : @"Unnamed Lock"];
      [lockIds addObject:p.machineId ?: @""];
    }
    if (lockIds.count > 0) {
      WWNSettingItem *lockMachine = ITEM(
          @"Lockscreen Machine (greeter)", @"LockscreenReplacementMachineId",
          WSettingPopup, lockIds.firstObject,
          @"Local Native greeter/lock machine. Unlock handoff resumes the "
          @"Desktop Replacement machine when Desktop is enabled.");
      lockMachine.options = lockNames;
      lockMachine.optionValues = lockIds;
      [desktopItems addObject:lockMachine];
    } else {
      [desktopItems
          addObject:ITEM(@"Lockscreen Machine", nil, WSettingInfo, @"None",
                         @"Create a Native machine with gtkgreet/gtklock (or "
                         @"similar) in Machine Configuration to enable "
                         @"Lockscreen Replacement.")];
    }

    desktop.items = desktopItems;
    [sects addObject:desktop];
  }
#endif

  // MACHINES (stubs)
  WWNPreferencesSection *machines = [[WWNPreferencesSection alloc] init];
  machines.title = @"Machines";
  machines.accessibilityIdentifier = @"wwn.settings.machines";
  machines.icon = @"server.rack";
#if TARGET_OS_IPHONE
  machines.iconColor = [UIColor systemCyanColor];
#else
  machines.iconColor = [NSColor systemCyanColor];
#endif
  machines.items = @[
    ITEM(@"Session Thumbnails", @"MachineSessionThumbnailsEnabled",
         WSettingSwitch, @YES,
         @"Save the last frame from a machine session and show it on machine cards."),
    // VM engine and container runtime are fixed per build target by the
    // wwn-vms / wwn-containers capability lanes; they are read-only here and
    // never user-configurable (Residual E). Engine swaps belong in the Nix
    // engines/bridges, not in user preferences.
    ITEM(@"Virtual Machine Engine", nil, WSettingInfo,
#if TARGET_OS_OSX
         @"Virtualization.framework",
#else
         @"QEMU (TCTI)",
#endif
         @"Selected automatically for this platform by wwn-vms. macOS: "
         @"Virtualization.framework. iOS/tvOS/visionOS: jitless QEMU-TCTI. "
         @"Android: QEMU/AVF."),
    ITEM(@"Virtual Machine VSock Port", @"MachineVMVsockPort",
         WSettingNumber, @"1024",
         @"vsock port the guest's waypipe server binds; bridged into Wawona."),
    ITEM(@"Container Runtime", nil, WSettingInfo,
#if TARGET_OS_OSX
         @"containerization.framework",
#else
         @"container-in-VM",
#endif
         @"Selected automatically for this platform by wwn-containers. macOS: "
         @"Apple Containerization framework. Mobile/Android: container-in-VM "
         @"(crun in a wwn-vms guest). watchOS: image management only."),
    ITEM(@"Container Image Store", @"MachineContainerImageStore", WSettingText,
         @"~/.local/share/wawona/oci",
         @"Content-addressable OCI store (wwn-oci) for pulled images. Universal "
         @"and App-Store-compliant on every target."),
    ITEM(
        @"Status", nil, WSettingInfo, @"Active",
        @"VM + container backends are provided by the wwn-vms / wwn-containers "
        @"dependencies. macOS runs them directly; other targets are "
        @"capability-gated (see each dep's COMPLIANCE.md).")
  ];
  [sects addObject:machines];

  // WAYPIPE
  WWNPreferencesSection *waypipe = [[WWNPreferencesSection alloc] init];
  waypipe.title = @"Waypipe";
  waypipe.accessibilityIdentifier = @"wwn.settings.waypipe";
  waypipe.icon = @"arrow.triangle.2.circlepath";
#if TARGET_OS_IPHONE
  waypipe.iconColor = [UIColor systemGreenColor];
#else
  waypipe.iconColor = [NSColor systemGreenColor];
#endif

  NSString *previewCommand =
      [[WWNWaypipeRunner sharedRunner]
          generateWaypipePreviewString:[WWNPreferencesManager sharedManager]];
  if (previewCommand.length == 0) {
    previewCommand = @"Preview unavailable";
  } else {
    // Keep the row compact: show a single-line preview, truncated by the cell.
    previewCommand =
        [[previewCommand stringByReplacingOccurrencesOfString:@"\n"
                                                   withString:@" "]
            stringByTrimmingCharactersInSet:[NSCharacterSet
                                                whitespaceAndNewlineCharacterSet]];
  }
  WWNSettingItem *previewBtn =
      ITEM(@"Waypipe Command Preview", @"WaypipePreview", WSettingButton, nil,
           previewCommand);
  previewBtn.actionBlock = ^{
    [weakSelf previewWaypipeCommand];
  };

  WWNSettingItem *compressItem =
      ITEM(@"Compression", @"WaypipeCompress", WSettingPopup, @"lz4",
           @"Compression method.");
  compressItem.options = @[ @"none", @"lz4", @"zstd" ];

  WWNSettingItem *videoItem =
      ITEM(@"Video Codec", @"WaypipeVideo", WSettingPopup, @"none",
           @"Lossy video codec.");
  videoItem.options = @[ @"none", @"h264", @"vp9", @"av1" ];

  WWNSettingItem *vEnc = ITEM(@"Encoding", @"WaypipeVideoEncoding",
                              WSettingPopup, @"hw", @"Hardware vs Software.");
  vEnc.options = @[ @"hw", @"sw", @"hwenc", @"swenc" ];

  WWNSettingItem *vDec = ITEM(@"Decoding", @"WaypipeVideoDecoding",
                              WSettingPopup, @"hw", @"Hardware vs Software.");
  vDec.options = @[ @"hw", @"sw", @"hwdec", @"swdec" ];

  waypipe.items = @[
    ITEM(@"Waypipe", nil, WSettingInfo, [self getWaypipeVersion],
         @"Global defaults for all machines. Per-machine Waypipe settings "
         @"override these values."),
    ITEM(@"Local IP", nil, WSettingInfo, [self localIPAddress], nil),
    ITEM(@"Display Number", @"WaylandDisplayNumber", WSettingNumber, @0,
         @"Display number for socket and waypipe (e.g., 0 = wayland-0)."),
    compressItem,
    ITEM(@"Comp. Level", @"WaypipeCompressLevel", WSettingNumber, @7,
         @"Zstd level (1-22)."),
    ITEM(@"Threads", @"WaypipeThreads", WSettingNumber, @0, @"0 = auto."),
    videoItem,
    vEnc,
    vDec,
    ITEM(@"Bits Per Frame", @"WaypipeVideoBpf", WSettingNumber, @"",
         @"Target bit rate per frame for video encoding. Recommended range: "
         @"1000-10000 bits per frame. Higher values provide better quality but "
         @"use more bandwidth. Leave empty for automatic bit rate."),
    ITEM(@"Use SSH Config", @"WaypipeUseSSHConfig", WSettingSwitch, @YES,
         @"Use SSH configuration from SSH section."),
    ITEM(@"Remote Command", @"WaypipeRemoteCommand", WSettingText, @"",
         @"Command to run remotely."),
    ITEM(@"Debug Mode", @"WaypipeDebug", WSettingSwitch, @NO,
         @"Print debug logs."),
    ITEM(@"Disable GPU", @"WaypipeNoGpu", WSettingSwitch, @NO,
         @"Block GPU protocols."),
    ITEM(@"One-shot", @"WaypipeOneshot", WSettingSwitch, @NO,
         @"Exit when client disconnects."),
    ITEM(@"Unlink Socket", @"WaypipeUnlinkSocket", WSettingSwitch, @NO,
         @"Unlink socket on exit."),
    ITEM(@"Login Shell", @"WaypipeLoginShell", WSettingSwitch, @NO,
         @"Run in login shell."),
    ITEM(@"VSock", @"WaypipeVsock", WSettingSwitch, @NO, @"Use VSock."),
    ITEM(@"XWayland", @"WaypipeXwls", WSettingSwitch, @NO,
         @"Enable XWayland support."),
    ITEM(
        @"Title Prefix", @"WaypipeTitlePrefix", WSettingText, @"",
        @"Prefix added to window titles. Example: \"Remote:\" will show "
        @"windows as \"Remote: Application Name\". Leave empty for no prefix."),
    ITEM(@"Sec Context", @"WaypipeSecCtx", WSettingText, @"",
         @"SELinux security context for waypipe processes. This is a Linux "
         @"security feature that labels processes with security attributes "
         @"(e.g., \"system_u:system_r:waypipe_t:s0\"). Only needed if SELinux "
         @"is enabled on the remote system. Leave empty to use default "
         @"context."),
    previewBtn
  ];
  [sects addObject:waypipe];

  // SSH (libssh2 on iOS, OpenSSH on macOS)
  WWNPreferencesSection *ssh = [[WWNPreferencesSection alloc] init];
#if TARGET_OS_IPHONE
  ssh.title = @"SSH";
#else
  ssh.title = @"OpenSSH";
#endif
  ssh.accessibilityIdentifier = @"wwn.settings.ssh";
  ssh.icon = @"lock.shield";
#if TARGET_OS_IPHONE
  ssh.iconColor = [UIColor systemBlueColor];
#else
  ssh.iconColor = [NSColor systemBlueColor];
#endif

  WWNSettingItem *sshAuthMethodItem =
      ITEM(@"Auth Method", @"SSHAuthMethod", WSettingPopup, @"Password",
           @"Authentication method.");
  sshAuthMethodItem.options = @[ @"Password", @"Public Key" ];

  WWNSettingItem *sshPingBtn =
      ITEM(@"Ping Host", @"SSHPingHost", WSettingButton, nil,
           @"Test network connectivity to SSH host (no authentication).");
  sshPingBtn.actionBlock = ^{
    [weakSelf pingSSHHost];
  };

  WWNSettingItem *sshTestBtn =
      ITEM(@"Test SSH Connection", @"SSHTestConnection", WSettingButton, nil,
           @"Test SSH connection with authentication (password or key).");
  sshTestBtn.actionBlock = ^{
    [weakSelf testSSHConnection];
  };

  // Build items list based on current auth method
  NSMutableArray *sshItems = [NSMutableArray array];

  // Version info
#if TARGET_OS_IPHONE
  [sshItems addObject:ITEM(@"SSH Library", nil, WSettingInfo,
                           [self getLibSSH2Version],
                           @"libssh2 SSH library used for connections.")];
#else
  [sshItems addObject:ITEM(@"SSH Library", nil, WSettingInfo,
                           [self getOpenSSHVersion],
                           @"OpenSSH SSH client used for connections.")];
#endif
#if !TARGET_OS_IPHONE
  [sshItems addObject:ITEM(@"sshpass", nil, WSettingInfo,
                           [self getSshpassVersion],
                           @"Password auth helper for non-interactive SSH.")];
#endif

  // Basic connection settings (always shown)
  [sshItems addObject:ITEM(@"SSH Host", @"SSHHost", WSettingText, @"",
                           @"Remote host address.")];
  [sshItems addObject:ITEM(@"SSH User", @"SSHUser", WSettingText, @"",
                           @"SSH username.")];
  [sshItems addObject:ITEM(@"SSH Port", @"SSHPort", WSettingText, @"22",
                           @"SSH port (1-65535).")];
  [sshItems addObject:sshAuthMethodItem];

  // Get current auth method to show appropriate nested options
  NSInteger authMethod =
      [[NSUserDefaults standardUserDefaults] integerForKey:@"SSHAuthMethod"];

  if (authMethod == 0) {
    // Password authentication
    [sshItems addObject:ITEM(@"Password", @"SSHPassword", WSettingPassword, @"",
                             @"SSH password.")];
  } else {
    // Public Key authentication — Generate / Import + path (synced to Waypipe*)
    WWNSettingItem *keyTypeItem =
        ITEM(@"Key Type", @"SSHKeyType", WSettingPopup, @"ed25519",
             @"Algorithm for Generate Key (ed25519, ecdsa, rsa).");
    keyTypeItem.options = @[ @"ed25519", @"ecdsa", @"rsa" ];
    [sshItems addObject:keyTypeItem];

    WWNSettingItem *genKeyBtn =
        ITEM(@"Generate Key", @"SSHGenerateKey", WSettingButton, nil,
             @"Create an OpenSSH-format key under Documents/ssh and set Key "
             @"Path (also WaypipeSSHKeyPath).");
    genKeyBtn.actionBlock = ^{
      [weakSelf generateSSHKey];
    };
    [sshItems addObject:genKeyBtn];

    WWNSettingItem *importGpgBtn =
        ITEM(@"Import GPG SSH Key", @"SSHImportGPGKey", WSettingButton, nil,
             @"Pair a GPG Authentication subkey: run gpg --export-ssh-key on a "
             @"host with GnuPG, then import the OpenSSH private key here "
             @"(also accepts id_ed25519 / id_rsa / id_ecdsa).");
    importGpgBtn.actionBlock = ^{
      [weakSelf importGPGSSHKey];
    };
    [sshItems addObject:importGpgBtn];

#if TARGET_OS_IPHONE
    [sshItems addObject:ITEM(@"Key Path", @"SSHKeyPath", WSettingText, @"",
                             @"Path to private key (Documents/ssh/… or "
                             @"absolute). Synced to WaypipeSSHKeyPath.")];
#else
    [sshItems
        addObject:ITEM(@"Key Path", @"SSHKeyPath", WSettingText,
                       @"~/.ssh/id_ed25519",
                       @"Path to private key (e.g. ~/.ssh/id_ed25519). Synced "
                       @"to WaypipeSSHKeyPath.")];
#endif
    [sshItems
        addObject:
            ITEM(@"Key Passphrase", @"SSHKeyPassphrase", WSettingPassword, @"",
                 @"Passphrase for encrypted private key (stored securely).")];
  }

  // Action buttons (always shown)
  [sshItems addObject:sshPingBtn];
  [sshItems addObject:sshTestBtn];

  ssh.items = sshItems;
  [sects addObject:ssh];

  // ABOUT
  WWNPreferencesSection *about = [[WWNPreferencesSection alloc] init];
  about.title = @"About";
  about.accessibilityIdentifier = @"wwn.settings.about";
  about.icon = @"info.circle";
#if TARGET_OS_IPHONE
  about.iconColor = [UIColor systemPurpleColor];
#else
  about.iconColor = [NSColor systemPurpleColor];
#endif

  WWNSettingItem *headerItem =
      ITEM(@"Wawona", nil, WSettingHeader, nil,
           @"A Wayland Compositor for macOS, iOS & Android");
  headerItem.imageName = @"Wawona";

  WWNSettingItem *sourceItem =
      ITEM(@"Source Code", nil, WSettingLink, nil, @"View on GitHub");
  sourceItem.urlString = @"https://github.com/wawona/wawona";
  sourceItem.iconURL = @"https://github.githubassets.com/images/modules/logos_"
                       @"page/GitHub-Mark.png";

  WWNSettingItem *donateItem =
      ITEM(@"GitHub Sponsors", nil, WSettingLink, nil, @"Sponsor on GitHub");
  donateItem.urlString = @"https://github.com/sponsors/aspauldingcode";
  donateItem.iconURL = @"https://encrypted-tbn0.gstatic.com/images?q=tbn:"
                       @"ANd9GcRp_gdQoe-SxKGw3IvS-1G_JPsMY70HkqxAPg&s";

  WWNSettingItem *authorItem =
      ITEM(@"Author", nil, WSettingInfo, @"Alex Spaulding", nil);
  authorItem.iconURL = @"https://github.com/aspauldingcode.png?size=160";

  WWNSettingItem *githubItem =
      ITEM(@"GitHub", nil, WSettingLink, nil, @"View GitHub Profile");
  githubItem.urlString = @"https://github.com/aspauldingcode";
  githubItem.iconURL = @"https://github.githubassets.com/images/modules/logos_"
                       @"page/GitHub-Mark.png";

  WWNSettingItem *xItem = ITEM(@"X", nil, WSettingLink, nil, @"Follow on X");
  xItem.urlString = @"https://x.com/aspauldingcode";
  xItem.iconURL = @"https://x.com/favicon.ico";

  WWNSettingItem *linkedinItem =
      ITEM(@"LinkedIn", nil, WSettingLink, nil, @"Connect on LinkedIn");
  linkedinItem.urlString = @"https://www.linkedin.com/in/aspauldingcode/";
  linkedinItem.iconURL = @"https://upload.wikimedia.org/wikipedia/commons/c/"
                         @"ca/LinkedIn_logo_initials.png";

  WWNSettingItem *websiteItem =
      ITEM(@"Portfolio", nil, WSettingLink, nil, @"Visit Website");
  websiteItem.urlString = @"https://aspauldingcode.com";
  websiteItem.iconURL = @"https://aspauldingcode.com/favicon.ico";

  WWNSettingItem *kofiItem =
      ITEM(@"Ko-fi", nil, WSettingLink, nil, @"Buy me a coffee ☕");
  kofiItem.urlString = @"https://ko-fi.com/aspauldingcode";
  kofiItem.iconURL = @"https://ko-fi.com/android-icon-192x192.png";

  about.items = @[
    headerItem, ITEM(@"Version", nil, WSettingInfo, [self getWWNVersion], nil),
    ITEM(@"Platform", nil, WSettingInfo,
#if TARGET_OS_IPHONE
         @"iOS",
#else
         @"macOS",
#endif
         nil),
    authorItem, websiteItem, githubItem, xItem, linkedinItem, kofiItem,
    donateItem
  ];
  [sects addObject:about];

  // DEPENDENCIES
  WWNPreferencesSection *deps = [[WWNPreferencesSection alloc] init];
  deps.title = @"Dependencies";
  deps.accessibilityIdentifier = @"wwn.settings.dependencies";
  deps.icon = @"shippingbox";
#if TARGET_OS_IPHONE
  deps.iconColor = [UIColor systemBrownColor];
#else
  deps.iconColor = [NSColor systemBrownColor];
#endif

  NSMutableArray *depItems = [NSMutableArray array];

  // Core dependencies
  [depItems
      addObject:ITEM(@"Waypipe", nil, WSettingInfo, [self getWaypipeVersion],
                     @"Remote Wayland display proxy")];
#if TARGET_OS_IPHONE
  [depItems
      addObject:ITEM(@"libssh2", nil, WSettingInfo, [self getLibSSH2Version],
                     @"SSH connection library")];
#else
  [depItems addObject:ITEM(@"OpenSSH", nil, WSettingInfo,
                           [self getOpenSSHVersion], @"Secure shell client")];
#endif
#if !TARGET_OS_IPHONE
  [depItems
      addObject:ITEM(@"sshpass", nil, WSettingInfo, [self getSshpassVersion],
                     @"Non-interactive SSH password auth")];
#endif
  [depItems
      addObject:ITEM(@"libwayland", nil, WSettingInfo,
                     [self getLibwaylandVersion], @"Wayland protocol library")];
  [depItems
      addObject:ITEM(@"xkbcommon", nil, WSettingInfo,
                     [self getXkbcommonVersion], @"Keyboard handling library")];

  // Compression
  [depItems addObject:ITEM(@"LZ4", nil, WSettingInfo, [self getLz4Version],
                           @"Fast compression algorithm")];
  [depItems addObject:ITEM(@"Zstd", nil, WSettingInfo, [self getZstdVersion],
                           @"Zstandard compression")];

  // Other libraries
  [depItems
      addObject:ITEM(@"libffi", nil, WSettingInfo, [self getLibffiVersion],
                     @"Foreign function interface")];

#if TARGET_OS_IPHONE
  // iOS-specific dependencies
  [depItems
      addObject:ITEM(@"epoll-shim", nil, WSettingInfo,
                     [self getEpollShimVersion], @"epoll compatibility layer")];
#endif

  deps.items = depItems;
  [sects addObject:deps];

  return sects;
}

- (NSString *)findWaypipeBinary {
  return [[WWNWaypipeRunner sharedRunner] findWaypipeBinary];
}

- (NSString *)getSocketPath {
  NSDictionary *runtimeState = [self runtimeStateSnapshot];
  NSString *stateDir = runtimeState[@"xdgRuntimeDir"];
  if ([stateDir isKindOfClass:[NSString class]] && stateDir.length > 0) {
    return stateDir;
  }

  const char *xdg_runtime_dir = getenv("XDG_RUNTIME_DIR");
  if (xdg_runtime_dir) {
    return [NSString stringWithUTF8String:xdg_runtime_dir];
  }
  // Fallback to /tmp/wawona-uid logic matching compositor host.
  uid_t uid = getuid();
  return [NSString stringWithFormat:@"/tmp/wawona-%d", uid];
}

- (NSDictionary *)runtimeStateSnapshot {
  uid_t uid = getuid();
  NSString *runtimeDir = [NSString stringWithFormat:@"/tmp/wawona-%d", uid];
  NSString *statePath =
      [runtimeDir stringByAppendingPathComponent:@"wawona-runtime-state.plist"];
  NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:statePath];
  if (![state isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  return state;
}

- (NSString *)localIPAddress {
  NSString *address = @"Not available";
  struct ifaddrs *interfaces = NULL;
  struct ifaddrs *temp_addr = NULL;
  int success = 0;

  // Retrieve the current interfaces - returns 0 on success
  success = getifaddrs(&interfaces);
  if (success == 0) {
    // Loop through linked list of interfaces
    temp_addr = interfaces;
    while (temp_addr != NULL) {
      if (temp_addr->ifa_addr->sa_family == AF_INET) {
        // Check if interface is en0 (WiFi) or en1 (Ethernet) or similar
        NSString *ifname = [NSString stringWithUTF8String:temp_addr->ifa_name];
        if ([ifname hasPrefix:@"en"] || [ifname hasPrefix:@"eth"]) {
          // Get NSString from C String
          char *ipCString =
              inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr);
          NSString *ipString = [NSString stringWithUTF8String:ipCString];

          // Skip localhost
          if (![ipString isEqualToString:@"127.0.0.1"]) {
            address = ipString;
            break;
          }
        }
      }
      temp_addr = temp_addr->ifa_next;
    }
  }

  // Free memory
  freeifaddrs(interfaces);
  return address;
}

- (NSString *)cleanVersion:(NSString *)raw {
  if (!raw || raw.length == 0)
    return @"v0.0.0";

  NSMutableString *clean = [NSMutableString stringWithString:@"v"];
  NSCharacterSet *digitsAndDots =
      [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];

  // Find numeric content
  BOOL foundStart = NO;
  for (NSUInteger i = 0; i < raw.length; i++) {
    unichar c = [raw characterAtIndex:i];
    if ([digitsAndDots characterIsMember:c]) {
      [clean appendFormat:@"%C", c];
      foundStart = YES;
    } else if (foundStart) {
      // Stop at first non-numeric char after finding some numbers
      break;
    }
  }

  if (clean.length == 1)
    return @"v0.0.0";
  return clean;
}

- (NSString *)getOpenSSHVersion {
  NSString *sshPath = nil;
  NSFileManager *fm = [NSFileManager defaultManager];

#if TARGET_OS_IPHONE
  // iOS: Report libssh2 version (used instead of OpenSSH binary)
  (void)sshPath;
  (void)fm;
  return [self getLibSSH2Version];
#else
  // macOS: Use system ssh and run ssh -V
  sshPath = @"/usr/bin/ssh";
  if (![fm fileExistsAtPath:sshPath])
    return @"Not found";

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = sshPath;
  task.arguments = @[ @"-V" ];

  NSPipe *pipe = [NSPipe pipe];
  task.standardError = pipe; // ssh -V outputs to stderr

  @try {
    [task launch];
    [task waitUntilExit];

    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output =
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // Parse "OpenSSH_X.Xp2, ..." to just "OpenSSH X.X"
    if ([output hasPrefix:@"OpenSSH_"]) {
      NSRange commaRange = [output rangeOfString:@","];
      if (commaRange.location != NSNotFound) {
        output = [output substringToIndex:commaRange.location];
      }

      // Preserve "OpenSSH" at the start
      NSString *versionPart =
          [output substringFromIndex:8]; // Length of "OpenSSH_"
      versionPart = [versionPart stringByReplacingOccurrencesOfString:@"p"
                                                           withString:@"."];
      versionPart = [versionPart stringByReplacingOccurrencesOfString:@"_"
                                                           withString:@" "];

      NSString *finalVer =
          [versionPart stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      return [self cleanVersion:finalVer];
    }
    return [self cleanVersion:output];
  } @catch (NSException *e) {
    return @"v0.0.0";
  }
#endif
}

- (NSString *)getLibSSH2Version {
#if TARGET_OS_IPHONE
  NSString *ver = [NSString stringWithUTF8String:WAWONA_LIBSSH2_VERSION];
  if ([ver isEqualToString:@"Bundled"]) {
    ver = [NSString stringWithUTF8String:LIBSSH2_VERSION];
  }
  if (ver && ![ver hasPrefix:@"v"]) {
    ver = [@"v" stringByAppendingString:ver];
  }
  return [self cleanVersion:ver];
#else
  return @"v0.0.0";
#endif
}

- (NSString *)getWaypipeVersion {
#if TARGET_OS_IPHONE
  NSString *ver = [NSString stringWithUTF8String:WAWONA_WAYPIPE_VERSION];
  if (ver && ![ver hasPrefix:@"v"]) {
    ver = [@"v" stringByAppendingString:ver];
  }
  return [self cleanVersion:ver];
#else
  NSString *waypipePath = [self findWaypipeBinary];
  if (!waypipePath) {
    NSString *ver = [NSString stringWithUTF8String:WAWONA_WAYPIPE_VERSION];
    return [self cleanVersion:ver];
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = waypipePath;
  task.arguments = @[ @"--version" ];

  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;

  @try {
    [task launch];
    [task waitUntilExit];

    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output =
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // Parse "waypipe X.X.X" or similar
    output = [output
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if (output.length > 0) {
      // If it contains "waypipe", extract version number
      NSRange waypipeRange =
          [output rangeOfString:@"waypipe" options:NSCaseInsensitiveSearch];
      if (waypipeRange.location != NSNotFound) {
        NSString *afterWaypipe = [output
            substringFromIndex:waypipeRange.location + waypipeRange.length];
        afterWaypipe = [afterWaypipe
            stringByTrimmingCharactersInSet:[NSCharacterSet
                                                whitespaceCharacterSet]];
        // Take first word (version number)
        NSArray *parts = [afterWaypipe
            componentsSeparatedByCharactersInSet:[NSCharacterSet
                                                     whitespaceCharacterSet]];
        if (parts.count > 0 && [parts[0] length] > 0) {
          return [self cleanVersion:parts[0]];
        }
      }
      return output;
    }
    return @"v0.0.0";
  } @catch (NSException *e) {
    return @"v0.0.0";
  }
#endif
}

#if !TARGET_OS_IPHONE
- (NSString *)getSshpassVersion {
  NSString *sshpassPath = WWNWawonaFindBundledExecutable(@"sshpass");

  if (!sshpassPath) {
    NSString *ver = [NSString stringWithUTF8String:WAWONA_SSHPASS_VERSION];
    return [self cleanVersion:ver];
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = sshpassPath;
  task.arguments = @[ @"-V" ];

  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;

  @try {
    [task launch];
    [task waitUntilExit];

    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output =
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // Parse "sshpass X.X" or similar
    output = [output
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if ([output containsString:@"sshpass"]) {
      // Extract version number
      NSRange spaceRange = [output rangeOfString:@" "];
      if (spaceRange.location != NSNotFound) {
        NSString *version = [output substringFromIndex:spaceRange.location + 1];
        version =
            [version stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // Take first word/line
        NSRange newlineRange = [version
            rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
        if (newlineRange.location != NSNotFound) {
          version = [version substringToIndex:newlineRange.location];
        }
        return [self cleanVersion:version];
      }
    }
    return [self cleanVersion:output];
  } @catch (NSException *e) {
    return @"v0.0.0";
  }
}
#endif

- (NSString *)getWWNVersion {
  // Use Nix-sourced version if available
  NSString *version = @WAWONA_VERSION;

  // If macro is default or unknown, fall back to bundle info
  if ([version isEqualToString:@"0.0.0-unknown"] ||
      [version containsString:@"unknown"]) {
    version = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  }

  // Ensure 'v' prefix
  if (version && ![version hasPrefix:@"v"]) {
    version = [@"v" stringByAppendingString:version];
  }

  return version ?: @"v0.0.0";
}

- (NSString *)getLibffiVersion {
  return
      [self cleanVersion:[NSString stringWithUTF8String:WAWONA_LIBFFI_VERSION]];
}

- (NSString *)getLz4Version {
  return [self cleanVersion:[NSString stringWithUTF8String:WAWONA_LZ4_VERSION]];
}

- (NSString *)getZstdVersion {
  return
      [self cleanVersion:[NSString stringWithUTF8String:WAWONA_ZSTD_VERSION]];
}

- (NSString *)getXkbcommonVersion {
  return [self
      cleanVersion:[NSString stringWithUTF8String:WAWONA_XKBCOMMON_VERSION]];
}

- (NSString *)getLibwaylandVersion {
  return [self
      cleanVersion:[NSString stringWithUTF8String:WAWONA_WAYLAND_VERSION]];
}

#if TARGET_OS_IPHONE
- (NSString *)getEpollShimVersion {
  return [self
      cleanVersion:[NSString stringWithUTF8String:WAWONA_EPOLL_SHIM_VERSION]];
}
#endif

- (void)openURL:(NSString *)urlString {
#if TARGET_OS_IPHONE
  NSURL *url = [NSURL URLWithString:urlString];
  if (url) {
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:nil];
  }
#else
  NSURL *url = [NSURL URLWithString:urlString];
  if (url) {
    [[NSWorkspace sharedWorkspace] openURL:url];
  }
#endif
}

- (void)runWaypipe {
  // Save any pending text field changes first (macOS only - iOS uses alerts)
#if !TARGET_OS_IPHONE
  // On macOS, text fields might have unsaved changes
  // Force end editing to commit any pending changes
  [self.window makeFirstResponder:nil];
#endif

  // Initialize status text
  if (!self.waypipeStatusText) {
    self.waypipeStatusText = [NSMutableString string];
  }
  [self.waypipeStatusText setString:@""];
  self.waypipeMarkedConnected = NO;

  WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];

  // Check if already running
  if (runner.isRunning) {
    [self.waypipeStatusText appendString:@"Waypipe is already running.\n"];
#if TARGET_OS_IPHONE
    [self presentSafeAlertWithTitle:@"Waypipe"
                            message:@"Waypipe is already running. Stop it "
                                    @"first, then try again."];
#endif
    return;
  }

#if TARGET_OS_IPHONE
  {
    __weak typeof(self) weakSelf = self;

    void (^showStatusAlert)(void) = ^{
      UIAlertController *statusAlert = [UIAlertController
          alertControllerWithTitle:@"Waypipe"
                           message:@"Launching waypipe...\n"
                    preferredStyle:UIAlertControllerStyleAlert];
#if !TARGET_OS_TV
      [statusAlert
          addAction:[UIAlertAction
                        actionWithTitle:@"Copy Log"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
                                  if ([UIApplication sharedApplication]
                                          .applicationState ==
                                      UIApplicationStateActive) {
                                    [UIPasteboard generalPasteboard].string =
                                        weakSelf.waypipeStatusText ?: @"";
                                  }
                                }]];
#endif
      [statusAlert
          addAction:[UIAlertAction
                        actionWithTitle:@"Stop"
                                  style:UIAlertActionStyleDestructive
                                handler:^(__unused UIAlertAction *action) {
                                  [[WWNWaypipeRunner sharedRunner] stopWaypipe];
                                  weakSelf.waypipeStatusAlert = nil;
                                }]];
      [statusAlert
          addAction:[UIAlertAction
                        actionWithTitle:@"Dismiss"
                                  style:UIAlertActionStyleCancel
                                handler:^(__unused UIAlertAction *action) {
                                  weakSelf.waypipeStatusAlert = nil;
                                }]];
      weakSelf.waypipeStatusAlert = statusAlert;
      [weakSelf presentViewController:statusAlert animated:YES completion:nil];
    };

    // Dismiss any existing presented view controller before showing status
    if (self.presentedViewController) {
      self.waypipeStatusAlert = nil;
      [self.presentedViewController
          dismissViewControllerAnimated:NO
                             completion:showStatusAlert];
    } else {
      showStatusAlert();
    }
  }
#else
  // macOS: Show status panel
  [self showWaypipeStatusPanel];
#endif

  // Launch waypipe
  WWNLog("UI", @"Launching Waypipe...");
  [[WWNWaypipeRunner sharedRunner]
      launchWaypipe:[WWNPreferencesManager sharedManager]];

  // Note: We do NOT automatically dismiss the settings view here.
  // Waypipe launch might require user interaction (e.g., password prompt)
  // or show errors that the user needs to see.
  // The user can manually dismiss the settings when they are ready.
}

#if !TARGET_OS_IPHONE
- (void)showWaypipeStatusPanel {
  // Close existing panel if any
  if (self.waypipeStatusPanel) {
    [self.waypipeStatusPanel close];
    self.waypipeStatusPanel = nil;
  }

  // Create a floating panel for waypipe status
  NSRect panelRect = NSMakeRect(0, 0, 500, 350);
  NSPanel *panel = [[NSPanel alloc]
      initWithContentRect:panelRect
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskUtilityWindow
                  backing:NSBackingStoreBuffered
                    defer:NO];
  panel.title = @"Waypipe Status";
  panel.floatingPanel = YES;
  panel.becomesKeyOnlyIfNeeded = YES;
  panel.level = NSFloatingWindowLevel;
  panel.releasedWhenClosed = NO;

  // Create scroll view for text
  NSScrollView *scrollView =
      [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, 480, 290)];
  scrollView.hasVerticalScroller = YES;
  scrollView.hasHorizontalScroller = NO;
  scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scrollView.borderType = NSBezelBorder;

  // Create text view
  NSTextView *textView =
      [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 480, 290)];
  textView.editable = NO;
  textView.selectable = YES;
  textView.font =
      [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
  textView.backgroundColor = [NSColor colorWithCalibratedWhite:0.1 alpha:1.0];
  textView.textColor = [NSColor colorWithCalibratedRed:0.0
                                                 green:1.0
                                                  blue:0.0
                                                 alpha:1.0]; // Terminal green
  textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [textView.textStorage
      setAttributedString:[[NSAttributedString alloc]
                              initWithString:self.waypipeStatusText
                                  attributes:@{
                                    NSFontAttributeName : textView.font,
                                    NSForegroundColorAttributeName :
                                        textView.textColor
                                  }]];

  scrollView.documentView = textView;
  [panel.contentView addSubview:scrollView];
  self.waypipeStatusTextView = textView;

  // Create buttons at bottom
  NSButton *copyButton = [NSButton buttonWithTitle:@"Copy Log"
                                            target:self
                                            action:@selector(copyWaypipeLog:)];
  copyButton.frame = NSMakeRect(10, 10, 100, 30);
  copyButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
  [panel.contentView addSubview:copyButton];

  NSButton *stopButton = [NSButton buttonWithTitle:@"Stop Waypipe"
                                            target:self
                                            action:@selector(stopWaypipe:)];
  stopButton.frame = NSMakeRect(120, 10, 120, 30);
  stopButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
  [panel.contentView addSubview:stopButton];
  self.waypipeStopButton = stopButton;

  NSButton *closeButton =
      [NSButton buttonWithTitle:@"Close"
                         target:self
                         action:@selector(closeWaypipePanel:)];
  closeButton.frame = NSMakeRect(390, 10, 100, 30);
  closeButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [panel.contentView addSubview:closeButton];

  self.waypipeStatusPanel = panel;

  // Position near settings window
  if (self.window) {
    NSRect settingsFrame = self.window.frame;
    NSRect panelFrame = panel.frame;
    panelFrame.origin.x = NSMaxX(settingsFrame) + 20;
    panelFrame.origin.y = NSMinY(settingsFrame);
    [panel setFrame:panelFrame display:YES];
  } else {
    [panel center];
  }

  [panel makeKeyAndOrderFront:nil];
}

- (void)updateWaypipeStatusPanel {
  if (self.waypipeStatusTextView && self.waypipeStatusText) {
    dispatch_async(dispatch_get_main_queue(), ^{
      NSDictionary *attrs = @{
        NSFontAttributeName : self.waypipeStatusTextView.font
            ?: [NSFont monospacedSystemFontOfSize:11
                                           weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : self.waypipeStatusTextView.textColor
            ?: [NSColor greenColor]
      };
      [self.waypipeStatusTextView.textStorage
          setAttributedString:[[NSAttributedString alloc]
                                  initWithString:self.waypipeStatusText
                                      attributes:attrs]];
      // Auto-scroll to bottom
      [self.waypipeStatusTextView
          scrollRangeToVisible:NSMakeRange(self.waypipeStatusText.length, 0)];

      // Update panel title based on connection status
      if (self.waypipeMarkedConnected && self.waypipeStatusPanel) {
        self.waypipeStatusPanel.title = @"Waypipe - Connected";
      }
    });
  }
}

- (void)copyWaypipeLog:(id)sender {
  if (self.waypipeStatusText) {
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:self.waypipeStatusText
                                        forType:NSPasteboardTypeString];
  }
}

- (void)stopWaypipe:(id)sender {
  [[WWNWaypipeRunner sharedRunner] stopWaypipe];
  [self.waypipeStatusText appendString:@"\n[User requested stop]\n"];
  [self updateWaypipeStatusPanel];
}

- (void)closeWaypipePanel:(id)sender {
  if (self.waypipeStatusPanel) {
    [self.waypipeStatusPanel close];
    self.waypipeStatusPanel = nil;
  }
}
#endif

- (void)testSSHConnection {
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  NSString *host = prefs.sshHost;
  NSString *user = prefs.sshUser;

  WWNLog("SSH", @"Attempting to test SSH connection to: '%@%@'",
         user ?: @"(nil)", host ?: @"(nil)");

  if (!host || host.length == 0) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"No Host Specified"
                         message:@"Please enter an SSH host address first."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"No Host Specified";
    alert.informativeText = @"Please enter an SSH host address first.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
    return;
  }

  if (!user || user.length == 0) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"No User Specified"
                         message:@"Please enter an SSH username first."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"No User Specified";
    alert.informativeText = @"Please enter an SSH username first.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
    return;
  }

#if TARGET_OS_IPHONE
  // iOS: Use libssh2 to perform a real SSH connection test with authentication
  // and remote command execution (uname -a).
  UIAlertController *progressAlert = [UIAlertController
      alertControllerWithTitle:@"Testing SSH Connection"
                       message:[NSString
                                   stringWithFormat:@"Connecting to %@@%@...",
                                                    user, host]
                preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:progressAlert animated:YES completion:nil];

  NSString *password = prefs.sshPassword;
  NSString *keyPath = prefs.sshKeyPath;
  NSString *keyPassphrase = prefs.sshKeyPassphrase;
  NSInteger authMethod = prefs.sshAuthMethod;
  NSInteger sshPort = prefs.sshPort > 0 ? prefs.sshPort : 22;
  NSString *portStr = [NSString stringWithFormat:@"%ld", (long)sshPort];

  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *resultTitle = nil;
        NSString *resultMessage = nil;

        // -- 1. TCP connect ------------------------------------------------
        struct addrinfo hints, *res = NULL;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        int gai = getaddrinfo([host UTF8String], [portStr UTF8String], &hints,
                              &res);
        if (gai != 0 || !res) {
          resultTitle = @"DNS Lookup Failed";
          resultMessage =
              [NSString stringWithFormat:@"Could not resolve host: %@\n\n%s",
                                         host, gai_strerror(gai)];
          goto show_result;
        }

        int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (sock < 0) {
          resultTitle = @"Socket Error";
          resultMessage = [NSString
              stringWithFormat:@"Failed to create socket: %s", strerror(errno)];
          freeaddrinfo(res);
          goto show_result;
        }

        // Set a 10-second connect timeout via SO_SNDTIMEO
        struct timeval tv = {.tv_sec = 10, .tv_usec = 0};
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

        if (connect(sock, res->ai_addr, res->ai_addrlen) != 0) {
          resultTitle = @"Connection Failed";
          resultMessage = [NSString
              stringWithFormat:
                  @"Could not connect to %@:%@\n\n%s\n\nCheck that:\n"
                  @"- The host address is correct\n"
                  @"- SSH server is running on the configured port\n"
                  @"- You are on the same network",
                  host, portStr, strerror(errno)];
          close(sock);
          freeaddrinfo(res);
          goto show_result;
        }
        freeaddrinfo(res);

        // -- 2. libssh2 handshake -----------------------------------------
        {
          int rc;
          libssh2_init(0);
          LIBSSH2_SESSION *session = libssh2_session_init();
          if (!session) {
            resultTitle = @"SSH Error";
            resultMessage = @"Failed to initialize libssh2 session.";
            close(sock);
            goto show_result;
          }

          // Set blocking mode with a reasonable timeout
          libssh2_session_set_timeout(session, 10000); // 10s

          rc = libssh2_session_handshake(session, sock);
          if (rc != 0) {
            char *errmsg = NULL;
            libssh2_session_last_error(session, &errmsg, NULL, 0);
            resultTitle = @"SSH Handshake Failed";
            resultMessage = [NSString
                stringWithFormat:@"SSH handshake with %@ failed (rc=%d).\n\n%s",
                                 host, rc, errmsg ?: "Unknown error"];
            libssh2_session_disconnect(session, "test done");
            libssh2_session_free(session);
            close(sock);
            goto show_result;
          }

          // Update progress on main thread
          dispatch_async(dispatch_get_main_queue(), ^{
            progressAlert.message = [NSString
                stringWithFormat:@"Authenticating %@@%@...", user, host];
          });

          // -- 3. Authenticate --------------------------------------------
          if (authMethod == 1 && keyPath.length > 0) {
            // Public key authentication
            NSString *expandedKey = [keyPath stringByExpandingTildeInPath];
            // Try with .pub file if it exists
            NSString *pubKeyPath =
                [expandedKey stringByAppendingString:@".pub"];
            if (![[NSFileManager defaultManager] fileExistsAtPath:pubKeyPath]) {
              pubKeyPath = nil;
            }
            rc = libssh2_userauth_publickey_fromfile(
                session, [user UTF8String],
                pubKeyPath ? [pubKeyPath UTF8String] : NULL,
                [expandedKey UTF8String],
                keyPassphrase.length > 0 ? [keyPassphrase UTF8String] : NULL);
          } else {
            // Password authentication
            rc = libssh2_userauth_password(
                session, [user UTF8String],
                password.length > 0 ? [password UTF8String] : "");
          }

          if (rc != 0) {
            char *errmsg = NULL;
            libssh2_session_last_error(session, &errmsg, NULL, 0);
            resultTitle = @"Authentication Failed";
            resultMessage = [NSString
                stringWithFormat:@"Failed to authenticate %@@%@ (%s).\n\n%s"
                                 @"\n\nCheck that:\n"
                                 @"- Username and %@ are correct\n"
                                 @"- The server accepts %@ authentication",
                                 user, host,
                                 authMethod == 1 ? "public key" : "password",
                                 errmsg ?: "Unknown error",
                                 authMethod == 1 ? @"key" : @"password",
                                 authMethod == 1 ? @"public key" : @"password"];
            libssh2_session_disconnect(session, "test done");
            libssh2_session_free(session);
            close(sock);
            goto show_result;
          }

          // Update progress on main thread
          dispatch_async(dispatch_get_main_queue(), ^{
            progressAlert.message =
                [NSString stringWithFormat:@"Running uname -a on %@...", host];
          });

          // -- 4. Execute uname -a ----------------------------------------
          LIBSSH2_CHANNEL *channel = libssh2_channel_open_session(session);
          if (!channel) {
            char *errmsg = NULL;
            libssh2_session_last_error(session, &errmsg, NULL, 0);
            resultTitle = @"Channel Error";
            resultMessage =
                [NSString stringWithFormat:@"Authenticated successfully but "
                                           @"failed to open channel.\n\n%s",
                                           errmsg ?: "Unknown error"];
            libssh2_session_disconnect(session, "test done");
            libssh2_session_free(session);
            close(sock);
            goto show_result;
          }

          rc = libssh2_channel_exec(channel, "uname -a");
          if (rc != 0) {
            resultTitle = @"Exec Error";
            resultMessage = @"Failed to execute remote command.";
            libssh2_channel_free(channel);
            libssh2_session_disconnect(session, "test done");
            libssh2_session_free(session);
            close(sock);
            goto show_result;
          }

          // Read output
          char buf[4096];
          NSMutableString *output = [NSMutableString string];
          while (1) {
            ssize_t n = libssh2_channel_read(channel, buf, sizeof(buf) - 1);
            if (n > 0) {
              buf[n] = '\0';
              [output appendFormat:@"%s", buf];
            } else {
              break;
            }
          }

          libssh2_channel_send_eof(channel);
          libssh2_channel_wait_eof(channel);
          libssh2_channel_wait_closed(channel);
          int exitCode = libssh2_channel_get_exit_status(channel);

          libssh2_channel_free(channel);
          libssh2_session_disconnect(session, "test done");
          libssh2_session_free(session);
          close(sock);

          // -- 5. Build result --------------------------------------------
          NSString *trimmedOutput =
              [output stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];

          if (exitCode == 0 && trimmedOutput.length > 0) {
            resultTitle = @"SSH Connection Successful";
            resultMessage = [NSString
                stringWithFormat:@"Connected to %@@%@\n\nRemote system:\n%@",
                                 user, host, trimmedOutput];
          } else if (exitCode == 0) {
            resultTitle = @"SSH Connection Successful";
            resultMessage = [NSString
                stringWithFormat:
                    @"Successfully connected and authenticated to %@@%@", user,
                    host];
          } else {
            resultTitle = @"Remote Command Failed";
            resultMessage = [NSString
                stringWithFormat:
                    @"Authenticated to %@@%@ but command exited with code %d."
                    @"\n\nOutput:\n%@",
                    user, host, exitCode,
                    trimmedOutput.length > 0 ? trimmedOutput : @"(none)"];
          }
        }

      show_result:
        dispatch_async(dispatch_get_main_queue(), ^{
          [progressAlert
              dismissViewControllerAnimated:YES
                                 completion:^{
                                   [self
                                       presentSafeAlertWithTitle:resultTitle
                                                         message:resultMessage];
                                 }];
        });
      });
#else
  // macOS implementation using sshpass (if available) or expect-like pty
  // approach Run the SSH test asynchronously to avoid blocking UI
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        WWNLog("SSH", @"Starting SSH test to %@@%@ (macOS)", user, host);

        NSString *password = prefs.sshPassword;
        BOOL usePasswordAuth =
            (prefs.sshAuthMethod == 0 && password.length > 0);

        // Check if sshpass is available for password auth
        NSString *sshpassPath = nil;
        if (usePasswordAuth) {
          sshpassPath = WWNWawonaFindBundledExecutable(@"sshpass");
          WWNLog("SSH", @"App bundle root: %@", WWNWawonaAppBundleRoot());
          WWNLog("SSH", @"Executable dir: %@", WWNWawonaExecutableDirectory());
          if (!sshpassPath) {
            NSArray *systemFallbacks = @[
              @"/opt/homebrew/bin/sshpass", @"/usr/local/bin/sshpass",
              @"/usr/bin/sshpass"
            ];
            NSFileManager *fm = [NSFileManager defaultManager];
            for (NSString *path in systemFallbacks) {
              if ([fm isExecutableFileAtPath:path]) {
                sshpassPath = path;
                break;
              }
            }
          }

          if (!sshpassPath) {
            WWNLog("SSH",
                   @"sshpass not found in any location. Password auth may "
                   @"fail.");
            WWNLog("SSH", @"To install sshpass: brew install "
                          @"hudochenkov/sshpass/sshpass");
          }
        }

        // Build SSH command arguments
        NSMutableArray *sshArgs = [NSMutableArray array];
        NSString *executablePath = @"/usr/bin/ssh";
        NSString *askpassScriptPath = nil;

        if (usePasswordAuth && sshpassPath) {
          // Use sshpass for password authentication
          executablePath = sshpassPath;
          [sshArgs addObject:@"-p"];
          [sshArgs addObject:password];
          [sshArgs addObject:@"ssh"];
          WWNLog("SSH", @"Using sshpass at: %@", sshpassPath);
        }

        [sshArgs addObject:@"-v"]; // Verbose for debugging
        [sshArgs addObject:@"-o"];
        [sshArgs addObject:@"ConnectTimeout=10"];
        [sshArgs addObject:@"-o"];
        [sshArgs addObject:@"StrictHostKeyChecking=no"];
        [sshArgs addObject:@"-o"];
        [sshArgs addObject:@"UserKnownHostsFile=/dev/null"];

        // Only use BatchMode if we're NOT doing password auth
        // Note: sshpass requires password prompts to work, so we cannot use
        // BatchMode with it
        if (!usePasswordAuth) {
          [sshArgs addObject:@"-o"];
          [sshArgs addObject:@"BatchMode=yes"];
        }

        // Add authentication method specific options
        if (prefs.sshAuthMethod == 1) { // Public Key
          [sshArgs addObject:@"-o"];
          [sshArgs addObject:@"PreferredAuthentications=publickey"];
          if (prefs.sshKeyPath.length > 0) {
            [sshArgs addObject:@"-i"];
            [sshArgs addObject:prefs.sshKeyPath];
          }
        } else { // Password auth
          [sshArgs addObject:@"-o"];
          [sshArgs
              addObject:
                  @"PreferredAuthentications=password,keyboard-interactive"];
          [sshArgs addObject:@"-o"];
          [sshArgs addObject:@"PubkeyAuthentication=no"];
          [sshArgs addObject:@"-o"];
          [sshArgs addObject:@"NumberOfPasswordPrompts=1"];
        }

        [sshArgs addObject:@"-4"]; // IPv4 only for faster connection
        NSInteger sshPort = prefs.sshPort > 0 ? prefs.sshPort : 22;
        [sshArgs addObject:@"-p"];
        [sshArgs addObject:[NSString stringWithFormat:@"%ld", (long)sshPort]];

        NSString *target = [NSString stringWithFormat:@"%@@%@", user, host];
        [sshArgs addObject:target];
        [sshArgs addObject:@"uname -a"];

        WWNLog("SSH", @"Running: %@ %@", executablePath,
               [sshArgs componentsJoinedByString:@" "]);

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = executablePath;
        task.arguments = sshArgs;

        NSMutableDictionary *env =
            [[[NSProcessInfo processInfo] environment] mutableCopy];

        // Password auth fallback when sshpass is unavailable:
        // use SSH_ASKPASS in forced mode so ssh does not require /dev/tty.
        if (usePasswordAuth && !sshpassPath) {
          NSString *scriptName =
              [NSString stringWithFormat:@"wawona-askpass-%@.sh",
                                         [[NSUUID UUID] UUIDString]];
          askpassScriptPath = [NSTemporaryDirectory()
              stringByAppendingPathComponent:scriptName];
          NSString *script = @"#!/bin/sh\n"
                              "printf '%s\\n' \"$WAWONA_SSH_PASSWORD\"\n";
          NSError *scriptError = nil;
          BOOL wrote = [script writeToFile:askpassScriptPath
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&scriptError];
          if (wrote &&
              chmod([askpassScriptPath fileSystemRepresentation], 0700) == 0) {
            env[@"SSH_ASKPASS"] = askpassScriptPath;
            env[@"SSH_ASKPASS_REQUIRE"] = @"force";
            env[@"DISPLAY"] = env[@"DISPLAY"] ?: @"wawona-ssh-test";
            env[@"WAWONA_SSH_PASSWORD"] = password ?: @"";
            WWNLog("SSH",
                   @"[SSH Test macOS] Using temporary SSH_ASKPASS helper");
          } else {
            WWNLog("SSH",
                   @"[SSH Test macOS] Failed to create SSH_ASKPASS helper: %@",
                   scriptError.localizedDescription ?: @"unknown error");
            askpassScriptPath = nil;
          }
        }
        task.environment = env;

        NSPipe *outputPipe = [NSPipe pipe];
        NSPipe *errorPipe = [NSPipe pipe];

        task.standardOutput = outputPipe;
        task.standardError = errorPipe;

        NSError *launchError = nil;
        [task launchAndReturnError:&launchError];

        if (launchError) {
          WWNLog("SSH", @"Launch error: %@", launchError);
          if (askpassScriptPath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:askpassScriptPath
                                                       error:nil];
          }
          dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = @"SSH Launch Failed";
            errorAlert.informativeText =
                [NSString stringWithFormat:@"Failed to launch SSH: %@",
                                           launchError.localizedDescription];
            [errorAlert addButtonWithTitle:@"OK"];
            [errorAlert runModal];
          });
          return;
        }

        // Wait for task with timeout
        dispatch_semaphore_t taskSemaphore = dispatch_semaphore_create(0);
        dispatch_async(
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
              [task waitUntilExit];
              dispatch_semaphore_signal(taskSemaphore);
            });

        dispatch_time_t taskTimeout =
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC));
        BOOL timedOut =
            (dispatch_semaphore_wait(taskSemaphore, taskTimeout) != 0);

        if (timedOut) {
          [task terminate];
          WWNLog("SSH", @"Timed out after 15 seconds");
          if (askpassScriptPath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:askpassScriptPath
                                                       error:nil];
          }
          dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = @"SSH Connection Timeout";
            errorAlert.informativeText =
                @"SSH connection test timed out after 15 seconds.\n\nThis may "
                @"indicate:\n- Network connectivity issues\n- SSH server not "
                @"responding\n- Authentication hanging";
            [errorAlert addButtonWithTitle:@"OK"];
            [errorAlert runModal];
          });
          return;
        }

        int exitCode = task.terminationStatus;
        NSData *outputData =
            [outputPipe.fileHandleForReading readDataToEndOfFile];
        NSData *errorData =
            [errorPipe.fileHandleForReading readDataToEndOfFile];
        NSString *outputString =
            [[NSString alloc] initWithData:outputData
                                  encoding:NSUTF8StringEncoding]
                ?: @"";
        NSString *errorString =
            [[NSString alloc] initWithData:errorData
                                  encoding:NSUTF8StringEncoding]
                ?: @"";

        WWNLog("SSH", @"Exit code: %d", exitCode);
        WWNLog("SSH", @"Output: %@", outputString);
        WWNLog("SSH", @"Stderr: %@", errorString);

        dispatch_async(dispatch_get_main_queue(), ^{
          if (askpassScriptPath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:askpassScriptPath
                                                       error:nil];
          }
          NSAlert *resultAlert = [[NSAlert alloc] init];

          if (exitCode == 0) {
            resultAlert.messageText = @"SSH Connection Successful";
            NSString *unameOutput = [outputString
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (unameOutput.length > 0) {
              resultAlert.informativeText = [NSString
                  stringWithFormat:@"Connected to %@@%@\n\nRemote system:\n%@",
                                   user, host, unameOutput];
            } else {
              resultAlert.informativeText = [NSString
                  stringWithFormat:
                      @"Successfully connected and authenticated to %@@%@",
                      user, host];
            }
            resultAlert.alertStyle = NSAlertStyleInformational;
          } else {
            resultAlert.messageText = @"SSH Connection Failed";
            NSMutableString *details = [NSMutableString
                stringWithFormat:@"SSH connection failed (exit code %d).\n\n",
                                 exitCode];

            // Parse common errors
            if ([errorString containsString:@"Permission denied"]) {
              [details appendString:
                           @"Authentication failed. Please check:\n- Username "
                           @"is correct\n- Password/key is correct\n- Auth "
                           @"method matches server config\n"];

              // Add specific note about sshpass for password auth
              if (usePasswordAuth && !sshpassPath) {
                [details appendString:@"\n⚠️ Password auth on macOS requires "
                                      @"'sshpass'.\nInstall via: brew install "
                                      @"hudochenkov/sshpass/sshpass\n"];
              }
            } else if ([errorString containsString:@"Connection refused"]) {
              [details appendString:@"Connection refused. Please check:\n- SSH "
                                    @"server is running on the host\n- Port 22 "
                                    @"is open\n- Firewall settings\n"];
            } else if ([errorString
                           containsString:@"Host key verification failed"]) {
              [details appendString:@"Host key verification failed.\n"];
            } else if ([errorString containsString:@"No route to host"]) {
              [details appendString:@"Network error: No route to host.\n"];
            } else if ([errorString containsString:@"Connection timed out"]) {
              [details appendString:@"Connection timed out.\n"];
            } else {
              // Show last few lines of error
              NSArray *lines = [errorString componentsSeparatedByString:@"\n"];
              if (lines.count > 3) {
                NSArray *lastLines =
                    [lines subarrayWithRange:NSMakeRange(lines.count - 4, 3)];
                [details
                    appendFormat:@"Last output:\n%@",
                                 [lastLines componentsJoinedByString:@"\n"]];
              } else {
                [details appendString:errorString];
              }
            }

            resultAlert.informativeText = details;
            resultAlert.alertStyle = NSAlertStyleWarning;
          }

          [resultAlert addButtonWithTitle:@"OK"]; // First: OK (Right/Default)
          [resultAlert
              addButtonWithTitle:@"Copy Log"]; // Second: Copy Log (Left)

          NSModalResponse response = [resultAlert runModal];
          if (response == NSAlertSecondButtonReturn) {
            // Copy log to clipboard
            NSString *fullLog =
                [NSString stringWithFormat:
                              @"SSH Test Log\n============\nHost: %@@%@\nExit "
                              @"Code: %d\n\nOutput:\n%@\n\nStderr:\n%@",
                              user, host, exitCode, outputString, errorString];
            NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
            [pasteboard clearContents];
            [pasteboard setString:fullLog forType:NSPasteboardTypeString];
          }
        });
      });
#endif
}

- (void)syncSSHKeyPrefsFromUI {
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  NSString *path = prefs.sshKeyPath ?: @"";
  NSString *pass = prefs.sshKeyPassphrase ?: @"";
  NSInteger method = prefs.sshAuthMethod;
  prefs.waypipeSSHKeyPath = path;
  prefs.waypipeSSHKeyPassphrase = pass;
  prefs.waypipeSSHAuthMethod = method;
  if (prefs.sshHost.length > 0)
    prefs.waypipeSSHHost = prefs.sshHost;
  if (prefs.sshUser.length > 0)
    prefs.waypipeSSHUser = prefs.sshUser;
  if (prefs.sshPassword.length > 0)
    prefs.waypipeSSHPassword = prefs.sshPassword;
}

- (void)generateSSHKey {
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  NSString *keyType =
      [[NSUserDefaults standardUserDefaults] stringForKey:@"SSHKeyType"]
          ?: @"ed25519";
  NSString *passphrase = prefs.sshKeyPassphrase ?: @"";
  NSError *err = nil;
  NSString *keyPath = [WWNSSHKeygen generateKeyType:keyType
                                         passphrase:passphrase
                                              error:&err];
  if (keyPath) {
    [self syncSSHKeyPrefsFromUI];
    self.sections = [self buildSections];
    [self debouncedReloadData];
    NSString *pubPath = [keyPath stringByAppendingString:@".pub"];
    NSString *pub =
        [NSString stringWithContentsOfFile:pubPath
                                  encoding:NSUTF8StringEncoding
                                     error:nil];
    NSString *msg =
        pub.length > 0
            ? [NSString stringWithFormat:@"%@\n%@", keyPath, pub]
            : keyPath;
#if TARGET_OS_IPHONE
    [self presentSafeAlertWithTitle:@"SSH Key Generated" message:msg];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"SSH Key Generated";
    alert.informativeText = msg;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
  } else {
    NSString *detail = err.localizedDescription ?: @"ssh-keygen failed";
#if TARGET_OS_IPHONE
    [self presentSafeAlertWithTitle:@"Key Generation Failed" message:detail];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Key Generation Failed";
    alert.informativeText = detail;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
  }
}

- (void)importGPGSSHKey {
  // Import OpenSSH-format private keys (including gpg --export-ssh-key output).
#if TARGET_OS_IPHONE && TARGET_OS_TV
  [self presentSafeAlertWithTitle:@"Import GPG SSH Key"
                          message:@"On tvOS, paste or set Key Path to an "
                                  @"OpenSSH-format private key under "
                                  @"Documents/ssh (gpg --export-ssh-key)."];
#elif TARGET_OS_IPHONE
  UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController
      alloc] initForOpeningContentTypes:@[ UTTypeData, UTTypeItem ]
                                 asCopy:YES];
  picker.allowsMultipleSelection = NO;
  picker.delegate = (id)self;
  self.documentPickerImportsSSHKey = YES;
  [self presentViewController:picker animated:YES completion:nil];
#else
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = YES;
  panel.canChooseDirectories = NO;
  panel.allowsMultipleSelection = NO;
  panel.message =
      @"Select an OpenSSH private key (gpg --export-ssh-key or id_*).";
  if ([panel runModal] != NSModalResponseOK)
    return;
  NSURL *url = panel.URL;
  if (!url)
    return;
  NSError *err = nil;
  NSString *dest = [WWNSSHKeygen installOpenSSHPrivateKeyAtURL:url error:&err];
  if (!dest) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Import Failed";
    alert.informativeText = err.localizedDescription ?: @"Could not import key";
    [alert runModal];
    return;
  }
  [self syncSSHKeyPrefsFromUI];
  self.sections = [self buildSections];
  [self debouncedReloadData];
  NSAlert *ok = [[NSAlert alloc] init];
  ok.messageText = @"GPG/OpenSSH Key Imported";
  ok.informativeText = dest;
  [ok runModal];
#endif
}

#if TARGET_OS_IPHONE && !TARGET_OS_TV
// Single UIDocumentPickerDelegate callback shared by importGPGSSHKey and
// importFileToShellHome; -documentPickerImportsSSHKey (set before presenting)
// selects which import runs. Previously two identical selectors were declared,
// which failed to compile on iOS.
- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  (void)controller;
  if (self.documentPickerSendsToAppleWatch) {
    self.documentPickerSendsToAppleWatch = NO;
    [self sendPickedFileToAppleWatch:urls];
    return;
  }
  if (!self.documentPickerImportsSSHKey) {
    [self importPickedFileToShellHome:urls];
    return;
  }
  NSURL *url = urls.firstObject;
  if (!url)
    return;
  NSError *err = nil;
  NSString *dest = [WWNSSHKeygen installOpenSSHPrivateKeyAtURL:url error:&err];
  if (!dest) {
    [self presentSafeAlertWithTitle:@"Import Failed"
                            message:err.localizedDescription ?: @"import failed"];
    return;
  }
  [self syncSSHKeyPrefsFromUI];
  self.sections = [self buildSections];
  [self presentSafeAlertWithTitle:@"GPG/OpenSSH Key Imported" message:dest];
}
#endif

- (void)pingSSHHost {
  WWNLog("UI", @"Ping SSH Host button pressed");
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  NSString *host = prefs.sshHost;

  WWNLog("SSH", @"Attempting to ping SSH host: '%@'", host ?: @"(nil)");

  if (!host || host.length == 0) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"No Host Specified"
                         message:@"Please enter an SSH host address first."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"No Host Specified";
    alert.informativeText = @"Please enter an SSH host address first.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
    return;
  }

#if TARGET_OS_IPHONE
  UIAlertController *progressAlert = [UIAlertController
      alertControllerWithTitle:@"Pinging SSH Host"
                       message:[NSString
                                   stringWithFormat:
                                       @"Testing network connectivity to %@...",
                                       host]
                preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:progressAlert animated:YES completion:nil];
#endif

  // Use Network framework for ping asynchronously
  nw_endpoint_t endpoint = nw_endpoint_create_host([host UTF8String], "22");
  nw_parameters_t parameters = nw_parameters_create_secure_tcp(
      NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
  nw_connection_t connection = nw_connection_create(endpoint, parameters);

  if (!connection) {
    NSString *errorMessage = @"Failed to create Network.framework connection";
    dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
      [progressAlert
          dismissViewControllerAnimated:YES
                             completion:^{
                               UIAlertController *resultAlert = [UIAlertController
                                   alertControllerWithTitle:@"Ping Failed"
                                                    message:
                                                        [NSString
                                                            stringWithFormat:
                                                                @"Failed to "
                                                                @"reach "
                                                                @"%@\n%@",
                                                                host,
                                                                errorMessage]
                                             preferredStyle:
                                                 UIAlertControllerStyleAlert];
                               [resultAlert
                                   addAction:
                                       [UIAlertAction
                                           actionWithTitle:@"OK"
                                                     style:
                                                         UIAlertActionStyleDefault
                                                   handler:nil]];
                               [self presentViewController:resultAlert
                                                  animated:YES
                                                completion:nil];
                             }];
#else
      NSAlert *resultAlert = [[NSAlert alloc] init];
      resultAlert.messageText = @"Ping Failed";
      resultAlert.informativeText = [NSString
          stringWithFormat:@"Failed to reach %@\n%@", host, errorMessage];
      [resultAlert addButtonWithTitle:@"OK"];
      [resultAlert runModal];
#endif
    });
    return;
  }

  dispatch_queue_t connectionQueue = dispatch_queue_create(
      "com.aspauldingcode.wawona.sshping", DISPATCH_QUEUE_SERIAL);
  nw_connection_set_queue(connection, connectionQueue);

  __block BOOL completed = NO;
  NSDate *startTime = [NSDate date];

  nw_connection_set_state_changed_handler(connection, ^(
                                              nw_connection_state_t state,
                                              nw_error_t nw_error) {
    if (completed)
      return;

    if (state == nw_connection_state_ready) {
      completed = YES;
      NSTimeInterval latency =
          [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
      nw_connection_cancel(connection);

      dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
        [progressAlert
            dismissViewControllerAnimated:YES
                               completion:^{
                                 UIAlertController *resultAlert = [UIAlertController
                                     alertControllerWithTitle:@"Ping Successful"
                                                      message:
                                                          [NSString
                                                              stringWithFormat:
                                                                  @"Successful"
                                                                  @"ly "
                                                                  @"reached "
                                                                  @"%@\nLatenc"
                                                                  @"y: %.0f "
                                                                  @"ms",
                                                                  host, latency]
                                               preferredStyle:
                                                   UIAlertControllerStyleAlert];
                                 [resultAlert
                                     addAction:
                                         [UIAlertAction
                                             actionWithTitle:@"OK"
                                                       style:
                                                           UIAlertActionStyleDefault
                                                     handler:nil]];
                                 [self presentViewController:resultAlert
                                                    animated:YES
                                                  completion:nil];
                               }];
#else
            NSAlert *resultAlert = [[NSAlert alloc] init];
            resultAlert.messageText = @"Ping Successful";
            resultAlert.informativeText = [NSString
                stringWithFormat:@"Successfully reached %@\nLatency: %.0f ms",
                                 host, latency];
            [resultAlert addButtonWithTitle:@"OK"];
            [resultAlert runModal];
#endif
      });
    } else if (state == nw_connection_state_failed ||
               state == nw_connection_state_cancelled) {
      if (completed)
        return;
      completed = YES;

      NSString *errorMessage = @"Connection failed";
      if (nw_error) {
        int error_code = nw_error_get_error_code(nw_error);
        errorMessage = [NSString stringWithFormat:@"Error %d", error_code];
      }

      dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
        [progressAlert
            dismissViewControllerAnimated:YES
                               completion:^{
                                 UIAlertController *resultAlert = [UIAlertController
                                     alertControllerWithTitle:@"Ping Failed"
                                                      message:
                                                          [NSString
                                                              stringWithFormat:
                                                                  @"Failed to "
                                                                  @"reach "
                                                                  @"%@\n%@",
                                                                  host,
                                                                  errorMessage]
                                               preferredStyle:
                                                   UIAlertControllerStyleAlert];
                                 [resultAlert
                                     addAction:
                                         [UIAlertAction
                                             actionWithTitle:@"OK"
                                                       style:
                                                           UIAlertActionStyleDefault
                                                     handler:nil]];
                                 [self presentViewController:resultAlert
                                                    animated:YES
                                                  completion:nil];
                               }];
#else
            NSAlert *resultAlert = [[NSAlert alloc] init];
            resultAlert.messageText = @"Ping Failed";
            resultAlert.informativeText = [NSString
                stringWithFormat:@"Failed to reach %@\n%@", host, errorMessage];
            [resultAlert addButtonWithTitle:@"OK"];
            [resultAlert runModal];
#endif
      });
    }
  });

  nw_connection_start(connection);

  // Timeout
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
      connectionQueue, ^{
        if (!completed) {
          completed = YES;
          nw_connection_cancel(connection);
          dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
            [progressAlert
                dismissViewControllerAnimated:YES
                                   completion:^{
                                     UIAlertController *resultAlert = [UIAlertController
                                         alertControllerWithTitle:@"Ping Failed"
                                                          message:
                                                              [NSString
                                                                  stringWithFormat:
                                                                      @"Connect"
                                                                      @"io"
                                                                      @"n "
                                                                      @"waiting"
                                                                      @" "
                                                                      @"timeout"
                                                                      @" "
                                                                      @"to "
                                                                      @"%@",
                                                                      host]
                                                   preferredStyle:
                                                       UIAlertControllerStyleAlert];
                                     [resultAlert
                                         addAction:
                                             [UIAlertAction
                                                 actionWithTitle:@"OK"
                                                           style:
                                                               UIAlertActionStyleDefault
                                                         handler:nil]];
                                     [self presentViewController:resultAlert
                                                        animated:YES
                                                      completion:nil];
                                   }];
#else
                       NSAlert *resultAlert = [[NSAlert alloc] init];
                       resultAlert.messageText = @"Ping Failed";
                       resultAlert.informativeText = [NSString
                           stringWithFormat:@"Connection waiting timeout to %@",
                                            host];
                       [resultAlert addButtonWithTitle:@"OK"];
                       [resultAlert runModal];
#endif
          });
        }
      });
}

- (void)pingHost {
  WWNLog("UI", @"Ping Host button pressed");
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  NSString *host = prefs.waypipeSSHHost ?: prefs.sshHost;

  WWNLog("SSH", @"Attempting to ping host: '%@'", host ?: @"(nil)");

  if (!host || host.length == 0) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"No Host Specified"
                         message:@"Please enter an SSH host address first."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"No Host Specified";
    alert.informativeText = @"Please enter an SSH host address first.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
#endif
    return;
  }

#if TARGET_OS_IPHONE
  UIAlertController *progressAlert = [UIAlertController
      alertControllerWithTitle:@"Pinging Host"
                       message:[NSString
                                   stringWithFormat:
                                       @"Testing connectivity to %@...", host]
                preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:progressAlert animated:YES completion:nil];
#endif

  // Perform ping on background thread using Network.framework
  nw_endpoint_t endpoint = nw_endpoint_create_host([host UTF8String], "22");

  // Explicitly configure for TCP without TLS, and enable local network access
  nw_parameters_t parameters = nw_parameters_create_secure_tcp(
      NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
  nw_parameters_set_include_peer_to_peer(parameters, true);

  nw_connection_t connection = nw_connection_create(endpoint, parameters);

  if (!connection) {
    NSString *errorMessage = @"Failed to create Network.framework connection";
    dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
      [progressAlert
          dismissViewControllerAnimated:YES
                             completion:^{
                               UIAlertController *resultAlert = [UIAlertController
                                   alertControllerWithTitle:@"Ping Failed"
                                                    message:
                                                        [NSString
                                                            stringWithFormat:
                                                                @"Failed to "
                                                                @"reach "
                                                                @"%@\n%@",
                                                                host,
                                                                errorMessage]
                                             preferredStyle:
                                                 UIAlertControllerStyleAlert];
                               [resultAlert
                                   addAction:
                                       [UIAlertAction
                                           actionWithTitle:@"OK"
                                                     style:
                                                         UIAlertActionStyleDefault
                                                   handler:nil]];
                               [self presentViewController:resultAlert
                                                  animated:YES
                                                completion:nil];
                             }];
#else
      NSAlert *resultAlert = [[NSAlert alloc] init];
      resultAlert.messageText = @"Ping Failed";
      resultAlert.informativeText = [NSString
          stringWithFormat:@"Failed to reach %@\n%@", host, errorMessage];
      [resultAlert addButtonWithTitle:@"OK"];
      [resultAlert runModal];
#endif
    });
    return;
  }

  dispatch_queue_t connectionQueue = dispatch_queue_create(
      "com.aspauldingcode.wawona.ping", DISPATCH_QUEUE_SERIAL);
  nw_connection_set_queue(connection, connectionQueue);

  __block BOOL completed = NO;
  NSDate *startTime = [NSDate date];

  nw_connection_set_state_changed_handler(connection, ^(
                                              nw_connection_state_t state,
                                              nw_error_t nw_error) {
    if (completed)
      return;

    if (state == nw_connection_state_ready) {
      completed = YES;
      NSTimeInterval latency =
          [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
      nw_connection_cancel(connection);

      dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
        [progressAlert
            dismissViewControllerAnimated:YES
                               completion:^{
                                 UIAlertController *resultAlert = [UIAlertController
                                     alertControllerWithTitle:@"Ping Successful"
                                                      message:
                                                          [NSString
                                                              stringWithFormat:
                                                                  @"Host "
                                                                  @"%@ is "
                                                                  @"reachab"
                                                                  @"le."
                                                                  @"\nLaten"
                                                                  @"cy: "
                                                                  @"%.0f "
                                                                  @"ms",
                                                                  host, latency]
                                               preferredStyle:
                                                   UIAlertControllerStyleAlert];
                                 [resultAlert
                                     addAction:
                                         [UIAlertAction
                                             actionWithTitle:@"OK"
                                                       style:
                                                           UIAlertActionStyleDefault
                                                     handler:nil]];
                                 [self presentViewController:resultAlert
                                                    animated:YES
                                                  completion:nil];
                               }];
#else
            NSAlert *resultAlert = [[NSAlert alloc] init];
            resultAlert.messageText = @"Ping Successful";
            resultAlert.informativeText = [NSString
                stringWithFormat:@"Host %@ is reachable.\nLatency: %.0f ms",
                                 host, latency];
            [resultAlert addButtonWithTitle:@"OK"];
            [resultAlert runModal];
#endif
      });
    } else if (state == nw_connection_state_failed ||
               state == nw_connection_state_cancelled) {
      if (completed)
        return;
      completed = YES;

      NSString *errorMessage = @"Connection failed";
      if (nw_error) {
        int error_code = nw_error_get_error_code(nw_error);
        errorMessage = [NSString stringWithFormat:@"Error %d", error_code];
      }

      dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
        [progressAlert
            dismissViewControllerAnimated:YES
                               completion:^{
                                 UIAlertController *resultAlert = [UIAlertController
                                     alertControllerWithTitle:@"Ping Failed"
                                                      message:
                                                          [NSString
                                                              stringWithFormat:
                                                                  @"Could "
                                                                  @"not "
                                                                  @"reach "
                                                                  @"%@.\n%"
                                                                  @"@",
                                                                  host,
                                                                  errorMessage]
                                               preferredStyle:
                                                   UIAlertControllerStyleAlert];
                                 [resultAlert
                                     addAction:
                                         [UIAlertAction
                                             actionWithTitle:@"OK"
                                                       style:
                                                           UIAlertActionStyleDefault
                                                     handler:nil]];
                                 [self presentViewController:resultAlert
                                                    animated:YES
                                                  completion:nil];
                               }];
#else
            NSAlert *resultAlert = [[NSAlert alloc] init];
            resultAlert.messageText = @"Ping Failed";
            resultAlert.informativeText =
                [NSString stringWithFormat:@"Could not reach %@.\n%@", host,
                                           errorMessage];
            [resultAlert addButtonWithTitle:@"OK"];
            [resultAlert runModal];
#endif
      });
    }
  });

  nw_connection_start(connection);

  // Timeout
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
      connectionQueue, ^{
        if (!completed) {
          completed = YES;
          nw_connection_cancel(connection);
          dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE
            [progressAlert
                dismissViewControllerAnimated:YES
                                   completion:^{
                                     UIAlertController *resultAlert = [UIAlertController
                                         alertControllerWithTitle:@"Ping Failed"
                                                          message:
                                                              [NSString
                                                                  stringWithFormat:
                                                                      @"Connect"
                                                                      @"io"
                                                                      @"n "
                                                                      @"waiting"
                                                                      @" "
                                                                      @"timeout"
                                                                      @" "
                                                                      @"after "
                                                                      @"10 "
                                                                      @"seconds"
                                                                      @" "
                                                                      @"to "
                                                                      @"%@",
                                                                      host]
                                                   preferredStyle:
                                                       UIAlertControllerStyleAlert];
                                     [resultAlert
                                         addAction:
                                             [UIAlertAction
                                                 actionWithTitle:@"OK"
                                                           style:
                                                               UIAlertActionStyleDefault
                                                         handler:nil]];
                                     [self presentViewController:resultAlert
                                                        animated:YES
                                                      completion:nil];
                                   }];
#else
                       NSAlert *resultAlert = [[NSAlert alloc] init];
                       resultAlert.messageText = @"Ping Failed";
                       resultAlert.informativeText = [NSString
                           stringWithFormat:
                               @"Connection waiting timeout after 10 seconds to %@",
                               host];
                       [resultAlert addButtonWithTitle:@"OK"];
                       [resultAlert runModal];
#endif
          });
        }
      });
}

#pragma mark - WWNWaypipeRunnerDelegate

- (void)runnerDidReceiveSSHPasswordPrompt:(NSString *)prompt {
  dispatch_async(dispatch_get_main_queue(), ^{
    WWNLog("SSH", @"SSH password prompt: %@", prompt);
#if TARGET_OS_IPHONE
    if (self.waypipeStatusAlert) {
      // Dismiss existing status alert if any
      [self.waypipeStatusAlert dismissViewControllerAnimated:NO completion:nil];
      self.waypipeStatusAlert = nil;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"SSH Password Required"
                         message:prompt ? prompt : @"Enter your SSH password:"
                  preferredStyle:UIAlertControllerStyleAlert];

    __block UITextField *passwordField = nil;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      passwordField = textField;
      textField.placeholder = @"Enter a Password...";
      textField.secureTextEntry = YES;

      // Add show/hide toggle button
      UIButton *toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
      [toggleButton setImage:[UIImage systemImageNamed:@"eye"]
                    forState:UIControlStateNormal];
      [toggleButton setImage:[UIImage systemImageNamed:@"eye.slash"]
                    forState:UIControlStateSelected];
      toggleButton.frame = CGRectMake(0, 0, 30, 30);
      toggleButton.contentMode = UIViewContentModeCenter;
      [toggleButton addTarget:self
                       action:@selector(togglePasswordVisibility:)
             forControlEvents:UIControlEventTouchUpInside];

      // Store reference to text field in button for toggling
      objc_setAssociatedObject(toggleButton, "passwordField", textField,
                               OBJC_ASSOCIATION_ASSIGN);

      textField.rightView = toggleButton;
      textField.rightViewMode = UITextFieldViewModeAlways;
    }];

    UIAlertAction *cancel =
        [UIAlertAction actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:nil];
    UIAlertAction *submit = [UIAlertAction
        actionWithTitle:@"Save & Connect"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  NSString *password = passwordField.text;
                  if (password && password.length > 0) {
                    // Save password
                    WWNPreferencesManager *prefs =
                        [WWNPreferencesManager sharedManager];
                    prefs.waypipeSSHPassword = password;

                    // Retry waypipe connection
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                 (int64_t)(0.1 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                                     [self runWaypipe];
                                   });
                  } else {
                    UIAlertController *errorAlert = [UIAlertController
                        alertControllerWithTitle:@"Password Required"
                                         message:@"Please enter a password."
                                  preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert
                        addAction:[UIAlertAction
                                      actionWithTitle:@"OK"
                                                style:UIAlertActionStyleDefault
                                              handler:nil]];
                    [self presentViewController:errorAlert
                                       animated:YES
                                     completion:nil];
                  }
                }];
    [alert addAction:cancel];
    [alert addAction:submit];

    // Safe presentation
    UIViewController *presenter = self;
    if (presenter.presentedViewController) {
      [presenter.presentedViewController
          dismissViewControllerAnimated:NO
                             completion:^{
                               [presenter presentViewController:alert
                                                       animated:YES
                                                     completion:nil];
                             }];
    } else {
      [presenter presentViewController:alert animated:YES completion:nil];
    }
#else
  // macOS: Use NSAlert with secure text field and eyeball toggle
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"SSH Password Required";
  alert.informativeText = prompt ? prompt : @"Enter your SSH password:";
  [alert addButtonWithTitle:@"Save & Connect"];
  [alert addButtonWithTitle:@"Cancel"];
  alert.alertStyle = NSAlertStyleInformational;

  // Create container view with password field and toggle button
  NSView *containerView =
      [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];

  // Create secure text field (hidden by default)
  NSSecureTextField *secureField =
      [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
  secureField.placeholderString = @"Enter a Password...";
  secureField.stringValue = @"";
  [containerView addSubview:secureField];

  // Create plain text field (for showing password)
  NSTextField *plainField =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
  plainField.placeholderString = @"Enter a Password...";
  plainField.stringValue = @"";
  plainField.hidden = YES;
  [containerView addSubview:plainField];

  // Create eyeball toggle button
  NSButton *toggleButton =
      [[NSButton alloc] initWithFrame:NSMakeRect(255, 2, 20, 20)];
  toggleButton.bezelStyle = NSBezelStyleInline;
  toggleButton.bordered = NO;
  toggleButton.image = [NSImage imageWithSystemSymbolName:@"eye"
                                 accessibilityDescription:@"Show password"];

  // Store references for toggle action
  objc_setAssociatedObject(toggleButton, "secureField", secureField,
                           OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(toggleButton, "plainField", plainField,
                           OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(toggleButton, "isSecure", @YES,
                           OBJC_ASSOCIATION_RETAIN);

  toggleButton.target = self;
  toggleButton.action = @selector(toggleMacOSPasswordVisibility:);

  [containerView addSubview:toggleButton];

  alert.accessoryView = containerView;

  NSModalResponse response = [alert runModal];
  if (response == NSAlertFirstButtonReturn) {
      // Logic for saving password on macOS
      NSString *password = nil;
      NSNumber *isSecure = objc_getAssociatedObject(toggleButton, "isSecure");
      if ([isSecure boolValue]) {
          password = secureField.stringValue;
      } else {
          password = plainField.stringValue;
      }
      
      if (password.length > 0) {
          WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
          prefs.waypipeSSHPassword = password;
           dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                       (int64_t)(0.1 * NSEC_PER_SEC)),
                         dispatch_get_main_queue(), ^{
                           [self runWaypipe];
                         });
      }
  }
#endif
  });
}

#if !TARGET_OS_IPHONE
// Action for toggling password visibility in macOS dialog
- (void)toggleMacOSPasswordVisibility:(NSButton *)sender {
  NSSecureTextField *secureField =
      objc_getAssociatedObject(sender, "secureField");
  NSTextField *plainField = objc_getAssociatedObject(sender, "plainField");
  NSNumber *isSecureNum = objc_getAssociatedObject(sender, "isSecure");
  BOOL isSecure = isSecureNum ? isSecureNum.boolValue : YES;

  if (isSecure) {
    plainField.stringValue = secureField.stringValue;
    secureField.hidden = YES;
    plainField.hidden = NO;
    sender.image = [NSImage imageWithSystemSymbolName:@"eye.slash"
                             accessibilityDescription:@"Hide password"];
    objc_setAssociatedObject(sender, "isSecure", @NO, OBJC_ASSOCIATION_RETAIN);
  } else {
    secureField.stringValue = plainField.stringValue;
    plainField.hidden = YES;
    secureField.hidden = NO;
    sender.image = [NSImage imageWithSystemSymbolName:@"eye"
                             accessibilityDescription:@"Show password"];
    objc_setAssociatedObject(sender, "isSecure", @YES, OBJC_ASSOCIATION_RETAIN);
  }
}
#endif

- (void)runnerDidReceiveSSHError:(NSString *)error {
  // Log error to status text
  NSString *errorLine =
      [NSString stringWithFormat:@"\n[SSH ERROR] %@\n", error];
  [self.waypipeStatusText appendString:errorLine];

#if TARGET_OS_IPHONE
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.waypipeStatusAlert) {
      [self.waypipeStatusAlert dismissViewControllerAnimated:YES
                                                  completion:nil];
      self.waypipeStatusAlert = nil;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"SSH/Waypipe Error"
                         message:error
                  preferredStyle:UIAlertControllerStyleAlert];

#if !TARGET_OS_TV
    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Copy Error"
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   if ([UIApplication sharedApplication]
                                           .applicationState ==
                                       UIApplicationStateActive) {
                                     [UIPasteboard generalPasteboard].string =
                                         error;
                                   }
                                 }]];
#endif

    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIViewController *presenter = self;
    if (presenter.presentedViewController) {
      [presenter.presentedViewController
          dismissViewControllerAnimated:NO
                             completion:^{
                               [presenter presentViewController:alert
                                                       animated:YES
                                                     completion:nil];
                             }];
    } else {
      [presenter presentViewController:alert animated:YES completion:nil];
    }
  });
#else
  dispatch_async(dispatch_get_main_queue(), ^{
    // Update status panel with error
    if (self.waypipeStatusPanel) {
      self.waypipeStatusPanel.title = @"Waypipe - Error";
    }
    [self updateWaypipeStatusPanel];

    // Also show an alert
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"SSH/Waypipe Error";
    alert.informativeText = error;
    alert.alertStyle = NSAlertStyleCritical;
    [alert addButtonWithTitle:@"Copy Error"];
    [alert addButtonWithTitle:@"OK"];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
      [[NSPasteboard generalPasteboard] clearContents];
      [[NSPasteboard generalPasteboard] setString:error
                                          forType:NSPasteboardTypeString];
    }
  });
#endif
}

- (void)runnerDidFinishWithExitCode:(int)exitCode {
  NSString *line =
      [NSString stringWithFormat:@"\n[Exited with code %d]\n", exitCode];
  [self.waypipeStatusText appendString:line];

#if TARGET_OS_IPHONE
  if (self.waypipeStatusAlert) {
    NSString *title = exitCode == 0 ? @"Waypipe Exited" : @"Waypipe Error";
    self.waypipeStatusAlert.title = title;
    self.waypipeStatusAlert.message = self.waypipeStatusText;
  }
#else
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.waypipeStatusPanel) {
      NSString *title =
          exitCode == 0 ? @"Waypipe - Exited" : @"Waypipe - Error";
      self.waypipeStatusPanel.title = title;
    }
    [self updateWaypipeStatusPanel];
  });
#endif
}

- (void)runnerDidReceiveOutput:(NSString *)output isError:(BOOL)isError {
  if (!output || output.length == 0)
    return;

  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.waypipeStatusText) {
      self.waypipeStatusText = [NSMutableString string];
    }

    // Prefix errors for clarity in the log
    NSString *formattedOutput =
        isError ? [NSString stringWithFormat:@"[stderr] %@", output] : output;
    [self.waypipeStatusText appendString:formattedOutput];

    // Limit log size
    NSUInteger maxLen = 50000;
    if (self.waypipeStatusText.length > maxLen) {
      [self.waypipeStatusText
          deleteCharactersInRange:NSMakeRange(0, self.waypipeStatusText.length -
                                                     maxLen)];
    }

#if TARGET_OS_IPHONE
    // Update the iOS status alert message in real-time
    if (self.waypipeStatusAlert) {
      // Show last ~500 chars to keep the alert readable
      NSString *displayText = self.waypipeStatusText;
      if (displayText.length > 500) {
        displayText = [@"...\n"
            stringByAppendingString:[displayText
                                        substringFromIndex:displayText.length -
                                                           500]];
      }
      self.waypipeStatusAlert.message = displayText;
    }
#else
    // Update text view if visible
    if (self.waypipeStatusTextView) {
      [self.waypipeStatusTextView.textStorage.mutableString
          setString:self.waypipeStatusText];
      [self.waypipeStatusTextView
          scrollRangeToVisible:NSMakeRange(self.waypipeStatusText.length, 0)];
    }
#endif

    // Re-use existing checks for connection success
    [self checkWaypipeSuccessIndicators:output];
  });
}

- (void)checkWaypipeSuccessIndicators:(NSString *)s {
  if (!self.waypipeMarkedConnected) {
    if ([s containsString:@"Authenticated to"] ||
        [s containsString:@"Entering interactive session"] ||
        [s containsString:@"Entering session"] ||
        [s containsString:@"debug1: Authentication succeeded"] ||
        [s containsString:@"Connection established"] ||
        [s containsString:@"Authenticated successfully"] ||
        [s containsString:@"SSH tunnel established"] ||
        [s containsString:@"pump threads started"]) {
      self.waypipeMarkedConnected = YES;
#if TARGET_OS_IPHONE
      if (self.waypipeStatusAlert) {
        self.waypipeStatusAlert.title = @"Waypipe - Connected";
      }
#else
      if (self.waypipeStatusPanel) {
        self.waypipeStatusPanel.title = @"Waypipe - Connected";
      }
#endif
    }
  }
}

- (void)runnerDidReadData:(NSData *)data {
  if (!data || data.length == 0) {
    return;
  }
  NSString *s =
      [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!s) {
    s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
  }
  [self runnerDidReceiveOutput:s isError:NO];
}

#if TARGET_OS_IPHONE

- (void)showPreferences:(id)sender {
  (void)sender;
  [self loadViewIfNeeded];
  UIViewController *presenter = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if (windowScene.activationState != UISceneActivationStateForegroundActive) {
      continue;
    }
    for (UIWindow *window in windowScene.windows) {
      if (window.isKeyWindow && window.rootViewController) {
        presenter = window.rootViewController;
        break;
      }
    }
    if (presenter) {
      break;
    }
  }
  if (!presenter) {
    presenter = UIApplication.sharedApplication.delegate.window.rootViewController;
  }
  if (!presenter) {
    return;
  }
  while (presenter.presentedViewController) {
    if ([presenter.presentedViewController isKindOfClass:[UINavigationController class]]) {
      UINavigationController *nav = (UINavigationController *)presenter.presentedViewController;
      if (nav.viewControllers.count > 0 &&
          [nav.viewControllers.firstObject isKindOfClass:[WWNPreferences class]]) {
        return;
      }
    }
    presenter = presenter.presentedViewController;
  }
  WWNSettingsSplitViewController *splitVC =
      [[WWNSettingsSplitViewController alloc] init];
  splitVC.modalPresentationStyle = UIModalPresentationFormSheet;
  [presenter presentViewController:splitVC animated:YES completion:nil];
}

- (void)selectSectionWithTitle:(NSString *)title {
  if (title.length == 0) {
    return;
  }
  for (WWNPreferencesSection *section in self.sections) {
    if ([section.title caseInsensitiveCompare:title] == NSOrderedSame) {
      self.activeSection = section;
      self.title = section.title;
      if ([section.title isEqualToString:@"Environment Variables"]) {
        // Show the full inventory inline instead of a button-only stub.
        [self openEnvironmentVariablesManager];
      }
      if (self.isViewLoaded) {
        [self.tableView reloadData];
      }
      break;
    }
  }
}

- (void)openMachinesConfiguration:(id)sender {
  (void)sender;
  UIViewController *presenter = self;
  if (presenter.presentedViewController != nil) {
    presenter = presenter.presentedViewController;
  }
  [[WWNMachinesCoordinator sharedCoordinator]
      presentMachinesFromViewController:presenter
                              onConnect:^{
                              }];
}

- (void)dismissSelf {
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
  if (self.activeSection) {
    return 1;
  }
  return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
  if (self.activeSection) {
    return self.activeSection.items.count;
  }
  return self.sections[sec].items.count;
}

- (NSString *)tableView:(UITableView *)tv
    titleForHeaderInSection:(NSInteger)sec {
  if (self.activeSection) {
    return self.activeSection.title;
  }
  return self.sections[sec].title;
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)ip {
  WWNSettingItem *item;
  if (self.activeSection) {
    item = self.activeSection.items[ip.row];
  } else {
    item = self.sections[ip.section].items[ip.row];
  }

  BOOL usesSubtitleInfoCell =
      (item.type == WSettingInfo && item.key == nil && item.desc.length > 0);
  NSString *cellIdentifier =
      usesSubtitleInfoCell ? @"InfoSubtitleCell" : @"Cell";
  UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cellIdentifier];
  if (!cell) {
    UITableViewCellStyle style = usesSubtitleInfoCell
                                     ? UITableViewCellStyleSubtitle
                                     : UITableViewCellStyleValue1;
    cell = [[UITableViewCell alloc] initWithStyle:style
                                  reuseIdentifier:cellIdentifier];
  }

  // Reset image to avoid phantom reuse
  cell.imageView.image = nil;
  cell.imageView.layer.cornerRadius = 0;
  cell.imageView.clipsToBounds = NO;

  cell.textLabel.text = item.title;
  cell.accessibilityLabel = item.title;
  cell.accessibilityIdentifier = item.accessibilityIdentifier;
  if (item.type != WSettingHeader) {
    cell.textLabel.font = [UIFont systemFontOfSize:17];
  }
  cell.textLabel.textColor =
      [UIColor labelColor]; // Reset to default color (not blue)
  cell.detailTextLabel.text = nil;
  cell.detailTextLabel.numberOfLines = 1;
  cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
  cell.accessoryView = nil;
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  if (item.type == WSettingSwitch) {
#if TARGET_OS_TV
    BOOL swOn = YES;
    BOOL swEnabled = item.interactive;
    if ([item.key isEqualToString:@"WaypipeOneshot"]) {
      swOn = YES;
      swEnabled = NO;
      cell.textLabel.textColor = [UIColor secondaryLabelColor];
      cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if ([item.key isEqualToString:@"ForceServerSideDecorations"]) {
      swOn = [[NSUserDefaults standardUserDefaults] boolForKey:item.key];
    } else {
      swOn = [[NSUserDefaults standardUserDefaults] boolForKey:item.key];
    }
    UIButton *toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [toggleBtn setTitle:(swOn ? @"On" : @"Off") forState:UIControlStateNormal];
    toggleBtn.enabled = swEnabled;
    toggleBtn.tag = (ip.section * 1000) + ip.row;
    [toggleBtn addTarget:self
                  action:@selector(tvSwitchButtonPressed:)
        forControlEvents:UIControlEventPrimaryActionTriggered];
    cell.accessoryView = toggleBtn;
#else
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
#if TARGET_OS_IPHONE
    // iOS: One-shot is always on (libssh2 in-process); show as on and disabled.
    // Row remains tappable so we can show "iOS does not allow this feature."
    if ([item.key isEqualToString:@"WaypipeOneshot"]) {
      sw.on = YES;
      sw.enabled = NO;
      cell.textLabel.textColor = [UIColor secondaryLabelColor];
      cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
      sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:item.key];
      sw.enabled = item.interactive;
      if (!item.interactive) {
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
      }
    }
#else
    sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:item.key];
    sw.enabled = item.interactive;
    if (!item.interactive) {
      cell.textLabel.textColor = [UIColor secondaryLabelColor];
    }
#endif
    sw.tag = (ip.section * 1000) + ip.row;
    [sw addTarget:self
                  action:@selector(swChg:)
        forControlEvents:UIControlEventValueChanged];

    // No info buttons for switches - removed per user request
    cell.accessoryView = sw;
#endif
  } else if (item.type == WSettingText || item.type == WSettingNumber) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!val) {
      val = item.defaultValue;
    }

    // Special handling for Display Number: show computed wayland-X value
    if ([item.key isEqualToString:@"WaylandDisplayNumber"]) {
      NSInteger displayNum =
          [val isKindOfClass:[NSNumber class]] ? [val integerValue] : 0;
      cell.detailTextLabel.text =
          [NSString stringWithFormat:@"%ld (wayland-%ld)", (long)displayNum,
                                     (long)displayNum];
    } else {
      cell.detailTextLabel.text = [val description];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WSettingPassword) {
    // For password fields, show dots if password exists, otherwise show
    // placeholder
    WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
    NSString *password = nil;
    if ([item.key isEqualToString:@"WaypipeSSHPassword"] ||
        [item.key isEqualToString:@"SSHPassword"]) {
      password = prefs.waypipeSSHPassword ?: prefs.sshPassword;
    } else if ([item.key isEqualToString:@"WaypipeSSHKeyPassphrase"] ||
               [item.key isEqualToString:@"SSHKeyPassphrase"]) {
      password = prefs.waypipeSSHKeyPassphrase ?: prefs.sshKeyPassphrase;
    }
    if (password && password.length > 0) {
      cell.detailTextLabel.text = @"Change";
    } else {
      cell.detailTextLabel.text = @"Set";
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WSettingPopup) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!val) {
      val = item.defaultValue;
    }

    // Special handling for Auth Method: convert integer to string
    if ([item.key isEqualToString:@"WaypipeSSHAuthMethod"] ||
        [item.key isEqualToString:@"SSHAuthMethod"]) {
      NSInteger methodIndex =
          [val isKindOfClass:[NSNumber class]] ? [val integerValue] : 0;
      if (methodIndex >= 0 && methodIndex < (NSInteger)item.options.count) {
        cell.detailTextLabel.text = item.options[methodIndex];
      } else {
        cell.detailTextLabel.text = item.options[0]; // Default to "Password"
      }
    } else {
      // If optionValues exists, find display text from options by matching
      // stored value
      if (item.optionValues && item.optionValues.count == item.options.count) {
        NSString *stored = [val description];
        for (NSInteger i = 0; i < (NSInteger)item.optionValues.count; i++) {
          if ([item.optionValues[i] isEqualToString:stored]) {
            cell.detailTextLabel.text = item.options[i];
            goto popup_done;
          }
        }
      }
      cell.detailTextLabel.text = [val description];
    }
  popup_done:
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (item.interactive) {
      cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
      cell.selectionStyle = UITableViewCellSelectionStyleNone;
      cell.textLabel.textColor = [UIColor secondaryLabelColor];
      cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
    }
  } else if (item.type == WSettingButton) {
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (item.type == WSettingInfo) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!val) {
      val = item.defaultValue;
    }
    if (usesSubtitleInfoCell) {
      NSString *valueString = [val description] ?: @"";
      cell.detailTextLabel.text = item.desc;
      cell.detailTextLabel.numberOfLines = 2;
      cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
      if (valueString.length > 0) {
        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.font = [UIFont systemFontOfSize:15];
        valueLabel.textColor = [UIColor secondaryLabelColor];
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.text = valueString;
        [valueLabel sizeToFit];
        cell.accessoryView = valueLabel;
      }
    } else {
      cell.detailTextLabel.text = [val description];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;

    // Reset image to avoid phantom reuse
    cell.imageView.image = nil;

    // Load icon image if URL provided (e.g. for Author profile pic)
    if (item.iconURL) {
      // Set a placeholder so UITableViewCell reserves space for the imageView
      cell.imageView.image = [UIImage systemImageNamed:@"person.circle.fill"];
      cell.imageView.layer.cornerRadius = 4;
      cell.imageView.clipsToBounds = YES;
      [[WWNImageLoader sharedLoader]
          loadImageFromURL:item.iconURL
                completion:^(WImage _Nullable image) {
                  if (image &&
                      [cell.textLabel.text isEqualToString:item.title]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      cell.imageView.image = image;
                      [cell setNeedsLayout];
                    });
                  }
                }];
    } else {
      cell.imageView.image = nil;
    }
  } else if (item.type == WSettingLink) {
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.detailTextLabel.text = item.desc;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    // Reset image to avoid phantom reuse
    cell.imageView.image = nil;

    // Load icon image if URL provided (e.g. for GitHub, Ko-fi, etc.)
    if (item.iconURL) {
      // Set a placeholder so UITableViewCell reserves space for the imageView
      cell.imageView.image = [UIImage systemImageNamed:@"link.circle.fill"];
      cell.imageView.layer.cornerRadius = 4;
      cell.imageView.clipsToBounds = YES;
      [[WWNImageLoader sharedLoader]
          loadImageFromURL:item.iconURL
                completion:^(WImage _Nullable image) {
                  if (image &&
                      [cell.textLabel.text isEqualToString:item.title]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      cell.imageView.image = image;
                      [cell setNeedsLayout];
                    });
                  }
                }];
    }
  } else if (item.type == WSettingHeader) {
    // Android-style About header: vertically stacked, centered layout.
    // Use a different reuse identifier so Auto Layout doesn't collide
    // with the standard Value1 cells.
    static NSString *const kHeaderID = @"AboutHeader";
    UITableViewCell *headerCell =
        [tv dequeueReusableCellWithIdentifier:kHeaderID];

    if (!headerCell) {
      headerCell =
          [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                 reuseIdentifier:kHeaderID];
      headerCell.selectionStyle = UITableViewCellSelectionStyleNone;
      headerCell.backgroundColor = [UIColor clearColor];

      UIStackView *stack = [[UIStackView alloc] init];
      stack.axis = UILayoutConstraintAxisVertical;
      stack.alignment = UIStackViewAlignmentCenter;
      stack.spacing = 0;
      stack.translatesAutoresizingMaskIntoConstraints = NO;
      stack.tag = 900;
      [headerCell.contentView addSubview:stack];

      [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor
            constraintEqualToAnchor:headerCell.contentView.topAnchor
                           constant:24],
        [stack.bottomAnchor
            constraintEqualToAnchor:headerCell.contentView.bottomAnchor
                           constant:-24],
        [stack.leadingAnchor
            constraintEqualToAnchor:headerCell.contentView.leadingAnchor
                           constant:20],
        [stack.trailingAnchor
            constraintEqualToAnchor:headerCell.contentView.trailingAnchor
                           constant:-20]
      ]];

      // Logo
      UIImageView *logo = [[UIImageView alloc] init];
      logo.contentMode = UIViewContentModeScaleAspectFit;
      logo.tag = 901;
      [stack addArrangedSubview:logo];
      [NSLayoutConstraint activateConstraints:@[
        [logo.widthAnchor constraintEqualToConstant:100],
        [logo.heightAnchor constraintEqualToConstant:100]
      ]];

      [stack setCustomSpacing:16 afterView:logo];

      // App title
      UILabel *titleLabel = [[UILabel alloc] init];
      titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
      titleLabel.textAlignment = NSTextAlignmentCenter;
      titleLabel.tag = 902;
      [stack addArrangedSubview:titleLabel];

      [stack setCustomSpacing:4 afterView:titleLabel];

      // Version
      UILabel *versionLabel = [[UILabel alloc] init];
      versionLabel.font = [UIFont systemFontOfSize:15];
      versionLabel.textColor = [UIColor secondaryLabelColor];
      versionLabel.textAlignment = NSTextAlignmentCenter;
      versionLabel.tag = 903;
      [stack addArrangedSubview:versionLabel];

      [stack setCustomSpacing:12 afterView:versionLabel];

      // Description
      UILabel *descLabel = [[UILabel alloc] init];
      descLabel.font = [UIFont systemFontOfSize:15];
      descLabel.textColor = [UIColor secondaryLabelColor];
      descLabel.textAlignment = NSTextAlignmentCenter;
      descLabel.numberOfLines = 0;
      descLabel.tag = 904;
      [stack addArrangedSubview:descLabel];
    }

    // Populate
    UIImageView *logo = [headerCell.contentView viewWithTag:901];
    UILabel *titleLabel = (UILabel *)[headerCell.contentView viewWithTag:902];
    UILabel *versionLabel = (UILabel *)[headerCell.contentView viewWithTag:903];
    UILabel *descLabel = (UILabel *)[headerCell.contentView viewWithTag:904];

    UIImage *logoImage = WWNAboutLogo();
    logo.image = logoImage;

    titleLabel.text = item.title;

    NSString *ver = [self getWWNVersion];
    versionLabel.text = [NSString stringWithFormat:@"Version %@", ver];

    descLabel.text = item.desc;

    return headerCell;
  }
  return cell;
}

#if !TARGET_OS_TV
- (void)swChg:(UISwitch *)s {
  WWNSettingItem *item;
  if (self.activeSection) {
    item = self.activeSection.items[s.tag % 1000];
  } else {
    item = self.sections[s.tag / 1000].items[s.tag % 1000];
  }
#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
  if ([item.key isEqualToString:WWNRootfsICloudSyncPreferenceKey]) {
    [self handleLocalShellICloudSyncToggle:s.on];
    return;
  }
#endif
#if TARGET_OS_OSX
  if ([item.key isEqualToString:kWWNPrefsDesktopReplacementEnabled] && s.on) {
    WWNSipStatusType sipStatus = [WWNSipStatus current];
    if (![WWNSipStatus allowsDesktopReplacement:sipStatus]) {
      s.on = NO;
      [[NSUserDefaults standardUserDefaults]
          setBool:NO
           forKey:kWWNPrefsDesktopReplacementEnabled];
      [self showDesktopReplacementSipHowTo];
      return;
    }
    NSString *dylib = [[WWNDesktopReplacementController sharedController]
        bundledDylibPath];
    if (dylib.length == 0) {
      s.on = NO;
      [[NSUserDefaults standardUserDefaults]
          setBool:NO
           forKey:kWWNPrefsDesktopReplacementEnabled];
      NSAlert *alert = [[NSAlert alloc] init];
      alert.messageText = @"Mode B dylib not in this build";
      alert.informativeText =
          @"Desktop Replacement requires libwayland-mac.dylib from the "
          @"desktop-host package (nix build .#wawona-macos-desktop-host). "
          @"Store-safe builds stay on Mode A in-window present.";
      alert.alertStyle = NSAlertStyleWarning;
      [alert runModal];
      return;
    }
  }
#endif
  [[NSUserDefaults standardUserDefaults] setBool:s.on forKey:item.key];
  if ([item.key isEqualToString:kWWNPrefsRenderMacOSPointer]) {
    // Nested Compositor Cursor interactivity depends on Show Virtual Cursor.
    self.sections = [self buildSections];
    if (self.activeSection) {
      for (WWNPreferencesSection *sect in self.sections) {
        if ([sect.title isEqualToString:self.activeSection.title]) {
          self.activeSection = sect;
          break;
        }
      }
    }
    [self.tableView reloadData];
  }
}
#endif

#if TARGET_OS_TV
- (void)tvSwitchButtonPressed:(UIButton *)button {
  if (!button.enabled) {
    return;
  }
  WWNSettingItem *item;
  if (self.activeSection) {
    item = self.activeSection.items[button.tag % 1000];
  } else {
    item = self.sections[button.tag / 1000].items[button.tag % 1000];
  }
  BOOL cur = [[NSUserDefaults standardUserDefaults] boolForKey:item.key];
  BOOL next = !cur;
  [[NSUserDefaults standardUserDefaults] setBool:next forKey:item.key];
  [button setTitle:(next ? @"On" : @"Off") forState:UIControlStateNormal];
}
#endif

- (void)showHelpForSetting:(UIButton *)button {
  NSInteger section = button.tag / 1000;
  NSInteger row = button.tag % 1000;
  WWNSettingItem *item;
  if (self.activeSection) {
    item = self.activeSection.items[row];
  } else {
    item = self.sections[section].items[row];
  }
  [self showHelpForSettingWithItem:item];
}

- (void)showHelpForSettingWithItem:(WWNSettingItem *)item {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:item.title
                                          message:item.desc
                                   preferredStyle:UIAlertControllerStyleAlert];

  UIAlertAction *okAction =
      [UIAlertAction actionWithTitle:@"OK"
                               style:UIAlertActionStyleDefault
                             handler:nil];
  [alert addAction:okAction];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
  [tv deselectRowAtIndexPath:ip animated:YES];
  WWNSettingItem *item;
  if (self.activeSection) {
    item = self.activeSection.items[ip.row];
  } else {
    item = self.sections[ip.section].items[ip.row];
  }

  if (!item.interactive) {
    return;
  }

#if TARGET_OS_IPHONE
  // One-shot is fixed on iOS; tapping shows explanation.
  if ([item.key isEqualToString:@"WaypipeOneshot"]) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:@"iOS does not allow disabling this feature."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return;
  }
#endif

  // For switch items with help buttons, show help when row is tapped
  // Info buttons removed from waypipe switches per user request
  // No action needed for switches - they're handled by swChg:

  if (item.type == WSettingText || item.type == WSettingNumber) {
    // Present text entry view controller
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:item.desc
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      id currentValue =
          [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
      if (!currentValue) {
        currentValue = item.defaultValue;
      }
      textField.text = [currentValue description];
      if (item.type == WSettingNumber) {
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
      } else {
        textField.keyboardType = UIKeyboardTypeDefault;
      }
      // Set placeholder text - special case for Remote Command
      if ([item.key isEqualToString:@"WaypipeRemoteCommand"]) {
        textField.placeholder = @"e.g. weston-simple-shm";
      } else {
        textField.placeholder = item.desc;
      }
    }];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:nil];
    UIAlertAction *saveAction = [UIAlertAction
        actionWithTitle:@"Save"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  UITextField *textField = alert.textFields.firstObject;
                  NSString *value = textField.text;

                  if (item.type == WSettingNumber) {
                    NSNumber *numberValue = @([value doubleValue]);
                    [[NSUserDefaults standardUserDefaults] setObject:numberValue
                                                              forKey:item.key];
                  } else {
                    [[NSUserDefaults standardUserDefaults] setObject:value
                                                              forKey:item.key];
                  }
                  // Reload the table view to show updated value
                  [tv reloadRowsAtIndexPaths:@[ ip ]
                            withRowAnimation:UITableViewRowAnimationNone];
                }];

    [alert addAction:cancelAction];
    [alert addAction:saveAction];

    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.type == WSettingPassword) {
    // Single modal for password entry - always show entry field
    // Saving a new password automatically overwrites any existing one
    WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:item.desc
                  preferredStyle:UIAlertControllerStyleAlert];

    __block UITextField *passwordField = nil;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      passwordField = textField;
      textField.secureTextEntry = YES;
      textField.placeholder = @"Enter a Password...";
      textField.text = @"";

      // Add show/hide toggle button
      UIButton *toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
      [toggleButton setImage:[UIImage systemImageNamed:@"eye"]
                    forState:UIControlStateNormal];
      [toggleButton setImage:[UIImage systemImageNamed:@"eye.slash"]
                    forState:UIControlStateSelected];
      toggleButton.frame = CGRectMake(0, 0, 30, 30);
      toggleButton.contentMode = UIViewContentModeCenter;
      [toggleButton addTarget:self
                       action:@selector(togglePasswordVisibility:)
             forControlEvents:UIControlEventTouchUpInside];

      // Store reference to text field in button for toggling
      objc_setAssociatedObject(toggleButton, "passwordField", textField,
                               OBJC_ASSOCIATION_ASSIGN);

      textField.rightView = toggleButton;
      textField.rightViewMode = UITextFieldViewModeAlways;
    }];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:nil];

    UIAlertAction *saveAction = [UIAlertAction
        actionWithTitle:@"Save"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  NSString *value = passwordField.text;

                  // Save password (overwrites existing if any)
                  if ([item.key isEqualToString:@"WaypipeSSHPassword"]) {
                    prefs.waypipeSSHPassword = value;
                  } else if ([item.key
                                 isEqualToString:@"WaypipeSSHKeyPassphrase"]) {
                    prefs.waypipeSSHKeyPassphrase = value;
                  } else if ([item.key isEqualToString:@"SSHPassword"]) {
                    prefs.sshPassword = value;
                  } else if ([item.key isEqualToString:@"SSHKeyPassphrase"]) {
                    prefs.sshKeyPassphrase = value;
                  }

                  // Reload the table view to show updated value
                  [tv reloadRowsAtIndexPaths:@[ ip ]
                            withRowAnimation:UITableViewRowAnimationNone];
                }];

    [alert addAction:cancelAction];
    [alert addAction:saveAction];

    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.type == WSettingLink) {
    // Open URL in browser
    if (item.urlString) {
      [self openURL:item.urlString];
    }
  } else if (item.type == WSettingHeader) {
    // Header cells are not tappable
    return;
  } else if (item.type == WSettingInfo) {
    // For info items, show copy dialog
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!val) {
      val = item.defaultValue;
    }
    NSString *valueString = [val description];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:[NSString stringWithFormat:@"%@\n\n%@",
                                                            item.desc,
                                                            valueString]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction =
        [UIAlertAction actionWithTitle:@"OK"
                                 style:UIAlertActionStyleCancel
                               handler:nil];

#if !TARGET_OS_TV
    UIAlertAction *copyAction = [UIAlertAction
        actionWithTitle:@"Copy"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                  if ([UIApplication sharedApplication].applicationState ==
                      UIApplicationStateActive) {
                    pasteboard.string = valueString;
                  }
                }];
    [alert addAction:copyAction];
#endif
    [alert addAction:okAction];

    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.type == WSettingPopup) {
    // Present popup selection
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:item.title
                         message:item.desc
                  preferredStyle:UIAlertControllerStyleActionSheet];

    id currentValue =
        [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!currentValue) {
      currentValue = item.defaultValue;
    }

    // Special handling for Auth Method: convert integer to string for
    // comparison
    NSString *currentValueString = nil;
    NSInteger currentIndex = -1;
    if ([item.key isEqualToString:@"WaypipeSSHAuthMethod"] ||
        [item.key isEqualToString:@"SSHAuthMethod"]) {
      currentIndex = [currentValue isKindOfClass:[NSNumber class]]
                         ? [currentValue integerValue]
                         : 0;
      if (currentIndex >= 0 && currentIndex < (NSInteger)item.options.count) {
        currentValueString = item.options[currentIndex];
      } else {
        currentValueString = item.options[0]; // Default to "Password"
        currentIndex = 0;
      }
    } else {
      currentValueString = [currentValue description];
    }

    for (NSInteger i = 0; i < (NSInteger)item.options.count; i++) {
      NSString *option = item.options[i];
      NSString *valueToStore =
          (item.optionValues && i < (NSInteger)item.optionValues.count)
              ? item.optionValues[i]
              : option;
      NSString *valueToStoreCopy = valueToStore;
      NSInteger optionIndex = i;
      UIAlertAction *optionAction = [UIAlertAction
          actionWithTitle:option
                    style:UIAlertActionStyleDefault
                  handler:^(UIAlertAction *alertAction) {
                    // For Auth Method, store as integer index
                    if ([item.key isEqualToString:@"WaypipeSSHAuthMethod"] ||
                        [item.key isEqualToString:@"SSHAuthMethod"]) {
                      [[NSUserDefaults standardUserDefaults]
                          setInteger:optionIndex
                              forKey:item.key];
                      // Auth method changed - rebuild sections to show
                      // appropriate nested options
                      self.sections = [self buildSections];
                      [tv reloadData];
                    } else {
                      [[NSUserDefaults standardUserDefaults]
                          setObject:valueToStoreCopy
                             forKey:item.key];
                      // Reload the table view to show updated value
                      [tv reloadRowsAtIndexPaths:@[ ip ]
                                withRowAnimation:UITableViewRowAnimationNone];
                    }
                  }];

      // Mark current selection with checkmark
      if ([item.key isEqualToString:@"WaypipeSSHAuthMethod"] ||
          [item.key isEqualToString:@"SSHAuthMethod"]) {
        if (i == currentIndex) {
          [optionAction setValue:@YES forKey:@"checked"];
        }
      } else {
        if ([valueToStore isEqualToString:currentValueString]) {
          [optionAction setValue:@YES forKey:@"checked"];
        }
      }

      [alert addAction:optionAction];
    }

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:nil];
    [alert addAction:cancelAction];

    // For iPad, we need to set the popover presentation
    if (alert.popoverPresentationController) {
      UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
      alert.popoverPresentationController.sourceView = cell;
      alert.popoverPresentationController.sourceRect = cell.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
  } else if (item.actionBlock) {
    item.actionBlock();
  }
}

#else

// MARK: - macOS Interface

- (void)showPreferences:(id)sender {
  if (self.winController) {
    [self.winController.window makeKeyAndOrderFront:sender];
    return;
  }

  NSWindow *win = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 700, 500)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskFullSizeContentView
                  backing:NSBackingStoreBuffered
                    defer:NO];
  win.title = @"Wawona Settings";
  win.movableByWindowBackground = YES;

  // Add Toolbar (Liquid Glass Style)
  NSToolbar *toolbar =
      [[NSToolbar alloc] initWithIdentifier:@"WWNPreferencesToolbar"];
  toolbar.delegate = self;
  toolbar.displayMode = NSToolbarDisplayModeIconOnly;
  win.toolbar = toolbar;

  // Use the glass content view we just configured
  NSView *v = win.contentView;

  self.sidebar = [[WWNPreferencesSidebar alloc] init];
  self.sidebar.parent = self;
  self.content = [[WWNPreferencesContent alloc] init];

  self.splitVC = [[NSSplitViewController alloc] init];
  NSSplitViewItem *sItem =
      [NSSplitViewItem sidebarWithViewController:self.sidebar];
  sItem.minimumThickness = 160; // Ensure enough width for "Connection" text
  sItem.maximumThickness = 220;
  NSSplitViewItem *cItem =
      [NSSplitViewItem contentListWithViewController:self.content];
  [self.splitVC addSplitViewItem:sItem];
  [self.splitVC addSplitViewItem:cItem];

  // Embed SplitVC in Visual Effect View
  self.splitVC.view.frame = v.bounds;
  self.splitVC.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [v addSubview:self.splitVC.view];

  self.winController = [[NSWindowController alloc] initWithWindow:win];
  [win center];
  [win makeKeyAndOrderFront:sender];

  if (self.sections.count > 0) {
    [self.sidebar.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                          byExtendingSelection:NO];
  }
}

- (void)showSection:(NSInteger)idx {
  self.content.section = self.sections[idx];
  [self.content reloadForCurrentSection];
}

- (void)selectSectionWithTitle:(NSString *)title {
  if (title.length == 0) {
    return;
  }
  NSUInteger idx = [self.sections
      indexOfObjectPassingTest:^BOOL(WWNPreferencesSection *_Nonnull section,
                                     NSUInteger i, BOOL *_Nonnull stop) {
        (void)i;
        (void)stop;
        return [section.title caseInsensitiveCompare:title] == NSOrderedSame;
      }];
  if (idx == NSNotFound) {
    return;
  }

  [self showSection:(NSInteger)idx];
  if (self.sidebar.outlineView) {
    [self.sidebar.outlineView
        selectRowIndexes:[NSIndexSet indexSetWithIndex:idx]
      byExtendingSelection:NO];
  }
}

- (void)openMachinesConfiguration:(id)sender {
  (void)sender;
  [[WWNMachinesCoordinator sharedCoordinator] showMachinesWindowAndActivate:YES];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:
    (NSToolbar *)toolbar {
  return @[
    @"com.apple.NSToolbar.toggleSidebar", NSToolbarFlexibleSpaceItemIdentifier
  ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:
    (NSToolbar *)toolbar {
  return @[ @"com.apple.NSToolbar.toggleSidebar" ];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
        itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
    willBeInsertedIntoToolbar:(BOOL)flag {
  if ([itemIdentifier isEqualToString:@"com.apple.NSToolbar.toggleSidebar"]) {
    NSToolbarItem *item =
        [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    item.label = @"Toggle Sidebar";
    item.paletteLabel = @"Toggle Sidebar";
    item.toolTip = @"Toggle Sidebar";
    item.image = [NSImage imageWithSystemSymbolName:@"sidebar.left"
                           accessibilityDescription:nil];
    item.target = nil; // First Responder
    item.action = @selector(toggleSidebar:);
    return item;
  }
  return nil;
}

- (void)toggleSidebar:(id)sender {
  [NSApp sendAction:@selector(toggleSidebar:) to:nil from:sender];
}

#endif

#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
- (void)handleLocalShellICloudSyncToggle:(BOOL)enabled {
  NSError *error = nil;
  if (![WWNRootfsProvider setICloudSyncEnabled:enabled error:&error]) {
#if TARGET_OS_IPHONE
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"iCloud Sync Failed"
                         message:error.localizedDescription
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"iCloud Sync Failed";
    alert.informativeText = error.localizedDescription;
    [alert runModal];
#endif
  }
  self.sections = [self buildSections];
#if TARGET_OS_IPHONE
  [self.tableView reloadData];
#else
  [self.content.tableView reloadData];
#endif
}
#endif

#if TARGET_OS_IPHONE
- (void)togglePasswordVisibility:(UIButton *)sender {
  UITextField *textField = objc_getAssociatedObject(sender, "passwordField");
  if (textField) {
    textField.secureTextEntry = !textField.secureTextEntry;
    sender.selected = !textField.secureTextEntry;
  }
}

- (void)showLocalShellHelp {
  NSDictionary *rootfs = [WWNRootfsProvider snapshot];
  NSString *message =
      [NSString stringWithFormat:
                    @"Shell HOME:\n%@\n\nBrowse: %@\n\n"
                    @"System root:\n%@",
                    rootfs[@"home"], rootfs[@"filesHint"],
                    rootfs[@"systemRoot"]];
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Local Shell Files"
                       message:message
                preferredStyle:UIAlertControllerStyleAlert];
#if !TARGET_OS_TV
  [alert
      addAction:[UIAlertAction actionWithTitle:@"Copy HOME Path"
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action) {
                                         UIPasteboard.generalPasteboard.string =
                                             rootfs[@"home"];
                                       }]];
#endif
  [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmResetShellDotfiles {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Reset Shell Dotfiles?"
                       message:@"This overwrites .zshenv, .zshrc, and .zlogin "
                               @"in your shell HOME with bundled templates. "
                               @"Other files in home/ are kept."
                preferredStyle:UIAlertControllerStyleAlert];
  [alert
      addAction:[UIAlertAction
                    actionWithTitle:@"Reset"
                              style:UIAlertActionStyleDestructive
                            handler:^(UIAlertAction *action) {
                              NSError *error = nil;
                              if (![WWNRootfsProvider refreshShellDotfiles:
                                                         &error]) {
                                UIAlertController *err = [UIAlertController
                                    alertControllerWithTitle:@"Reset Failed"
                                                     message:error
                                                               .localizedDescription
                                              preferredStyle:
                                                  UIAlertControllerStyleAlert];
                                [err addAction:[UIAlertAction
                                                   actionWithTitle:@"OK"
                                                             style:
                                                                 UIAlertActionStyleDefault
                                                           handler:nil]];
                                [self presentViewController:err
                                                   animated:YES
                                                 completion:nil];
                                return;
                              }
                              self.sections = [self buildSections];
                              [self.tableView reloadData];
                              UIAlertController *ok = [UIAlertController
                                  alertControllerWithTitle:@"Dotfiles Reset"
                                                   message:@"Shell dotfiles "
                                                           @"restored from "
                                                           @"bundle templates."
                                            preferredStyle:
                                                UIAlertControllerStyleAlert];
                              [ok addAction:[UIAlertAction
                                                actionWithTitle:@"OK"
                                                          style:
                                                              UIAlertActionStyleDefault
                                                        handler:nil]];
                              [self presentViewController:ok
                                                 animated:YES
                                               completion:nil];
                            }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmReinstallSystemTree {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Reinstall System Tree?"
                       message:@"Re-copies etc/ and usr/ from the app bundle "
                               @"into Application Support. Your shell HOME "
                               @"(Documents/Wawona/home) is not modified."
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Reinstall"
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
                                 NSError *error = nil;
                                 if (![WWNRootfsProvider reinstallSystemTree:
                                                            &error]) {
                                   UIAlertController *err = [UIAlertController
                                       alertControllerWithTitle:@"Reinstall Failed"
                                                        message:error.localizedDescription
                                                 preferredStyle:
                                                     UIAlertControllerStyleAlert];
                                   [err addAction:[UIAlertAction
                                                      actionWithTitle:@"OK"
                                                                style:
                                                                    UIAlertActionStyleDefault
                                                              handler:nil]];
                                   [self presentViewController:err
                                                        animated:YES
                                                      completion:nil];
                                   return;
                                 }
                                 self.sections = [self buildSections];
                                 [self.tableView reloadData];
                               }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

#if !TARGET_OS_TV
- (void)importFileToShellHome {
  UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
      initForOpeningContentTypes:@[ UTTypeItem ]
                      asCopy:YES];
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  self.documentPickerImportsSSHKey = NO;
  self.documentPickerSendsToAppleWatch = NO;
  if (picker.popoverPresentationController) {
    picker.popoverPresentationController.sourceView = self.view;
    picker.popoverPresentationController.sourceRect = self.view.bounds;
  }
  [self presentViewController:picker animated:YES completion:nil];
}

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST && !TARGET_OS_TV && !TARGET_OS_WATCH && !TARGET_OS_VISION
- (void)sendDocumentToAppleWatch {
  UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
      initForOpeningContentTypes:@[ UTTypeItem ]
                          asCopy:YES];
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  self.documentPickerImportsSSHKey = NO;
  self.documentPickerSendsToAppleWatch = YES;
  if (picker.popoverPresentationController) {
    picker.popoverPresentationController.sourceView = self.view;
    picker.popoverPresentationController.sourceRect = self.view.bounds;
  }
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)sendPickedFileToAppleWatch:(NSArray<NSURL *> *)urls {
  NSURL *src = urls.firstObject;
  if (!src) {
    return;
  }
  BOOL accessed = [src startAccessingSecurityScopedResource];
  NSString *err =
      [[WWNWatchCompanionBridge sharedBridge] sendDocumentAtURL:src];
  if (accessed) {
    [src stopAccessingSecurityScopedResource];
  }
  if (err) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Send Failed"
                         message:err
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
  } else {
    self.sections = [self buildSections];
    [self.tableView reloadData];
    UIAlertController *ok = [UIAlertController
        alertControllerWithTitle:@"Queued for Watch"
                         message:[NSString
                                     stringWithFormat:
                                         @"%@ will transfer when the Watch is "
                                         @"available.",
                                         src.lastPathComponent ?: @"File"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [ok addAction:[UIAlertAction actionWithTitle:@"OK"
                                           style:UIAlertActionStyleDefault
                                         handler:nil]];
    [self presentViewController:ok animated:YES completion:nil];
  }
}
#endif

- (void)importPickedFileToShellHome:(NSArray<NSURL *> *)urls {
  NSURL *src = urls.firstObject;
  if (!src) {
    return;
  }
  BOOL accessed = [src startAccessingSecurityScopedResource];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *home = [WWNRootfsProvider snapshot][@"home"];
  [WWNRootfsProvider prepareUserAccess];
  NSString *baseName = src.lastPathComponent.length ? src.lastPathComponent
                                                    : @"imported-file";
  NSString *dest = [home stringByAppendingPathComponent:baseName];
  if ([fm fileExistsAtPath:dest]) {
    NSString *stem = [baseName stringByDeletingPathExtension];
    NSString *ext = [baseName pathExtension];
    NSString *suffix =
        [[NSUUID UUID].UUIDString substringToIndex:8];
    baseName = ext.length
        ? [NSString stringWithFormat:@"%@-%@.%@", stem, suffix, ext]
        : [NSString stringWithFormat:@"%@-%@", stem, suffix];
    dest = [home stringByAppendingPathComponent:baseName];
  }
  NSError *error = nil;
  if (![fm copyItemAtURL:src toURL:[NSURL fileURLWithPath:dest] error:&error]) {
    UIAlertController *err = [UIAlertController
        alertControllerWithTitle:@"Import Failed"
                         message:error.localizedDescription
                  preferredStyle:UIAlertControllerStyleAlert];
    [err addAction:[UIAlertAction actionWithTitle:@"OK"
                                           style:UIAlertActionStyleDefault
                                         handler:nil]];
    [self presentViewController:err animated:YES completion:nil];
  } else {
    UIAlertController *ok = [UIAlertController
        alertControllerWithTitle:@"Imported"
                         message:[NSString stringWithFormat:
                                               @"Saved to ~/ %@", baseName]
                  preferredStyle:UIAlertControllerStyleAlert];
    [ok addAction:[UIAlertAction actionWithTitle:@"OK"
                                           style:UIAlertActionStyleDefault
                                         handler:nil]];
    [self presentViewController:ok animated:YES completion:nil];
  }
  if (accessed) {
    [src stopAccessingSecurityScopedResource];
  }
}
#endif /* !TARGET_OS_TV */
#endif /* TARGET_OS_IPHONE */

#if TARGET_OS_OSX
- (void)showLocalShellHelp {
  NSDictionary *rootfs = [WWNRootfsProvider snapshot];
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Local Shell Files";
  alert.informativeText =
      [NSString stringWithFormat:@"Shell HOME:\n%@\n\n%@\n\nSystem root:\n%@",
                                 rootfs[@"home"], rootfs[@"filesHint"],
                                 rootfs[@"systemRoot"]];
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Copy HOME Path"];
  NSModalResponse response = [alert runModal];
  if (response == NSAlertSecondButtonReturn) {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:rootfs[@"home"] ?: @"" forType:NSPasteboardTypeString];
  }
}

- (void)openEnvironmentVariablesManager {
  // SwiftUI Environment Variables GUI (#157) — WWNEnvironmentSettingsPresenter in WawonaUI.
  Class presenter = NSClassFromString(@"WWNEnvironmentSettingsPresenter");
  if (presenter && [presenter respondsToSelector:@selector(presentFromHost:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [presenter performSelector:@selector(presentFromHost:) withObject:self];
#pragma clang diagnostic pop
    return;
  }
#if TARGET_OS_IPHONE
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Environment Variables"
                       message:@"Open Machine Settings → Environment, or rebuild "
                               @"with WawonaUI linked."
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
#else
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Environment Variables";
  alert.informativeText =
      @"Open Machine Settings → Environment, or rebuild with WawonaUI linked.";
  [alert runModal];
#endif
}

- (void)openLocalShellInFinder {
  if (![WWNRootfsProvider openUserFilesLocation]) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Could Not Open Finder";
    alert.informativeText = [WWNRootfsProvider snapshot][@"home"];
    [alert runModal];
  }
}

- (void)showDesktopReplacementSipHowTo {
  WWNSipStatusType sipStatus = [WWNSipStatus current];
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Desktop Replacement — SIP Requirements";
  alert.informativeText = [WWNSipStatus desktopReplacementHowToMessage];
  if ([WWNSipStatus allowsDesktopReplacement:sipStatus]) {
    alert.alertStyle = NSAlertStyleInformational;
  } else {
    alert.alertStyle = NSAlertStyleWarning;
  }
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Copy csrutil Command"];
  NSModalResponse response = [alert runModal];
  if (response == NSAlertSecondButtonReturn) {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:@"csrutil enable --without debug"
            forType:NSPasteboardTypeString];
  }
}
#endif

- (void)previewWaypipeCommand {
  id runner = [WWNWaypipeRunner sharedRunner];
  WWNLog("SSH", @"previewWaypipeCommand: runner=%@, class=%@", runner,
         [runner class]);
  NSString *cmdString = [runner
      generateWaypipePreviewString:[WWNPreferencesManager sharedManager]];

#if TARGET_OS_OSX
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Waypipe Command Preview";
  alert.informativeText = cmdString;
  [alert addButtonWithTitle:@"OK"];       // First button: FirstButtonReturn
                                          // (Default/Right)
  [alert addButtonWithTitle:@"Copy Log"]; // Second button: SecondButtonReturn
                                          // (Left)
  NSModalResponse response = [alert runModal];

  if (response == NSAlertSecondButtonReturn) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:cmdString forType:NSPasteboardTypeString];
  }
#else
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:@"Waypipe Command Preview"
                                          message:cmdString
                                   preferredStyle:UIAlertControllerStyleAlert];

#if !TARGET_OS_TV
  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Copy"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                 if ([UIApplication sharedApplication]
                                         .applicationState ==
                                     UIApplicationStateActive) {
                                   [UIPasteboard generalPasteboard].string =
                                       cmdString;
                                 }
                               }]];
#endif

  [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
#endif
}

@end

// MARK: - Helper Implementations

#if !TARGET_OS_IPHONE

@implementation WWNPreferencesSidebar
- (void)loadView {
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
  self.view = v;
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:v.bounds];
  sv.drawsBackground = NO;
  sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.outlineView = [[NSOutlineView alloc] initWithFrame:sv.bounds];
  self.outlineView.dataSource = self;
  self.outlineView.delegate = self;
  self.outlineView.headerView = nil;
  self.outlineView.rowHeight = 24.0; // Standard sidebar height
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"M"];
  col.width = 180;    // Ensure column is wide enough for sidebar text
  col.minWidth = 100; // Minimum width to prevent text wrapping
  col.resizingMask = NSTableColumnAutoresizingMask; // Auto-resize with sidebar
  [self.outlineView addTableColumn:col];
  self.outlineView.outlineTableColumn = col;
  self.outlineView.autoresizesOutlineColumn = YES; // Auto-size outline column
  sv.documentView = self.outlineView;
  sv.hasHorizontalScroller = NO; // No horizontal scroll in sidebar
  [v addSubview:sv];
}
- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
  return item ? 0 : self.parent.sections.count;
}
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
  return NO;
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)idx ofItem:(id)item {
  return self.parent.sections[idx];
}
- (NSView *)outlineView:(NSOutlineView *)ov
     viewForTableColumn:(NSTableColumn *)tc
                   item:(id)item {
  WWNPreferencesSection *s = item;
  NSTableCellView *cell = [ov makeViewWithIdentifier:@"Cell" owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 28)];
    cell.identifier = @"Cell";

    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSZeroRect];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:iv];
    cell.imageView = iv;

    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSZeroRect];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.bordered = NO;
    tf.drawsBackground = NO;
    tf.editable = NO;
    tf.maximumNumberOfLines = 1; // Single line only - no wrapping
    tf.lineBreakMode =
        NSLineBreakByTruncatingTail; // Truncate with ellipsis if needed
    tf.cell.truncatesLastVisibleLine = YES;
    [tf setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                 forOrientation:
                                     NSLayoutConstraintOrientationHorizontal]; // Allow truncation if needed
    [cell addSubview:tf];
    cell.textField = tf;

    [NSLayoutConstraint activateConstraints:@[
      [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:5],
      [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
      [iv.widthAnchor constraintEqualToConstant:20],
      [iv.heightAnchor constraintEqualToConstant:20],

      [tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:5],
      [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor
                                        constant:-5],
      [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
    ]];
  }
  cell.imageView.image =
      [NSImage imageWithSystemSymbolName:s.icon accessibilityDescription:nil];
  cell.imageView.contentTintColor = s.iconColor;
  cell.textField.stringValue = s.title;
  return cell;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)n {
  NSInteger row = self.outlineView.selectedRow;
  if (row >= 0)
    [self.parent showSection:row];
}
@end

// MARK: - WWNPreferenceCell
// A robust, statically laid-out cell to prevent visual corruption and reduce
// LOC.
@interface WWNPreferenceCell : NSTableCellView <NSTextFieldDelegate>
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *descLabel;
@property(nonatomic, strong) NSSwitch *switchControl;
@property(nonatomic, strong) NSTextField *textControl;
@property(nonatomic, strong) NSButton *buttonControl;
@property(nonatomic, strong) NSPopUpButton *popupControl;
@property(nonatomic, strong) NSImageView *iconView; // For link icons
@property(nonatomic, strong)
    NSImageView *headerImageView; // For large logos/avatars
@property(nonatomic, strong)
    NSLayoutConstraint *leadingConstraint; // New: for layout
@property(nonatomic, strong) NSLayoutConstraint *trailingConstraint;
@property(nonatomic, strong) WWNSettingItem *item;
@property(nonatomic, assign) id delegate; // MRC: use assign for delegates
- (void)configureWithItem:(WWNSettingItem *)item
                   target:(id)target
                   action:(SEL)action;
@end

@implementation WWNPreferenceCell
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.identifier = @"PCell";

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:13];
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.maximumNumberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.cell.truncatesLastVisibleLine = YES;
    [_titleLabel
        setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                 forOrientation:
                                     NSLayoutConstraintOrientationVertical];
    [_titleLabel
        setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                 forOrientation:
                                     NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_titleLabel];

    _descLabel = [NSTextField labelWithString:@""];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.font = [NSFont systemFontOfSize:11];
    _descLabel.textColor = [NSColor secondaryLabelColor];
    _descLabel.maximumNumberOfLines = 1;
    _descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _descLabel.cell.truncatesLastVisibleLine = YES;
    [_descLabel
        setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                 forOrientation:
                                     NSLayoutConstraintOrientationVertical];
    [_descLabel
        setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                 forOrientation:
                                     NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_descLabel];

    // Initialize all potential controls hidden
    _switchControl = [[NSSwitch alloc] init];
    _switchControl.translatesAutoresizingMaskIntoConstraints = NO;
    _switchControl.hidden = YES;
    [self addSubview:_switchControl];

    // Text Field (standard AppKit)
    _textControl = [[NSTextField alloc] init];
    _textControl.placeholderString = @"";
    _textControl.delegate = self; // Cell handles own delegate events
    _textControl.translatesAutoresizingMaskIntoConstraints = NO;
    _textControl.hidden = YES;
    [self addSubview:_textControl];

    // Button (standard AppKit)
    _buttonControl = [[NSButton alloc] init];
    _buttonControl.title = @"Run";
    _buttonControl.bezelStyle = NSBezelStyleRounded;
    _buttonControl.translatesAutoresizingMaskIntoConstraints = NO;
    _buttonControl.hidden = YES;
    [self addSubview:_buttonControl];

    _popupControl =
        [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _popupControl.translatesAutoresizingMaskIntoConstraints = NO;
    _popupControl.hidden = YES;
    [self addSubview:_popupControl];

    _iconView = [[NSImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.hidden = YES;
    _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:_iconView];

    _headerImageView = [[NSImageView alloc] init];
    _headerImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _headerImageView.hidden = YES;
    _headerImageView.wantsLayer = YES;
    _headerImageView.layer.masksToBounds = YES;
    _headerImageView.layer.cornerRadius = 0.0;
    _headerImageView.layer.contentsGravity = kCAGravityResizeAspect;
    [self addSubview:_headerImageView];

    // Static Auto Layout - Two column design:
    // Left column (labels): leading to ~55% of width
    // Right column (controls): ~45% of width, right-aligned
    CGFloat controlAreaWidth = 160; // Fixed width for control area
    CGFloat spacing = 16;           // Space between labels and controls

    [NSLayoutConstraint activateConstraints:@[
      // Title label - left column
      (_leadingConstraint =
           [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:20]),
      [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
      (_trailingConstraint = [_titleLabel.trailingAnchor
           constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                    constant:-(controlAreaWidth + spacing +
                                               20)]),

      // Description label - below title, same width constraints
      [_descLabel.leadingAnchor
          constraintEqualToAnchor:_titleLabel.leadingAnchor],
      [_descLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                           constant:2],
      [_descLabel.trailingAnchor
          constraintEqualToAnchor:_titleLabel.trailingAnchor],

      // Switch control - right column
      [_switchControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                    constant:-20],
      [_switchControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

      // Text control - right column with fixed width
      [_textControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                  constant:-20],
      [_textControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_textControl.widthAnchor constraintEqualToConstant:controlAreaWidth],

      // Button control - right column
      [_buttonControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                    constant:-20],
      [_buttonControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_buttonControl.widthAnchor constraintGreaterThanOrEqualToConstant:80],

      // Popup control - right column with fixed width
      [_popupControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                   constant:-20],
      [_popupControl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_popupControl.widthAnchor constraintEqualToConstant:controlAreaWidth],

      // Icon view (for links, etc.)
      [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                              constant:20],
      [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_iconView.widthAnchor constraintEqualToConstant:24],
      [_iconView.heightAnchor constraintEqualToConstant:24],

      // Header image view
      [_headerImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:20],
      [_headerImageView.centerYAnchor
          constraintEqualToAnchor:self.centerYAnchor],
      [_headerImageView.widthAnchor constraintEqualToConstant:48],
      [_headerImageView.heightAnchor constraintEqualToConstant:48],
    ]];
  }
  return self;
}

- (void)configureWithItem:(WWNSettingItem *)item
                   target:(id)target
                   action:(SEL)action {
  self.item = item;
  self.delegate = target; // Store controller as delegate
  self.titleLabel.stringValue = item.title ?: @"";
  self.descLabel.stringValue = item.desc ?: @"";

  // Reset Visibility
  self.switchControl.hidden = YES;
  self.textControl.hidden = YES;
  self.buttonControl.hidden = YES;
  self.popupControl.hidden = YES;
  self.headerImageView.hidden = YES;
  self.headerImageView.image = nil;
  self.iconView.image = nil; // Reset to avoid reuse flickering

  // Reset text wrapping/truncation state on reuse.
  self.descLabel.maximumNumberOfLines = 1;
  self.descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.descLabel.cell.wraps = NO;
  self.descLabel.cell.truncatesLastVisibleLine = YES;

  self.textControl.maximumNumberOfLines = 1;
  self.textControl.cell.wraps = NO;
  self.textControl.cell.usesSingleLineMode = YES;
  self.textControl.lineBreakMode = NSLineBreakByTruncatingTail;
  self.textControl.cell.truncatesLastVisibleLine = YES;

  NSControl *active = nil;

  // Base leading constraint
  self.leadingConstraint.constant = 20;

  // Icon logic
  if (item.iconURL) {
    self.iconView.hidden = NO;
    [[WWNImageLoader sharedLoader] loadImageFromURL:item.iconURL
                                         completion:^(WImage _Nullable image) {
                                           if (image) {
                                             self.iconView.image = image;
                                           }
                                         }];
    self.leadingConstraint.constant = 48; // Space for 24x24 icon + margin
  } else {
    self.iconView.hidden = YES;
  }

  if (item.type == WSettingSwitch) {
    self.switchControl.hidden = NO;
    self.switchControl.state =
        [[NSUserDefaults standardUserDefaults] boolForKey:item.key]
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    self.switchControl.enabled = item.interactive;
    self.switchControl.target = target;
    self.switchControl.action = action;
    active = self.switchControl;
  } else if (item.type == WSettingText || item.type == WSettingNumber) {
    self.textControl.hidden = NO;
    NSString *val =
        [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    self.textControl.stringValue =
        val ? val : ([item.defaultValue description] ?: @"");
    self.textControl.target = target;
    self.textControl.action = action;

    // Configure as editable text field
    self.textControl.editable = YES;
    self.textControl.selectable = YES;
    self.textControl.bezeled = YES;
    self.textControl.bezelStyle = NSTextFieldRoundedBezel;
    self.textControl.bordered = NO;
    self.textControl.drawsBackground =
        YES; // Needs background for rounded bezel
    self.textControl.backgroundColor = [NSColor controlBackgroundColor];

    // Set placeholder text for empty fields
    if ([item.key isEqualToString:@"WaypipeRemoteCommand"]) {
      self.textControl.placeholderString = @"e.g. weston-simple-shm";
    } else if ([item.key containsString:@"Host"]) {
      self.textControl.placeholderString = @"Remote host address";
    } else if ([item.key containsString:@"User"]) {
      self.textControl.placeholderString = @"SSH username";
    } else if ([item.key containsString:@"Path"]) {
      self.textControl.placeholderString = @"Enter path...";
    } else {
      self.textControl.placeholderString = nil;
    }

    // Use middle truncation for path-like fields (like Socket Directory)
    if ([item.key isEqualToString:@"WaylandSocketDir"] ||
        [item.key containsString:@"Dir"] || [item.key containsString:@"Path"]) {
      self.textControl.lineBreakMode = NSLineBreakByTruncatingMiddle;
      self.textControl.cell.truncatesLastVisibleLine = YES;
    } else {
      self.textControl.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    active = self.textControl;
  } else if (item.type == WSettingPassword) {
    // For password fields, show a button that opens a password entry dialog
    self.buttonControl.hidden = NO;
    // For password fields, get stored value to show status
    WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
    NSString *password = nil;
    if ([item.key isEqualToString:@"WaypipeSSHPassword"] ||
        [item.key isEqualToString:@"SSHPassword"]) {
      password = prefs.waypipeSSHPassword ?: prefs.sshPassword;
    } else if ([item.key isEqualToString:@"WaypipeSSHKeyPassphrase"] ||
               [item.key isEqualToString:@"SSHKeyPassphrase"]) {
      password = prefs.waypipeSSHKeyPassphrase ?: prefs.sshKeyPassphrase;
    }
    // Show button text based on whether password exists
    if (password && password.length > 0) {
      self.buttonControl.title = @"Change";
    } else {
      self.buttonControl.title = @"Set";
    }
    self.buttonControl.target = target;
    self.buttonControl.action = action;
    active = self.buttonControl;
  } else if (item.type == WSettingButton) {
    self.buttonControl.hidden = NO;
    self.buttonControl.title =
        [item.key isEqualToString:@"WaypipePreview"] ? @"Preview" : @"Run";
    self.buttonControl.target = target;
    self.buttonControl.action = action;
    active = self.buttonControl;
  } else if (item.type == WSettingPopup) {
    self.popupControl.hidden = NO;
    [self.popupControl removeAllItems];
    [self.popupControl addItemsWithTitles:item.options];

    // Handle SSHAuthMethod specially - stored as integer index
    if ([item.key isEqualToString:@"SSHAuthMethod"] ||
        [item.key isEqualToString:@"WaypipeSSHAuthMethod"]) {
      NSInteger methodIndex =
          [[NSUserDefaults standardUserDefaults] integerForKey:item.key];
      if (methodIndex >= 0 && methodIndex < (NSInteger)item.options.count) {
        [self.popupControl selectItemAtIndex:methodIndex];
      } else {
        [self.popupControl selectItemAtIndex:0]; // Default to Password
      }
    } else {
      NSString *val =
          [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
      NSString *stored = val ? val : [item.defaultValue description];
      if (item.optionValues && item.optionValues.count == item.options.count) {
        for (NSInteger i = 0; i < (NSInteger)item.optionValues.count; i++) {
          if ([item.optionValues[i] isEqualToString:stored]) {
            [self.popupControl selectItemAtIndex:i];
            goto popup_sel_done;
          }
        }
      }
      [self.popupControl selectItemWithTitle:stored];
    }
  popup_sel_done:
    self.popupControl.enabled = item.interactive;
    self.popupControl.target = target;
    self.popupControl.action = action;
    active = self.popupControl;
  } else if (item.type == WSettingInfo) {
    // Info type: show read-only text with copy button
    self.textControl.hidden = NO;
    NSString *val =
        [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    self.textControl.stringValue =
        val ? val : ([item.defaultValue description] ?: @"");
    self.textControl.editable = NO;
    self.textControl.selectable = YES;
    self.textControl.bezeled = NO;
    self.textControl.bordered = NO;
    self.textControl.backgroundColor = [NSColor clearColor];
    self.textControl.drawsBackground = NO;
    BOOL isConnectionInfoField =
        [item.key isEqualToString:@"XDGRuntimeDir"] ||
        [item.key isEqualToString:@"WaylandDisplay"] ||
        [item.key isEqualToString:@"WaylandSocketPath"] ||
        [item.key isEqualToString:@"WaylandShellSetup"];
    if (isConnectionInfoField) {
      // Connection rows often contain long path/env snippets; render fully.
      self.descLabel.maximumNumberOfLines = 0;
      self.descLabel.lineBreakMode = NSLineBreakByWordWrapping;
      self.descLabel.cell.wraps = YES;
      self.descLabel.cell.truncatesLastVisibleLine = NO;

      self.textControl.maximumNumberOfLines = 0;
      self.textControl.cell.wraps = YES;
      self.textControl.cell.usesSingleLineMode = NO;
      self.textControl.cell.truncatesLastVisibleLine = NO;
      self.textControl.lineBreakMode = NSLineBreakByWordWrapping;
    } else if ([item.key isEqualToString:@"WaylandSocketDir"] ||
               [item.key containsString:@"Dir"] ||
               [item.key containsString:@"Path"]) {
      // Finder-style truncation for non-Connection path info rows.
      self.textControl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    } else {
      self.textControl.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    active = self.textControl;
  } else if (item.type == WSettingLink) {
    // Show a small icon and description for the link
    self.titleLabel.textColor = [NSColor linkColor];
    self.buttonControl.hidden = NO;
    self.buttonControl.title = item.desc ?: @"Open";
    self.buttonControl.target = target;
    self.buttonControl.action = action;
    active = self.buttonControl;
  } else if (item.type == WSettingHeader) {
    // Header type: icon on the left, title + subtitle to the right
    self.titleLabel.font = [NSFont boldSystemFontOfSize:16];
    self.titleLabel.alignment = NSTextAlignmentLeft;
    self.descLabel.stringValue = item.desc ?: @"";
    self.descLabel.textColor = [NSColor secondaryLabelColor];

    if (item.imageURL || item.imageName) {
      self.headerImageView.hidden = NO;

      // Prefer the dark variant for the Settings > About header image.
      NSImage *icon = [NSImage imageNamed:@"Wawona-iOS-Dark-1024x1024@1x.png"];
      if (!icon) {
        NSString *darkPath = [[NSBundle mainBundle]
            pathForResource:@"Wawona-iOS-Dark-1024x1024@1x"
                     ofType:@"png"];
        if (darkPath) {
          icon = [[NSImage alloc] initWithContentsOfFile:darkPath];
        }
      }
      if (!icon) {
        icon = [NSImage imageNamed:@"Wawona"];
      }
      if (!icon) {
        NSString *pngPath =
            [[NSBundle mainBundle] pathForResource:@"Wawona" ofType:@"png"];
        if (pngPath) {
          icon = [[NSImage alloc] initWithContentsOfFile:pngPath];
        }
      }
      if (!icon) {
        NSString *lightPath = [[NSBundle mainBundle]
            pathForResource:@"Wawona-iOS-Light-1024x1024@1x"
                     ofType:@"png"];
        if (lightPath) {
          icon = [[NSImage alloc] initWithContentsOfFile:lightPath];
        }
      }

      if (icon) {
        self.headerImageView.image = icon;
      } else {
        // Last resort: remote URL
        NSString *img = item.imageURL ?: item.imageName;
        [[WWNImageLoader sharedLoader]
            loadImageFromURL:img
                  completion:^(WImage _Nullable image) {
                    if (image) {
                      self.headerImageView.image = image;
                    }
                  }];
      }

      // Inset text labels to the right of the 48px image + padding
      self.leadingConstraint.constant = 80;
      active = nil; // Headers never have a right-side control
    }

    // Final layout refinement:
    // If we have an active control (switch, text, button, etc.), we need to
    // leave space for it on the right. Otherwise, use full width.
    if (active) {
      self.trailingConstraint.constant =
          -(160 + 16 + 20); // Control + Spacing + Margin
    } else {
      self.trailingConstraint.constant = -20; // Full width
    }
  }
}

- (void)controlTextDidChange:(NSNotification *)obj {
  NSTextField *tf = [obj object];
  if (tf == self.textControl) {
    // Forward to act: with tag
    SEL actSel = NSSelectorFromString(@"act:");
    if ([self.delegate respondsToSelector:actSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      [self.delegate performSelector:actSel withObject:tf];
#pragma clang diagnostic pop
    }
  }
}
@end

@interface WWNSeparatorRowView : NSTableRowView
@end
@implementation WWNSeparatorRowView
- (void)drawSeparatorInRect:(NSRect)dirtyRect {
  // Draw custom iOS-style separator
  NSRect sRect =
      NSMakeRect(20, 0, self.bounds.size.width - 20, 1.0); // Inset left
  [[NSColor separatorColor] setFill];
  NSRectFill(sRect);
}
@end

/* Private interface for WWNPreferencesContent — macOS only (see #if !TARGET_OS_IPHONE guard). */
@interface WWNPreferencesContent ()
#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
- (void)handleLocalShellICloudSyncToggle:(BOOL)enabled;
#endif
@end

@implementation WWNPreferencesContent
- (void)loadView {
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
  self.view = v;
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:v.bounds];
  sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  sv.drawsBackground = NO; // Fix Unified Background
  self.scrollView = sv;

  self.tableView = [[NSTableView alloc] initWithFrame:sv.bounds];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.headerView = nil;
  self.tableView.backgroundColor =
      [NSColor clearColor];                           // Fix Unified Background
  self.tableView.gridStyleMask = NSTableViewGridNone; // Custom separators
  self.tableView.intercellSpacing =
      NSMakeSize(0, 0); // Tight packing for custom rows
  self.tableView.columnAutoresizingStyle =
      NSTableViewUniformColumnAutoresizingStyle;

  NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"C"];
  c.width = sv.bounds.size.width;                 // Match scroll view width
  c.minWidth = 300;                               // Minimum column width
  c.resizingMask = NSTableColumnAutoresizingMask; // Auto-resize with window
  [self.tableView addTableColumn:c];
  sv.documentView = self.tableView;
  sv.hasHorizontalScroller = NO; // No horizontal scroll - content should fit
  [v addSubview:sv];
}

- (void)reloadForCurrentSection {
  BOOL isEnvironment =
      [self.section.title isEqualToString:@"Environment Variables"];
  if (isEnvironment) {
    [self embedEnvironmentVariablesIfNeeded];
    self.scrollView.hidden = YES;
    self.environmentHostView.hidden = NO;
    return;
  }
  if (self.environmentHostView) {
    self.environmentHostView.hidden = YES;
  }
  self.scrollView.hidden = NO;
  [self.tableView reloadData];
}

- (void)embedEnvironmentVariablesIfNeeded {
  if (self.environmentHostView) {
    self.environmentHostView.hidden = NO;
    return;
  }
  Class presenter = NSClassFromString(@"WWNEnvironmentSettingsPresenter");
  if (!presenter || ![presenter respondsToSelector:@selector(macOSHostingView)]) {
    self.scrollView.hidden = NO;
    [self.tableView reloadData];
    return;
  }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  NSView *host = [presenter performSelector:@selector(macOSHostingView)];
#pragma clang diagnostic pop
  if (![host isKindOfClass:[NSView class]]) {
    self.scrollView.hidden = NO;
    [self.tableView reloadData];
    return;
  }
  host.frame = self.view.bounds;
  host.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self.view addSubview:host];
  self.environmentHostView = host;
  self.scrollView.hidden = YES;
}

// Use custom row view for separators
- (NSTableRowView *)tableView:(NSTableView *)tableView
                rowViewForRow:(NSInteger)row {
  WWNSeparatorRowView *rv =
      [tableView makeViewWithIdentifier:@"Row" owner:self];
  if (!rv) {
    rv = [[WWNSeparatorRowView alloc] initWithFrame:NSZeroRect];
    rv.identifier = @"Row";
  }
  return rv;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
  return self.section.items.count;
}

- (NSView *)tableView:(NSTableView *)tv
    viewForTableColumn:(NSTableColumn *)tc
                   row:(NSInteger)row {
  WWNPreferenceCell *cell = [tv makeViewWithIdentifier:@"PCell" owner:self];
  if (!cell) {
    cell = [[WWNPreferenceCell alloc] initWithFrame:NSMakeRect(0, 0, 400, 50)];
  }
  WWNSettingItem *item = self.section.items[row];
  [cell configureWithItem:item target:self action:@selector(act:)];

  // Ensure tags are set correctly for 'act:' lookup if needed (though we rely
  // on sender usually)
  if (!cell.switchControl.hidden)
    cell.switchControl.tag = row;
  if (!cell.textControl.hidden)
    cell.textControl.tag = row;
  if (!cell.buttonControl.hidden)
    cell.buttonControl.tag = row;
  if (!cell.popupControl.hidden)
    cell.popupControl.tag = row;

  return cell;
}

- (void)act:(id)sender {
  NSInteger row = (NSInteger)[sender tag];
  if (row < 0 || row >= (NSInteger)self.section.items.count) {
    return;
  }

  WWNSettingItem *item = self.section.items[row];

  // Handle password fields - show a dialog for password entry
  if (item.type == WSettingPassword) {
    [self showPasswordDialogForItem:item row:row];
    return;
  }

  if (item.type == WSettingButton) {
    if (item.actionBlock) {
      item.actionBlock();
    }
    return;
  }

  if (item.type == WSettingInfo) {
    // For Info type, copy to clipboard on click
    NSString *val =
        [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
    NSString *valueString = val ? val : [item.defaultValue description];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:valueString forType:NSPasteboardTypeString];
    return;
  }

  if (item.type == WSettingLink) {
    // For Link type, open URL in browser
    if (item.urlString) {
      NSURL *url = [NSURL URLWithString:item.urlString];
      if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
      }
    }
    return;
  }

  if (item.type == WSettingHeader) {
    // Header is not clickable
    return;
  }

  id val = nil;
  if ([sender isKindOfClass:[NSSwitch class]]) {
    if (!item.interactive) {
      return;
    }
    val = @([(NSSwitch *)sender state] == NSControlStateValueOn);
#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
    if ([item.key isEqualToString:WWNRootfsICloudSyncPreferenceKey]) {
      [self handleLocalShellICloudSyncToggle:[(NSNumber *)val boolValue]];
      return;
    }
#endif
  } else if ([sender isKindOfClass:[NSTextField class]]) {
    val = [(NSTextField *)sender stringValue];
    // For text fields, save immediately when value changes
    if (val && item.key) {
      [[NSUserDefaults standardUserDefaults] setObject:val forKey:item.key];
    }
    return; // Return early for text fields - they save on each change
  } else if ([sender isKindOfClass:[NSPopUpButton class]]) {
    if (!item.interactive) {
      return;
    }
    // Handle SSHAuthMethod specially - store as integer index
    if ([item.key isEqualToString:@"SSHAuthMethod"] ||
        [item.key isEqualToString:@"WaypipeSSHAuthMethod"]) {
      NSInteger selectedIndex = [(NSPopUpButton *)sender indexOfSelectedItem];
      [[NSUserDefaults standardUserDefaults] setInteger:selectedIndex
                                                 forKey:item.key];

      // Auth method changed - rebuild sections to show appropriate nested
      // options
      WWNPreferences *prefs = [WWNPreferences sharedPreferences];
      prefs.sections = [prefs buildSections];
      [self.tableView reloadData];

      [[NSNotificationCenter defaultCenter]
          postNotificationName:@"WWNPreferencesChanged"
                        object:nil];
      return;
    }
    NSInteger idx = [(NSPopUpButton *)sender indexOfSelectedItem];
    if (item.optionValues && idx >= 0 &&
        idx < (NSInteger)item.optionValues.count) {
      val = item.optionValues[idx];
    } else {
      val = [(NSPopUpButton *)sender titleOfSelectedItem];
    }
  }

  if (val && item.key) {
    [[NSUserDefaults standardUserDefaults] setObject:val forKey:item.key];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"WWNPreferencesChanged"
                      object:nil];
    if ([item.key isEqualToString:kWWNPrefsRenderMacOSPointer]) {
      WWNPreferences *prefs = [WWNPreferences sharedPreferences];
      prefs.sections = [prefs buildSections];
      [self.tableView reloadData];
    }
  }
}

- (void)showPasswordDialogForItem:(WWNSettingItem *)item row:(NSInteger)row {
  // Single modal for password entry - always show entry field
  // Saving a new password automatically overwrites any existing one
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = item.title;
  alert.informativeText = item.desc ?: @"Enter password:";
  [alert addButtonWithTitle:@"Save"];
  [alert addButtonWithTitle:@"Cancel"];

  // Create container view with password field and toggle button
  NSView *containerView =
      [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];

  // Create secure text field (hidden by default)
  NSSecureTextField *secureField =
      [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
  secureField.placeholderString = @"Enter a Password...";
  secureField.stringValue = @"";
  [containerView addSubview:secureField];

  // Create plain text field (for showing password)
  NSTextField *plainField =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
  plainField.placeholderString = @"Enter a Password...";
  plainField.stringValue = @"";
  plainField.hidden = YES;
  [containerView addSubview:plainField];

  // Create eyeball toggle button
  NSButton *toggleButton =
      [[NSButton alloc] initWithFrame:NSMakeRect(255, 2, 20, 20)];
  toggleButton.bezelStyle = NSBezelStyleInline;
  toggleButton.bordered = NO;
  toggleButton.image = [NSImage imageWithSystemSymbolName:@"eye"
                                 accessibilityDescription:@"Show password"];

  // Store references for toggle action
  objc_setAssociatedObject(toggleButton, "secureField", secureField,
                           OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(toggleButton, "plainField", plainField,
                           OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(toggleButton, "isSecure", @YES,
                           OBJC_ASSOCIATION_RETAIN);

  toggleButton.target = self;
  toggleButton.action = @selector(toggleMacOSPasswordVisibility:);

  [containerView addSubview:toggleButton];

  alert.accessoryView = containerView;

  // Make the secure field first responder when alert appears
  [alert.window makeFirstResponder:secureField];

  NSModalResponse response = [alert runModal];

  if (response == NSAlertFirstButtonReturn) {
    // Save button clicked - get password from whichever field is visible
    NSNumber *isSecureNum = objc_getAssociatedObject(toggleButton, "isSecure");
    NSString *enteredPassword = isSecureNum.boolValue ? secureField.stringValue
                                                      : plainField.stringValue;

    // Save password (overwrites existing if any)
    if ([item.key isEqualToString:@"WaypipeSSHPassword"]) {
      prefs.waypipeSSHPassword = enteredPassword;
    } else if ([item.key isEqualToString:@"WaypipeSSHKeyPassphrase"]) {
      prefs.waypipeSSHKeyPassphrase = enteredPassword;
    } else if ([item.key isEqualToString:@"SSHPassword"]) {
      prefs.sshPassword = enteredPassword;
    } else if ([item.key isEqualToString:@"SSHKeyPassphrase"]) {
      prefs.sshKeyPassphrase = enteredPassword;
    }

    // Update the button text to reflect new state
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                              columnIndexes:[NSIndexSet indexSetWithIndex:0]];
  }
  // Cancel = do nothing
}

- (void)toggleMacOSPasswordVisibility:(NSButton *)sender {
  NSSecureTextField *secureField =
      objc_getAssociatedObject(sender, "secureField");
  NSTextField *plainField = objc_getAssociatedObject(sender, "plainField");
  NSNumber *isSecureNum = objc_getAssociatedObject(sender, "isSecure");
  BOOL isSecure = isSecureNum ? isSecureNum.boolValue : YES;

  if (isSecure) {
    // Switch to plain text (show password)
    plainField.stringValue = secureField.stringValue;
    secureField.hidden = YES;
    plainField.hidden = NO;
    [plainField.window makeFirstResponder:plainField];
    sender.image = [NSImage imageWithSystemSymbolName:@"eye.slash"
                             accessibilityDescription:@"Hide password"];
    objc_setAssociatedObject(sender, "isSecure", @NO, OBJC_ASSOCIATION_RETAIN);
  } else {
    // Switch to secure (hide password)
    secureField.stringValue = plainField.stringValue;
    plainField.hidden = YES;
    secureField.hidden = NO;
    [secureField.window makeFirstResponder:secureField];
    sender.image = [NSImage imageWithSystemSymbolName:@"eye"
                             accessibilityDescription:@"Show password"];
    objc_setAssociatedObject(sender, "isSecure", @YES, OBJC_ASSOCIATION_RETAIN);
  }
}

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row {
  if (row < (NSInteger)self.section.items.count) {
    WWNSettingItem *item = self.section.items[row];
    if (item.type == WSettingHeader) {
      return 68.0; // Taller row for header with icon
    }
    BOOL isConnectionSection = [self.section.title isEqualToString:@"Connection"];
    BOOL isConnectionInfoRow =
        isConnectionSection && item.type == WSettingInfo &&
        ([item.key isEqualToString:@"XDGRuntimeDir"] ||
         [item.key isEqualToString:@"WaylandDisplay"] ||
         [item.key isEqualToString:@"WaylandSocketPath"] ||
         [item.key isEqualToString:@"WaylandShellSetup"]);
    if (isConnectionInfoRow) {
      NSString *val =
          [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
      if (!val) {
        val = [item.defaultValue description] ?: @"";
      }
      NSUInteger valueLines =
          1 + MIN((NSUInteger)3, (NSUInteger)(val.length / 46));
      if ([val containsString:@"\n"]) {
        valueLines += 1;
      }
      NSUInteger descLines =
          item.desc.length > 0
              ? (1 + MIN((NSUInteger)2, (NSUInteger)(item.desc.length / 70)))
              : 0;
      CGFloat dynamicHeight =
          18.0 + (CGFloat)descLines * 14.0 + (CGFloat)valueLines * 15.0;
      return MAX(62.0, MIN(132.0, dynamicHeight));
    }
  }
  return 50.0;
}

#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
- (void)handleLocalShellICloudSyncToggle:(BOOL)enabled {
  NSError *error = nil;
  if (![WWNRootfsProvider setICloudSyncEnabled:enabled error:&error]) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"iCloud Sync Failed";
    alert.informativeText = error.localizedDescription ?: @"Unknown error.";
    [alert runModal];
  }
  [self.tableView reloadData];
}
#endif

@end

#endif
