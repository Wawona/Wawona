#import "WWNSceneDelegate.h"
#import "../macos/ui/Settings/WWNPreferencesManager.h"
#if TARGET_OS_IPHONE
#import "../../platform/macos/WWNRootfsProvider.h"
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST && !TARGET_OS_TV && !TARGET_OS_WATCH && !TARGET_OS_VISION
#import "WWNWatchCompanionBridge.h"
#endif
#endif
#import "../macos/WWNCompositorBridge.h"
#import "../macos/ui/Settings/WWNPreferences.h"
#import "../macos/ui/Settings/WWNWaypipeRunner.h"
#import "../macos/ui/Machines/WWNMachinesCoordinator.h"
#import "../macos/ui/Machines/WWNMachineProfileStore.h"
#import "../macos/ui/Machines/WWNMachineSessionBridge.h"
#import "WWNCompositorBridge.h"
#import "WWNStartupLogViewController.h"
#import "WWNCompositorView_ios.h"
#import "WWNGameControllerManager.h"
#import "WWNModeBDesktop.h"
#if WWN_MODE_B
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
extern void iland_egl_set_metal_native_display(void *native);
#endif
#import "../../util/WWNLog.h"
#import "../../util/WWNStartupLogger.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>
#import <TargetConditionals.h>
#if __has_include("Wawona-Swift.h")
#import "Wawona-Swift.h"
#endif
/* Mode B tipa can ship a Wawona-Swift.h that does not export the SwiftUI
   tab chrome host. Talk to it through a protocol + runtime class lookup. */
@protocol WWNClientTabChromeHosting <NSObject>
@property(nonatomic, copy, nullable) void (^onSelectId)(uint64_t);
@property(nonatomic, copy, nullable) void (^onCloseId)(uint64_t);
@property(nonatomic, readonly, nullable) UIView *hostView;
@property(nonatomic, readonly) uint64_t selectedId;
- (void)attachTo:(UIView *)parentView;
- (void)setHidden:(BOOL)hidden;
- (void)reloadWithIds:(NSArray<NSNumber *> *)ids
               titles:(NSArray<NSString *> *)titles
           selectedId:(NSNumber *)selectedId;
- (void)reloadWithIds:(NSArray<NSNumber *> *)ids
               titles:(NSArray<NSString *> *)titles
           selectedId:(NSNumber *)selectedId
        previewImages:(NSDictionary<NSNumber *, UIImage *> *)previewImages;
@end
static inline Class WWNClientTabChromeControllerClass(void) {
  return NSClassFromString(@"WWNClientTabChromeController");
}

typedef NS_ENUM(NSInteger, WWNSessionExitTrigger) {
  WWNSessionExitTriggerShake = 0,
  WWNSessionExitTriggerSwipeBack,
  WWNSessionExitTriggerMenuOrEscape,
};

@interface WWNWelcomeViewController : UIViewController
@property(nonatomic, copy) dispatch_block_t onContinue;
@property(nonatomic, weak) UIButton *continueButton;
@end

@interface WWNSceneDelegate (PrimaryGeometry)
- (void)wwn_handleWindowSceneGeometryChange;
@end

@interface WWNCompositorHostViewController : UIViewController
@property(nonatomic, assign) BOOL defersSystemGesturesForCompositor;
/// visionOS Escape / legacy short-Menu session-exit hook.
@property(nonatomic, copy, nullable) dispatch_block_t onMenuOrEscapeDuringSession;
#if TARGET_OS_TV
/// Short Menu/Back: confirm leaving the session (easy exit from any client).
@property(nonatomic, copy, nullable) dispatch_block_t onTvMenuShortPressDuringSession;
/// Long-press Menu/Back and remote shake: confirm leave (same as iOS shake).
@property(nonatomic, copy, nullable) dispatch_block_t onTvMenuLongPressDuringSession;
/// When NO (Machines UI, keyboard, or exit alert), Menu is left to UIKit.
@property(nonatomic, assign) BOOL interceptsMenuForSessionExit;
- (void)cancelTvMenuLongPress;
- (void)wwn_tvMenuBegan;
- (void)wwn_tvMenuEnded;
- (void)wwn_tvMenuCancelled;
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
  // UIEvent shake is an iPhone/iPad device gesture. tvOS remotes do not
  // get a system shake event. 1st-gen Siri Remote shake is GCMotion.
  if (motion == UIEventSubtypeMotionShake && self.onShake) {
    self.onShake();
  }
}

@end


#if WWN_MODE_B
typedef NS_ENUM(NSInteger, WWNModeBHidRoute) {
  WWNModeBHidRouteGreeter = 0,
  WWNModeBHidRouteWestonDrm,
  WWNModeBHidRouteHostCompositor,
};

@interface WWNModeBDesktopInputView : UIView
@property(nonatomic, assign) CGSize displaySize;
@property(nonatomic, copy) void (^onMachineSelected)(NSInteger index);
@property(nonatomic, copy) void (^onHomeRequested)(void);
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) NSTimer *labPollTimer;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, assign) uint32_t tickCount;
@property(nonatomic, assign) BOOL sessionInputActive;
@property(nonatomic, assign) WWNModeBHidRoute hidRoute;
@property(nonatomic, assign) int32_t primaryTouchId;
@property(nonatomic, assign) NSInteger sessionTouchLogLeft;
@property(nonatomic, assign) BOOL sessionScrollActive;
@property(nonatomic, assign) CGPoint sessionScrollCenter;
- (void)startDisplayLink;
- (void)stopDisplayLink;
- (void)stopLabPoll;
- (void)enterSessionInputModeWithRoute:(WWNModeBHidRoute)route;
- (void)enterGreeterInputMode;
- (void)injectHidTouchId:(int32_t)touchId state:(int)state at:(CGPoint)viewPoint;
@end

static WWNCompositorView_ios *WWNModeBFindCompositor(UIView *root) {
  if ([root isKindOfClass:[WWNCompositorView_ios class]]) {
    return (WWNCompositorView_ios *)root;
  }
  for (UIView *child in root.subviews) {
    WWNCompositorView_ios *found = WWNModeBFindCompositor(child);
    if (found) {
      return found;
    }
  }
  return nil;
}

@implementation WWNModeBDesktopInputView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.opaque = YES;
    self.multipleTouchEnabled = YES;
    self.exclusiveTouch = YES;
    self.userInteractionEnabled = YES;
    self.hidRoute = WWNModeBHidRouteGreeter;
    self.sessionTouchLogLeft = 8;
    self.backgroundColor = [UIColor colorWithRed:0x10 / 255.0
                                           green:0x17 / 255.0
                                            blue:0x24 / 255.0
                                           alpha:1.0];
    self.layer.contentsGravity = kCAGravityResize;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.numberOfLines = 2;
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont monospacedSystemFontOfSize:22
                                             weight:UIFontWeightBold];
    title.text = @"WAWONA MACHINES\nMODE B OWN DISPLAY";
    [self addSubview:title];
    self.titleLabel = title;
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectZero];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.numberOfLines = 2;
    status.textColor = UIColor.whiteColor;
    status.font = [UIFont monospacedSystemFontOfSize:11
                                              weight:UIFontWeightMedium];
    status.text = @"MODE B IOMFB starting";
    [self addSubview:status];
    self.statusLabel = status;
    [NSLayoutConstraint activateConstraints:@[
      [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                          constant:36],
      [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                           constant:-36],
      [title.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor
                                      constant:36],
      [status.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                           constant:12],
      [status.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                            constant:-12],
      [status.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor
                                          constant:-8],
    ]];
    [self startDisplayLink];
    [self startLabPoll];
  }
  return self;
}

- (void)startLabPoll {
  if (self.labPollTimer) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  self.labPollTimer = [NSTimer timerWithTimeInterval:0.2
                                              repeats:YES
                                                block:^(NSTimer *timer) {
                                                  (void)timer;
                                                  [weakSelf pollLabSelect];
                                                }];
  [[NSRunLoop mainRunLoop] addTimer:self.labPollTimer
                            forMode:NSRunLoopCommonModes];
}

- (void)stopLabPoll {
  [self.labPollTimer invalidate];
  self.labPollTimer = nil;
}

- (void)pollLabSelect {
  // CADisplayLink pauses once IOMFB owns the panel (UIKit view is covered).
  // The lab select file must still be consumed or Weston/Niri/VM never start.
  // Session (phase >= 2) still reads `home` so we can leave without killing
  // IOMFB via SpringBoard (that path is scene background, not this file).
  uint32_t phase = wwn_modeb_desktop_phase();
  if (phase >= 2) {
    [self consumeLabSelectFile];
    return;
  }
  if (phase == 1) {
    [self consumeLabSelectFile];
    wwn_modeb_desktop_refresh();
  }
}

- (void)startDisplayLink {
  if (self.displayLink) return;
  self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                 selector:@selector(tickGreeter:)];
  self.displayLink.preferredFramesPerSecond = 30;
  [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop
                         forMode:NSRunLoopCommonModes];
  [self startLabPoll];
}

- (void)stopDisplayLink {
  [self.displayLink invalidate];
  self.displayLink = nil;
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  if (self.window) {
    [self startDisplayLink];
  } else {
    [self stopDisplayLink];
  }
}

