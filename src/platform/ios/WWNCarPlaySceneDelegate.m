//
//  WWNCarPlaySceneDelegate.m
//  Wawona. CarPlay template scene. See header.
//

#import "WWNCarPlaySceneDelegate.h"

#ifdef WWN_HAS_CARPLAY

#import "../../util/WWNLog.h"
#import "WWNCompositorBridge.h"

@implementation WWNCarPlaySceneDelegate {
  CPInterfaceController *_interfaceController;
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)scene
    didConnectInterfaceController:(CPInterfaceController *)interfaceController {
  (void)scene;
  _interfaceController = interfaceController;
  WWNLog("CARPLAY", @"CarPlay scene connected");

  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  BOOL running = [bridge isRunning];

  CPListItem *status = [[CPListItem alloc]
      initWithText:@"Compositor"
        detailText:running
                       ? [NSString stringWithFormat:@"Running (%@)",
                                                    [bridge socketName]]
                       : @"Stopped"];
  CPListSection *section =
      [[CPListSection alloc] initWithItems:@[ status ]
                                    header:@"Wawona Status"
                         sectionIndexTitle:nil];
  CPListTemplate *list =
      [[CPListTemplate alloc] initWithTitle:@"Wawona"
                                   sections:@[ section ]];
  [interfaceController setRootTemplate:list animated:NO completion:nil];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)scene
    didDisconnectInterfaceController:(CPInterfaceController *)interfaceController {
  (void)scene;
  (void)interfaceController;
  _interfaceController = nil;
  WWNLog("CARPLAY", @"CarPlay scene disconnected");
}

@end

#endif /* WWN_HAS_CARPLAY */
