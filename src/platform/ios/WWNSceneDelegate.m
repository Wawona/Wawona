#import "WWNSceneDelegate.h"
#import "../macos/ui/Settings/WWNPreferencesManager.h"
#if TARGET_OS_IPHONE && !TARGET_OS_TV
#import "../../platform/macos/WWNRootfsProvider.h"
#endif
#import "../macos/WWNCompositorBridge.h"
#import "../macos/ui/Settings/WWNPreferences.h"
#import "../macos/ui/Settings/WWNWaypipeRunner.h"
#import "../macos/ui/Machines/WWNMachinesCoordinator.h"
#import "../macos/ui/Machines/WWNMachineProfileStore.h"
#import "WWNCompositorBridge.h"
#import "WWNStartupLogViewController.h"
#import "WWNCompositorView_ios.h"
#import "../../util/WWNLog.h"
#import "../../util/WWNStartupLogger.h"
#import <math.h>
#import <TargetConditionals.h>

typedef NS_ENUM(NSInteger, WWNSessionExitTrigger) {
  WWNSessionExitTriggerShake = 0,
  WWNSessionExitTriggerSwipeBack,
  WWNSessionExitTriggerMenuOrEscape,
};

@interface WWNWelcomeViewController : UIViewController
@property(nonatomic, copy) dispatch_block_t onContinue;
@property(nonatomic, weak) UIButton *continueButton;
@end

@interface WWNCompositorHostViewController : UIViewController
@property(nonatomic, assign) BOOL defersSystemGesturesForCompositor;
@property(nonatomic, copy, nullable) dispatch_block_t onMenuOrEscapeDuringSession;
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

#if TARGET_OS_TV || TARGET_OS_VISION
- (BOOL)canBecomeFirstResponder {
  return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands {
  NSMutableArray<UIKeyCommand *> *commands = [NSMutableArray array];
#if TARGET_OS_VISION
  [commands addObject:[UIKeyCommand keyCommandWithInput:UIKeyInputEscape
                                            modifierFlags:0
                                                   action:@selector(handleSessionExitKeyCommand:)]];
#endif
  return commands;
}

- (void)handleSessionExitKeyCommand:(UIKeyCommand *)command {
  (void)command;
  if (self.onMenuOrEscapeDuringSession) {
    self.onMenuOrEscapeDuringSession();
  }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
#if TARGET_OS_TV
  for (UIPress *press in presses) {
    if (press.type == UIPressTypeMenu && self.onMenuOrEscapeDuringSession) {
      self.onMenuOrEscapeDuringSession();
      return;
    }
  }
#endif
  [super pressesEnded:presses withEvent:event];
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
/// Host IME overlap (points) reported by WWNCompositorView_ios.
@property(nonatomic, assign) CGFloat hostKeyboardOverlap;
/// Wawona accessory bar reserve (points) for wl_output shrink.
@property(nonatomic, assign) CGFloat hostKeyboardAccessoryHeight;
/// Soft-keyboard geometry says hardware keyboard is active (no IME resize).
@property(nonatomic, assign) BOOL hostHardwareKeyboardActive;
/// Last applied Respect Safe Area value — used to skip redundant logs.
@property(nonatomic, assign) BOOL lastRespectSafeArea;
@property(nonatomic, assign) BOOL hasAppliedSafeArea;
@property(nonatomic, assign) BOOL showingMachinesUI;
@property(nonatomic, strong) UIViewController *machinesViewController;
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *machinesViewConstraints;
@property(nonatomic, assign) CFTimeInterval lastShakePromptTime;
@property(nonatomic, assign) BOOL sessionExitPromptVisible;
#if !TARGET_OS_VISION && !TARGET_OS_TV
@property(nonatomic, strong) UIScreenEdgePanGestureRecognizer *backSwipeGesture;
#endif
/// Startup log overlay shown during the Machines → compositor transition.
@property(nonatomic, strong, nullable) WWNStartupLogViewController *startupLogVC;
/// In-window client tabs (issue #84); shown when >1 live client.
@property(nonatomic, strong, nullable) UISegmentedControl *clientTabsControl;
@property(nonatomic, strong, nullable) NSLayoutConstraint *clientTabsTopConstraint;
@end

@implementation WWNSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
#if TARGET_OS_IPHONE && !TARGET_OS_TV
  [WWNRootfsProvider prepareUserAccess];
#endif
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
#if TARGET_OS_TV || TARGET_OS_VISION
  rootViewController.onMenuOrEscapeDuringSession = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf handleMenuOrEscapeDuringSession];
  };