- (void)consumeLabSelectFile {
  // vphone sock HID stays with SpringBoard while IOMFB owns the panel.
  // Guest `echo 0 >/tmp/wwn-modeb-select` (or weston/niri) starts a card.
  NSString *path = @"/tmp/wwn-modeb-select";
  NSString *body =
      [NSString stringWithContentsOfFile:path
                                encoding:NSUTF8StringEncoding
                                   error:nil];
  if (body.length == 0) {
    return;
  }
  NSString *token =
      [body stringByTrimmingCharactersInSet:NSCharacterSet
                                                .whitespaceAndNewlineCharacterSet]
          .lowercaseString;
  /* Named tokens belong to SceneDelegate consumeModeBLabSelectFile, which
     resolves the real profile. Hardcoded weston=0 niri=1 vm=2 does not
     match the painted card order (Weston, JIT VM, Default, ...). */
  if ([token isEqualToString:@"weston"] || [token isEqualToString:@"niri"] ||
      [token isEqualToString:@"vm"] ||
      [token isEqualToString:@"virtual_machine"] ||
      [token isEqualToString:@"container"] ||
      [token isEqualToString:@"replace"] || [token isEqualToString:@"engage"]) {
    return;
  }
  [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
  if ([token isEqualToString:@"home"] || [token isEqualToString:@"greeter"]) {
    WWNLog("MODEB", @"lab select file token=%@ (return to greeter)", token);
    if (self.onHomeRequested) {
      self.onHomeRequested();
    }
    return;
  }
  if (wwn_modeb_desktop_phase() >= 2) {
    return;
  }
  NSInteger index = token.integerValue;
  if (index < 0) {
    return;
  }
  float x = (float)(self.displaySize.width * 0.5);
  float y = 150.f + 38.f + (float)index * 94.f;
  WWNLog("MODEB", @"lab select file token=%@ index=%ld at %.0f,%.0f", token,
         (long)index, x, y);
  int32_t selection = wwn_modeb_desktop_handle_touch(x, y, 1);
  if (selection > 0 && self.onMachineSelected) {
    [self stopDisplayLink];
    self.onMachineSelected(selection - 1);
  }
}

- (void)enterSessionInputModeWithRoute:(WWNModeBHidRoute)route {
  self.sessionInputActive = YES;
  self.hidRoute = route;
  self.opaque = NO;
  self.backgroundColor = UIColor.clearColor;
  self.layer.contents = nil;
  self.titleLabel.hidden = YES;
  self.statusLabel.hidden = YES;
  self.userInteractionEnabled = YES;
  self.multipleTouchEnabled = YES;
  // Do not exclusiveTouch: Safari-style tab chrome sits above this overlay
  // and must receive square.on.square / overview hits.
  self.exclusiveTouch = NO;
  self.primaryTouchId = 0;
  self.sessionTouchLogLeft = 8;
  self.sessionScrollActive = NO;
  [self.superview bringSubviewToFront:self];
  [self startLabPoll];
  WWNLog("MODEB", @"IOMFB HID overlay session route=%ld (keep hit target)",
         (long)route);
}

- (void)enterGreeterInputMode {
  self.sessionInputActive = NO;
  self.hidRoute = WWNModeBHidRouteGreeter;
  self.opaque = YES;
  self.backgroundColor = [UIColor colorWithRed:0x10 / 255.0
                                         green:0x17 / 255.0
                                          blue:0x24 / 255.0
                                         alpha:1.0];
  self.titleLabel.hidden = NO;
  self.statusLabel.hidden = NO;
  self.userInteractionEnabled = YES;
  self.multipleTouchEnabled = YES;
  self.primaryTouchId = 0;
  [self.superview bringSubviewToFront:self];
  [self startDisplayLink];
}

- (CGPoint)westonLogicalPointForViewPoint:(CGPoint)point {
  uint32_t logicalW = 0;
  uint32_t logicalH = 0;
  if (wwn_weston_logical_size) {
    wwn_weston_logical_size(&logicalW, &logicalH);
  }
  if (logicalW == 0 || logicalH == 0) {
    CGFloat scale = self.window.screen.scale;
    if (scale < 1.0) {
      scale = 1.0;
    }
    if (self.displaySize.width > 0 && self.displaySize.height > 0) {
      logicalW = (uint32_t)lround(self.displaySize.width / scale);
      logicalH = (uint32_t)lround(self.displaySize.height / scale);
    }
  }
  CGFloat vw = self.bounds.size.width;
  CGFloat vh = self.bounds.size.height;
  if (logicalW == 0 || logicalH == 0 || vw <= 0 || vh <= 0) {
    return point;
  }
  return CGPointMake(point.x * (CGFloat)logicalW / vw,
                     point.y * (CGFloat)logicalH / vh);
}

- (void)injectWestonTouches:(NSSet<UITouch *> *)touches
                      state:(int)state
                      event:(UIEvent *)event {
  (void)event;
  if (!wwn_weston_inject_touch) {
    return;
  }
  for (UITouch *touch in touches) {
    CGPoint loc = [self westonLogicalPointForViewPoint:[touch locationInView:self]];
    int32_t touchId = (int32_t)touch.hash;
    wwn_weston_inject_touch(touchId, state, loc.x, loc.y);
    if (wwn_weston_inject_pointer && touchId == self.primaryTouchId) {
      wwn_weston_inject_pointer(state, loc.x, loc.y);
    }
    if (self.sessionTouchLogLeft > 0) {
      self.sessionTouchLogLeft -= 1;
      WWNLog("MODEB", @"weston-drm touch id=%d state=%d %.1f,%.1f left=%ld",
             (int)touchId, state, loc.x, loc.y, (long)self.sessionTouchLogLeft);
    }
  }
}

- (void)dispatchSessionTouches:(NSSet<UITouch *> *)touches
                         state:(int)state
                         event:(UIEvent *)event {
  BOOL westonLive =
      wwn_weston_input_ready && wwn_weston_input_ready() != 0 &&
      wwn_weston_inject_touch;
  if (self.hidRoute == WWNModeBHidRouteWestonDrm || westonLive) {
    if (!westonLive) {
      if (self.sessionTouchLogLeft > 0) {
        self.sessionTouchLogLeft -= 1;
        WWNLog("MODEB", @"weston-drm touch wait (seat not ready) state=%d",
               state);
      }
      return;
    }
    [self injectWestonTouches:touches state:state event:event];
    return;
  }
  UIView *root = self.window.rootViewController.view;
  WWNCompositorView_ios *surface = WWNModeBFindCompositor(root);
  if (!surface) {
    surface = WWNModeBFindCompositor(self.window);
  }
  if (surface) {
    if (self.sessionTouchLogLeft > 0) {
      self.sessionTouchLogLeft -= 1;
      CGPoint p = [touches.anyObject locationInView:self];
      WWNLog("MODEB", @"host-compositor touch state=%d %.0f,%.0f left=%ld",
             state, p.x, p.y, (long)self.sessionTouchLogLeft);
    }
    [surface wwnForwardOverlayTouches:touches
                                state:state
                                event:event
                             fromView:self];
    return;
  }
  if (self.sessionTouchLogLeft > 0) {
    self.sessionTouchLogLeft -= 1;
    WWNLog("MODEB", @"session touch dropped (no weston seat, no host view)");
  }
}

- (void)tickGreeter:(CADisplayLink *)link {
  (void)link;
  uint32_t phase = wwn_modeb_desktop_phase();
  if (self.sessionInputActive) {
    self.titleLabel.hidden = YES;
    self.statusLabel.hidden = YES;
    self.layer.contents = nil;
    if (phase >= 2) {
      [self consumeLabSelectFile];
    }
    return;
  }
  if (phase == 1) {
    [self consumeLabSelectFile];
  }
  if (phase != 1) {
    self.titleLabel.hidden = NO;
    self.layer.contents = nil;
    self.tickCount += 1;
    if ((self.tickCount % 30) == 1) {
      self.statusLabel.text =
          @"MODE B UIKit greeter  IOMFB idle (wait for foreground)";
      WWNLog("MODEB", @"greeter idle tick=%u phase=%u", self.tickCount, phase);
    }
    return;
  }
  int32_t refresh = wwn_modeb_desktop_refresh();
  void *surface = NULL;
  uint32_t surfaceId = 0;
  uint32_t width = 0;
  uint32_t height = 0;
  int32_t front = wwn_modeb_desktop_front_surface(&surface, &surfaceId, &width,
                                                  &height);
  if (front == 0 && surface) {
    self.layer.contents = (__bridge id)(IOSurfaceRef)surface;
    self.titleLabel.hidden = YES;
  } else {
    self.layer.contents = nil;
    self.titleLabel.hidden = NO;
  }
  self.tickCount += 1;
  if ((self.tickCount % 30) == 1) {
    int32_t present = wwn_modeb_desktop_last_present();
    self.statusLabel.text = [NSString
        stringWithFormat:
            @"MODE B IOMFB %ux%u  present=%d refresh=%d  backing=%u",
            width, height, present, refresh, surfaceId];
    WWNLog("MODEB",
           @"greeter latch tick=%u present=%d refresh=%d backing=%u %ux%u",
           self.tickCount, present, refresh, surfaceId, width, height);
  }
}

- (void)finishTouch:(UITouch *)touch ended:(BOOL)ended {
  if (self.bounds.size.width <= 0 || self.bounds.size.height <= 0) return;
  CGPoint point = [touch locationInView:self];
  float x = point.x * self.displaySize.width / self.bounds.size.width;
  float y = point.y * self.displaySize.height / self.bounds.size.height;
  int32_t selection = wwn_modeb_desktop_handle_touch(x, y, ended ? 1 : 0);
  if (selection > 0 && self.onMachineSelected) {
    [self stopDisplayLink];
    self.onMachineSelected(selection - 1);
  }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (self.sessionInputActive) {
    if (self.primaryTouchId == 0) {
      self.primaryTouchId = (int32_t)touches.anyObject.hash;
    }
    [self dispatchSessionTouches:touches state:1 event:event];
    return;
  }
  [self finishTouch:touches.anyObject ended:NO];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (!self.sessionInputActive) {
    return;
  }
  NSInteger fingerCount = (NSInteger)[[event touchesForView:self] count];
  if (fingerCount >= 2 && wwn_weston_inject_axis &&
      (self.hidRoute == WWNModeBHidRouteWestonDrm ||
       (wwn_weston_input_ready && wwn_weston_input_ready()))) {
    CGFloat sumX = 0;
    CGFloat sumY = 0;
    NSUInteger n = 0;
    for (UITouch *touch in [event touchesForView:self]) {
      if (touch.phase == UITouchPhaseEnded ||
          touch.phase == UITouchPhaseCancelled) {
        continue;
      }
      CGPoint loc = [self westonLogicalPointForViewPoint:[touch locationInView:self]];
      sumX += loc.x;
      sumY += loc.y;
      n += 1;
    }
    if (n >= 2) {
      CGPoint center = CGPointMake(sumX / (CGFloat)n, sumY / (CGFloat)n);
      if (!self.sessionScrollActive) {
        self.sessionScrollActive = YES;
        self.sessionScrollCenter = center;
      } else {
        CGFloat dy = center.y - self.sessionScrollCenter.y;
        CGFloat dx = center.x - self.sessionScrollCenter.x;
        self.sessionScrollCenter = center;
        if (fabs(dy) > 0.5) {
          wwn_weston_inject_axis(0, (double)-dy);
        }
        if (fabs(dx) > 0.5) {
          wwn_weston_inject_axis(1, (double)-dx);
        }
      }
    }
  } else {
    self.sessionScrollActive = NO;
  }
  [self dispatchSessionTouches:touches state:2 event:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (self.sessionInputActive) {
    [self dispatchSessionTouches:touches state:0 event:event];
    NSInteger left =
        (NSInteger)[[event touchesForView:self] count] - (NSInteger)touches.count;
    if (left <= 0) {
      self.primaryTouchId = 0;
      self.sessionScrollActive = NO;
    }
    return;
  }
  [self finishTouch:touches.anyObject ended:YES];
}

- (void)injectHidTouchId:(int32_t)touchId state:(int)state at:(CGPoint)viewPoint {
  if (self.sessionInputActive) {
    BOOL westonLive =
        wwn_weston_input_ready && wwn_weston_input_ready() != 0 &&
        wwn_weston_inject_touch;
    if (self.hidRoute == WWNModeBHidRouteWestonDrm || westonLive) {
      if (!westonLive || !wwn_weston_inject_touch) {
        return;
      }
      CGPoint loc = [self westonLogicalPointForViewPoint:viewPoint];
      if (state == 1 && self.primaryTouchId == 0) {
        self.primaryTouchId = touchId;
      }
      wwn_weston_inject_touch(touchId, state, loc.x, loc.y);
      if (wwn_weston_inject_pointer &&
          (touchId == self.primaryTouchId || self.primaryTouchId == 0)) {
        wwn_weston_inject_pointer(state, loc.x, loc.y);
      }
      if (state == 0 && touchId == self.primaryTouchId) {
        self.primaryTouchId = 0;
      }
      return;
    }
    UIView *root = self.window.rootViewController.view;
    WWNCompositorView_ios *surface = WWNModeBFindCompositor(root);
    if (!surface) {
      surface = WWNModeBFindCompositor(self.window);
    }
    if (surface) {
      [surface wwnInjectHidTouchId:touchId state:state viewPoint:viewPoint];
    }
    return;
  }
  if (self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
    return;
  }
  float x = (float)(viewPoint.x * self.displaySize.width / self.bounds.size.width);
  float y = (float)(viewPoint.y * self.displaySize.height / self.bounds.size.height);
  int32_t selection = wwn_modeb_desktop_handle_touch(x, y, state == 0 ? 1 : 0);
  if (selection > 0 && self.onMachineSelected) {
    [self stopDisplayLink];
    self.onMachineSelected(selection - 1);
  }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (!self.sessionInputActive) {
    return;
  }
  if (wwn_weston_input_ready && wwn_weston_input_ready() &&
      wwn_weston_inject_touch_cancel) {
    wwn_weston_inject_touch_cancel();
  } else {
    [self dispatchSessionTouches:touches state:3 event:event];
  }
  self.primaryTouchId = 0;
  self.sessionScrollActive = NO;
}

- (void)dealloc {
  [self stopLabPoll];
  [self stopDisplayLink];
}

@end
#endif

#if TARGET_OS_TV
static WWNCompositorView_ios *WWNFindCompositorSurface(UIView *root) {
  if ([root isKindOfClass:[WWNCompositorView_ios class]]) {
    return (WWNCompositorView_ios *)root;
  }
  for (UIView *child in root.subviews) {
    WWNCompositorView_ios *found = WWNFindCompositorSurface(child);
    if (found != nil) {
      return found;
    }
  }
  return nil;
}
#endif

@implementation WWNCompositorHostViewController {
#if TARGET_OS_TV
  NSTimer *_tvMenuLongPressTimer;
  BOOL _tvMenuLongPressFired;
#endif
}

#if !TARGET_OS_TV
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
#if WWN_MODE_B
  if (self.defersSystemGesturesForCompositor) {
    return UIRectEdgeAll;
  }
#endif
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

- (void)viewDidLoad {
  [super viewDidLoad];
#if !TARGET_OS_TV
  if (@available(iOS 17.0, visionOS 1.0, *)) {
    __weak typeof(self) weakSelf = self;
    [self registerForTraitChanges:@[
      [UITraitHorizontalSizeClass class],
      [UITraitVerticalSizeClass class]
    ]
                      withHandler:^(__kindof id<UITraitEnvironment> traitEnvironment,
                                    UITraitCollection *previousCollection) {
      (void)traitEnvironment;
      (void)previousCollection;
      [weakSelf wwn_notifyPrimarySceneGeometry];
    }];
  }
#endif
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self wwn_notifyPrimarySceneGeometry];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  (void)size;
  __weak typeof(self) weakSelf = self;
  [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
    (void)ctx;
    [weakSelf wwn_notifyPrimarySceneGeometry];
  }
      completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        (void)ctx;
        [weakSelf wwn_notifyPrimarySceneGeometry];
      }];
}

