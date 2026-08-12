#import "WWNSceneDelegate.h"
#import "../macos/ui/Settings/WWNPreferencesManager.h"
#if TARGET_OS_IPHONE
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
/// visionOS Escape / legacy short-Menu session-exit hook.
@property(nonatomic, copy, nullable) dispatch_block_t onMenuOrEscapeDuringSession;
#if TARGET_OS_TV
/// Short Menu/Back: send Escape into the Wayland client (in-app Back).
@property(nonatomic, copy, nullable) dispatch_block_t onTvMenuShortPressDuringSession;
/// Long-press Menu/Back: tvOS replacement for shake-to-exit (confirm leave session).
@property(nonatomic, copy, nullable) dispatch_block_t onTvMenuLongPressDuringSession;
/// When NO (Machines UI), Menu is left to the system focus/back stack.
@property(nonatomic, assign) BOOL interceptsMenuForSessionExit;
- (void)cancelTvMenuLongPress;
#endif
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
#if !TARGET_OS_TV
  // tvOS does not deliver UIEventSubtypeMotionShake for the Siri Remote.
  // Session exit on TV uses long-press Menu instead (see host VC).
  if (motion == UIEventSubtypeMotionShake && self.onShake) {
    self.onShake();
  }
#endif
}

@end

@implementation WWNCompositorHostViewController {
#if TARGET_OS_TV
  NSTimer *_tvMenuLongPressTimer;
  BOOL _tvMenuLongPressFired;
#endif
}

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

#if TARGET_OS_TV
/// Deliberate hold — tvOS analogue of iOS shake-to-exit. Short Menu is Escape.
static const NSTimeInterval kWWNTvMenuLongPressDuration = 0.85;

- (void)_cancelTvMenuLongPressTimer {
  [_tvMenuLongPressTimer invalidate];
  _tvMenuLongPressTimer = nil;
}

- (void)cancelTvMenuLongPress {
  [self _cancelTvMenuLongPressTimer];
  _tvMenuLongPressFired = NO;
}

- (void)_tvMenuLongPressFired:(NSTimer *)timer {
  (void)timer;
  _tvMenuLongPressTimer = nil;
  _tvMenuLongPressFired = YES;
  if (self.onTvMenuLongPressDuringSession) {
    self.onTvMenuLongPressDuringSession();
  }
}