#endif
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

  // Machines UI is the initial surface; keep compositor hidden until a session starts.
  self.compositorContainer.hidden = YES;

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

  // Observe preference changes so the user can toggle at runtime
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(userDefaultsDidChange:)
             name:NSUserDefaultsDidChangeNotification
           object:nil];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(forceSSDPreferenceDidChange:)
             name:kWWNForceSSDChangedNotification
           object:nil];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleNativeClientWillLaunch:)
             name:WWNNativeClientWillLaunchNotification
           object:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleNativeClientDidTerminate:)
             name:@"WWNNativeClientProcessDidTerminateNotification"
           object:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleClientMinimizeRequested:)
             name:WWNClientMinimizeRequestedNotification
           object:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(hostKeyboardGeometryDidChange:)
             name:WWNHostKeyboardGeometryDidChangeNotification
           object:nil];

  WWNLog("SCENE", @"Wawona Scene connected and window created.");

  if (![[WWNCompositorBridge sharedBridge] isRunning]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      UIAlertController *alert = [UIAlertController
          alertControllerWithTitle:@"Compositor Failed to Start"
                           message:@"Wayland did not start, but Machines should "
                                   @"still appear. Connect again after relaunch."
                    preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                style:UIAlertActionStyleDefault
                                              handler:nil]];
      [self.window.rootViewController presentViewController:alert
                                                   animated:YES
                                                 completion:nil];
    });
  }

  [self presentWelcomeIfNeeded];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Safe Area

- (void)applyRespectSafeAreaPreference {
  BOOL respectSafeArea =
      [[WWNPreferencesManager sharedManager] respectSafeArea];

  BOOL compositorActive = !self.compositorContainer.hidden;
  BOOL usingSafeArea = self.safeAreaConstraints.firstObject.isActive;
  BOOL usingFullScreen = self.fullScreenConstraints.firstObject.isActive;
  BOOL constraintsMatch =
      (respectSafeArea && usingSafeArea) || (!respectSafeArea && usingFullScreen);

  if (self.hasAppliedSafeArea && self.lastRespectSafeArea == respectSafeArea &&
      constraintsMatch) {
    return;
  }

  self.lastRespectSafeArea = respectSafeArea;
  self.hasAppliedSafeArea = YES;
  WWNLog("SCENE", @"Respect Safe Area = %@%@",
         respectSafeArea ? @"YES" : @"NO",
         compositorActive ? @" (compositor session)" : @"");

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

- (void)userDefaultsDidChange:(NSNotification *)note {
  (void)note;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self applyRespectSafeAreaPreference];
    [self updateOutputSizeFromContainerForced:YES];
  });
}

- (void)forceSSDPreferenceDidChange:(NSNotification *)note {
  (void)note;
  dispatch_async(dispatch_get_main_queue(), ^{
    [[WWNCompositorBridge sharedBridge]
        setForceSSD:[[WWNPreferencesManager sharedManager] forceServerSideDecorations]];
  });
}

