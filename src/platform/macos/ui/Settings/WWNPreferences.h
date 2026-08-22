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

+ (instancetype)sharedPreferences NS_SWIFT_NAME(shared());
- (void)showPreferences:(nullable id)sender NS_SWIFT_NAME(show(_:));
- (void)selectSectionWithTitle:(NSString *)title;
- (void)openEnvironmentVariablesManager;
- (void)openMachinesConfiguration:(id)sender;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)dismissSelf;
#endif

@end

NS_ASSUME_NONNULL_END
