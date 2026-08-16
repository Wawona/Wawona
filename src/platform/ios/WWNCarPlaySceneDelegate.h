//
//  WWNCarPlaySceneDelegate.h
//  Wawona. CarPlay template scene.
//
//  CarPlay only allows template-based UI for non-media apps, so Wawona's
//  CarPlay presence is a status dashboard: connected machines, running
//  clients, and the compositor state. Full Wayland surfaces cannot legally
//  render on the car screen.
//
//  Requires the Apple-granted CarPlay entitlement (see
//  src/resources/app-bundle/Wawona-CarPlay.entitlements.template). Without it
//  the scene role never connects and this class stays dormant.
//

#import <TargetConditionals.h>

#if !TARGET_OS_TV && !TARGET_OS_VISION && !TARGET_OS_WATCH && !TARGET_OS_OSX
#if __has_include(<CarPlay/CarPlay.h>)
#define WWN_HAS_CARPLAY 1
#import <CarPlay/CarPlay.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNCarPlaySceneDelegate
    : UIResponder <CPTemplateApplicationSceneDelegate>
@end

NS_ASSUME_NONNULL_END

#endif /* __has_include */
#endif /* platform guard */