- (void)wwn_notifyPrimarySceneGeometry {
  UIWindow *window = self.view.window;
  id delegate = window.windowScene.delegate;
  if ([delegate isKindOfClass:[WWNSceneDelegate class]]) {
    [(WWNSceneDelegate *)delegate wwn_handleWindowSceneGeometryChange];
  }
}

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
/// Deliberate hold. Also used for 1st-gen remote shake. Short Menu confirms exit.
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

- (void)wwn_tvMenuBegan {
  if (!self.interceptsMenuForSessionExit) {
    return;
  }
  _tvMenuLongPressFired = NO;
  [self _cancelTvMenuLongPressTimer];
  __weak typeof(self) weakSelf = self;
  _tvMenuLongPressTimer =
      [NSTimer timerWithTimeInterval:kWWNTvMenuLongPressDuration
                              repeats:NO
                                block:^(__unused NSTimer *t) {
                                  __strong typeof(weakSelf) strongSelf = weakSelf;
                                  [strongSelf _tvMenuLongPressFired:t];
                                }];
  [[NSRunLoop mainRunLoop] addTimer:_tvMenuLongPressTimer
                            forMode:NSRunLoopCommonModes];
}

- (void)wwn_tvMenuEnded {
  if (!self.interceptsMenuForSessionExit) {
    return;
  }
  BOOL fired = _tvMenuLongPressFired;
  [self _cancelTvMenuLongPressTimer];
  _tvMenuLongPressFired = NO;
  if (!fired && self.onTvMenuShortPressDuringSession) {
    self.onTvMenuShortPressDuringSession();
  }
}

