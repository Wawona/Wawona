#import "WWNSceneDelegate.h"
#import "../macos/ui/Settings/WWNPreferencesManager.h"
#import "../macos/ui/Settings/WWNPreferences.h"
#import "../macos/ui/Settings/WWNWaypipeRunner.h"
#import "../macos/ui/Machines/WWNMachinesCoordinator.h"
#import "WWNCompositorBridge.h"
#import <math.h>
#import <TargetConditionals.h>
#import "../../util/WWNLog.h"

@interface WWNWelcomeViewController : UIViewController
@property(nonatomic, copy) dispatch_block_t onContinue;
@property(nonatomic, weak) UIButton *continueButton;
@end

@interface WWNCompositorHostViewController : UIViewController
@property(nonatomic, assign) BOOL defersSystemGesturesForCompositor;
@end

@interface WWNShakeAwareWindow : UIWindow
@property(nonatomic, copy) dispatch_block_t onShake;
@end

@implementation WWNShakeAwareWindow

- (BOOL)canBecomeFirstResponder {
  return YES;
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
  [super motionEnded:motion withEvent:event];
  if (motion == UIEventSubtypeMotionShake && self.onShake) {
    self.onShake();
  }
}

@end

@implementation WWNCompositorHostViewController

#if !TARGET_OS_TV
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
  return self.defersSystemGesturesForCompositor ? UIRectEdgeBottom : UIRectEdgeNone;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
  return self.defersSystemGesturesForCompositor;
}

// Deprecated on recent SDKs; still the supported way to drive status bar from this VC.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (BOOL)prefersStatusBarHidden {
  return self.defersSystemGesturesForCompositor;
}
#pragma clang diagnostic pop

/// While the Wayland session is immersive, use this controller’s deferral/hiding
/// preferences. UIKit otherwise may walk children/presented VCs and ignore the host.
- (UIViewController *)childViewControllerForScreenEdgesDeferringSystemGestures {
  if (self.defersSystemGesturesForCompositor) {
    return nil;
  }
  return [super childViewControllerForScreenEdgesDeferringSystemGestures];
}
#endif

#if !TARGET_OS_TV
- (UIViewController *)childViewControllerForHomeIndicatorAutoHidden {
  if (self.defersSystemGesturesForCompositor) {
    return nil;
  }
  return [super childViewControllerForHomeIndicatorAutoHidden];
}
#endif

#if !TARGET_OS_VISION && !TARGET_OS_TV
- (UIViewController *)childViewControllerForStatusBarHidden {
  if (self.defersSystemGesturesForCompositor) {
    return nil;
  }
  return [super childViewControllerForStatusBarHidden];
}
#endif

@end

@implementation WWNWelcomeViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];

  UIView *card = [[UIView alloc] init];
  card.translatesAutoresizingMaskIntoConstraints = NO;
#if TARGET_OS_TV
  card.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
#else
  card.backgroundColor = [UIColor secondarySystemBackgroundColor];
#endif
  card.layer.cornerRadius = 16.0;
  card.layer.masksToBounds = YES;
  [self.view addSubview:card];

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = @"Welcome to Wawona";
  titleLabel.textAlignment = NSTextAlignmentCenter;
  titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
  titleLabel.numberOfLines = 0;

  UILabel *bodyLabel = [[UILabel alloc] init];
  bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  bodyLabel.text =
      @"Minimal Wayland compositing for Apple platforms and Android.";
  bodyLabel.textAlignment = NSTextAlignmentCenter;
  bodyLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
  bodyLabel.numberOfLines = 0;
  bodyLabel.textColor = [UIColor secondaryLabelColor];

  UIButton *continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
  continueButton.translatesAutoresizingMaskIntoConstraints = NO;
  [continueButton setTitle:@"Continue" forState:UIControlStateNormal];
  continueButton.titleLabel.font =
      [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
  UIButtonConfiguration *continueConfig = [UIButtonConfiguration filledButtonConfiguration];
  continueConfig.baseBackgroundColor = [UIColor systemBlueColor];
  continueConfig.baseForegroundColor = [UIColor whiteColor];
  continueConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
  continueConfig.contentInsets = NSDirectionalEdgeInsetsMake(12.0, 20.0, 12.0, 20.0);
  continueButton.configuration = continueConfig;
  [continueButton addTarget:self
                     action:@selector(handleContinueTapped)
           forControlEvents:UIControlEventTouchUpInside];
#if TARGET_OS_TV
  // Siri Remote select triggers primary action on tvOS.
  [continueButton addTarget:self
                     action:@selector(handleContinueTapped)
           forControlEvents:UIControlEventPrimaryActionTriggered];
#endif
  self.continueButton = continueButton;

  UIStackView *stack = [[UIStackView alloc]
      initWithArrangedSubviews:@[ titleLabel, bodyLabel, continueButton ]];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 18.0;
  [card addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor
                                                    constant:24.0],
    [self.view.trailingAnchor constraintGreaterThanOrEqualToAnchor:card.trailingAnchor
                                                           constant:24.0],
    [card.widthAnchor constraintEqualToConstant:340.0],

    [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:28.0],
    [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22.0],
    [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22.0],
    [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22.0],
  ]];

  [continueButton.heightAnchor constraintEqualToConstant:48.0].active = YES;