- (void)hostKeyboardGeometryDidChange:(NSNotification *)note {
  NSDictionary *info = note.userInfo;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.hostKeyboardOverlap =
        [info[@"overlap"] respondsToSelector:@selector(doubleValue)]
            ? (CGFloat)[info[@"overlap"] doubleValue]
            : 0.0;
    self.hostKeyboardAccessoryHeight =
        [info[@"accessoryHeight"] respondsToSelector:@selector(doubleValue)]
            ? (CGFloat)[info[@"accessoryHeight"] doubleValue]
            : 0.0;
    self.hostHardwareKeyboardActive =
        [info[@"hardwareKeyboard"] respondsToSelector:@selector(boolValue)]
            ? [info[@"hardwareKeyboard"] boolValue]
            : NO;
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

  BOOL resizeForKeyboard =
      [[WWNPreferencesManager sharedManager] resizeDisplayForVirtualKeyboard] &&
      !self.hostHardwareKeyboardActive;
  if (resizeForKeyboard) {
    CGFloat reserved =
        self.hostKeyboardOverlap + self.hostKeyboardAccessoryHeight;
    if (reserved > 0.0) {
      sz.height = MAX(120.0, sz.height - reserved);
    }
  }

  if (!forced && CGSizeEqualToSize(sz, self.lastOutputSize) &&
      fabsf(self.lastOutputScale - wlScale) < 0.001f) {
    return;
  }
  BOOL sizeChanged = !CGSizeEqualToSize(sz, self.lastOutputSize) ||
      fabsf(self.lastOutputScale - wlScale) >= 0.001f;
  self.lastOutputSize = sz;
  self.lastOutputScale = wlScale;

  WWNCompositorBridge *compositor = [WWNCompositorBridge sharedBridge];
  [compositor setOutputWidth:(uint32_t)sz.width
                      height:(uint32_t)sz.height
                       scale:wlScale];

  if (sizeChanged) {
    WWNLog("SCENE", @"Output size: %.0fx%.0f @ %.1fx (auto-scale %@)",
          sz.width, sz.height, wlScale, autoScale ? @"ON" : @"OFF");
  }
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
  if (![self isAnyClientSessionRunning]) {
    return;
  }
  if ([self isSwipeBackToCloseEnabled]) {
    [self presentSessionExitConfirmationForTrigger:WWNSessionExitTriggerSwipeBack];
  } else {
    [self closeActiveWaylandSession];
  }
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
    [self showMachinesUI];
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
  return [runner isAnyNativeClientRunning];
}

- (BOOL)isAnyClientSessionRunning {
  WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
  return runner.isRunning || [self isAnyNativeClientRunning];
}

- (nullable WWNMachineProfile *)activeMachineProfile {
  NSString *activeId = [WWNMachineProfileStore activeMachineId];
  if (activeId.length == 0) {
    return nil;
  }
  return [WWNMachineProfileStore profileById:activeId];
}

- (BOOL)isShakeToCloseEnabled {
  return [WWNMachineProfileStore resolvedShakeToCloseForProfile:[self activeMachineProfile]];
}

- (BOOL)isSwipeBackToCloseEnabled {
  return [WWNMachineProfileStore resolvedSwipeBackToCloseForProfile:[self activeMachineProfile]];
}

- (void)handleShakeGesture {
  if (![self isShakeToCloseEnabled]) {
    return;
  }
  [self presentSessionExitConfirmationForTrigger:WWNSessionExitTriggerShake];
}

- (void)handleMenuOrEscapeDuringSession {
  if (self.showingMachinesUI || ![self isAnyClientSessionRunning]) {
    return;
  }
  [self presentSessionExitConfirmationForTrigger:WWNSessionExitTriggerMenuOrEscape];
}