- (void)wwn_tvMenuCancelled {
  [self _cancelTvMenuLongPressTimer];
  _tvMenuLongPressFired = NO;
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  if (self.interceptsMenuForSessionExit && [self _setContainsMenuPress:presses]) {
    [self wwn_tvMenuBegan];
    return;
  }
  [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  if (self.interceptsMenuForSessionExit && [self _setContainsMenuPress:presses]) {
    [self wwn_tvMenuEnded];
    return;
  }
  [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  if (self.interceptsMenuForSessionExit && [self _setContainsMenuPress:presses]) {
    [self wwn_tvMenuCancelled];
    return;
  }
  [super pressesCancelled:presses withEvent:event];
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
  if (self.interceptsMenuForSessionExit) {
    WWNCompositorView_ios *surface = WWNFindCompositorSurface(self.view);
    if (surface != nil) {
      return @[ surface ];
    }
  }
  return [super preferredFocusEnvironments];
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
// other client's window. Report layout-driven size changes (Stage Manager
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
// the final target size, so use it as a backstop. Without it, a resize that
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
  // Keep Continue as its own a11y node. XCTest otherwise collapses the modal
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
    [card.widthAnchor constraintEqualToConstant:
#if TARGET_OS_TV
                          720.0
#else
                          340.0
#endif
    ],

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
/// Last reported output size. Used to skip redundant updates.
@property(nonatomic, assign) CGSize lastOutputSize;
/// Re-entrancy guard for rotate / layout geometry pushes.
@property(nonatomic, assign) BOOL applyingSceneGeometry;
/// Last reported output scale. Used with size to skip redundant updates.
@property(nonatomic, assign) float lastOutputScale;
/// Host IME overlap (points) reported by WWNCompositorView_ios.
@property(nonatomic, assign) CGFloat hostKeyboardOverlap;
/// Wawona accessory bar reserve (points) for wl_output shrink.
@property(nonatomic, assign) CGFloat hostKeyboardAccessoryHeight;
/// Soft-keyboard geometry says hardware keyboard is active (no IME resize).
@property(nonatomic, assign) BOOL hostHardwareKeyboardActive;
/// Last applied Respect Safe Area value. Used to skip redundant logs.
@property(nonatomic, assign) BOOL lastRespectSafeArea;
@property(nonatomic, assign) BOOL hasAppliedSafeArea;
@property(nonatomic, assign) BOOL showingMachinesUI;
@property(nonatomic, strong) UIViewController *machinesViewController;
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *machinesViewConstraints;
@property(nonatomic, assign) CFTimeInterval lastShakePromptTime;
@property(nonatomic, assign) BOOL sessionExitPromptVisible;
#if WWN_MODE_B
@property(nonatomic, copy) NSArray<WWNMachineProfile *> *modeBProfiles;
@property(nonatomic, assign) BOOL modeBDesktopActive;
@property(nonatomic, assign) BOOL modeBSessionStarting;
@property(nonatomic, assign) BOOL modeBSessionLive;
@property(nonatomic, assign) UIBackgroundTaskIdentifier modeBOwnDisplayTask;
@property(nonatomic, strong) UIView *modeBFailureView;
@property(nonatomic, strong) NSTimer *modeBLabPollTimer;
@property(nonatomic, strong) dispatch_source_t modeBLabPollSource;
@property(nonatomic, strong) WWNModeBDesktopInputView *modeBGreeterView;
- (BOOL)engageModeBDesktopReplacement;
- (void)pushModeBProfilesToGreeter;
- (void)showModeBGreeterPicker;
- (void)hideModeBGreeterPicker;
- (void)applyModeBSessionChrome;
- (BOOL)startModeBMachineProfile:(WWNMachineProfile *)profile;
- (void)leaveModeBDesktopToMachines;
- (void)restoreModeBIOMFBForLeaveWithReason:(NSString *)reason;
- (void)dismissModeBHostChrome;
- (BOOL)modeBOwnDisplayEngaged;
- (void)recoverModeBGreeterAfterSession;
- (void)holdModeBOwnDisplayBackgroundTask;
- (void)endModeBOwnDisplayBackgroundTask;
- (void)startModeBLabPoll;
- (void)stopModeBLabPoll;
- (void)consumeModeBLabSelectFile;
- (void)handleModeBHidTouchId:(int32_t)touchId
                        state:(int)state
                           at:(CGPoint)viewPoint;
#endif
#if !TARGET_OS_VISION && !TARGET_OS_TV
@property(nonatomic, strong) UIScreenEdgePanGestureRecognizer *backSwipeGesture;
#endif
/// Startup log overlay shown during the Machines → compositor transition.
@property(nonatomic, strong, nullable) WWNStartupLogViewController *startupLogVC;
/// In-window client tabs (issue #84); shown for any live Wayland client so
/// the last tab still has a Safari-style close.
@property(nonatomic, strong, nullable) id<WWNClientTabChromeHosting> clientTabsControl;
/// Window ids parallel to clientTabsControl chips (Wayland clients only).
@property(nonatomic, copy, nullable) NSArray<NSNumber *> *clientTabWindowIds;
- (BOOL)usesClientTabChrome;
- (void)refreshClientTabs;
- (void)raiseClientTabChrome;
- (void)clientTabSelectWindowId:(uint64_t)target;
- (void)clientTabCloseWindowId:(uint64_t)target;
- (NSArray<NSString *> *)clientTabTitles;
/// iPadOS / visionOS multi-window (#120): when this scene delegate hosts a
/// single Wayland client in its own UIWindowScene, the client's window id
/// (0 = primary Machines scene). Used to tear the client down on disconnect.
@property(nonatomic, assign) uint64_t hostedClientWindowId;
- (void)updateOutputSizeFromRect:(CGRect)bounds forced:(BOOL)forced;
@end

@implementation WWNSceneDelegate

#if WWN_MODE_B
static __weak WWNSceneDelegate *sModeBDesktopScene = nil;

static void WWNModeBHidSinkTrampoline(int32_t touchId, int state, double viewX,
                                      double viewY) {
  [sModeBDesktopScene handleModeBHidTouchId:touchId
                                      state:state
                                         at:CGPointMake(viewX, viewY)];
}

static void WWNModeBLabLog(NSString *fmt, ...) {
  FILE *f = fopen("/tmp/wwn-modeb-scene.log", "a");
  if (!f) {
    return;
  }
  va_list args;
  va_start(args, fmt);
  NSString *line = [[NSString alloc] initWithFormat:fmt arguments:args];
  va_end(args);
  fprintf(f, "%s\n", line.UTF8String);
  fclose(f);
}

static void WWNModeBLabDumpLogRing(const char *why) {
  FILE *f = fopen("/tmp/wwn-modeb-scene.log", "a");
  if (!f) {
    return;
  }
  fprintf(f, "---- log-ring %s ----\n", why ? why : "");
  char *dump = wwn_log_ring_dump(NULL);
  if (dump && dump[0]) {
    fputs(dump, f);
    if (dump[strlen(dump) - 1] != '\n') {
      fputc('\n', f);
    }
  }
  if (dump) {
    WWNStringFree(dump);
  }
  fclose(f);
}

static WWNMachineProfile *WWNModeBNativeClientProfile(NSString *name,
                                                      NSString *clientId) {
  WWNMachineProfile *profile = [WWNMachineProfile defaultProfile];
  profile.name = name;
  BOOL weston = [clientId isEqualToString:@"weston"];
  BOOL niri = [clientId isEqualToString:@"niri"];
  profile.settingsOverrides = @{
    @"NativeClientId" : clientId,
    @"EnableLauncher" : @YES,
    @"WestonEnabled" : @(weston),
    @"NiriEnabled" : @(niri),
    @"WestonTerminalEnabled" : @NO,
    @"WestonSimpleSHMEnabled" : @NO,
    @"FootEnabled" : @NO,
  };
  profile.runtimeOverrides = @{
    @"bundledAppID" : clientId,
    @"useBundledApp" : @YES,
  };
  return profile;
}

static WWNMachineProfile *WWNModeBTypedProfile(NSString *name, NSString *type) {
  WWNMachineProfile *profile = [WWNMachineProfile defaultProfile];
  profile.name = name;
  profile.type = type;
  profile.settingsOverrides = @{};
  profile.runtimeOverrides = @{};
  return profile;
}

static NSArray<WWNMachineProfile *> *WWNModeBEnsureCompositorProfiles(
    NSArray<WWNMachineProfile *> *loaded) {
  BOOL hasWeston = NO;
  BOOL hasNiri = NO;
  BOOL hasVm = NO;
  BOOL hasContainer = NO;
  BOOL hasWasm = NO;
  for (WWNMachineProfile *profile in loaded) {
    NSString *cid =
        [profile.settingsOverrides[@"NativeClientId"] isKindOfClass:[NSString class]]
            ? profile.settingsOverrides[@"NativeClientId"]
            : @"";
    NSString *rid =
        [profile.runtimeOverrides[@"bundledAppID"] isKindOfClass:[NSString class]]
            ? profile.runtimeOverrides[@"bundledAppID"]
            : @"";
    NSString *name = profile.name.lowercaseString;
    NSString *type = profile.type.lowercaseString;
    if ([cid isEqualToString:@"weston"] || [rid isEqualToString:@"weston"] ||
        [name isEqualToString:@"weston"]) {
      hasWeston = YES;
    }
    if ([cid isEqualToString:@"niri"] || [rid isEqualToString:@"niri"] ||
        [name isEqualToString:@"niri"]) {
      hasNiri = YES;
    }
    if ([type isEqualToString:kWWNMachineTypeVirtualMachine] ||
        [name containsString:@"virtual"]) {
      hasVm = YES;
    }
    if ([type isEqualToString:kWWNMachineTypeContainer] ||
        [name containsString:@"container"]) {
      hasContainer = YES;
    }
    if ([type isEqualToString:kWWNMachineTypeWasm] ||
        [cid isEqualToString:@"wawona-wasm"] ||
        [rid isEqualToString:@"hello-wasi-gui"] ||
        [rid isEqualToString:@"wawona-wasm"] ||
        [name containsString:@"wasm"] ||
        [name containsString:@"wasi"]) {
      hasWasm = YES;
    }
  }
  NSMutableArray<WWNMachineProfile *> *out = [NSMutableArray array];
  if (!hasWeston) {
    [out addObject:WWNModeBNativeClientProfile(@"Weston", @"weston")];
  }
  if (!hasNiri) {
    [out addObject:WWNModeBNativeClientProfile(@"Niri", @"niri")];
  }
  if (!hasVm) {
    [out addObject:WWNModeBTypedProfile(@"JIT Virtual Machine",
                                       kWWNMachineTypeVirtualMachine)];
  }
  if (!hasContainer) {
    [out addObject:WWNModeBTypedProfile(@"JIT Container in VM",
                                       kWWNMachineTypeContainer)];
  }
  if (!hasWasm) {
    WWNMachineProfile *wasm = WWNModeBTypedProfile(@"hello-wasi-gui",
                                                  kWWNMachineTypeWasm);
    wasm.runtimeOverrides = @{
      @"bundledAppID" : @"hello-wasi-gui",
      @"wasmCommand" : @"wasm hello-wasi-gui",
      @"useBundledApp" : @YES,
    };
    [out addObject:wasm];
  }
  if (loaded.count > 0) {
    [out addObjectsFromArray:loaded];
  }
  return out;
}

static WWNMachineProfile *WWNModeBProfileForSession(NSArray<WWNMachineProfile *> *profiles,
                                                    uint8_t kind,
                                                    NSString *label) {
  for (WWNMachineProfile *profile in profiles) {
    if (label.length > 0 &&
        ([profile.name caseInsensitiveCompare:label] == NSOrderedSame ||
         [profile.machineId caseInsensitiveCompare:label] == NSOrderedSame)) {
      return profile;
    }
  }
  for (WWNMachineProfile *profile in profiles) {
    if (kind == 3 &&
        [profile.type isEqualToString:kWWNMachineTypeVirtualMachine]) {
      return profile;
    }
    if (kind == 4 && [profile.type isEqualToString:kWWNMachineTypeContainer]) {
      return profile;
    }
    if (kind == 5) {
      NSString *name = profile.name.lowercaseString;
      if ([name containsString:@"weston"] || [name containsString:@"niri"]) {
        return profile;
      }
    }
  }
  return nil;
}

static int32_t WWNModeBPresentLogicalSession(uint32_t sessionId, uint8_t kind,
                                             const char *label) {
  WWNSceneDelegate *scene = sModeBDesktopScene;
  [WWNMachineSessionBridge stopAllActiveTransports];
  if (kind == 0 || sessionId == 0) {
    [scene leaveModeBDesktopToMachines];
    return 0;
  }
  if (kind == 1) {
    return 0;
  }
  NSString *want = label ? [NSString stringWithUTF8String:label] : @"";
  WWNMachineProfile *profile =
      WWNModeBProfileForSession(scene.modeBProfiles, kind, want);
  if (!profile || ![scene startModeBMachineProfile:profile]) {
    return -1;
  }
  [scene applyModeBSessionChrome];
  return 0;
}
#endif

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

  // Wire the resize callback BEFORE the view is loaded/added to any window -
  // loadView/viewDidLoad below and the rootViewController assignment can
  // trigger the first layout pass, and we don't want that first (correct)
  // size to be silently swallowed by a nil callback.
  //
  // This window's size is driven exclusively by its own dedicated scene -
  // never by the primary Machines scene's shared output (#120). Push a
  // per-window resize on every layout/transition change (Stage Manager
  // drag, Split View, rotation, …) instead of the shared
  // setOutputWidth:height:scale:.
  //
  // OWL / SizeAuthority gate: mirrors WWNCompositorView_ios.layoutSubviews'
  // mayInjectHostSize (hostLocked || followHostSize). clientView (the actual
  // WWNCompositorView_ios) is a flex-resizing subview of this controller's
  // view, so its own layoutSubviews already independently observes this same
  // bounds change and applies the identical gate. Without this check here
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
  // Files-app layout is phone/pad/vision only. TV has no Files browser.
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
  // an NSUserActivity. Host ONLY that client's view in this scene. Do not
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
  shakeWindow.onShake = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf handleShakeGesture];
  };
  self.window = shakeWindow;
  self.window.backgroundColor = [UIColor blackColor];

  // Root view controller. Fills the full screen
  WWNCompositorHostViewController *rootViewController =
      [[WWNCompositorHostViewController alloc] init];
  rootViewController.defersSystemGesturesForCompositor = NO;
#if TARGET_OS_TV
  // Menu always confirms leaving the session. Nested clients can Send Escape
  // from the alert. Long-press Menu and remote shake use the same confirm.
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
  NSNotificationCenter *tvNc = [NSNotificationCenter defaultCenter];
  [tvNc addObserver:self
           selector:@selector(_tvRemoteMenuBegan:)
               name:WWNTvRemoteMenuBeganNotification
             object:nil];
  [tvNc addObserver:self
           selector:@selector(_tvRemoteMenuEnded:)
               name:WWNTvRemoteMenuEndedNotification
             object:nil];
  [tvNc addObserver:self
           selector:@selector(_tvRemoteMenuCancelled:)
               name:WWNTvRemoteMenuCancelledNotification
             object:nil];
  [tvNc addObserver:self
           selector:@selector(_tvRemoteShake:)
               name:WWNTvRemoteShakeNotification
             object:nil];
  [tvNc addObserver:self
           selector:@selector(_tvRequestSessionExit:)
               name:WWNTvRequestSessionExitNotification
             object:nil];
  [tvNc addObserver:self
           selector:@selector(_tvKeyboardFocusDidChange:)
               name:WWNTvKeyboardFocusDidChangeNotification
             object:nil];
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

  // Compositor container. An intermediate view whose bounds
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
#if WWN_MODE_B
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleModeBDesktopReplacementChanged:)
             name:kWWNModeBDesktopReplacementChangedNotification
           object:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleModeBDesktopReplacementReplaceNow:)
             name:kWWNModeBDesktopReplacementReplaceNowNotification
           object:nil];
#endif

  WWNLog("SCENE", @"Wawona Scene connected and window created.");
#if WWN_MODE_B
  // Lab select must work from Welcome / Machines, not only after IOMFB
  // engage. Build 17 left /tmp/wwn-modeb-select unconsumed until Replace now.
  [self startModeBLabPoll];
  WWNModeBLabLog(@"scene connected lab-poll=1");
#endif

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

