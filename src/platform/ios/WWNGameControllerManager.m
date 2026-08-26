//
//  WWNGameControllerManager.m
//  Wawona. GameController framework input. See header.
//

#import "WWNGameControllerManager.h"
#import "../../util/WWNLog.h"
#import "WWNCompositorBridge.h"
#import "WWNCompositorView_ios.h"

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

NSNotificationName const WWNTvRemoteShakeNotification =
    @"WWNTvRemoteShakeNotification";
NSNotificationName const WWNTvRemoteMenuBeganNotification =
    @"WWNTvRemoteMenuBeganNotification";
NSNotificationName const WWNTvRemoteMenuEndedNotification =
    @"WWNTvRemoteMenuEndedNotification";
NSNotificationName const WWNTvRemoteMenuCancelledNotification =
    @"WWNTvRemoteMenuCancelledNotification";

// Linux input-event-codes.h button values.
static const uint32_t kBtnLeft = 0x110;
static const uint32_t kBtnRight = 0x111;
static const uint32_t kBtnMiddle = 0x112;

/// Cursor speed in points/second at full stick deflection.
static const CGFloat kStickCursorSpeed = 900.0;
/// Siri Remote clickpad / 1st-gen touch surface as a relative pointer.
static const CGFloat kSiriTouchpadCursorSpeed = 1400.0;
/// Scroll speed at full deflection (wl_pointer axis units/second).
static const CGFloat kStickScrollSpeed = 600.0;
/// Deadzone for analog sticks.
static const float kStickDeadzone = 0.15f;
/// 1st-gen Siri Remote userAcceleration magnitude (g). Apple has no shake event.
static const double kRemoteShakeG = 2.2;
static const NSTimeInterval kRemoteShakeCooldown = 1.2;

@implementation WWNGameControllerManager {
  BOOL _started;
  CADisplayLink *_stickLink;
  CFTimeInterval _lastStickTick;
  CFTimeInterval _lastRemoteShakeTime;
}

+ (instancetype)sharedManager {
  static WWNGameControllerManager *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[WWNGameControllerManager alloc] init];
  });
  return shared;
}

/// The compositor view that should receive virtual-pointer input: the focused
/// (topmost) client window view, falling back to the container.
- (WWNCompositorView_ios *)_targetView {
  UIView *container = [WWNCompositorBridge sharedBridge].containerView;
  if (!container) {
    return nil;
  }
  for (UIView *subview in [container.subviews reverseObjectEnumerator]) {
    if ([subview isKindOfClass:[WWNCompositorView_ios class]] &&
        !subview.hidden) {
      return (WWNCompositorView_ios *)subview;
    }
  }
  if ([container isKindOfClass:[WWNCompositorView_ios class]]) {
    return (WWNCompositorView_ios *)container;
  }
  return nil;
}

- (void)start {
  if (_started) {
    return;
  }
  _started = YES;

  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self
         selector:@selector(_controllerConnected:)
             name:GCControllerDidConnectNotification
           object:nil];
  [nc addObserver:self
         selector:@selector(_controllerDisconnected:)
             name:GCControllerDidDisconnectNotification
           object:nil];
  for (GCController *controller in GCController.controllers) {
    [self _configureController:controller];
  }

  if (@available(iOS 14.0, tvOS 14.0, *)) {
    [nc addObserver:self
           selector:@selector(_mouseConnected:)
               name:GCMouseDidConnectNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(_mouseDisconnected:)
               name:GCMouseDidDisconnectNotification
             object:nil];
    for (GCMouse *mouse in GCMouse.mice) {
      [self _configureMouse:mouse];
    }
    [nc addObserver:self
           selector:@selector(_keyboardChanged:)
               name:GCKeyboardDidConnectNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(_keyboardChanged:)
               name:GCKeyboardDidDisconnectNotification
             object:nil];
    _keyboardConnected = (GCKeyboard.coalescedKeyboard != nil);
  }
  WWNLog("GAMEPAD", @"GameController manager started (%lu controller(s))",
         (unsigned long)GCController.controllers.count);
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_stickLink invalidate];
}