- (BOOL)_setContainsMenuPress:(NSSet<UIPress *> *)presses {
  for (UIPress *press in presses) {
    if (press.type == UIPressTypeMenu) {
      return YES;
    }
  }
  return NO;
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  if (self.interceptsMenuForSessionExit && [self _setContainsMenuPress:presses]) {
    _tvMenuLongPressFired = NO;
    [self _cancelTvMenuLongPressTimer];
    __weak typeof(self) weakSelf = self;
    // CommonModes so the hold timer still fires while UIPress tracking runs.
    _tvMenuLongPressTimer =
        [NSTimer timerWithTimeInterval:kWWNTvMenuLongPressDuration
                               repeats:NO
                                 block:^(__unused NSTimer *t) {
                                   __strong typeof(weakSelf) strongSelf = weakSelf;
                                   [strongSelf _tvMenuLongPressFired:t];
                                 }];
    [[NSRunLoop mainRunLoop] addTimer:_tvMenuLongPressTimer
                              forMode:NSRunLoopCommonModes];
    // Consume Menu so short release is Escape-to-client, not system app-exit.
    return;
  }
  [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  if (self.interceptsMenuForSessionExit && [self _setContainsMenuPress:presses]) {
    BOOL fired = _tvMenuLongPressFired;
    [self _cancelTvMenuLongPressTimer];
    _tvMenuLongPressFired = NO;
    if (!fired && self.onTvMenuShortPressDuringSession) {
      self.onTvMenuShortPressDuringSession();
    }
    return;
  }
  [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  if (self.interceptsMenuForSessionExit && [self _setContainsMenuPress:presses]) {
    [self _cancelTvMenuLongPressTimer];
    _tvMenuLongPressFired = NO;
    return;
  }
  [super pressesCancelled:presses withEvent:event];
}

- (void)dealloc {
  [self _cancelTvMenuLongPressTimer];
}
#endif // TARGET_OS_TV
#endif // TARGET_OS_TV || TARGET_OS_VISION

@end

// iPadOS / visionOS multi-window (#120): hosts a single Wayland client's view
// in its own dedicated UIWindowScene (see -connectClientWindowScene:). This
// window's geometry is independent of the primary Machines scene and of any
// other client's window — report layout-driven size changes (Stage Manager
// drag, Split View, rotation, …) so the scene delegate can push a per-window
// injectWindowResize instead of relying on the shared/global output size.
@interface WWNClientSceneHostViewController : UIViewController
@property(nonatomic, copy, nullable) void (^onSizeChanged)(CGSize size);
@end

@implementation WWNClientSceneHostViewController {
  CGSize _wwnLastReportedSize;
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self wwnReportSizeIfChanged:self.view.bounds.size];
}

// viewDidLayoutSubviews tracks *live* drag frames (mirrors macOS live-resize
// streaming), but Stage Manager / Split View / rotation transitions can
// coalesce or skip intermediate layout passes on iPadOS/visionOS, especially
// when the client itself isn't actively re-laying-out content that would
// otherwise trigger Auto Layout. viewWillTransitionToSize:… is the
// OS-guaranteed callback for *every* scene bounds change and always carries
// the final target size, so use it as a backstop — without it, a resize that
// doesn't otherwise dirty layout can silently never reach injectWindowResize:
// and the client keeps rendering at its old size (#120).
- (void)viewWillTransitionToSize:(CGSize)size
        withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  [self wwnReportSizeIfChanged:size];
  __weak typeof(self) weakSelf = self;
  [coordinator animateAlongsideTransition:nil
                                completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
    // Report once more after the transition settles in case the coordinator's
    // target size differed from the final laid-out bounds (e.g. safe-area
    // insets resolved late).
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf) {
      [strongSelf wwnReportSizeIfChanged:strongSelf.view.bounds.size];
    }
  }];
}

- (void)wwnReportSizeIfChanged:(CGSize)size {
  if (size.width <= 0 || size.height <= 0) {
    return;
  }
  if (CGSizeEqualToSize(size, _wwnLastReportedSize)) {
    return;
  }
  _wwnLastReportedSize = size;
  if (self.onSizeChanged) {
    self.onSizeChanged(size);
  }
}

@end