- (void)presentSessionExitConfirmationForTrigger:(WWNSessionExitTrigger)trigger {
  (void)trigger;
  if (self.sessionExitPromptVisible) {
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

  self.sessionExitPromptVisible = YES;
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
                                 strongSelf.sessionExitPromptVisible = NO;
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
                                 strongSelf.sessionExitPromptVisible = NO;
                               }]];

  [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)closeActiveWaylandSession {
  if (self.sessionExitPromptVisible) {
    UIViewController *presenter = self.window.rootViewController;
    while (presenter.presentedViewController) {
      presenter = presenter.presentedViewController;
    }
    [presenter dismissViewControllerAnimated:NO completion:nil];
    self.sessionExitPromptVisible = NO;
  }

  WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
  [runner stopActiveIOSBundledClient];

  if (runner.isRunning) {
    [runner stopWaypipe];
  }

  // Session was force-closed outside the SwiftUI machine card actions; clear the
  // active machine and nudge the Machines view-model to resync transient status.
  [WWNMachineProfileStore setActiveMachineId:nil];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:@"WWNNativeClientProcessDidTerminateNotification"
                    object:runner];

  self.compositorContainer.hidden = YES;
  self.clientTabsControl.hidden = YES;
  [self setCompositorGestureDeferralEnabled:NO];
#if !TARGET_OS_VISION
  [self applyRespectSafeAreaPreference];
#endif
  [self showMachinesUI];
}

- (void)handleNativeClientWillLaunch:(NSNotification *)notification {
  NSString *clientId = notification.userInfo[@"clientId"];
  [self showStartupLogForClient:clientId];
  [self hideMachinesUIAndRevealCompositor];
  [self refreshClientTabs];
}

- (void)refreshClientTabs {
#if TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_VISION
  if (self.compositorContainer.hidden) {
    self.clientTabsControl.hidden = YES;
    return;
  }
  NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:@"Shell"];
  NSString *active =
      [WWNWaypipeRunner sharedRunner].activeIOSBundledClientId;
  if (active.length > 0 &&
      ![active isEqualToString:@"weston-terminal"] &&
      ![active isEqualToString:@"Shell"]) {
    [titles addObject:active];
  }
  if (titles.count <= 1) {
    self.clientTabsControl.hidden = YES;
    return;
  }
  if (!self.clientTabsControl) {
    self.clientTabsControl =
        [[UISegmentedControl alloc] initWithItems:titles];
    self.clientTabsControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.clientTabsControl.selectedSegmentIndex = 0;
    [self.clientTabsControl addTarget:self
                               action:@selector(clientTabChanged:)
                     forControlEvents:UIControlEventValueChanged];
    [self.window.rootViewController.view addSubview:self.clientTabsControl];
    UILayoutGuide *safe =
        self.window.rootViewController.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
      [self.clientTabsControl.topAnchor
          constraintEqualToAnchor:safe.topAnchor
                         constant:4],
      [self.clientTabsControl.leadingAnchor
          constraintEqualToAnchor:safe.leadingAnchor
                         constant:12],
      [self.clientTabsControl.trailingAnchor
          constraintEqualToAnchor:safe.trailingAnchor
                         constant:-12],
    ]];
  } else {
    [self.clientTabsControl removeAllSegments];
    for (NSUInteger i = 0; i < titles.count; i++) {
      [self.clientTabsControl insertSegmentWithTitle:titles[i]
                                             atIndex:i
                                            animated:NO];
    }
  }
  self.clientTabsControl.hidden = NO;
  [self.window.rootViewController.view
      bringSubviewToFront:self.clientTabsControl];
#endif
}

- (void)clientTabChanged:(UISegmentedControl *)control {
  NSString *title = [control titleForSegmentAtIndex:control.selectedSegmentIndex];
  WWNLog("TABS", @"focus client tab=%@", title ?: @"(nil)");
  // Focus/activate is compositor-side; chrome tracks live clients (#84).
}

// ---------------------------------------------------------------------------
// Startup log overlay
// ---------------------------------------------------------------------------