#if TARGET_OS_TV
  // Ensure the primary CTA is focused when the welcome screen appears.
  [self setNeedsFocusUpdate];
  [self updateFocusIfNeeded];
#endif
}

- (void)handleContinueTapped {
  WWNLog("SCENE", @"Welcome continue tapped");
  if (self.onContinue) {
    self.onContinue();
  }
}

#if TARGET_OS_TV
- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
  if (self.continueButton != nil) {
    return @[ self.continueButton ];
  }
  return [super preferredFocusEnvironments];
}
#endif

@end

@interface WWNSceneDelegate ()
/// Constraints that pin compositorContainer to the safe area.
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *safeAreaConstraints;
/// Constraints that pin compositorContainer edge-to-edge (full screen).
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *fullScreenConstraints;
/// Last reported output size — used to skip redundant updates.
@property(nonatomic, assign) CGSize lastOutputSize;
/// Last reported output scale — used with size to skip redundant updates.
@property(nonatomic, assign) float lastOutputScale;
/// Last applied Respect Safe Area value — used to skip redundant logs.
@property(nonatomic, assign) BOOL lastRespectSafeArea;
@property(nonatomic, assign) BOOL hasAppliedSafeArea;
@property(nonatomic, assign) BOOL showingMachinesUI;
@property(nonatomic, assign) CFTimeInterval lastShakePromptTime;
@property(nonatomic, assign) BOOL shakePromptVisible;
#if !TARGET_OS_VISION && !TARGET_OS_TV
@property(nonatomic, strong) UIScreenEdgePanGestureRecognizer *backSwipeGesture;
#endif
@end

@implementation WWNSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
  if (![scene isKindOfClass:[UIWindowScene class]])
    return;

  UIWindowScene *windowScene = (UIWindowScene *)scene;
  WWNShakeAwareWindow *shakeWindow =
      [[WWNShakeAwareWindow alloc] initWithWindowScene:windowScene];
  __weak typeof(self) weakSelf = self;
  shakeWindow.onShake = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf handleShakeGesture];
  };
  self.window = shakeWindow;
  self.window.backgroundColor = [UIColor blackColor];

  // Root view controller — fills the full screen
  WWNCompositorHostViewController *rootViewController =
      [[WWNCompositorHostViewController alloc] init];
  rootViewController.defersSystemGesturesForCompositor = NO;
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
  [self.window becomeFirstResponder];

  // Force layout so the compositor container gets its real frame
  [root layoutIfNeeded];

  // Update compositor output to match the container's resolved size
  [self updateOutputSizeFromContainer];

#if !TARGET_OS_VISION && !TARGET_OS_TV
  [self setupBackSwipeGesture];
#endif
  self.compositorContainer.hidden = YES;

  // Observe preference changes so the user can toggle at runtime
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(preferencesDidChange:)
             name:NSUserDefaultsDidChangeNotification
           object:nil];

  WWNLog("SCENE", @"Wawona Scene connected and window created.");

  [self presentWelcomeIfNeeded];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Safe Area

