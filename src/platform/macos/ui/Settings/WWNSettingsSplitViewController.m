#import <TargetConditionals.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR

#import "WWNSettingsSplitViewController.h"
#import "WWNPreferences.h"
#import "WWNSettingsSidebarViewController.h"

@interface WWNSettingsSplitViewController () <UISplitViewControllerDelegate>
@end

@implementation WWNSettingsSplitViewController

- (instancetype)init {
  self = [super initWithStyle:UISplitViewControllerStyleDoubleColumn];
  if (self) {
    self.delegate = self;
    self.preferredDisplayMode =
        UISplitViewControllerDisplayModeOneBesideSecondary;
    self.preferredSplitBehavior = UISplitViewControllerSplitBehaviorTile;

    WWNPreferences *preferences = [WWNPreferences sharedPreferences];
    WWNSettingsSidebarViewController *sidebar =
        [[WWNSettingsSidebarViewController alloc]
            initWithPreferences:preferences];

    [self setViewController:sidebar
                  forColumn:UISplitViewControllerColumnPrimary];
    [self setViewController:preferences
                  forColumn:UISplitViewControllerColumnSecondary];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  // Additional setup if needed
}

#pragma mark - UISplitViewControllerDelegate

- (WWNSettingsSidebarViewController *)wwn_sidebarController {
  UIViewController *primary =
      [self viewControllerForColumn:UISplitViewControllerColumnPrimary];
  if ([primary isKindOfClass:[UINavigationController class]]) {
    primary = ((UINavigationController *)primary).viewControllers.firstObject;
  }
  if ([primary isKindOfClass:[WWNSettingsSidebarViewController class]]) {
    return (WWNSettingsSidebarViewController *)primary;
  }
  return nil;
}

- (BOOL)splitViewController:(UISplitViewController *)splitViewController
    collapseSecondaryViewController:(UIViewController *)secondaryViewController
          ontoPrimaryViewController:(UIViewController *)primaryViewController {
  // Return YES to prevent collapsing the secondary view controller onto the
  // primary view controller This allows the primary (sidebar) to be the initial
  // view on iPhone
  return YES;
}

- (void)splitViewControllerDidExpand:(UISplitViewController *)svc {
  (void)svc;
  [[self wwn_sidebarController] wwn_syncDismissButtonWithSplitView];
}

- (void)splitViewControllerDidCollapse:(UISplitViewController *)svc {
  (void)svc;
  [[self wwn_sidebarController] wwn_syncDismissButtonWithSplitView];
}

@end

#endif // TARGET_OS_IPHONE