- (void)showStartupLogForClient:(NSString *)clientId
{
  /* Begin capturing before launching so we don't miss early messages. */
  [[WWNStartupLogger shared] beginCapture];

  /* Inject a header line so the log is never empty on first render. */
  NSString *label = clientId.length > 0 ? clientId : @"wayland client";
  NSString *header = [NSString stringWithFormat:
      @"[LAUNCH] Starting %@ …", label];
  [[WWNStartupLogger shared] appendLine:header];

  WWNStartupLogViewController *logVC = [[WWNStartupLogViewController alloc] init];
  logVC.clientLabel = label;
  self.startupLogVC = logVC;

  /* Add as child view controller over the compositor container. */
  UIViewController *host = self.window.rootViewController;
  [host addChildViewController:logVC];
  logVC.view.translatesAutoresizingMaskIntoConstraints = NO;
  logVC.view.alpha = 0.0;
  [host.view addSubview:logVC.view];
  [NSLayoutConstraint activateConstraints:@[
      [logVC.view.topAnchor constraintEqualToAnchor:host.view.topAnchor],
      [logVC.view.bottomAnchor constraintEqualToAnchor:host.view.bottomAnchor],
      [logVC.view.leadingAnchor constraintEqualToAnchor:host.view.leadingAnchor],
      [logVC.view.trailingAnchor constraintEqualToAnchor:host.view.trailingAnchor],
  ]];
  [logVC didMoveToParentViewController:host];

  [UIView animateWithDuration:0.25 animations:^{
    logVC.view.alpha = 1.0;
  }];

  /* Observe the first Wayland frame to auto-dismiss. */
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleFirstWaylandFrame:)
             name:@"WWNFirstWaylandFrameNotification"
           object:nil];
}

- (void)handleFirstWaylandFrame:(NSNotification *)notification
{
  (void)notification;
  [[NSNotificationCenter defaultCenter] removeObserver:self
      name:@"WWNFirstWaylandFrameNotification"
    object:nil];

  /* Brief delay so the user sees at least a few log lines before fade-out. */
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    [self dismissStartupLog];
  });
}

- (void)dismissStartupLog
{
  WWNStartupLogViewController *logVC = self.startupLogVC;
  if (!logVC) return;
  self.startupLogVC = nil;
  [logVC dismissWithCompletion:nil];
}

- (void)handleNativeClientDidTerminate:(NSNotification *)notification {
  (void)notification;
  dispatch_async(dispatch_get_main_queue(), ^{
    /* If the client terminated before the first frame, dismiss the log. */
    [self dismissStartupLog];
    [self refreshClientTabs];

    if ([self isAnyClientSessionRunning]) {
      return;
    }
    self.compositorContainer.hidden = YES;
    self.clientTabsControl.hidden = YES;
    [self setCompositorGestureDeferralEnabled:NO];
#if !TARGET_OS_VISION
    [self applyRespectSafeAreaPreference];
#endif
    [self showMachinesUI];
  });
}

- (void)handleClientMinimizeRequested:(NSNotification *)notification {
  (void)notification;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.sessionExitPromptVisible) {
      return;
    }
    if (![self isAnyClientSessionRunning]) {
      return;
    }
    [self showMachinesUI];
  });
}

- (void)revealCompositor {
  self.compositorContainer.hidden = NO;
#if !TARGET_OS_VISION
  [self applyRespectSafeAreaPreference];
#endif
  [self setCompositorGestureDeferralEnabled:YES];
  self.showingMachinesUI = NO;
#if TARGET_OS_TV || TARGET_OS_VISION
  if ([self.window.rootViewController isKindOfClass:[WWNCompositorHostViewController class]]) {
    [self.window.rootViewController becomeFirstResponder];
  }
#endif
  // Force a layout pass so compositorContainer.bounds reflects the actual
  // screen dimensions before we push the size to the Wayland compositor.
  // Without this, a just-revealed container may still report CGSizeZero or
  // stale bounds, causing the nested Weston compositor to launch with the
  // wrong --width/--height and leave gutters on screen.
  [self.window.rootViewController.view layoutIfNeeded];
  [self updateOutputSizeFromContainerForced:YES];
}