#if WWN_MODE_B
- (void)showModeBDesktopFailureWithCode:(int32_t)code {
  const char *raw = wwn_modeb_desktop_last_error();
  NSString *detail =
      raw && raw[0] ? [NSString stringWithUTF8String:raw] : @"Unknown IOMFB error";
  UIViewController *host = self.window.rootViewController;
  if (!host) {
    return;
  }
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Desktop Replacement failed"
                       message:[NSString stringWithFormat:@"%@ (error %d)",
                                                          detail, code]
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
  [host presentViewController:alert animated:YES completion:nil];
}

- (BOOL)modeBOwnDisplayEngaged {
  return self.modeBDesktopActive &&
         (self.modeBSessionStarting || self.modeBSessionLive ||
          wwn_modeb_desktop_phase() >= 1);
}

- (void)dismissModeBHostChrome {
  /* Settings is a sheet on the window root. Replace now / machine start
     must drop it or IOMFB hands the panel back to that UIKit modal. */
  UIViewController *root = self.window.rootViewController;
  if (root.presentedViewController) {
    [root dismissViewControllerAnimated:NO completion:nil];
  }
  if (self.machinesViewController.presentedViewController) {
    [self.machinesViewController dismissViewControllerAnimated:NO
                                                    completion:nil];
  }
  if (self.machinesViewController) {
    self.machinesViewController.view.hidden = YES;
  }
  self.showingMachinesUI = NO;
}

- (void)handleModeBHidTouchId:(int32_t)touchId
                        state:(int)state
                           at:(CGPoint)viewPoint {
  if (!self.modeBGreeterView) {
    [self showModeBGreeterPicker];
  }
  [self.modeBGreeterView injectHidTouchId:touchId state:state at:viewPoint];
}

- (void)recoverModeBGreeterAfterSession {
  self.modeBSessionLive = NO;
  self.modeBSessionStarting = NO;
  wwn_modeb_desktop_recover_to_greeter();
  [self pushModeBProfilesToGreeter];
  [self showModeBGreeterPicker];
  [self.modeBGreeterView enterGreeterInputMode];
  WWNModeBLabLog(@"recover IOMFB greeter (stay own-display)");
}

- (void)applyModeBSessionChrome {
  [self dismissModeBHostChrome];
  self.compositorContainer.hidden = NO;
  self.compositorContainer.alpha = 1.0;
  [self.window.rootViewController.view layoutIfNeeded];
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)),
      dispatch_get_main_queue(), ^{
        int32_t adopted = wwn_modeb_desktop_adopt_text_sessions();
        WWNLog("MODEB", @"Logical PTY sessions available: %d", adopted);
      });
  [self setCompositorGestureDeferralEnabled:YES];
  if (self.modeBGreeterView) {
    [self.window bringSubviewToFront:self.modeBGreeterView];
  }
  // Tab chrome must stay above the clear Mode B HID overlay.
  [self raiseClientTabChrome];
  [self refreshClientTabs];
}

- (BOOL)startModeBMachineProfile:(WWNMachineProfile *)profile {
  if (!profile) {
    return NO;
  }
  if (![self engageModeBDesktopReplacement]) {
    return NO;
  }
  [self dismissModeBHostChrome];
  self.modeBSessionStarting = YES;
  self.modeBSessionLive = YES;
  [self holdModeBOwnDisplayBackgroundTask];
  WWNModeBLabLog(@"start profile=%@ phase=%u", profile.machineId,
                 wwn_modeb_desktop_phase());
  [WWNMachineProfileStore setActiveMachineId:profile.machineId];
  [WWNMachineProfileStore applyMachineToRuntimePrefs:profile];
  wwn_modeb_desktop_enter_session();
  [self applyModeBSessionChrome];
  NSDictionary *ro =
      [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
          ? profile.runtimeOverrides
          : @{};
  NSDictionary *so =
      [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
          ? profile.settingsOverrides
          : @{};
  NSString *cid = @"";
  if ([ro[@"bundledAppID"] isKindOfClass:[NSString class]] &&
      [(NSString *)ro[@"bundledAppID"] length] > 0) {
    cid = ro[@"bundledAppID"];
  } else if ([so[@"NativeClientId"] isKindOfClass:[NSString class]]) {
    cid = so[@"NativeClientId"];
  }
  WWNModeBHidRoute route = WWNModeBHidRouteHostCompositor;
  if ([cid isEqualToString:@"weston"]) {
    route = WWNModeBHidRouteWestonDrm;
  }
  NSString *profileType = profile.type.lowercaseString ?: @"";
  BOOL relayGuest = [profileType isEqualToString:kWWNMachineTypeVirtualMachine] ||
                    [profileType isEqualToString:kWWNMachineTypeContainer];
  [self showModeBGreeterPicker];
  [self.modeBGreeterView enterSessionInputModeWithRoute:route];
  /* showModeBGreeterPicker restarts the latch. Stop it again for Relay so
     greeter paint cannot overwrite the VM/container IOSurface. */
  if (relayGuest) {
    [self.modeBGreeterView stopDisplayLink];
  }
  WWNModeBLabLog(@"session HID overlay client=%@ route=%ld", cid, (long)route);
  NSError *error = nil;
  BOOL ok = [WWNMachineSessionBridge connectProfile:profile error:&error];
  WWNModeBLabLog(@"connect %@ ok=%d err=%@", profile.machineId, (int)ok,
                 error.localizedDescription ?: @"");
  WWNModeBLabDumpLogRing("after-connect");
  if (!ok) {
    WWNLog("MODEB", @"Machine %@ failed to start: %@", profile.machineId,
           error.localizedDescription);
    [self recoverModeBGreeterAfterSession];
    return NO;
  }
  /* connectProfile can post DidTerminate for a leftover client before
     weston/niri report running. Keep starting set so that does not
     restore the greeter or Settings over IOMFB. */
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   if (self.modeBSessionLive) {
                     self.modeBSessionStarting = NO;
                   }
                 });
  return YES;
}

- (void)holdModeBOwnDisplayBackgroundTask {
  if (self.modeBOwnDisplayTask != UIBackgroundTaskInvalid &&
      self.modeBOwnDisplayTask != 0) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  self.modeBOwnDisplayTask = [[UIApplication sharedApplication]
      beginBackgroundTaskWithName:@"wwn.modeb.own-display"
                expirationHandler:^{
                  __strong typeof(weakSelf) strongSelf = weakSelf;
                  WWNModeBLabLog(@"own-display bg task expired");
                  if (!strongSelf) {
                    return;
                  }
                  /* IOMFB own-display keeps UIKit Background. iOS expires
                     the slice (~30s). Renew while the session is live.
                     Leave only when the user actually dismissed it. */
                  BOOL stay = strongSelf.modeBSessionLive ||
                              strongSelf.modeBSessionStarting ||
                              [strongSelf modeBOwnDisplayEngaged];
                  [strongSelf endModeBOwnDisplayBackgroundTask];
                  if (stay) {
                    [strongSelf holdModeBOwnDisplayBackgroundTask];
                    WWNModeBLabLog(@"own-display bg task renewed");
                    return;
                  }
                  [strongSelf leaveModeBDesktopToMachines];
                }];
  WWNModeBLabLog(@"own-display bg task=%lu",
                 (unsigned long)self.modeBOwnDisplayTask);
}

- (void)endModeBOwnDisplayBackgroundTask {
  if (self.modeBOwnDisplayTask == UIBackgroundTaskInvalid ||
      self.modeBOwnDisplayTask == 0) {
    self.modeBOwnDisplayTask = UIBackgroundTaskInvalid;
    return;
  }
  [[UIApplication sharedApplication] endBackgroundTask:self.modeBOwnDisplayTask];
  self.modeBOwnDisplayTask = UIBackgroundTaskInvalid;
}

- (void)leaveModeBDesktopToMachines {
  [self restoreModeBIOMFBForLeaveWithReason:@"return-to-machines"];
  [self showMachinesUI];
}

- (void)restoreModeBIOMFBForLeaveWithReason:(NSString *)reason {
  [self stopModeBLabPoll];
  [self hideModeBGreeterPicker];
  if (!self.modeBDesktopActive && wwn_modeb_desktop_phase() == 0) {
    return;
  }
  [WWNMachineSessionBridge stopAllActiveTransports];
  UIBackgroundTaskIdentifier task = [[UIApplication sharedApplication]
      beginBackgroundTaskWithName:@"wwn.modeb.iomfb-restore"
                expirationHandler:nil];
  WWNModeBLabDumpLogRing(reason.UTF8String ?: "leave");
  int32_t restore = wwn_modeb_desktop_restore();
  self.modeBDesktopActive = NO;
  self.modeBSessionLive = NO;
  self.modeBSessionStarting = NO;
  [self endModeBOwnDisplayBackgroundTask];
  WWNLog("MODEB", @"IOMFB restore on %@: %d", reason ?: @"leave", restore);
  WWNModeBLabLog(@"IOMFB restore on %@: %d", reason ?: @"leave", restore);
  if (task != UIBackgroundTaskInvalid) {
    [[UIApplication sharedApplication] endBackgroundTask:task];
  }
}

- (BOOL)engageModeBDesktopReplacement {
  if (self.modeBDesktopActive && wwn_modeb_desktop_phase() != 0) {
    return YES;
  }
  if (![WWNSharedUserDefaults() boolForKey:kWWNPrefsDesktopReplacementEnabled]) {
    WWNLog("MODEB", @"IOMFB engage refused: Desktop Replacement is off");
    WWNModeBLabLog(@"engage refused: Desktop Replacement off");
    return NO;
  }
  WWNModeBLabLog(@"engage IOMFB begin");
#if WWN_MODE_B
  /* Capture Metal before IOMFB exclusive. vphone IOMFB session later
     reports MTLCreateSystemDefaultDevice()=nil; keep a layer for ANGLE. */
  {
    id<MTLDevice> metal = MTLCreateSystemDefaultDevice();
    WWNModeBLabLog(@"Metal device before IOMFB=%p", metal);
    if (metal) {
      static CAMetalLayer *layer;
      if (!layer) {
        layer = [CAMetalLayer layer];
        layer.device = metal;
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = NO;
        layer.drawableSize = CGSizeMake(64, 64);
      }
      iland_egl_set_metal_native_display((__bridge void *)layer);
    }
  }
#endif
  sModeBDesktopScene = self;
  wwn_modeb_set_hid_sink(WWNModeBHidSinkTrampoline);
  wwn_modeb_desktop_set_present_session(WWNModeBPresentLogicalSession);
  self.modeBProfiles =
      WWNModeBEnsureCompositorProfiles([WWNMachineProfileStore loadProfiles]);
  uint32_t width = 0;
  uint32_t height = 0;
  int32_t start = wwn_modeb_desktop_start(&width, &height);
  if (start != 0 || width == 0 || height == 0) {
    const char *raw = wwn_modeb_desktop_last_error();
    NSString *detail =
        raw && raw[0] ? [NSString stringWithUTF8String:raw] : @"unknown";
    WWNLog("MODEB", @"IOMFB ownership failed (%d): %@", start, detail);
    WWNModeBLabLog(@"engage IOMFB failed rc=%d %@", start, detail);
    [self showModeBDesktopFailureWithCode:start];
    return NO;
  }
  self.modeBDesktopActive = YES;
  [self holdModeBOwnDisplayBackgroundTask];
  [self startModeBLabPoll];
  [self pushModeBProfilesToGreeter];
  [self setCompositorGestureDeferralEnabled:YES];
  WWNLog("MODEB", @"Desktop Replacement IOMFB + igetty at %ux%u", width, height);
  WWNModeBLabLog(@"engage IOMFB %ux%u", width, height);
  return YES;
}

