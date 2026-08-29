//
//  WWNExternalDisplaySupport.h
//  Wawona. IOS AirPlay / external display mirroring.
//
//  When an external (AirPlay or wired) display connects, iOS creates a scene
//  with the ExternalDisplayNonInteractive role. WWNExternalSceneDelegate hosts
//  a WWNExternalMirrorView on that scene which mirrors the compositor's
//  presented Wayland frames plus the virtual cursor. Input stays on the
//  device: the internal screen switches to touchpad mode (pref-gated) so the
//  device acts as a trackpad driving the cursor shown on the big screen.
//

#import <TargetConditionals.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue when an external display scene connects/disconnects.
extern NSNotificationName const WWNExternalDisplayDidConnectNotification;
extern NSNotificationName const WWNExternalDisplayDidDisconnectNotification;

/// Posted by WWNCompositorView_ios whenever the virtual (touchpad) cursor
/// changes. userInfo: @"position" (NSValue/CGPoint, container coords),
/// @"hidden" (NSNumber/BOOL), @"width"/@"height" (NSNumber), and optionally
/// @"contents" (CGImageRef bridged id).
extern NSNotificationName const WWNVirtualCursorStateNotification;

/// YES while an external display scene is connected.
BOOL WWNExternalDisplayIsConnected(void);

/// Mirrors presented Wayland window frames (and the virtual cursor) onto an
/// external display, aspect-fit scaled from the compositor container space.
@interface WWNExternalMirrorView : UIView

/// Mirror one window's presented frame. `frame` is in compositor-container
/// coordinates; `containerSize` is the logical size of that container. Pass
/// image == NULL to remove the window's mirror layer.
- (void)mirrorWindow:(uint64_t)windowId
               image:(nullable CGImageRef)image
               frame:(CGRect)frame
         contentRect:(CGRect)contentRect
       containerSize:(CGSize)containerSize
       contentsScale:(CGFloat)contentsScale
     contentsGravity:(NSString *)contentsGravity;

/// Drop a destroyed window's mirror layer.
- (void)removeWindow:(uint64_t)windowId;

@end

/// Scene delegate for UIWindowSceneSessionRoleExternalDisplayNonInteractive.
@interface WWNExternalSceneDelegate : NSObject <UIWindowSceneDelegate>
@property(nonatomic, strong, nullable) UIWindow *window;
@end

NS_ASSUME_NONNULL_END