@implementation WWNWelcomeViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];

  self.view.accessibilityIdentifier = @"wwn.welcome.root";

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
  titleLabel.accessibilityIdentifier = @"wwn.welcome.title";

  UILabel *bodyLabel = [[UILabel alloc] init];
  bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  bodyLabel.text = @"The portable nested compositor that makes no assumptions "
                   @"about the host.";
  bodyLabel.textAlignment = NSTextAlignmentCenter;
  bodyLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
  bodyLabel.numberOfLines = 0;
  bodyLabel.textColor = [UIColor secondaryLabelColor];

  UIButton *continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
  continueButton.translatesAutoresizingMaskIntoConstraints = NO;
  [continueButton setTitle:@"Continue" forState:UIControlStateNormal];
  continueButton.titleLabel.font =
      [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
  continueButton.accessibilityIdentifier = @"wwn.welcome.continue";
  continueButton.accessibilityLabel = @"Continue";
  // Keep Continue as its own a11y node — XCTest otherwise collapses the modal
  // to a single "Welcome to Wawona" other (CI smoke cannot press by id).
  card.isAccessibilityElement = NO;
  titleLabel.isAccessibilityElement = YES;
  bodyLabel.isAccessibilityElement = YES;
  continueButton.isAccessibilityElement = YES;
  self.view.accessibilityViewIsModal = YES;
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
/// Window ids parallel to clientTabsControl segments (Wayland clients only).
@property(nonatomic, copy, nullable) NSArray<NSNumber *> *clientTabWindowIds;
/// iPadOS / visionOS multi-window (#120): when this scene delegate hosts a
/// single Wayland client in its own UIWindowScene, the client's window id
/// (0 = primary Machines scene). Used to tear the client down on disconnect.
@property(nonatomic, assign) uint64_t hostedClientWindowId;
@end

@implementation WWNSceneDelegate

#if !TARGET_OS_TV
// iPadOS / visionOS multi-window (#120): host a single Wayland client toplevel
// in its own dedicated UIWindowScene. Called from -scene:willConnectToSession:
// when the scene was activated by -[WWNCompositorBridge handleWindowCreated]
// with a client-window user activity.
- (void)connectClientWindowScene:(UIWindowScene *)windowScene
                     forWindowId:(uint64_t)windowId
                         session:(UISceneSession *)session {
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  UIView *clientView = [bridge takePendingSceneClientViewForWindowId:windowId];
  if (!clientView) {
    // The client was destroyed before its scene connected: nothing to host.
    WWNLog("SCENE",
           @"client-window scene connected for window %llu but no pending view; "
           @"ignoring",
           windowId);
    return;
  }

  self.hostedClientWindowId = windowId;

  UIWindow *hostWindow =
      [[UIWindow alloc] initWithWindowScene:windowScene];
  hostWindow.backgroundColor = [UIColor blackColor];
  WWNClientSceneHostViewController *hostController =
      [[WWNClientSceneHostViewController alloc] init];

  // Wire the resize callback BEFORE the view is loaded/added to any window —
  // loadView/viewDidLoad below and the rootViewController assignment can
  // trigger the first layout pass, and we don't want that first (correct)
  // size to be silently swallowed by a nil callback.
  //
  // This window's size is driven exclusively by its own dedicated scene —
  // never by the primary Machines scene's shared output (#120). Push a
  // per-window resize on every layout/transition change (Stage Manager
  // drag, Split View, rotation, …) instead of the shared
  // setOutputWidth:height:scale:.
  //
  // OWL / SizeAuthority gate: mirrors WWNCompositorView_ios.layoutSubviews'
  // mayInjectHostSize (hostLocked || followHostSize). clientView (the actual
  // WWNCompositorView_ios) is a flex-resizing subview of this controller's
  // view, so its own layoutSubviews already independently observes this same
  // bounds change and applies the identical gate — without this check here
  // too, this callback unconditionally forced host authority on every
  // fixed-size demo client (weston-flower/smoke, simple-shm), stretching
  // their small negotiated buffer to fill the dedicated scene window instead
  // of leaving it centered at the size the client actually wants.
  __weak WWNCompositorBridge *weakBridge = bridge;
  hostController.onSizeChanged = ^(CGSize size) {
    if (![weakBridge shouldFollowHostSizeForWindowId:windowId]) {
      WWNLog("SCENE",
             @"Dedicated scene window %llu size changed → %.0fx%.0f but "
             @"client does not follow host size; leaving negotiated size "
             @"alone",
             windowId, size.width, size.height);
      return;
    }
    uint32_t w = (uint32_t)MAX(1, lround(size.width));
    uint32_t h = (uint32_t)MAX(1, lround(size.height));
    WWNLog("SCENE",
           @"Dedicated scene window %llu size changed → injectWindowResize "
           @"%.0fx%.0f",
           windowId, size.width, size.height);
    [weakBridge injectWindowResize:windowId width:w height:h];
    [weakBridge resyncFillPrimaryHostStateForWindowId:windowId];
  };

  hostController.view.backgroundColor = [UIColor blackColor];
  hostWindow.rootViewController = hostController;

  clientView.frame = hostController.view.bounds;
  clientView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [hostController.view addSubview:clientView];

  hostWindow.hidden = NO;
  [hostWindow makeKeyAndVisible];
  self.window = hostWindow;

  [bridge registerClientHostWindow:hostWindow forWindowId:windowId];

  // Title the scene so it reads correctly in the app switcher / Stage Manager.
  NSString *title = [bridge titleForHostWindowId:windowId];
  if (title.length > 0) {
    windowScene.title = title;
  }

  WWNLog("SCENE",
         @"Hosted Wayland client window %llu in dedicated UIWindowScene (%.0fx%.0f)",
         windowId, hostWindow.bounds.size.width, hostWindow.bounds.size.height);
}
#endif

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
#if TARGET_OS_IPHONE
  // Install rootfs + XDG_* / HOME for every Apple-mobile scene (incl. tvOS).
  // Files-app layout is phone/pad/vision only — TV has no Files browser.
  [WWNRootfsProvider applyShellEnvironment];
#if !TARGET_OS_TV
  [WWNRootfsProvider prepareUserAccess];
#endif
#endif
  if (![scene isKindOfClass:[UIWindowScene class]])
    return;

  UIWindowScene *windowScene = (UIWindowScene *)scene;

#if !TARGET_OS_TV
  // iPadOS / visionOS multi-window (#120): a scene requested by
  // -handleWindowCreated for a specific Wayland client carries its window id in
  // an NSUserActivity. Host ONLY that client's view in this scene — do not
  // rebuild the Machines UI or touch the shared compositor container (that path
  // belongs to the primary scene below).
  uint64_t clientSceneWindowId = 0;
  for (NSUserActivity *activity in connectionOptions.userActivities) {
    if ([activity.activityType
            isEqualToString:WWNClientWindowSceneActivityType]) {
      NSNumber *wid = activity.userInfo[WWNClientWindowSceneWindowIdKey];
      if ([wid isKindOfClass:[NSNumber class]]) {
        clientSceneWindowId = wid.unsignedLongLongValue;
      }
      break;
    }
  }
  if (clientSceneWindowId != 0) {
    [self connectClientWindowScene:windowScene
                       forWindowId:clientSceneWindowId
                           session:session];
    return;
  }
#endif

  WWNShakeAwareWindow *shakeWindow =
      [[WWNShakeAwareWindow alloc] initWithWindowScene:windowScene];
  __weak typeof(self) weakSelf = self;
#if !TARGET_OS_TV
  shakeWindow.onShake = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf handleShakeGesture];
  };
