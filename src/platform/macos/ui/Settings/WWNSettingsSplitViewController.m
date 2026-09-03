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

    UINavigationController *sidebarNav =
        [[UINavigationController alloc] initWithRootViewController:sidebar];
    UINavigationController *detailNav =
        [[UINavigationController alloc] initWithRootViewController:preferences];
    sidebar.detailNavigationController = detailNav;
    preferences.settingsColumnNavigationController = detailNav;
    [self setViewController:sidebarNav
                  forColumn:UISplitViewControllerColumnPrimary];
    [self setViewController:detailNav
                  forColumn:UISplitViewControllerColumnSecondary];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
#if TARGET_OS_TV
  self.view.clipsToBounds = NO;
  UIViewController *primary =
      [self viewControllerForColumn:UISplitViewControllerColumnPrimary];
  primary.view.clipsToBounds = NO;
  if ([primary isKindOfClass:[UINavigationController class]]) {
    ((UINavigationController *)primary).view.clipsToBounds = NO;
  }
  UIViewController *secondary =
      [self viewControllerForColumn:UISplitViewControllerColumnSecondary];
  secondary.view.clipsToBounds = NO;
  if ([secondary isKindOfClass:[UINavigationController class]]) {
    ((UINavigationController *)secondary).view.clipsToBounds = NO;
  }
#endif
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
#if !TARGET_OS_TV && !TARGET_OS_VISION
  UISheetPresentationController *sheet = self.sheetPresentationController;
  if (sheet) {
    sheet.prefersGrabberVisible = YES;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
  }
#endif
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
#if TARGET_OS_TV
  (void)splitViewController;
  (void)secondaryViewController;
  (void)primaryViewController;
  // Keep sidebar + detail both on screen. Collapsing produces an iPhone
  // list in the corner of a 1920px display.
  return NO;
#else
  // Return YES to prevent collapsing the secondary view controller onto the
  // primary view controller This allows the primary (sidebar) to be the initial
  // view on iPhone
  return YES;
#endif
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