- (void)applyRespectSafeAreaPreference {
#if !TARGET_OS_VISION
  // Active Wayland compositor view: always edge-to-edge (true “fullscreen” output)
  // so the client can use the full display and home-indicator deferral matches
  // immersive apps (e.g. games). Respect Safe Area applies only when the
  // compositor container is hidden (machines / welcome).
  if (!self.compositorContainer.hidden) {
    if (self.fullScreenConstraints.firstObject.isActive) {
      return;
    }
    WWNLog("SCENE", @"Compositor session: forcing edge-to-edge layout (immersive)");
    [NSLayoutConstraint deactivateConstraints:self.safeAreaConstraints];
    [NSLayoutConstraint activateConstraints:self.fullScreenConstraints];
    UIView *root = self.window.rootViewController.view;
    [root setNeedsLayout];
    [root layoutIfNeeded];
    [self updateOutputSizeFromContainerForced:YES];
    for (UIView *child in self.compositorContainer.subviews) {
      child.frame = self.compositorContainer.bounds;
    }
    return;
  }
#endif

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

  CGFloat screenScale = self.window.traitCollection.displayScale;
  if (screenScale <= 0.0) {
    screenScale = 1.0;
  }
  BOOL autoScale = [[WWNPreferencesManager sharedManager] autoScale];
  float wlScale = autoScale ? (float)screenScale : 1.0f;

  if (!forced && CGSizeEqualToSize(sz, self.lastOutputSize) &&
      fabsf(self.lastOutputScale - wlScale) < 0.001f) {
    return;
  }
  self.lastOutputSize = sz;
  self.lastOutputScale = wlScale;

  WWNCompositorBridge *compositor = [WWNCompositorBridge sharedBridge];
  [compositor setOutputWidth:(uint32_t)sz.width
                      height:(uint32_t)sz.height
                       scale:wlScale];

  WWNLog("SCENE", @"Output size: %.0fx%.0f @ %.1fx (auto-scale %@)",
        sz.width, sz.height, wlScale, autoScale ? @"ON" : @"OFF");
}

#pragma mark - Session Exit Gestures

- (void)setCompositorGestureDeferralEnabled:(BOOL)enabled {
  if (![self.window.rootViewController
          isKindOfClass:[WWNCompositorHostViewController class]]) {
    return;
  }
  WWNCompositorHostViewController *host =
      (WWNCompositorHostViewController *)self.window.rootViewController;
  if (host.defersSystemGesturesForCompositor == enabled) {
    return;
  }
  host.defersSystemGesturesForCompositor = enabled;
#if !TARGET_OS_TV
  [host setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
  [host setNeedsUpdateOfHomeIndicatorAutoHidden];
#endif
#if !TARGET_OS_VISION && !TARGET_OS_TV
  [host setNeedsStatusBarAppearanceUpdate];
#endif
}

#if !TARGET_OS_VISION && !TARGET_OS_TV
- (void)setupBackSwipeGesture {
  UIView *root = self.window.rootViewController.view;
  UIScreenEdgePanGestureRecognizer *gesture =
      [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self
                                                        action:@selector(handleBackSwipeGesture:)];
  gesture.edges = UIRectEdgeLeft;
  [root addGestureRecognizer:gesture];
  self.backSwipeGesture = gesture;
}

- (void)handleBackSwipeGesture:(UIScreenEdgePanGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateEnded) {
    return;
  }
  if ([self isShakeToCloseEnabled]) {
    return;
  }
  if (![self isAnyClientSessionRunning]) {
    return;
  }
  [self closeActiveWaylandSession];
}
#endif

#pragma mark - UIWindowSceneDelegate

// Called when the scene's coordinate space, interface orientation, or trait
// collection changes — this is the primary rotation notification in the
// UIScene lifecycle.  We must update the Wayland compositor output size so
// that wl_output.mode events are sent and xdg_toplevel windows reconfigure.
//
// Deprecated in iOS 26 — migrate to registerForTraitChanges: when the
// minimum deployment target is raised to iOS 17+.
- (void)wwn_handleWindowSceneGeometryChange {
  WWNLog("SCENE", @"Scene geometry changed (container %.0fx%.0f)",
        self.compositorContainer.bounds.size.width,
        self.compositorContainer.bounds.size.height);

  [self.window.rootViewController.view layoutIfNeeded];

  CGRect containerBounds = self.compositorContainer.bounds;
  for (UIView *child in self.compositorContainer.subviews) {
    child.frame = containerBounds;
  }

  [self updateOutputSizeFromContainer];
}

