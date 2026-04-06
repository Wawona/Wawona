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
  UICollectionLayoutListConfiguration *config =
      [[UICollectionLayoutListConfiguration alloc]
          initWithAppearance:UICollectionLayoutListAppearanceSidebar];
  UICollectionViewCompositionalLayout *layout =
      [UICollectionViewCompositionalLayout layoutWithListConfiguration:config];

  self = [super initWithCollectionViewLayout:layout];
  if (self) {
    _preferencesDetailViewController = preferences;
    _hasPerformedInitialSelection = NO;
  }
  return self;
}
// ... (viewDidLoad stays same) ...

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
  self.navigationController.navigationBar.prefersLargeTitles = YES;

  // Add Done button to dismiss settings

  // Configure cell registration
  UICollectionViewCellRegistration *cellRegistration =
      [UICollectionViewCellRegistration
          registrationWithCellClass:[UICollectionViewListCell class]
               configurationHandler:^(UICollectionViewListCell *cell,
                                      NSIndexPath *indexPath,
                                      WWNPreferencesSection *section) {
                 UIListContentConfiguration *content =
                     [cell defaultContentConfiguration];
                 content.text = section.title;
                 content.image = [UIImage systemImageNamed:section.icon];

                 // Use the section color for the icon
                 if (section.iconColor) {
                   content.imageProperties.tintColor = section.iconColor;
                 }

                 cell.contentConfiguration = content;
                 cell.accessories =
                     @[ [[UICellAccessoryDisclosureIndicator alloc] init] ];
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

  // Set the active section on the detail view controller
  self.preferencesDetailViewController.activeSection = section;

  // Refresh the detail view
  [self.preferencesDetailViewController.tableView reloadData];
  self.preferencesDetailViewController.title = section.title;

  // On iPhone (compact width), we need to push the detail view
  // On iPad (regular width), the split view shows both, so we just update the
  // detail
  if (self.splitViewController.isCollapsed) {
    [self.splitViewController
        showDetailViewController:self.preferencesDetailViewController
                          sender:nil];
  } else {
    // Ensure detail is shown (might be needed if we were in a different state)
    if (self.preferencesDetailViewController.parentViewController != self &&
        self.preferencesDetailViewController.parentViewController !=
            self.splitViewController) {
      [self.splitViewController
          showDetailViewController:self.preferencesDetailViewController
                            sender:nil];
    }
  }
}

@end

#endif // TARGET_OS_IPHONE