#endif
  self.window = shakeWindow;
  self.window.backgroundColor = [UIColor blackColor];

  // Root view controller — fills the full screen
  WWNCompositorHostViewController *rootViewController =
      [[WWNCompositorHostViewController alloc] init];
  rootViewController.defersSystemGesturesForCompositor = NO;
#if TARGET_OS_TV
  // Siri Remote has no shake API. Long-press Menu = shake-to-exit;
  // short Menu = Escape (client Back) so nested apps stay usable.
  rootViewController.onTvMenuShortPressDuringSession = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf handleTvMenuShortPressDuringSession];
  };
  rootViewController.onTvMenuLongPressDuringSession = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf handleShakeGesture];
  };
#elif TARGET_OS_VISION
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
         selector:@selector(handleClientFocusRequested:)
             name:WWNClientFocusRequestedNotification
           object:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleHostWindowsDidChange:)
             name:WWNHostWindowsDidChangeNotification
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

  if (![self startAutoClientIfRequested]) {
    [self presentWelcomeIfNeeded];
  }
}

// Acceptance / CI parity with macOS main.m: when WAWONA_AUTO_CLIENT is set
// (simctl launch passes SIMCTL_CHILD_WAWONA_AUTO_CLIENT into the app's
// environment), skip the modal welcome and drive a bundled client straight from
// launch. This lets the bundled-clients matrix exercise iOS without depending on
// the XCUITest runner / agent-device UI automation (which needs a runner build
// that times out on cold CI). Returns YES when it took over launch.
- (BOOL)startAutoClientIfRequested {
  const char *autoClientEnv = getenv("WAWONA_AUTO_CLIENT");
  if (!autoClientEnv || !autoClientEnv[0]) {
    return NO;
  }
  NSString *autoClient = [NSString stringWithUTF8String:autoClientEnv];
  if (autoClient.length == 0) {
    return NO;
  }
  // Welcome sheet is modal and would block an automated auto-client start.
  [[WWNPreferencesManager sharedManager] setHasSeenWelcome:YES];
  WWNLog("SCENE", @"WAWONA_AUTO_CLIENT=%@ — starting bundled client", autoClient);
  // Give the compositor bridge the same head start Machines Start implies
  // (mirrors the 1.5s delay in macOS main.m).
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [[WWNWaypipeRunner sharedRunner] launchBundledClientWithId:autoClient];
      });
  return YES;
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
#if !TARGET_OS_TV
  // Dedicated client scenes resize via WWNClientSceneHostViewController; the
  // primary Machines scene owns compositorContainer / shared wl_output.
  if (self.hostedClientWindowId != 0) {
    return;
  }
