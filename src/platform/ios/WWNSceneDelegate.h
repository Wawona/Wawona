#import <UIKit/UIKit.h>

@interface WWNSceneDelegate : UIResponder <UIWindowSceneDelegate>

@property(strong, nonatomic) UIWindow *window;

/// The intermediate container that holds all Wayland surface views.
/// It is pinned either to the safe area (Respect Safe Area = ON)
/// or to the full screen edges (OFF).
@property(strong, nonatomic) UIView *compositorContainer;

/// Re-evaluate constraints and output size for the current
/// Respect Safe Area preference.  Called on init and on toggle.
- (void)applyRespectSafeAreaPreference;

/// iOS 11/12 have no UIScene.  The app delegate supplies a classic UIWindow
/// and this delegate installs the same UIKit compositor/Machines host.
- (void)connectLegacyWindow:(UIWindow *)window;
- (void)legacyApplicationDidBecomeActive;
- (void)legacyApplicationDidEnterBackground;

@end
