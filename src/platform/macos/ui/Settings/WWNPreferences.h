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
/// Secondary-column nav for Settings. Env Vars may replace this table as the
/// visible root; keep the column nav so we can swap back.
@property(nonatomic, weak, nullable)
    UINavigationController *settingsColumnNavigationController;
#else
@class WWNPreferencesSection;
@interface WWNPreferences : NSWindowController
@property(nonatomic, strong, readonly)
    NSArray<WWNPreferencesSection *> *sections;
#endif

+ (instancetype)sharedPreferences NS_SWIFT_NAME(shared());
- (void)showPreferences:(nullable id)sender NS_SWIFT_NAME(show(_:));
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
/// Embed sidebar + catalog in `hostView` (in-app window or NSPreferencePane).
- (void)installMacSettingsInterfaceInView:(NSView *)hostView;
#endif
- (void)selectSectionWithTitle:(NSString *)title;
- (void)openEnvironmentVariablesManager;
- (void)openMachinesConfiguration:(id)sender;
/// Rebuild `sections` from `buildSections` (auth method / cursor prefs change
/// which rows a section shows). Used by the SwiftUI unified window.
- (void)rebuildSections;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)dismissSelf;
#endif

@end

NS_ASSUME_NONNULL_END