#endif
  if (!self.compositorContainer) {
    return;
  }
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
#if !TARGET_OS_TV
  // iPadOS / visionOS multi-window (#120): closing a client's dedicated
  // UIWindowScene (app switcher / Stage Manager) must ask the Wayland client to
  // close so the compositor tears the toplevel down instead of leaking it.
  if (self.hostedClientWindowId != 0) {
    uint64_t wid = self.hostedClientWindowId;
    self.hostedClientWindowId = 0;
    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
    if (![bridge requestHostCloseForWindowId:wid]) {
      [bridge requestForceDestroyHostWindowForWindowId:wid];
    }
  }
#endif
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
  if (self.showingMachinesUI || ![self isAnyClientSessionRunning]) {
    return;
  }
  if (![self isShakeToCloseEnabled]) {
    return;
  }
  [self presentSessionExitConfirmationForTrigger:WWNSessionExitTriggerShake];
}

#if TARGET_OS_TV
/// Linux KEY_ESC — matches compositor view / bridge injection.
static const uint32_t kWWNTvMenuEscapeKeycode = 1;

- (void)handleTvMenuShortPressDuringSession {
  if (self.showingMachinesUI || ![self isAnyClientSessionRunning]) {
    return;
  }
  if (self.sessionExitPromptVisible) {
    return;
  }
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  uint32_t ts = (uint32_t)(CACurrentMediaTime() * 1000.0);
  [bridge injectKeyWithKeycode:kWWNTvMenuEscapeKeycode pressed:YES timestamp:ts];
  [bridge injectKeyWithKeycode:kWWNTvMenuEscapeKeycode pressed:NO timestamp:ts + 1];
}
#endif

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

  // Ask Wayland toplevels to close first (xdg_toplevel.close), then escalate
  // remaining hosts to force-destroy before killing the session (#52).
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  NSArray<NSNumber *> *hostIds = [bridge allHostWindowIds];
  for (NSNumber *wid in hostIds) {
    [bridge requestHostCloseForWindowId:wid.unsignedLongLongValue];
  }

  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   __strong typeof(weakSelf) strongSelf = weakSelf;
                   if (!strongSelf) {
                     return;
                   }
                   WWNCompositorBridge *b = [WWNCompositorBridge sharedBridge];
                   for (NSNumber *wid in [b allHostWindowIds]) {
                     [b requestForceDestroyHostWindowForWindowId:
                             wid.unsignedLongLongValue];
                   }

                   WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
                   [runner stopActiveIOSBundledClient];
                   if (runner.isRunning) {
                     [runner stopWaypipe];
                   }

                   [WWNMachineProfileStore setActiveMachineId:nil];
                   [[NSNotificationCenter defaultCenter]
                       postNotificationName:
                           @"WWNNativeClientProcessDidTerminateNotification"
                                     object:runner];

                   strongSelf.compositorContainer.hidden = YES;
                   strongSelf.clientTabsControl.hidden = YES;
                   [strongSelf setCompositorGestureDeferralEnabled:NO];
#if !TARGET_OS_VISION
                   [strongSelf applyRespectSafeAreaPreference];
#endif
                   [strongSelf showMachinesUI];
                 });
}