// ---------------------------------------------------------------------------
#pragma mark - Gamepads
// ---------------------------------------------------------------------------

- (void)_controllerConnected:(NSNotification *)note {
  [self _configureController:note.object];
}

- (void)_controllerDisconnected:(NSNotification *)note {
  (void)note;
  _gamepadConnected = (GCController.controllers.count > 0);
  if (!_gamepadConnected) {
    [self _stopStickLink];
  }
  WWNLog("GAMEPAD", @"Controller disconnected (%lu remain)",
         (unsigned long)GCController.controllers.count);
}

- (void)_postTvMenuPressed:(BOOL)pressed {
#if TARGET_OS_TV
  NSNotificationName name = pressed ? WWNTvRemoteMenuBeganNotification
                                    : WWNTvRemoteMenuEndedNotification;
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
  });
#else
  (void)pressed;
#endif
}

- (void)_bindMenuButton:(GCControllerButtonInput *)button {
  if (!button) {
    return;
  }
  __weak __typeof(self) weakSelf = self;
  button.pressedChangedHandler =
      ^(GCControllerButtonInput *b, float value, BOOL pressed) {
        (void)b;
        (void)value;
        [weakSelf _postTvMenuPressed:pressed];
      };
}

- (void)_noteRemoteShake {
#if TARGET_OS_TV
  CFTimeInterval now = CACurrentMediaTime();
  if (now - _lastRemoteShakeTime < kRemoteShakeCooldown) {
    return;
  }
  _lastRemoteShakeTime = now;
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:WWNTvRemoteShakeNotification
                      object:nil];
  });
#endif
}

- (BOOL)_shouldEnableRemoteShake:(GCController *)controller {
  if (!controller.motion) {
    return NO;
  }
  if (@available(iOS 15.0, tvOS 15.0, *)) {
    NSString *cat = controller.productCategory;
    // Black glass 1st-gen: Micro profile with motion.
    if ([cat isEqualToString:GCProductCategorySiriRemote1stGen]) {
      return YES;
    }
    // Silver clickpad remotes (2nd gen and 3rd gen USB-C): Directional, no IMU.
    if ([cat isEqualToString:GCProductCategorySiriRemote2ndGen]) {
      return NO;
    }
    // iPhone Control Center / Apple TV Remote app: touch only, no gyro.
    if ([cat isEqualToString:GCProductCategoryControlCenterRemote]) {
      return NO;
    }
    if ([cat isEqualToString:GCProductCategoryCoalescedRemote]) {
      return NO;
    }
  }
  // DualSense / Xbox / MFi: real IMU, not a virtual remote.
  return controller.extendedGamepad != nil;
}

- (void)_configureMotion:(GCController *)controller {
  if (![self _shouldEnableRemoteShake:controller]) {
    return;
  }
  GCMotion *motion = controller.motion;
  if (!motion) {
    return;
  }
  if (@available(iOS 14.0, tvOS 14.0, *)) {
    motion.sensorsActive = YES;
  }
  __weak __typeof(self) weakSelf = self;
  motion.valueChangedHandler = ^(GCMotion *m) {
    // Apple does not deliver UIEventSubtypeMotionShake for the Siri Remote.
    // Classify a shake from userAcceleration (g, gravity removed).
    GCAcceleration a = m.userAcceleration;
    double mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    if (mag >= kRemoteShakeG) {
      [weakSelf _noteRemoteShake];
    }
  };
}