- (void)pushModeBProfilesToGreeter {
  if (!self.modeBProfiles) {
    self.modeBProfiles =
        WWNModeBEnsureCompositorProfiles([WWNMachineProfileStore loadProfiles]);
  }
  NSString *preferred = [WWNSharedUserDefaults()
      stringForKey:kWWNPrefsDesktopReplacementMachineId];
  NSMutableArray<WWNMachineProfile *> *ordered =
      [self.modeBProfiles mutableCopy];
  if (preferred.length > 0) {
    NSUInteger idx =
        [ordered indexOfObjectPassingTest:^BOOL(WWNMachineProfile *p, NSUInteger i,
                                                BOOL *stop) {
          (void)i;
          (void)stop;
          return [p.machineId isEqualToString:preferred];
        }];
    if (idx != NSNotFound && idx > 0) {
      WWNMachineProfile *front = ordered[idx];
      [ordered removeObjectAtIndex:idx];
      [ordered insertObject:front atIndex:0];
    }
  }
  self.modeBProfiles = ordered;
  NSMutableArray *rows = [NSMutableArray array];
  for (WWNMachineProfile *profile in ordered) {
    [rows addObject:@{
      @"machineId" : profile.machineId ?: @"",
      @"name" : profile.name.length ? profile.name : @"Unnamed",
      @"type" : profile.type.length ? profile.type : @"native",
    }];
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:rows
                                                 options:0
                                                   error:nil];
  if (!data) {
    return;
  }
  NSString *json = [[NSString alloc] initWithData:data
                                         encoding:NSUTF8StringEncoding];
  int32_t rc = wwn_modeb_desktop_set_profiles_json(json.UTF8String);
  WWNModeBLabLog(@"greeter profiles=%lu rc=%d", (unsigned long)ordered.count, rc);
}

- (void)showModeBGreeterPicker {
  uint32_t width = 0;
  uint32_t height = 0;
  wwn_modeb_desktop_size(&width, &height);
  if (width == 0 || height == 0) {
    width = (uint32_t)(self.window.bounds.size.width * self.window.screen.scale);
    height =
        (uint32_t)(self.window.bounds.size.height * self.window.screen.scale);
  }
  if (!self.modeBGreeterView) {
    WWNModeBDesktopInputView *view =
        [[WWNModeBDesktopInputView alloc] initWithFrame:self.window.bounds];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.accessibilityIdentifier = @"wwn.modeb.igetty-picker";
    __weak typeof(self) weakSelf = self;
    view.onMachineSelected = ^(NSInteger index) {
      WWNMachineProfile *profile =
          (index >= 0 && (NSUInteger)index < weakSelf.modeBProfiles.count)
              ? weakSelf.modeBProfiles[(NSUInteger)index]
              : nil;
      WWNModeBLabLog(@"picker card=%ld id=%@", (long)index,
                     profile.machineId ?: @"(none)");
      [weakSelf startModeBMachineProfile:profile];
    };
    view.onHomeRequested = ^{
      [weakSelf leaveModeBDesktopToMachines];
    };
    [self.window addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
      [view.leadingAnchor constraintEqualToAnchor:self.window.leadingAnchor],
      [view.trailingAnchor constraintEqualToAnchor:self.window.trailingAnchor],
      [view.topAnchor constraintEqualToAnchor:self.window.topAnchor],
      [view.bottomAnchor constraintEqualToAnchor:self.window.bottomAnchor],
    ]];
    self.modeBGreeterView = view;
  }
  self.modeBGreeterView.displaySize = CGSizeMake(width, height);
  self.modeBGreeterView.hidden = NO;
  [self.window bringSubviewToFront:self.modeBGreeterView];
  [self.modeBGreeterView startDisplayLink];
}

- (void)hideModeBGreeterPicker {
  [self.modeBGreeterView stopLabPoll];
  [self.modeBGreeterView stopDisplayLink];
  [self.modeBGreeterView removeFromSuperview];
  self.modeBGreeterView = nil;
}

- (void)handleModeBDesktopReplacementChanged:(NSNotification *)note {
  BOOL enabled = [note.userInfo[@"enabled"] boolValue];
  if (!enabled) {
    [self leaveModeBDesktopToMachines];
    return;
  }
  WWNLog("MODEB", @"Desktop Replacement enabled. Panel stays on Machines "
                  @"until Replace now or Start Weston/Niri");
}

- (void)handleModeBDesktopReplacementReplaceNow:(NSNotification *)note {
  (void)note;
  WWNModeBLabLog(@"Replace now: begin phase=%u", wwn_modeb_desktop_phase());
  [WWNSharedUserDefaults() setBool:YES
                            forKey:kWWNPrefsDesktopReplacementEnabled];
  [self dismissModeBHostChrome];
  if (self.modeBSessionLive || wwn_modeb_desktop_phase() >= 2) {
    [WWNMachineSessionBridge stopAllActiveTransports];
    self.modeBSessionLive = NO;
    self.modeBSessionStarting = NO;
    wwn_modeb_desktop_recover_to_greeter();
    [self pushModeBProfilesToGreeter];
    [self showModeBGreeterPicker];
    [self.modeBGreeterView enterGreeterInputMode];
    WWNModeBLabLog(@"Replace now: back to igetty picker");
    return;
  }
  if (![self engageModeBDesktopReplacement]) {
    return;
  }
  [self showModeBGreeterPicker];
  WWNModeBLabLog(@"Replace now: igetty picker (no auto-start)");
}

- (void)startModeBLabPoll {
  if (self.modeBLabPollTimer || self.modeBLabPollSource) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  self.modeBLabPollTimer = [NSTimer timerWithTimeInterval:0.2
                                                  repeats:YES
                                                    block:^(NSTimer *timer) {
                                                      (void)timer;
                                                      [weakSelf consumeModeBLabSelectFile];
                                                    }];
  [[NSRunLoop mainRunLoop] addTimer:self.modeBLabPollTimer
                            forMode:NSRunLoopCommonModes];
  /* NSTimer pauses when the scene is not ForegroundActive. A GCD timer
     still hops to main so Replace / weston select works after uiopen. */
  dispatch_source_t source =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                             dispatch_get_main_queue());
  dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, 0),
                            (uint64_t)(0.2 * NSEC_PER_SEC),
                            (uint64_t)(0.05 * NSEC_PER_SEC));
  dispatch_source_set_event_handler(source, ^{
    [weakSelf consumeModeBLabSelectFile];
  });
  self.modeBLabPollSource = source;
  dispatch_resume(source);
}

- (void)stopModeBLabPoll {
  [self.modeBLabPollTimer invalidate];
  self.modeBLabPollTimer = nil;
  if (self.modeBLabPollSource) {
    dispatch_source_cancel(self.modeBLabPollSource);
    self.modeBLabPollSource = nil;
  }
}

- (void)consumeModeBLabSelectFile {
  /* Real /tmp (no-sandbox), container tmp, and mobile Documents. Root-owned
     /tmp files can be invisible to the tipa even at 0666. */
  char raw[128];
  FILE *sf = NULL;
  const char *opened = NULL;
  NSString *containerTmp = [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"wwn-modeb-select"];
  NSString *docs = [NSSearchPathForDirectoriesInDomains(
      NSDocumentDirectory, NSUserDomainMask, YES)
                        .firstObject
                        stringByAppendingPathComponent:@"wwn-modeb-select"];
  const char *candidates[] = {
      "/tmp/wwn-modeb-select",
      "/var/tmp/wwn-modeb-select",
      "/var/mobile/Documents/wwn-modeb-select",
      containerTmp.fileSystemRepresentation,
      docs.fileSystemRepresentation,
      NULL,
  };
  for (const char **path = candidates; *path; path++) {
    sf = fopen(*path, "r");
    if (sf) {
      opened = *path;
      break;
    }
  }
  if (!sf) {
    return;
  }
  size_t n = fread(raw, 1, sizeof(raw) - 1, sf);
  fclose(sf);
  unlink(opened);
  raw[n] = '\0';
  WWNModeBLabLog(@"lab select file=%s bytes=%zu", opened, n);
  NSString *body = [[NSString alloc] initWithBytes:raw
                                            length:n
                                          encoding:NSUTF8StringEncoding];
  if (body.length == 0) {
    return;
  }
  NSString *token =
      [body stringByTrimmingCharactersInSet:NSCharacterSet
                                                .whitespaceAndNewlineCharacterSet]
          .lowercaseString;
  WWNModeBLabLog(@"lab select token=%@", token);
  if ([token isEqualToString:@"replace"] ||
      [token isEqualToString:@"engage"]) {
    [self handleModeBDesktopReplacementReplaceNow:nil];
    return;
  }
  if ([token isEqualToString:@"home"] || [token isEqualToString:@"off"] ||
      [token isEqualToString:@"machines"]) {
    [self leaveModeBDesktopToMachines];
    return;
  }
  if (!self.modeBProfiles) {
    self.modeBProfiles =
        WWNModeBEnsureCompositorProfiles([WWNMachineProfileStore loadProfiles]);
  }
  WWNMachineProfile *profile = nil;
  if ([token isEqualToString:@"weston"] || [token isEqualToString:@"niri"]) {
    for (WWNMachineProfile *candidate in self.modeBProfiles) {
      NSString *cid =
          [candidate.settingsOverrides[@"NativeClientId"] isKindOfClass:[NSString class]]
              ? candidate.settingsOverrides[@"NativeClientId"]
              : @"";
      if ([cid isEqualToString:token] ||
          [candidate.name.lowercaseString isEqualToString:token]) {
        profile = candidate;
        break;
      }
    }
  } else if ([token isEqualToString:@"vm"] ||
             [token isEqualToString:@"virtual_machine"]) {
    for (WWNMachineProfile *candidate in self.modeBProfiles) {
      NSString *type = candidate.type.lowercaseString;
      NSString *name = candidate.name.lowercaseString;
      if ([type isEqualToString:kWWNMachineTypeVirtualMachine] ||
          [name containsString:@"virtual"]) {
        profile = candidate;
        break;
      }
    }
  } else if ([token isEqualToString:@"wasm"] ||
             [token isEqualToString:@"hello-wasi-gui"] ||
             [token isEqualToString:@"wawona-wasm"]) {
    for (WWNMachineProfile *candidate in self.modeBProfiles) {
      NSString *type = candidate.type.lowercaseString;
      NSString *name = candidate.name.lowercaseString;
      NSString *rid =
          [candidate.runtimeOverrides[@"bundledAppID"] isKindOfClass:[NSString class]]
              ? candidate.runtimeOverrides[@"bundledAppID"]
              : @"";
      if ([type isEqualToString:kWWNMachineTypeWasm] ||
          [rid isEqualToString:@"hello-wasi-gui"] ||
          [rid isEqualToString:@"wawona-wasm"] ||
          [name containsString:@"wasm"] || [name containsString:@"wasi"]) {
        profile = candidate;
        break;
      }
    }
  } else if ([token isEqualToString:@"container"]) {
    for (WWNMachineProfile *candidate in self.modeBProfiles) {
      NSString *type = candidate.type.lowercaseString;
      NSString *name = candidate.name.lowercaseString;
      if ([type isEqualToString:kWWNMachineTypeContainer] ||
          [name containsString:@"container"]) {
        profile = candidate;
        break;
      }
    }
  }
  WWNModeBLabLog(@"lab select token=%@ profile=%@", token,
                 profile.machineId ?: @"(none)");
  if (profile) {
    [WWNSharedUserDefaults() setBool:YES
                              forKey:kWWNPrefsDesktopReplacementEnabled];
    [self startModeBMachineProfile:profile];
  }
}
#endif

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
  WWNLog("SCENE", @"WAWONA_AUTO_CLIENT=%@. Starting bundled client", autoClient);
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
  if (bounds.size.width <= 0 || bounds.size.height <= 0) {
    bounds = self.window.bounds;
  }
  [self updateOutputSizeFromRect:bounds forced:forced];
}

