//
//  WWNGameControllerManager.h
//  Wawona. GameController framework input (gamepads, GCMouse, GCKeyboard).
//
//  Maps connected game controllers and framework-level mice onto the
//  compositor's virtual pointer:
//    - GCMouse: relative deltas, left/right/middle buttons, scroll wheel.
//    - Gamepad: left stick / dpad moves the cursor, A = left click,
//      B = right click, right stick scrolls.
//    - Siri Remote (tvOS): GCMicroGamepad dpad is the clickpad trackpad.
//      Menu posts session-exit. Shake is 1st-gen only, via GCMotion.
//  GCKeyboard presence is tracked only. Key events already arrive through
//  UIKit's pressesBegan/pressesEnded path and must not be double-injected.
//

#import <TargetConditionals.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 1st-gen Siri Remote `GCMotion` shake (we classify acceleration ourselves).
FOUNDATION_EXPORT NSNotificationName const WWNTvRemoteShakeNotification;
/// Menu/Back on the Siri Remote (GameController buttonMenu backup for UIKit).
FOUNDATION_EXPORT NSNotificationName const WWNTvRemoteMenuBeganNotification;
FOUNDATION_EXPORT NSNotificationName const WWNTvRemoteMenuEndedNotification;
FOUNDATION_EXPORT NSNotificationName const WWNTvRemoteMenuCancelledNotification;

@interface WWNGameControllerManager : NSObject

+ (instancetype)sharedManager;

/// Begin observing controller/mouse/keyboard connections. Idempotent.
- (void)start;

/// YES when a hardware gamepad is currently connected.
@property(nonatomic, readonly) BOOL gamepadConnected;
/// YES when a GCMouse is currently connected.
@property(nonatomic, readonly) BOOL mouseConnected;
/// YES when a GCKeyboard is currently connected.
@property(nonatomic, readonly) BOOL keyboardConnected;

@end

NS_ASSUME_NONNULL_END