- (void)handleNativeClientWillLaunch:(NSNotification *)notification {
  NSString *clientId = notification.userInfo[@"clientId"];
  [self showStartupLogForClient:clientId];
  // iPadOS / visionOS multi-window (#120): this fires on the PRIMARY scene's
  // delegate (the client's own scene doesn't exist yet — it's requested
  // later, once the toplevel actually maps). When clients get their own
  // dedicated UIWindowScene, the primary Machines scene must stay exactly as
  // it is — hiding its Machines UI and revealing its (now-unused, empty)
  // compositorContainer leaves the user with a black, uninteractable window
  // and no way to launch another machine.
  //
  // Exception: forceRevealPrimary (iland/kmscube scene-activation fallback)
  // when the Metal host could not get a dedicated scene and landed on the
  // primary container — Machines would otherwise cover it permanently.
  BOOL forceReveal =
      [notification.userInfo[@"forceRevealPrimary"] boolValue];
  if (forceReveal || ![self clientsUseDedicatedScenes]) {
    [self hideMachinesUIAndRevealCompositor];
  }
  [self refreshClientTabs];
}

/// iPadOS / visionOS multi-window (#120): YES when Wayland clients are hosted
/// in their own dedicated `UIWindowScene` rather than the primary scene's
/// shared compositor container. The primary (Machines) scene must never hide
/// its SwiftUI configuration UI or reveal its compositor container for such
/// clients — they render in a different OS window entirely.
- (BOOL)clientsUseDedicatedScenes {
  return [[WWNCompositorBridge sharedBridge] perWindowHostingEnabled];
}

- (void)handleHostWindowsDidChange:(NSNotification *)notification {
  (void)notification;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self refreshClientTabs];
  });
}

/// Phone + tvOS: in-window tabs for Wayland clients (#84).
/// iPadOS / visionOS use one UIWindowScene per client (no Shell tab strip).
- (BOOL)usesClientTabChrome {
#if TARGET_OS_VISION
  return NO;
#elif TARGET_OS_TV
  return YES;
#elif TARGET_OS_IPHONE
  // Phone only — iPadOS uses one UIWindowScene per Wayland client.
  return UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad;
#else
  return NO;
#endif
}

- (void)refreshClientTabs {
  if (![self usesClientTabChrome]) {
    self.clientTabsControl.hidden = YES;
    self.clientTabWindowIds = nil;
    return;
  }
  if (self.compositorContainer.hidden) {
    self.clientTabsControl.hidden = YES;
    return;
  }

  // Tabs = live Wayland toplevels only. Shell / Machines is host chrome and
  // must never appear as a segment (nested niri used to show Shell + Niri).
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  // Preserve selection by Wayland window id, not by segment index: creating or
  // closing a client reorders/renumbers segments, so an index would silently
  // select the wrong client (#84). Capture BEFORE clientTabWindowIds is
  // replaced below.
  NSNumber *previouslySelectedWindowId = nil;
  if (self.clientTabsControl &&
      self.clientTabsControl.selectedSegmentIndex >= 0 &&
      (NSUInteger)self.clientTabsControl.selectedSegmentIndex <
          self.clientTabWindowIds.count) {
    previouslySelectedWindowId =
        self.clientTabWindowIds[(NSUInteger)self.clientTabsControl
                                    .selectedSegmentIndex];
  }

  NSArray<NSNumber *> *ids = [bridge tabbedClientWindowIds];
  NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:ids.count];
  for (NSNumber *wid in ids) {
    [titles addObject:[bridge titleForHostWindowId:wid.unsignedLongLongValue]];
  }
  self.clientTabWindowIds = ids;

  if (titles.count <= 1) {
    self.clientTabsControl.hidden = YES;
    // Dropping back to a single client: make sure it is visible again — an
    // earlier tab switch may have hidden it while another tab was selected.
    if (ids.count == 1) {
      [bridge focusTabbedClientWindowId:ids[0].unsignedLongLongValue];
    }
    return;
  }

  if (!self.clientTabsControl) {
    self.clientTabsControl =
        [[UISegmentedControl alloc] initWithItems:titles];
    self.clientTabsControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.clientTabsControl.accessibilityIdentifier = @"wwn.client.tabs";
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
  NSInteger select = NSNotFound;
  if (previouslySelectedWindowId != nil) {
    NSUInteger found = [ids indexOfObject:previouslySelectedWindowId];
    if (found != NSNotFound) {
      select = (NSInteger)found;
    }
  }
  if (select == NSNotFound || select < 0 ||
      (NSUInteger)select >= titles.count) {
    // New client (or the selected one closed): follow the newest tab.
    select = (NSInteger)(titles.count - 1);
  }
  self.clientTabsControl.selectedSegmentIndex = select;
  self.clientTabsControl.hidden = NO;
  [self.window.rootViewController.view
      bringSubviewToFront:self.clientTabsControl];
  // Keep the visible surface in sync with the selected tab: focus hides the
  // other tabbed clients so the selection is actually what the user sees.
  [bridge focusTabbedClientWindowId:
              self.clientTabWindowIds[(NSUInteger)select].unsignedLongLongValue];
#if TARGET_OS_TV
  // tvOS: let the focus engine re-evaluate so the segmented control is
  // reachable with the Siri Remote once it (dis)appears.
  UIViewController *rootVC = self.window.rootViewController;
  [rootVC setNeedsFocusUpdate];
  [rootVC updateFocusIfNeeded];
#endif
  WWNLog("TABS", @"refreshed %lu Wayland client tab(s): %@",
         (unsigned long)titles.count, [titles componentsJoinedByString:@", "]);
}

