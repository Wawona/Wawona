#import <TargetConditionals.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR

#import "WWNSettingsSidebarViewController.h"
#import "WWNPreferences.h"
#import "WWNSettingsModel.h"

@interface WWNSettingsSidebarViewController () {
  BOOL _hasPerformedInitialSelection;
}
@property(nonatomic, strong)
    UICollectionViewDiffableDataSource<NSString *, WWNPreferencesSection *>
        *dataSource;
@end

@implementation WWNSettingsSidebarViewController

- (instancetype)initWithPreferences:(WWNPreferences *)preferences {
#if TARGET_OS_TV
  // tvOS does not expose the inset-grouped list appearance.
  UICollectionLayoutListConfiguration *config =
      [[UICollectionLayoutListConfiguration alloc]
          initWithAppearance:UICollectionLayoutListAppearancePlain];
#else
  UICollectionLayoutListConfiguration *config =
      [[UICollectionLayoutListConfiguration alloc]
          initWithAppearance:UICollectionLayoutListAppearanceSidebar];
#endif
  UICollectionViewCompositionalLayout *layout =
      [UICollectionViewCompositionalLayout layoutWithListConfiguration:config];

  self = [super initWithCollectionViewLayout:layout];
  if (self) {
    _preferencesDetailViewController = preferences;
    _hasPerformedInitialSelection = NO;
  }
  return self;
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];

  // Ensure selection matches active section on initial presentation ONLY ONCE
  // AND only if the split view is NOT collapsed (iPhone/compact width).
  // If collapsed, we want to stay on the list (sidebar) and not auto-navigate
  // to detail.
  if (!_hasPerformedInitialSelection &&
      self.preferencesDetailViewController.sections.count > 0 &&
      !self.splitViewController.collapsed) {

    _hasPerformedInitialSelection = YES;

    // Only select if nothing is currently selected (e.g. fresh launch)
    if (self.collectionView.indexPathsForSelectedItems.count == 0) {
      NSInteger index = 0;
      if (self.preferencesDetailViewController.activeSection) {
        index = [self.preferencesDetailViewController.sections
            indexOfObject:self.preferencesDetailViewController.activeSection];
        if (index == NSNotFound) {
          index = 0;
        }
      }

      NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
      [self.collectionView
          selectItemAtIndexPath:indexPath
                       animated:NO
                 scrollPosition:UICollectionViewScrollPositionNone];

      // Trigger selection logic to update Detail view
      [self collectionView:self.collectionView
          didSelectItemAtIndexPath:indexPath];
    }
  }
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.title = @"Settings";
  self.view.accessibilityIdentifier = @"wwn.settings.root";
  self.view.accessibilityLabel = @"Settings";
#if TARGET_OS_TV
  // tvOS focus rings draw larger than the cell. Parent clipsToBounds would
  // cut the platter at the split divider (a common UIKit issue).
  self.view.clipsToBounds = NO;
  self.collectionView.clipsToBounds = NO;
  self.collectionView.layer.masksToBounds = NO;
  self.collectionView.contentInset = UIEdgeInsetsMake(8, 12, 24, 28);
  self.collectionView.remembersLastFocusedIndexPath = YES;
#else
  self.navigationController.navigationBar.prefersLargeTitles = YES;
