#import <TargetConditionals.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNSettingsSplitViewController : UISplitViewController

@end

NS_ASSUME_NONNULL_END

#endif