- (void)clientTabChanged:(UISegmentedControl *)control {
  NSInteger idx = control.selectedSegmentIndex;
  if (idx < 0 || (NSUInteger)idx >= self.clientTabWindowIds.count) {
    return;
  }
  uint64_t target = self.clientTabWindowIds[(NSUInteger)idx].unsignedLongLongValue;
  NSString *title = [control titleForSegmentAtIndex:idx];
  WWNLog("TABS", @"focus Wayland client tab=%@ window=%llu", title ?: @"(nil)",
         target);
  [[WWNCompositorBridge sharedBridge] focusTabbedClientWindowId:target];
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

#if TARGET_OS_VISION
  /* visionOS Simulator: UITextView/UIScrollView scroll-indicator creation
   * throws in Gestures/UIPointerInteraction and can take down the process
   * (ISSUE-016). Capture logs without presenting the overlay UI. */
  (void)label;
  return;
#else
  if ([self clientsUseDedicatedScenes]) {
    // iPadOS multi-window (#120): this notification fires on the PRIMARY
    // scene's delegate, but the client is launching into its OWN dedicated
    // UIWindowScene which doesn't exist yet. Presenting the overlay here
    // would show it on top of the (uninvolved) Machines UI instead of the
    // client's eventual window — capture logs without presenting.
    (void)label;
    return;
  }
#endif
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
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.sessionExitPromptVisible) {
      return;
    }
    if (![self isAnyClientSessionRunning]) {
      return;
    }
    NSNumber *windowId = notification.userInfo[@"windowId"];
    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

#if !TARGET_OS_TV
    // Dedicated client scene: hide only this OS window; primary scene shows
    // Machines below.
    if (self.hostedClientWindowId != 0) {
      if (windowId &&
          windowId.unsignedLongLongValue == self.hostedClientWindowId) {
        self.window.hidden = YES;
      }
      return;
    }
#endif

    // Keep the Wayland client alive; only park the host chrome and return to
    // Machines. Focus reverses this via handleClientFocusRequested:.
    NSString *machineId = notification.userInfo[@"machineId"];
    if (machineId.length == 0) {
      machineId = [WWNMachineProfileStore activeMachineId];
    }
    if ([self clientsUseDedicatedScenes] && windowId) {
      [bridge setClientHostWindowHidden:YES
                             forWindowId:windowId.unsignedLongLongValue];
    } else {
      [bridge setClientHostWindowsHidden:YES forMachineId:machineId];
    }
    // Dedicated client scenes are separate UIWindowScenes — bring the primary
    // Machines scene forward so minimize visibly parks to Machines (#120).
    [self.window makeKeyAndVisible];
    [self showMachinesUI];
  });
}