#endif
  [self wwn_syncDismissButtonWithSplitView];

  // Configure cell registration
  UICollectionViewCellRegistration *cellRegistration =
      [UICollectionViewCellRegistration
          registrationWithCellClass:[UICollectionViewListCell class]
               configurationHandler:^(UICollectionViewListCell *cell,
                                      NSIndexPath *indexPath,
                                      WWNPreferencesSection *section) {
                 (void)indexPath;
                 cell.accessories =
                     @[ [[UICellAccessoryDisclosureIndicator alloc] init] ];
                 cell.accessibilityLabel = section.title;
                 cell.accessibilityIdentifier =
                     section.accessibilityIdentifier
                         ?: [NSString
                                stringWithFormat:@"wwn.settings.%@",
                                                 [[section.title lowercaseString]
                                                     stringByReplacingOccurrencesOfString:
                                                         @" "
                                                                             withString:@"."]];
#if TARGET_OS_TV
                 cell.configurationUpdateHandler =
                     ^(UICollectionViewListCell *updatedCell,
                       UICellConfigurationState *state) {
                       UIListContentConfiguration *content =
                           [updatedCell defaultContentConfiguration];
                       content.text = section.title;
                       content.image = [UIImage systemImageNamed:section.icon];
                       if (state.isFocused) {
                         // Focused tvOS platter is light. labelColor stays
                         // white and the title vanishes without this swap.
                         content.textProperties.color = [UIColor blackColor];
                         content.imageProperties.tintColor = [UIColor darkGrayColor];
                       } else if (section.iconColor) {
                         content.textProperties.color = [UIColor labelColor];
                         content.imageProperties.tintColor = section.iconColor;
                       } else {
                         content.textProperties.color = [UIColor labelColor];
                       }
                       updatedCell.contentConfiguration = content;
                       UIBackgroundConfiguration *bg =
                           [UIBackgroundConfiguration listGroupedCellConfiguration];
                       bg.backgroundInsets =
                           NSDirectionalEdgeInsetsMake(4, 8, 4, 12);
                       updatedCell.backgroundConfiguration = bg;
                     };
#else
                 UIListContentConfiguration *content =
                     [cell defaultContentConfiguration];
                 content.text = section.title;
                 content.image = [UIImage systemImageNamed:section.icon];
                 if (section.iconColor) {
                   content.imageProperties.tintColor = section.iconColor;
                 }
                 cell.contentConfiguration = content;
#endif
               }];

  // Configure data source
  self.dataSource = [[UICollectionViewDiffableDataSource alloc]
      initWithCollectionView:self.collectionView
                cellProvider:^UICollectionViewCell *_Nullable(
                    UICollectionView *collectionView, NSIndexPath *indexPath,
                    WWNPreferencesSection *itemIdentifier) {
                  return [collectionView
                      dequeueConfiguredReusableCellWithRegistration:
                          cellRegistration
                                                       forIndexPath:indexPath
                                                               item:
                                                                   itemIdentifier];
                }];

  [self updateSnapshot];
}

- (void)dismissSettings {
  [self.splitViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self wwn_syncDismissButtonWithSplitView];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:
           (id<UIViewControllerTransitionCoordinator>)coordinator {
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  [coordinator
      animateAlongsideTransition:^(
          id<UIViewControllerTransitionCoordinatorContext> context) {
        (void)context;
        [self wwn_syncDismissButtonWithSplitView];
      }
      completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        (void)context;
        [self wwn_syncDismissButtonWithSplitView];
      }];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
  [super traitCollectionDidChange:previousTraitCollection];
  [self wwn_syncDismissButtonWithSplitView];
}

// Expanded split (iPhone landscape / iPad): the system already shows the
// sidebar toggle. Done lives on the detail column (blue checkmark). Showing
// another Done on this nav bar duplicates it next to the toggle.
// tvOS is always two columns: never put Done in the sidebar.
- (void)wwn_syncDismissButtonWithSplitView {
#if TARGET_OS_TV
  self.navigationItem.rightBarButtonItem = nil;
  self.navigationItem.leftBarButtonItem = nil;
  return;
#else
  UISplitViewController *split = self.splitViewController;
  if (split && !split.collapsed) {
    self.navigationItem.rightBarButtonItem = nil;
    return;
  }
  if (self.navigationItem.rightBarButtonItem) {
    return;
  }
  UIBarButtonItem *done =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                    target:self
                                                    action:@selector(dismissSettings)];
  done.accessibilityIdentifier = @"wwn.settings.done";
  done.accessibilityLabel = @"Done";
  self.navigationItem.rightBarButtonItem = done;
#endif
}

- (void)updateSnapshot {
  NSDiffableDataSourceSnapshot<NSString *, WWNPreferencesSection *>
      *snapshot = [[NSDiffableDataSourceSnapshot alloc] init];
  [snapshot appendSectionsWithIdentifiers:@[ @"Main" ]];
  [snapshot
      appendItemsWithIdentifiers:self.preferencesDetailViewController.sections];
  [self.dataSource applySnapshot:snapshot animatingDifferences:NO];
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView
    didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
  WWNPreferencesSection *section =
      [self.dataSource itemIdentifierForIndexPath:indexPath];

  self.preferencesDetailViewController.activeSection = section;
  self.preferencesDetailViewController.title = section.title;

  // Always show the secondary nav. After Env Vars swaps in the inventory,
  // Preferences is no longer in that nav, so falling back to it would show
  // the stub table again.
  UIViewController *detail = self.detailNavigationController
      ?: self.preferencesDetailViewController.navigationController
      ?: self.preferencesDetailViewController;
  if (self.splitViewController.isCollapsed) {
    [self.splitViewController showDetailViewController:detail sender:nil];
  } else if (self.preferencesDetailViewController.parentViewController !=
                 self &&
             self.preferencesDetailViewController.parentViewController !=
                 self.splitViewController &&
             self.detailNavigationController.parentViewController !=
                 self.splitViewController &&
             self.preferencesDetailViewController.navigationController
                     .parentViewController != self.splitViewController) {
    [self.splitViewController showDetailViewController:detail sender:nil];
  }
}

@end

#endif // TARGET_OS_IPHONE
