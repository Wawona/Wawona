#import <TargetConditionals.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>

@class WWNPreferences;

NS_ASSUME_NONNULL_BEGIN

@interface WWNSettingsSidebarViewController : UICollectionViewController

@property (nonatomic, weak) WWNPreferences *preferencesDetailViewController;
/// Secondary-column nav. Keep this even when Env Vars replaces Preferences as
/// the visible root; otherwise collapsed iPhone `showDetail` falls back to the
/// Preferences table (the one-row "Open Environment Variables" stub).
@property (nonatomic, weak) UINavigationController *detailNavigationController;

- (instancetype)initWithPreferences:(WWNPreferences *)preferences;
- (void)wwn_syncDismissButtonWithSplitView;

@end

NS_ASSUME_NONNULL_END

#endif