- (void)_configureExtendedGamepad:(GCExtendedGamepad *)pad {
  __weak __typeof(self) weakSelf = self;
  pad.buttonA.pressedChangedHandler =
      ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button;
        (void)value;
        [[weakSelf _targetView] clickVirtualPointerButton:kBtnLeft
                                                  pressed:pressed];
      };
  pad.buttonB.pressedChangedHandler =
      ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button;
        (void)value;
        [[weakSelf _targetView] clickVirtualPointerButton:kBtnRight
                                                  pressed:pressed];
      };
  pad.dpad.valueChangedHandler =
      ^(GCControllerDirectionPad *dpad, float xValue, float yValue) {
        (void)dpad;
        if (fabsf(xValue) > 0.5f || fabsf(yValue) > 0.5f) {
          [[weakSelf _targetView] moveVirtualPointerByDx:xValue * 10.0
                                                      dy:-yValue * 10.0];
        }
      };
  if (@available(iOS 14.0, tvOS 14.0, *)) {
#if TARGET_OS_TV
    [self _bindMenuButton:pad.buttonMenu];
#endif
  }
}

- (void)_configureMicroGamepad:(GCMicroGamepad *)micro {
  // Relative finger motion on the clickpad / 1st-gen touch surface.
  // Absolute values pin the cursor to pad coordinates and fight swipe-look.
  micro.reportsAbsoluteDpadValues = NO;
  if (@available(iOS 14.0, tvOS 14.0, *)) {
#if TARGET_OS_TV
    [self _bindMenuButton:micro.buttonMenu];
#endif
  }
  // Select/clickpad click already arrives as UIPressTypeSelect. Do not also
  // bind buttonA or a cube gets a double click.
}

- (void)_configureController:(GCController *)controller {
  BOOL any = NO;
  if (controller.extendedGamepad) {
    [self _configureExtendedGamepad:controller.extendedGamepad];
    any = YES;
  }
  if (controller.microGamepad) {
    [self _configureMicroGamepad:controller.microGamepad];
    any = YES;
  }
#if TARGET_OS_TV
  [self _configureMotion:controller];
#endif
  if (!any) {
    return;
  }
  _gamepadConnected = YES;
  NSString *category = @"(unknown)";
  if (@available(iOS 13.0, tvOS 13.0, *)) {
    category = controller.productCategory ?: @"(nil)";
  }
  WWNLog("GAMEPAD",
         @"Controller connected: %@ category=%@ extended=%d micro=%d motion=%d "
         @"shake=%d",
         controller.vendorName ?: @"(unnamed)", category,
         controller.extendedGamepad != nil ? 1 : 0,
         controller.microGamepad != nil ? 1 : 0, controller.motion != nil ? 1 : 0,
         [self _shouldEnableRemoteShake:controller] ? 1 : 0);
  [self _startStickLink];
}