#if TARGET_OS_VISION
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)windowScene:(UIWindowScene *)windowScene
    didUpdateCoordinateSpace:
        (id<UICoordinateSpace>)previousCoordinateSpace
        interfaceOrientation:
            (UIInterfaceOrientation)previousInterfaceOrientation
        traitCollection:(UITraitCollection *)previousTraitCollection {
  (void)windowScene;
  (void)previousCoordinateSpace;
  (void)previousInterfaceOrientation;
  (void)previousTraitCollection;
  [self wwn_handleWindowSceneGeometryChange];
}
#pragma clang diagnostic pop
#elif !TARGET_OS_TV
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)windowScene:(UIWindowScene *)windowScene
    didUpdateCoordinateSpace:
        (id<UICoordinateSpace>)previousCoordinateSpace
        interfaceOrientation:
            (UIInterfaceOrientation)previousInterfaceOrientation
        traitCollection:(UITraitCollection *)previousTraitCollection {
  (void)windowScene;
  (void)previousCoordinateSpace;
  (void)previousInterfaceOrientation;
  (void)previousTraitCollection;
  [self wwn_handleWindowSceneGeometryChange];
}
#pragma clang diagnostic pop
#endif

#if TARGET_OS_TV
- (void)windowScene:(UIWindowScene *)windowScene
    didUpdateEffectiveGeometry:(UIWindowSceneGeometry *)previousEffectiveGeometry
    API_AVAILABLE(tvos(26.0)) {
  (void)windowScene;
  (void)previousEffectiveGeometry;
  [self wwn_handleWindowSceneGeometryChange];
}
#endif

#if TARGET_OS_VISION
- (void)windowScene:(UIWindowScene *)windowScene
    didUpdateEffectiveGeometry:(UIWindowSceneGeometry *)previousEffectiveGeometry
    API_AVAILABLE(visionos(26.0)) {
  (void)windowScene;
  (void)previousEffectiveGeometry;
  [self wwn_handleWindowSceneGeometryChange];
}
#endif

#if !TARGET_OS_TV && !TARGET_OS_VISION
- (void)windowScene:(UIWindowScene *)windowScene
    didUpdateEffectiveGeometry:(UIWindowSceneGeometry *)previousEffectiveGeometry
    API_AVAILABLE(ios(26.0)) {
  (void)windowScene;
  (void)previousEffectiveGeometry;
  [self wwn_handleWindowSceneGeometryChange];
}
#endif

#pragma mark - Scene Lifecycle

- (void)sceneDidDisconnect:(UIScene *)scene {
  WWNLog("SCENE", @"Scene disconnected");
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
  WWNLog("SCENE", @"Scene became active");
  // Only re-show the machines UI if the compositor is visible but nothing is
  // actually rendering into it (neither waypipe nor any native client).
  BOOL compositorVisible = !self.compositorContainer.hidden;
  BOOL somethingRunning = [WWNWaypipeRunner sharedRunner].isRunning
                          || [self isAnyNativeClientRunning];
  if (compositorVisible && !somethingRunning) {
    self.compositorContainer.hidden = YES;
    [self setCompositorGestureDeferralEnabled:NO];
#if !TARGET_OS_VISION
    [self applyRespectSafeAreaPreference];
#endif
    [self presentMachinesConfigurationAfterWelcome];
  }
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

- (void)presentWelcomeIfNeeded {
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  if ([prefs hasSeenWelcome]) {
    [self presentMachinesConfigurationAfterWelcome];
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController *root = self.window.rootViewController;
    if (!root) {
      return;
    }

    WWNWelcomeViewController *welcomeController =
        [[WWNWelcomeViewController alloc] init];
    welcomeController.modalPresentationStyle = UIModalPresentationOverFullScreen;
    welcomeController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

    __weak typeof(self) weakSelf = self;
    __weak typeof(welcomeController) weakWelcomeController = welcomeController;
    welcomeController.onContinue = ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      __strong typeof(weakWelcomeController) strongWelcomeController =
          weakWelcomeController;
      if (!strongSelf) {
        return;
      }

      [[WWNPreferencesManager sharedManager] setHasSeenWelcome:YES];
      if (strongWelcomeController.presentingViewController) {
        [strongWelcomeController
            dismissViewControllerAnimated:YES
                               completion:^{
                                 [strongSelf
                                     presentMachinesConfigurationAfterWelcome];
                               }];
      } else {
        [strongSelf presentMachinesConfigurationAfterWelcome];
      }
    };

    [root presentViewController:welcomeController animated:YES completion:nil];
  });
}