- (void)updateOutputSizeFromRect:(CGRect)bounds forced:(BOOL)forced {
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
      [WWNMachineProfileStore resolvedResizeDisplayForVirtualKeyboardActive] &&
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
// collection changes. This is the primary rotation notification in the
// UIScene lifecycle.  We must update the Wayland compositor output size so
// that wl_output.mode events are sent and xdg_toplevel windows reconfigure.
//
// Deprecated in iOS 26. Migrate to registerForTraitChanges: when the
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
  if (self.applyingSceneGeometry) {
    return;
  }
  self.applyingSceneGeometry = YES;
  @try {
  [self.window.rootViewController.view layoutIfNeeded];
  [self.compositorContainer layoutIfNeeded];

  CGRect containerBounds = self.compositorContainer.bounds;
  CGSize windowSize = self.window.bounds.size;
  BOOL orientationMismatch =
      containerBounds.size.width > 1.0 && windowSize.width > 1.0 &&
      ((containerBounds.size.width > containerBounds.size.height) !=
       (windowSize.width > windowSize.height));
  if (containerBounds.size.width <= 0 || containerBounds.size.height <= 0 ||
      orientationMismatch) {
    BOOL respectSafeArea =
        [[WWNPreferencesManager sharedManager] respectSafeArea];
    containerBounds = respectSafeArea
        ? UIEdgeInsetsInsetRect(self.window.bounds, self.window.safeAreaInsets)
        : self.window.bounds;
    WWNLog("SCENE", @"Scene geometry used window fallback %.0fx%.0f",
          containerBounds.size.width, containerBounds.size.height);
  }

  WWNLog("SCENE", @"Scene geometry changed (container %.0fx%.0f)",
        containerBounds.size.width, containerBounds.size.height);

  for (UIView *child in self.compositorContainer.subviews) {
    child.frame = containerBounds;
  }

  [self updateOutputSizeFromRect:containerBounds forced:YES];
  } @finally {
    self.applyingSceneGeometry = NO;
  }
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
#if WWN_MODE_B
  [self restoreModeBIOMFBForLeaveWithReason:@"scene disconnect"];
#endif
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
#if WWN_MODE_B
  WWNModeBLabLog(@"scene became active phase=%u", wwn_modeb_desktop_phase());
  [self consumeModeBLabSelectFile];
  if (self.hostedClientWindowId == 0 && self.modeBDesktopActive &&
      wwn_modeb_desktop_phase() == 0 &&
      [WWNSharedUserDefaults() boolForKey:kWWNPrefsDesktopReplacementEnabled] &&
      (self.modeBSessionLive || self.modeBSessionStarting)) {
    [self engageModeBDesktopReplacement];
  }
#endif
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST && !TARGET_OS_TV && !TARGET_OS_WATCH && !TARGET_OS_VISION
  [[WWNWatchCompanionBridge sharedBridge] activate];
#endif
  // Only re-show the machines UI if the compositor is visible but nothing is
  // actually rendering into it (neither waypipe nor any native client).
  BOOL compositorVisible = !self.compositorContainer.hidden;
  BOOL somethingRunning = [WWNWaypipeRunner sharedRunner].isRunning
                          || [self isAnyNativeClientRunning];
#if WWN_MODE_B
  // Own-display session start resigns then becomes active before weston/niri
  // report running. Do not hide the compositor or bounce back to Machines.
  if ([self modeBOwnDisplayEngaged]) {
    somethingRunning = YES;
  }
#endif
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
#if WWN_MODE_B
  // Desktop Replacement IOMFB looks like resign. Restoring then is
  // RunningBoard 0xDEAD10CC. Only restore on toggle off or leave.
  if ([self modeBOwnDisplayEngaged]) {
    WWNLog("MODEB",
           @"resign ignored: own-display session (phase=%u starting=%d live=%d)",
           wwn_modeb_desktop_phase(), (int)self.modeBSessionStarting,
           (int)self.modeBSessionLive);
    WWNModeBLabLog(@"resign ignored phase=%u starting=%d live=%d",
                   wwn_modeb_desktop_phase(), (int)self.modeBSessionStarting,
                   (int)self.modeBSessionLive);
    return;
  }
  [self restoreModeBIOMFBForLeaveWithReason:@"resign-active"];
#endif
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
  WWNLog("SCENE", @"Scene will enter foreground");
#if WWN_MODE_B
  [self consumeModeBLabSelectFile];
#endif
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
  WWNLog("SCENE", @"Scene did enter background");
#if WWN_MODE_B
  // IOMFB session start also delivers Background. Restoring then kills
  // the compositor mid-start (build 14: process gone, no new DEAD10CC ips).
  if ([self modeBOwnDisplayEngaged]) {
    [self holdModeBOwnDisplayBackgroundTask];
    WWNLog("MODEB",
           @"background ignored: own-display session (phase=%u starting=%d live=%d)",
           wwn_modeb_desktop_phase(), (int)self.modeBSessionStarting,
           (int)self.modeBSessionLive);
    WWNModeBLabLog(@"background ignored phase=%u starting=%d live=%d",
                   wwn_modeb_desktop_phase(), (int)self.modeBSessionStarting,
                   (int)self.modeBSessionLive);
    return;
  }
  [self restoreModeBIOMFBForLeaveWithReason:@"background"];
#endif
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

#if TARGET_OS_TV
/// Linux KEY_ESC. Matches compositor view / bridge injection.
static const uint32_t kWWNTvMenuEscapeKeycode = 1;

- (WWNCompositorHostViewController *)_tvHost {
  if ([self.window.rootViewController
          isKindOfClass:[WWNCompositorHostViewController class]]) {
    return (WWNCompositorHostViewController *)self.window.rootViewController;
  }
  return nil;
}

- (void)_tvosSyncMenuIntercept {
  WWNCompositorHostViewController *host = [self _tvHost];
  if (!host) {
    return;
  }
  WWNCompositorView_ios *surface = WWNFindCompositorSurface(host.view);
  BOOL keyboardUp = surface.isFirstResponder;
  BOOL on = !self.showingMachinesUI && [self isAnyClientSessionRunning] &&
            !self.sessionExitPromptVisible && !keyboardUp;
  host.interceptsMenuForSessionExit = on;
  if (!on) {
    [host cancelTvMenuLongPress];
  }
}

- (void)_tvRemoteMenuBegan:(NSNotification *)note {
  (void)note;
  [[self _tvHost] wwn_tvMenuBegan];
}

- (void)_tvRemoteMenuEnded:(NSNotification *)note {
  (void)note;
  [[self _tvHost] wwn_tvMenuEnded];
}

- (void)_tvRemoteMenuCancelled:(NSNotification *)note {
  (void)note;
  [[self _tvHost] wwn_tvMenuCancelled];
}

- (void)_tvRemoteShake:(NSNotification *)note {
  (void)note;
  [self handleShakeGesture];
}

- (void)_tvRequestSessionExit:(NSNotification *)note {
  (void)note;
  if (self.showingMachinesUI || ![self isAnyClientSessionRunning]) {
    return;
  }
  [self presentSessionExitConfirmationForTrigger:WWNSessionExitTriggerMenuOrEscape];
}

- (void)_tvKeyboardFocusDidChange:(NSNotification *)note {
  (void)note;
  [self _tvosSyncMenuIntercept];
}

- (void)injectTvMenuEscapeToClient {
  if (self.showingMachinesUI || ![self isAnyClientSessionRunning]) {
    return;
  }
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  uint32_t ts = (uint32_t)(CACurrentMediaTime() * 1000.0);
  [bridge injectKeyWithKeycode:kWWNTvMenuEscapeKeycode pressed:YES timestamp:ts];
  [bridge injectKeyWithKeycode:kWWNTvMenuEscapeKeycode pressed:NO timestamp:ts + 1];
}
#endif

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
- (void)handleTvMenuShortPressDuringSession {
  if (self.showingMachinesUI || ![self isAnyClientSessionRunning]) {
    return;
  }
  if (self.sessionExitPromptVisible) {
    return;
  }
  [self presentSessionExitConfirmationForTrigger:WWNSessionExitTriggerMenuOrEscape];
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
#if TARGET_OS_TV
  [self _tvosSyncMenuIntercept];
#endif
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Close current Wayland app?"
                       message:
#if TARGET_OS_TV
                           @"Stop the session and return to Machines. "
                           @"Send Escape if a nested compositor needs Back."
#else
                           @"This will stop the current session and return to Machines."
#endif
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
#if TARGET_OS_TV
                                 [strongSelf _tvosSyncMenuIntercept];
#endif
                               }]];

#if TARGET_OS_TV
  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Send Escape"
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction *action) {
                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                 if (!strongSelf) {
                                   return;
                                 }
                                 strongSelf.sessionExitPromptVisible = NO;
                                 [strongSelf injectTvMenuEscapeToClient];
                                 [strongSelf _tvosSyncMenuIntercept];
                               }]];
#endif

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
                   [strongSelf.clientTabsControl setHidden:YES];
                   [strongSelf setCompositorGestureDeferralEnabled:NO];
