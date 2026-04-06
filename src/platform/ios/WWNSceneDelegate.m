#import "WWNSceneDelegate.h"
#import "../macos/ui/Settings/WWNPreferencesManager.h"
#import "../macos/ui/Settings/WWNSettingsSplitViewController.h"
#import "WWNCompositorBridge.h"
#import <objc/message.h>
#import "../../util/WWNLog.h"

@interface WWNSceneDelegate ()
@property(nonatomic, strong) UIButton *settingsButton;
/// Constraints that pin compositorContainer to the safe area.
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *safeAreaConstraints;
/// Constraints that pin compositorContainer edge-to-edge (full screen).
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *fullScreenConstraints;
/// Last reported output size — used to skip redundant updates.
@property(nonatomic, assign) CGSize lastOutputSize;
/// Last applied Respect Safe Area value — used to skip redundant logs.
@property(nonatomic, assign) BOOL lastRespectSafeArea;
@property(nonatomic, assign) BOOL hasAppliedSafeArea;
@end

@implementation WWNSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
  if (![scene isKindOfClass:[UIWindowScene class]])
    return;

  UIWindowScene *windowScene = (UIWindowScene *)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  self.window.backgroundColor = [UIColor blackColor];

  // Root view controller — fills the full screen
  UIViewController *rootViewController = [[UIViewController alloc] init];
  rootViewController.view =
      [[UIView alloc] initWithFrame:self.window.bounds];
  rootViewController.view.backgroundColor = [UIColor blackColor];
  self.window.rootViewController = rootViewController;

  // Compositor container — an intermediate view whose bounds
  // determine the Wayland output size.  It is either pinned to the
  // safe area layout guide ("Respect Safe Area" ON) or to the full
  // screen edges (OFF).
  UIView *root = rootViewController.view;
  self.compositorContainer = [[UIView alloc] init];
  self.compositorContainer.translatesAutoresizingMaskIntoConstraints = NO;
  self.compositorContainer.backgroundColor = [UIColor blackColor];
  self.compositorContainer.clipsToBounds = YES;
  [root addSubview:self.compositorContainer];

  // Prepare both sets of constraints (only one active at a time)
  self.safeAreaConstraints = @[
    [self.compositorContainer.topAnchor
        constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor],
    [self.compositorContainer.bottomAnchor
        constraintEqualToAnchor:root.safeAreaLayoutGuide.bottomAnchor],
    [self.compositorContainer.leadingAnchor
        constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor],
    [self.compositorContainer.trailingAnchor
        constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor],
  ];
  self.fullScreenConstraints = @[
    [self.compositorContainer.topAnchor
        constraintEqualToAnchor:root.topAnchor],
    [self.compositorContainer.bottomAnchor
        constraintEqualToAnchor:root.bottomAnchor],
    [self.compositorContainer.leadingAnchor
        constraintEqualToAnchor:root.leadingAnchor],
    [self.compositorContainer.trailingAnchor
        constraintEqualToAnchor:root.trailingAnchor],
  ];

  // Connect compositor to our container
  WWNCompositorBridge *compositor = [WWNCompositorBridge sharedBridge];
  compositor.containerView = self.compositorContainer;

  // Activate the correct constraint set based on the preference
  [self applyRespectSafeAreaPreference];

  [self.window makeKeyAndVisible];

  // Force layout so the compositor container gets its real frame
  [root layoutIfNeeded];

  // Update compositor output to match the container's resolved size
  [self updateOutputSizeFromContainer];

  // Settings button — always anchored to the safe area
  [self setupSettingsButton];

  // Observe preference changes so the user can toggle at runtime
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(preferencesDidChange:)
             name:NSUserDefaultsDidChangeNotification
           object:nil];

  WWNLog("SCENE", @"Wawona Scene connected and window created.");
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Safe Area

- (void)applyRespectSafeAreaPreference {
  BOOL respectSafeArea =
      [[WWNPreferencesManager sharedManager] respectSafeArea];

  if (self.hasAppliedSafeArea && self.lastRespectSafeArea == respectSafeArea)
    return;

  self.lastRespectSafeArea = respectSafeArea;
  self.hasAppliedSafeArea = YES;
  WWNLog("SCENE", @"Respect Safe Area = %@", respectSafeArea ? @"YES" : @"NO");

  // Deactivate the old set, activate the new one
  if (respectSafeArea) {
    [NSLayoutConstraint deactivateConstraints:self.fullScreenConstraints];
    [NSLayoutConstraint activateConstraints:self.safeAreaConstraints];
  } else {
    [NSLayoutConstraint deactivateConstraints:self.safeAreaConstraints];
    [NSLayoutConstraint activateConstraints:self.fullScreenConstraints];
  }

  // Animate the transition
  UIView *root = self.window.rootViewController.view;
  [UIView animateWithDuration:0.25
      animations:^{
        [root layoutIfNeeded];
      }
      completion:^(BOOL finished) {
        [self updateOutputSizeFromContainer];

        // Also resize all existing window subviews to fill the new container
        for (UIView *child in self.compositorContainer.subviews) {
          child.frame = self.compositorContainer.bounds;
        }
      }];
}

- (void)preferencesDidChange:(NSNotification *)note {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self applyRespectSafeAreaPreference];
    [self updateOutputSizeFromContainerForced:YES];
  });
}

#pragma mark - Output Size

- (void)updateOutputSizeFromContainer {
  [self updateOutputSizeFromContainerForced:NO];
}