- (BOOL)isAnyNativeClientRunning {
  WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
  return runner.westonRunning
      || runner.westonTerminalRunning
      || runner.isWestonSimpleSHMRunning
      || runner.footRunning;
}

- (BOOL)isAnyClientSessionRunning {
  WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
  return runner.isRunning || [self isAnyNativeClientRunning];
}

- (BOOL)isShakeToCloseEnabled {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *key = @"wawona.pref.shakeToCloseEnabled";
  if ([defaults objectForKey:key] == nil) {
    return YES;
  }
  return [defaults boolForKey:key];
}

- (void)handleShakeGesture {
  if (![self isShakeToCloseEnabled]) {
    return;
  }
  if (self.shakePromptVisible) {
    return;
  }

  CFTimeInterval now = CACurrentMediaTime();
  if (now - self.lastShakePromptTime < 1.5) {
    return;
  }
  self.lastShakePromptTime = now;

  if (![self isAnyClientSessionRunning]) {
    return;
  }

  UIViewController *presenter = self.window.rootViewController;
  if (!presenter) {
    return;
  }
  while (presenter.presentedViewController) {
    presenter = presenter.presentedViewController;
  }

  self.shakePromptVisible = YES;
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Close current Wayland app?"
                       message:@"This will stop the current session and return to Machines."
                preferredStyle:UIAlertControllerStyleAlert];

  __weak typeof(self) weakSelf = self;
  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:^(__unused UIAlertAction *action) {
                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                 if (!strongSelf) {
                                   return;
                                 }
                                 strongSelf.shakePromptVisible = NO;
                               }]];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Close"
                                 style:UIAlertActionStyleDestructive
                               handler:^(__unused UIAlertAction *action) {
                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                 if (!strongSelf) {
                                   return;
                                 }
                                 [strongSelf closeActiveWaylandSession];
                                 strongSelf.shakePromptVisible = NO;
                               }]];

  [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)closeActiveWaylandSession {
  WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
  if (runner.isRunning) {
    [runner stopWaypipe];
  }
  if (runner.westonRunning) {
    [runner stopWeston];
  }
  if (runner.westonTerminalRunning) {
    [runner stopWestonTerminal];
  }
  if (runner.footRunning) {
    [runner stopFoot];
  }
  if (runner.isWestonSimpleSHMRunning) {
    [runner stopWestonSimpleSHM];
  }

  self.compositorContainer.hidden = YES;
  [self setCompositorGestureDeferralEnabled:NO];
#if !TARGET_OS_VISION
  [self applyRespectSafeAreaPreference];
#endif
  [self presentMachinesConfigurationAfterWelcome];
}

- (void)revealCompositor {
  self.compositorContainer.hidden = NO;
#if !TARGET_OS_VISION
  [self applyRespectSafeAreaPreference];
#endif
  [self setCompositorGestureDeferralEnabled:YES];
  self.showingMachinesUI = NO;
  [self updateOutputSizeFromContainerForced:YES];
}

- (void)presentMachinesConfigurationAfterWelcome {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self setCompositorGestureDeferralEnabled:NO];
    if (self.showingMachinesUI) {
      return;
    }
    self.showingMachinesUI = YES;
    UIViewController *presenter = self.window.rootViewController;
    if (!presenter) {
      self.showingMachinesUI = NO;
      return;
    }
    __weak typeof(self) weakSelf = self;
    [[WWNMachinesCoordinator sharedCoordinator]
        presentMachinesFromViewController:presenter
                                onConnect:^{
                                  __strong typeof(weakSelf) strongSelf = weakSelf;
                                  if (!strongSelf) {
                                    return;
                                  }
                                  // Dismiss the machines modal first, then reveal
                                  // the compositor once the animation finishes.
                                  UIViewController *root =
                                      strongSelf.window.rootViewController;
                                  UIViewController *presented =
                                      root.presentedViewController;
                                  if (presented) {
                                    [presented
                                        dismissViewControllerAnimated:YES
                                        completion:^{
                                          [strongSelf revealCompositor];
                                        }];
                                  } else {
                                    [strongSelf revealCompositor];
                                  }
                                }];
  });
}

@end