#if !TARGET_OS_VISION
                   [strongSelf applyRespectSafeAreaPreference];
#endif
                   [strongSelf showMachinesUI];
                 });
}

- (void)handleNativeClientWillLaunch:(NSNotification *)notification {
  NSString *clientId = notification.userInfo[@"clientId"];
#if WWN_MODE_B
  /* Machines Start stays nested. IOMFB own-display is Replace now / picker
     only. Do not engage the panel just because the toggle is on. */
  if ([self modeBOwnDisplayEngaged]) {
    [self dismissModeBHostChrome];
    WWNModeBLabLog(@"will-launch %@ own-display (no Settings / startup log)",
                   clientId ?: @"");
  } else
#endif
  {
    [self showStartupLogForClient:clientId];
  }
  // iPadOS / visionOS multi-window (#120): this fires on the PRIMARY scene's
  // delegate (the client's own scene doesn't exist yet. It's requested
  // later, once the toplevel actually maps). When clients get their own
  // dedicated UIWindowScene, the primary Machines scene must stay exactly as
  // it is. Hiding its Machines UI and revealing its (now-unused, empty)
  // compositorContainer leaves the user with a black, uninteractable window
  // and no way to launch another machine.
  //
  // Exception: forceRevealPrimary (iland/kmscube scene-activation fallback)
  // when the Metal host could not get a dedicated scene and landed on the
  // primary container. Machines would otherwise cover it permanently.
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
/// clients. They render in a different OS window entirely.
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
  // Phone only. IPadOS uses one UIWindowScene per Wayland client.
  return UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad;
#else
  return NO;
#endif
}

- (void)refreshClientTabs {
  if (![self usesClientTabChrome]) {
    [self.clientTabsControl setHidden:YES];
    self.clientTabWindowIds = nil;
    return;
  }
  if (self.compositorContainer.hidden) {
    [self.clientTabsControl setHidden:YES];
    return;
  }

  // Tabs = live Wayland toplevels only. Shell / Machines is host chrome and
  // must never appear as a segment (nested niri used to show Shell + Niri).
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  // Selection is by Wayland window id, not tab index (#84). Capture BEFORE
  // clientTabWindowIds is replaced so we can detect newly mapped toplevels.
  NSNumber *previouslySelectedWindowId = nil;
  if (self.clientTabsControl) {
    uint64_t sid = self.clientTabsControl.selectedId;
    if (sid != 0) {
      previouslySelectedWindowId = @(sid);
    }
  }
  NSArray<NSNumber *> *previousIds = self.clientTabWindowIds ?: @[];

  NSArray<NSNumber *> *ids = [bridge tabbedClientWindowIds];
  NSMutableArray<NSString *> *titles =
      [NSMutableArray arrayWithCapacity:ids.count];
  for (NSNumber *wid in ids) {
    [titles addObject:[bridge titleForHostWindowId:wid.unsignedLongLongValue]];
  }

  // Safari: a newly mapped toplevel becomes the active tab. Prefer ids that
  // were not in the previous list over keeping the old selection (that left
  // keyboard on the new client while the UI stayed on weston-terminal).
  NSNumber *selectId = nil;
  if (previousIds.count > 0) {
    NSSet<NSNumber *> *prevSet = [NSSet setWithArray:previousIds];
    for (NSNumber *wid in ids) {
      if (![prevSet containsObject:wid]) {
        selectId = wid; // sorted ascending; last write = newest id
      }
    }
  }
  if (selectId == nil) {
    if (previouslySelectedWindowId != nil &&
        [ids containsObject:previouslySelectedWindowId]) {
      selectId = previouslySelectedWindowId;
    } else {
      selectId = ids.lastObject;
    }
  }

  self.clientTabWindowIds = ids;

  if (titles.count == 0) {
    [self.clientTabsControl setHidden:YES];
    return;
  }

  // Phone chrome is for switching. One live client needs no square.on.square.
  if (titles.count < 2) {
    [self.clientTabsControl setHidden:YES];
    if (selectId != nil) {
      [bridge focusTabbedClientWindowId:selectId.unsignedLongLongValue];
    }
    WWNLog("TABS", @"single Wayland client; tab chrome hidden (%@)",
           titles.firstObject ?: @"(nil)");
    return;
  }

  if (!self.clientTabsControl) {
    Class cls = WWNClientTabChromeControllerClass();
    if (!cls) {
      WWNLog("TABS",
             @"WWNClientTabChromeController missing (SwiftUI tab chrome not "
             @"linked)");
      return;
    }
    self.clientTabsControl = [[cls alloc] init];
    __weak typeof(self) weakSelf = self;
    self.clientTabsControl.onSelectId = ^(uint64_t wid) {
      [weakSelf clientTabSelectWindowId:wid];
    };
    self.clientTabsControl.onCloseId = ^(uint64_t wid) {
      [weakSelf clientTabCloseWindowId:wid];
    };
    // UIWindow (not root VC): Mode B IOMFB HID overlay is also a window
    // subview and used to cover tabs attached only under rootViewController.
    if (!self.window) {
      WWNLog("TABS", @"no UIWindow yet; defer client tab chrome attach");
      return;
    }
    [self.clientTabsControl attachTo:self.window];
  }
  NSMutableDictionary<NSNumber *, UIImage *> *previews =
      [NSMutableDictionary dictionary];
  for (NSNumber *wid in ids) {
    UIImage *img =
        [bridge previewImageForHostWindowId:wid.unsignedLongLongValue];
    if (img) {
      previews[wid] = img;
    }
  }
  [self.clientTabsControl reloadWithIds:ids
                                 titles:titles
                             selectedId:selectId
                          previewImages:previews];
  [self.clientTabsControl setHidden:NO];
  [self raiseClientTabChrome];
  // Keep the visible surface in sync with the selected tab: focus hides the
  // other tabbed clients so the selection is actually what the user sees.
  [bridge focusTabbedClientWindowId:selectId.unsignedLongLongValue];
#if TARGET_OS_TV
  UIViewController *rootVC = self.window.rootViewController;
  [rootVC setNeedsFocusUpdate];
  [rootVC updateFocusIfNeeded];
#endif
  WWNLog("TABS", @"refreshed %lu Wayland client tab(s), selected=%@: %@",
         (unsigned long)titles.count, selectId,
         [titles componentsJoinedByString:@", "]);
}

- (void)raiseClientTabChrome {
  UIView *host = self.clientTabsControl.hostView;
  if (!host || !self.window) {
    return;
  }
  if (host.superview != self.window) {
    [self.clientTabsControl attachTo:self.window];
    host = self.clientTabsControl.hostView;
  }
  if (host) {
    [self.window bringSubviewToFront:host];
  }
}

- (void)clientTabSelectWindowId:(uint64_t)target {
  if (target == 0) {
    return;
  }
  NSString *title = [[WWNCompositorBridge sharedBridge]
      titleForHostWindowId:target];
  WWNLog("TABS", @"focus Wayland client tab=%@ window=%llu", title ?: @"(nil)",
         target);
  [[WWNCompositorBridge sharedBridge] focusTabbedClientWindowId:target];
  [self.clientTabsControl reloadWithIds:self.clientTabWindowIds
                                 titles:[self clientTabTitles]
                             selectedId:@(target)];
}

- (NSArray<NSString *> *)clientTabTitles {
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  NSMutableArray<NSString *> *titles =
      [NSMutableArray arrayWithCapacity:self.clientTabWindowIds.count];
  for (NSNumber *wid in self.clientTabWindowIds) {
    [titles addObject:[bridge titleForHostWindowId:wid.unsignedLongLongValue]];
  }
  return titles;
}

- (void)clientTabCloseWindowId:(uint64_t)target {
  if (target == 0) {
    return;
  }
  NSString *title = [[WWNCompositorBridge sharedBridge]
      titleForHostWindowId:target];
  BOOL last = self.clientTabWindowIds.count <= 1;
  WWNLog("TABS", @"close Wayland client tab=%@ window=%llu last=%d",
         title ?: @"(nil)", target, last ? 1 : 0);
  if (last) {
    // Last tab: leave the session, same as the session Close action.
    [self closeActiveWaylandSession];
    return;
  }
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  [bridge requestHostCloseForWindowId:target];
  // Safari-style: the tab must actually go away. xdg_toplevel.close is a
  // request; escalate that one window if the client ignores it.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   NSArray<NSNumber *> *still = [bridge tabbedClientWindowIds];
                   if ([still containsObject:@(target)]) {
                     [bridge requestForceDestroyHostWindowForWindowId:target];
                   }
                 });
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
    // client's eventual window. Capture logs without presenting.
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
#if WWN_MODE_B
    /* Own-display: a leftover DidTerminate must not restore IOMFB or
       Settings. Stay on the panel. Dead session → igetty greeter. */
    if (self.modeBDesktopActive) {
      if (self.modeBSessionStarting) {
        WWNModeBLabLog(@"did-terminate ignored: session starting");
        return;
      }
      if (self.modeBSessionLive || wwn_modeb_desktop_phase() >= 2) {
        [self recoverModeBGreeterAfterSession];
        return;
      }
      return;
    }
#endif
    self.compositorContainer.hidden = YES;
    [self.clientTabsControl setHidden:YES];
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
#if WWN_MODE_B
    if ([self modeBOwnDisplayEngaged]) {
      WWNModeBLabLog(@"minimize ignored: own-display");
      return;
    }
#endif
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
    // Dedicated client scenes are separate UIWindowScenes. Bring the primary
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
    // Dedicated-scene host (iPadOS/visionOS client window): bring that scene
    // forward. Do not return early without also handling primary-scene Focus
    // when the request carries a machineId (Machines "Focus" button).
    if (self.hostedClientWindowId != 0 && windowId &&
        windowId.unsignedLongLongValue == self.hostedClientWindowId) {
      self.window.hidden = NO;
      [self.window makeKeyAndVisible];
      WWNLog("SCENE", @"Focus restored dedicated client window %llu",
             self.hostedClientWindowId);
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
    // their own UIWindowScene, not the primary scene's shared container -
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
  [self _tvosSyncMenuIntercept];
  WWNCompositorHostViewController *host = [self _tvHost];
  [host setNeedsFocusUpdate];
  [host updateFocusIfNeeded];
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
#if WWN_MODE_B
  if ([self modeBOwnDisplayEngaged]) {
    WWNLog("MODEB", @"showMachinesUI ignored: own-display engaged");
    WWNModeBLabLog(@"showMachinesUI ignored: own-display engaged");
    return;
  }
#endif
  [self setCompositorGestureDeferralEnabled:NO];
  self.compositorContainer.hidden = YES;
  [self.clientTabsControl setHidden:YES];
#if !TARGET_OS_VISION
  [self applyRespectSafeAreaPreference];
#endif
#if TARGET_OS_TV
  [self _tvosSyncMenuIntercept];
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
          // Machines scene must stay exactly as it is. Unconditionally
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