- (void)embedMachinesViewController:(UIViewController *)machinesVC
                         inParent:(UIViewController *)parent {
  if (self.machinesViewController == machinesVC) {
    machinesVC.view.hidden = NO;
    [parent.view bringSubviewToFront:machinesVC.view];
    return;
  }

  if (self.machinesViewController != nil) {
    [self removeEmbeddedMachinesViewController];
  }

  [parent addChildViewController:machinesVC];
  machinesVC.view.translatesAutoresizingMaskIntoConstraints = NO;
  [parent.view addSubview:machinesVC.view];
  [parent.view bringSubviewToFront:machinesVC.view];

  self.machinesViewConstraints = @[
    [machinesVC.view.topAnchor constraintEqualToAnchor:parent.view.topAnchor],
    [machinesVC.view.bottomAnchor constraintEqualToAnchor:parent.view.bottomAnchor],
    [machinesVC.view.leadingAnchor constraintEqualToAnchor:parent.view.leadingAnchor],
    [machinesVC.view.trailingAnchor constraintEqualToAnchor:parent.view.trailingAnchor],
  ];
  [NSLayoutConstraint activateConstraints:self.machinesViewConstraints];

  [machinesVC didMoveToParentViewController:parent];
  self.machinesViewController = machinesVC;
}

- (void)removeEmbeddedMachinesViewController {
  if (!self.machinesViewController) {
    return;
  }

  if (self.machinesViewConstraints.count > 0) {
    [NSLayoutConstraint deactivateConstraints:self.machinesViewConstraints];
    self.machinesViewConstraints = nil;
  }

  [self.machinesViewController willMoveToParentViewController:nil];
  [self.machinesViewController.view removeFromSuperview];
  [self.machinesViewController removeFromParentViewController];
  self.machinesViewController = nil;
}

- (void)showMachinesUI {
  [self setCompositorGestureDeferralEnabled:NO];
  self.compositorContainer.hidden = YES;
#if !TARGET_OS_VISION
  [self applyRespectSafeAreaPreference];
#endif

  if (self.machinesViewController) {
    self.machinesViewController.view.hidden = NO;
    [self.window.rootViewController.view
        bringSubviewToFront:self.machinesViewController.view];
    self.showingMachinesUI = YES;
    return;
  }

  [self presentMachinesConfigurationAfterWelcome];
}

- (void)hideMachinesUIAndRevealCompositor {
  if (self.machinesViewController) {
    self.machinesViewController.view.hidden = YES;
  }
  self.showingMachinesUI = NO;
  [self revealCompositor];
}

- (void)presentMachinesConfigurationAfterWelcome {
  void (^presentBlock)(void) = ^{
    [self setCompositorGestureDeferralEnabled:NO];
    if (self.machinesViewController) {
      self.machinesViewController.view.hidden = NO;
      self.showingMachinesUI = YES;
      return;
    }

    UIViewController *parent = self.window.rootViewController;
    if (!parent) {
      self.showingMachinesUI = NO;
      return;
    }

    __weak typeof(self) weakSelf = self;
    UIViewController *machinesVC = [[WWNMachinesCoordinator sharedCoordinator]
        buildMachinesViewControllerWithOnConnect:^{
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf) {
            return;
          }
          [strongSelf hideMachinesUIAndRevealCompositor];
        }];
    if (!machinesVC) {
      self.showingMachinesUI = NO;
      UIAlertController *alert = [UIAlertController
          alertControllerWithTitle:@"Machines UI Unavailable"
                           message:@"SwiftUI machines view failed to load. Regenerate the Xcode project and rebuild."
                    preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                style:UIAlertActionStyleDefault
                                              handler:nil]];
      [parent presentViewController:alert animated:YES completion:nil];
      return;
    }

    [self embedMachinesViewController:machinesVC inParent:parent];
    self.showingMachinesUI = YES;
  };

  if ([NSThread isMainThread]) {
    presentBlock();
  } else {
    dispatch_async(dispatch_get_main_queue(), presentBlock);
  }
}

@end
