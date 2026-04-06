#import <TargetConditionals.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>

@class WWNPreferences;

NS_ASSUME_NONNULL_BEGIN

@interface WWNSettingsSidebarViewController : UICollectionViewController

@property (nonatomic, weak) WWNPreferences *preferencesDetailViewController;

- (instancetype)initWithPreferences:(WWNPreferences *)preferences;

@end

NS_ASSUME_NONNULL_END

#endif
