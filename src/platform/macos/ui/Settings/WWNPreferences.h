#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

NS_ASSUME_NONNULL_BEGIN

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@class WWNPreferencesSection;
@interface WWNPreferences : UITableViewController
@property(nonatomic, strong, readonly)
    NSArray<WWNPreferencesSection *> *sections;
@property(nonatomic, strong) WWNPreferencesSection *activeSection;
#else
@class WWNPreferencesSection;
@interface WWNPreferences : NSWindowController
@property(nonatomic, strong, readonly)
    NSArray<WWNPreferencesSection *> *sections;
#endif

+ (instancetype)sharedPreferences;
- (void)showPreferences:(id)sender;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)dismissSelf;
#endif

@end

NS_ASSUME_NONNULL_END