- (void)handleClientFocusRequested:(NSNotification *)notification {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.sessionExitPromptVisible) {
      return;
    }
    if (![self isAnyClientSessionRunning]) {
      return;
    }
    NSNumber *windowId = notification.userInfo[@"windowId"];
    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

#if !TARGET_OS_TV
    if (self.hostedClientWindowId != 0) {
      if (!windowId ||
          windowId.unsignedLongLongValue == self.hostedClientWindowId) {
        self.window.hidden = NO;
        [self.window makeKeyAndVisible];
      }
      return;
    }
#endif

    NSString *machineId = notification.userInfo[@"machineId"];
    if (machineId.length == 0) {
      machineId = [WWNMachineProfileStore activeMachineId];
    }
    if (machineId.length > 0) {
      [WWNMachineProfileStore setActiveMachineId:machineId];
    }
    if ([self clientsUseDedicatedScenes] && windowId) {
      [bridge setClientHostWindowHidden:NO
                             forWindowId:windowId.unsignedLongLongValue];
    } else {
      [bridge setClientHostWindowsHidden:NO forMachineId:machineId ?: @""];
    }
    // iPadOS / visionOS multi-window (#120): dedicated-scene clients live in
    // their own UIWindowScene, not the primary scene's shared container —
    // the primary (Machines) scene must stay exactly as it is. Focusing such
    // a client is handled below via focusClientWindowsForMachineId:, which
    // brings its own window/scene forward.
    if (![self clientsUseDedicatedScenes]) {
      [self hideMachinesUIAndRevealCompositor];
    }
    [self refreshClientTabs];
    (void)[bridge focusClientWindowsForMachineId:machineId ?: @""];
    WWNLog("SCENE", @"Focus restored compositor for machine=%@",
           machineId.length > 0 ? machineId : @"(active)");
  });
}

- (void)revealCompositor {
  self.compositorContainer.hidden = NO;
#if !TARGET_OS_VISION
  [self applyRespectSafeAreaPreference];
#endif
  [self setCompositorGestureDeferralEnabled:YES];
  self.showingMachinesUI = NO;
#if TARGET_OS_TV
  if ([self.window.rootViewController
          isKindOfClass:[WWNCompositorHostViewController class]]) {
    WWNCompositorHostViewController *host =
        (WWNCompositorHostViewController *)self.window.rootViewController;
    host.interceptsMenuForSessionExit = YES;
    [host becomeFirstResponder];
  }
#elif TARGET_OS_VISION
  if ([self.window.rootViewController isKindOfClass:[WWNCompositorHostViewController class]]) {
    [self.window.rootViewController becomeFirstResponder];
  }
#endif
  // Force a layout pass so compositorContainer.bounds reflects the actual
  // screen dimensions before we push wl_output / host geometry to the
  // Wayland compositor. Client window sizes are negotiated via xdg_toplevel
  // (not launch --width/--height argv).
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
  self.clientTabsControl.hidden = YES;
#if !TARGET_OS_VISION
  [self applyRespectSafeAreaPreference];
#endif
#if TARGET_OS_TV
  if ([self.window.rootViewController
          isKindOfClass:[WWNCompositorHostViewController class]]) {
    WWNCompositorHostViewController *host =
        (WWNCompositorHostViewController *)self.window.rootViewController;
    host.interceptsMenuForSessionExit = NO;
    [host cancelTvMenuLongPress];
  }
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
          // iPadOS / visionOS multi-window (#120): this "Start"/"Connect"
          // callback fires on the PRIMARY scene the instant the user taps
          // Start, well before any dedicated client UIWindowScene exists.
          // When clients get their own dedicated scene, the primary
          // Machines scene must stay exactly as it is — unconditionally
          // hiding its Machines UI and revealing its (now-unused, empty)
          // compositorContainer here is exactly what turned the primary
          // window black and uninteractable. See the matching guards in
          // handleNativeClientWillLaunch: / handleClientFocusRequested:.
          if (![strongSelf clientsUseDedicatedScenes]) {
            [strongSelf hideMachinesUIAndRevealCompositor];
          }
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