- (void)updateOutputSizeFromContainerForced:(BOOL)forced {
  CGRect bounds = self.compositorContainer.bounds;
  if (bounds.size.width <= 0 || bounds.size.height <= 0)
    return;

  CGSize sz = bounds.size;
  if (!forced && CGSizeEqualToSize(sz, self.lastOutputSize))
    return;
  self.lastOutputSize = sz;

  UIWindowScene *ws = self.window.windowScene;
  CGFloat screenScale = ws.screen.scale;
  BOOL autoScale = [[WWNPreferencesManager sharedManager] autoScale];
  float wlScale = autoScale ? (float)screenScale : 1.0f;

  WWNCompositorBridge *compositor = [WWNCompositorBridge sharedBridge];
  [compositor setOutputWidth:(uint32_t)sz.width
                      height:(uint32_t)sz.height
                       scale:wlScale];

  WWNLog("SCENE", @"Output size: %.0fx%.0f @ %.1fx (auto-scale %@)",
        sz.width, sz.height, wlScale, autoScale ? @"ON" : @"OFF");
}

#pragma mark - Settings Button

- (void)setupSettingsButton {
  UIView *root = self.window.rootViewController.view;
  UIImage *gearImage = [UIImage systemImageNamed:@"gear"];

  self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.settingsButton.clipsToBounds = NO;

  UIButtonConfiguration *buttonConfig = nil;
  SEL glassSelector = NSSelectorFromString(@"glassButtonConfiguration");
  if ([UIButtonConfiguration respondsToSelector:glassSelector]) {
    buttonConfig = ((id(*)(id, SEL))objc_msgSend)([UIButtonConfiguration class],
                                                   glassSelector);
  }
  if (!buttonConfig) {
    buttonConfig = [UIButtonConfiguration borderedButtonConfiguration];
  }

  buttonConfig.image = gearImage;
  self.settingsButton.configuration = buttonConfig;

  // Add the button to the root view (not the compositor container)
  // so it's always visible above Wayland surfaces.
  [root addSubview:self.settingsButton];

  [self.settingsButton addTarget:self
                          action:@selector(openSettings:)
                forControlEvents:UIControlEventTouchUpInside];

  // Always anchor to the safe area regardless of the toggle
  [NSLayoutConstraint activateConstraints:@[
    [self.settingsButton.topAnchor
        constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor
                       constant:20],
    [self.settingsButton.trailingAnchor
        constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor
                       constant:-20],
    [self.settingsButton.widthAnchor constraintEqualToConstant:44],
    [self.settingsButton.heightAnchor constraintEqualToConstant:44],
  ]];
  [root bringSubviewToFront:self.settingsButton];
}

- (void)openSettings:(id)sender {
  UIViewController *presenter = self.window.rootViewController;
  if (presenter.presentedViewController != nil) {
    presenter = presenter.presentedViewController;
  }

  WWNSettingsSplitViewController *settingsController =
      [[WWNSettingsSplitViewController alloc] init];
  settingsController.modalPresentationStyle = UIModalPresentationAutomatic;
  settingsController.modalInPresentation = NO;
  if (@available(iOS 15.0, *)) {
    UISheetPresentationController *sheet =
        settingsController.sheetPresentationController;
    sheet.prefersGrabberVisible = YES;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
  }
  [presenter presentViewController:settingsController
                          animated:YES
                        completion:nil];
}

#pragma mark - UIWindowSceneDelegate

// Called when the scene's coordinate space, interface orientation, or trait
// collection changes — this is the primary rotation notification in the
// UIScene lifecycle.  We must update the Wayland compositor output size so
// that wl_output.mode events are sent and xdg_toplevel windows reconfigure.
//
// Deprecated in iOS 26 — migrate to registerForTraitChanges: when the
// minimum deployment target is raised to iOS 17+.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)windowScene:(UIWindowScene *)windowScene
    didUpdateCoordinateSpace:
        (id<UICoordinateSpace>)previousCoordinateSpace
        interfaceOrientation:
            (UIInterfaceOrientation)previousInterfaceOrientation
        traitCollection:(UITraitCollection *)previousTraitCollection {
#pragma clang diagnostic pop

  WWNLog("SCENE", @"Coordinate space changed (was %.0fx%.0f)",
        previousCoordinateSpace.bounds.size.width,
        previousCoordinateSpace.bounds.size.height);

  // Force a layout pass so compositorContainer gets the new bounds
  [self.window.rootViewController.view layoutIfNeeded];

  // Resize all window views to fill the new container bounds
  CGRect containerBounds = self.compositorContainer.bounds;
  for (UIView *child in self.compositorContainer.subviews) {
    child.frame = containerBounds;
  }

  // Update the Wayland output.  The bridge coalesces rapid resize events
  // so at most one block is on the compositor queue; _compositorTick
  // flushes the Wayland socket every frame.
  [self updateOutputSizeFromContainer];
}

#pragma mark - Scene Lifecycle

- (void)sceneDidDisconnect:(UIScene *)scene {
  WWNLog("SCENE", @"Scene disconnected");
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
  WWNLog("SCENE", @"Scene became active");
}

- (void)sceneWillResignActive:(UIScene *)scene {
  WWNLog("SCENE", @"Scene will resign active");
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
  WWNLog("SCENE", @"Scene will enter foreground");
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
  WWNLog("SCENE", @"Scene did enter background");
}

@end