- (void)_startStickLink {
  if (_stickLink) {
    return;
  }
  _lastStickTick = 0;
  _stickLink = [CADisplayLink displayLinkWithTarget:self
                                           selector:@selector(_stickTick:)];
  [_stickLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)_stopStickLink {
  [_stickLink invalidate];
  _stickLink = nil;
}

/// Per-frame analog sampling: extended left stick moves the cursor, right
/// stick scrolls. Siri Remote microGamepad dpad is the clickpad trackpad.
/// Event handlers cannot express "held at constant deflection".
- (void)_stickTick:(CADisplayLink *)link {
  CFTimeInterval now = link.timestamp;
  CFTimeInterval dt = _lastStickTick > 0 ? (now - _lastStickTick) : 0;
  _lastStickTick = now;
  if (dt <= 0 || dt > 0.25) {
    return;
  }
  WWNCompositorView_ios *view = [self _targetView];
  if (!view) {
    return;
  }
  for (GCController *controller in GCController.controllers) {
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (pad) {
      float lx = pad.leftThumbstick.xAxis.value;
      float ly = pad.leftThumbstick.yAxis.value;
      if (fabsf(lx) > kStickDeadzone || fabsf(ly) > kStickDeadzone) {
        [view moveVirtualPointerByDx:lx * kStickCursorSpeed * dt
                                  dy:-ly * kStickCursorSpeed * dt];
      }
      float rx = pad.rightThumbstick.xAxis.value;
      float ry = pad.rightThumbstick.yAxis.value;
      if (fabsf(rx) > kStickDeadzone || fabsf(ry) > kStickDeadzone) {
        [view scrollVirtualPointerByDx:rx * kStickScrollSpeed * dt
                                    dy:-ry * kStickScrollSpeed * dt];
      }
      continue;
    }
    GCMicroGamepad *micro = controller.microGamepad;
    if (!micro) {
      continue;
    }
    float x = micro.dpad.xAxis.value;
    float y = micro.dpad.yAxis.value;
    if (fabsf(x) > kStickDeadzone || fabsf(y) > kStickDeadzone) {
      [view moveVirtualPointerByDx:x * kSiriTouchpadCursorSpeed * dt
                                dy:-y * kSiriTouchpadCursorSpeed * dt];
    }
  }
}

// ---------------------------------------------------------------------------
#pragma mark - GCMouse
// ---------------------------------------------------------------------------

- (void)_mouseConnected:(NSNotification *)note API_AVAILABLE(ios(14.0), tvos(14.0)) {
  [self _configureMouse:note.object];
}

- (void)_mouseDisconnected:(NSNotification *)note API_AVAILABLE(ios(14.0), tvos(14.0)) {
  (void)note;
  _mouseConnected = (GCMouse.mice.count > 0);
  WWNLog("GAMEPAD", @"Mouse disconnected (%lu remain)",
         (unsigned long)GCMouse.mice.count);
}

- (void)_configureMouse:(GCMouse *)mouse API_AVAILABLE(ios(14.0), tvos(14.0)) {
  GCMouseInput *input = mouse.mouseInput;
  if (!input) {
    return;
  }
  _mouseConnected = YES;
  WWNLog("GAMEPAD", @"Mouse connected: %@", mouse.vendorName);

  __weak __typeof(self) weakSelf = self;
  input.mouseMovedHandler = ^(GCMouseInput *m, float deltaX, float deltaY) {
    (void)m;
    dispatch_async(dispatch_get_main_queue(), ^{
      // GCMouse Y is inverted relative to UIKit coordinates.
      [[weakSelf _targetView] moveVirtualPointerByDx:deltaX dy:-deltaY];
    });
  };
  input.leftButton.pressedChangedHandler =
      ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button;
        (void)value;
        dispatch_async(dispatch_get_main_queue(), ^{
          [[weakSelf _targetView] clickVirtualPointerButton:kBtnLeft
                                                    pressed:pressed];
        });
      };
  input.rightButton.pressedChangedHandler =
      ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button;
        (void)value;
        dispatch_async(dispatch_get_main_queue(), ^{
          [[weakSelf _targetView] clickVirtualPointerButton:kBtnRight
                                                    pressed:pressed];
        });
      };
  input.middleButton.pressedChangedHandler =
      ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button;
        (void)value;
        dispatch_async(dispatch_get_main_queue(), ^{
          [[weakSelf _targetView] clickVirtualPointerButton:kBtnMiddle
                                                    pressed:pressed];
        });
      };
  input.scroll.valueChangedHandler =
      ^(GCControllerDirectionPad *scroll, float xValue, float yValue) {
        (void)scroll;
        dispatch_async(dispatch_get_main_queue(), ^{
          [[weakSelf _targetView] scrollVirtualPointerByDx:xValue * 10.0
                                                        dy:yValue * 10.0];
        });
      };
}

// ---------------------------------------------------------------------------
#pragma mark - GCKeyboard
// ---------------------------------------------------------------------------

- (void)_keyboardChanged:(NSNotification *)note {
  (void)note;
  if (@available(iOS 14.0, tvOS 14.0, *)) {
    _keyboardConnected = (GCKeyboard.coalescedKeyboard != nil);
  }
  WWNLog("GAMEPAD", @"Hardware keyboard %@",
         _keyboardConnected ? @"connected" : @"disconnected");
}

@end
