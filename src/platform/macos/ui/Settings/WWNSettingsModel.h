#import "WWNSettingsDefines.h"
#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface WWNSettingItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy, nullable) NSString *key;
/// Stable agent-device / XCUITest id (`wwn.settings.<key>` when key is set).
@property(nonatomic, copy, nullable) NSString *accessibilityIdentifier;
@property(nonatomic, copy, nullable) NSString *desc;
@property(nonatomic, assign) WWNSettingType type;
@property(nonatomic, strong, nullable) id defaultValue;
@property(nonatomic, strong, nullable) NSArray *options;       // Display titles
@property(nonatomic, strong, nullable) NSArray *optionValues;   // Stored values (optional; if nil, options used for both)
@property(nonatomic, copy, nullable) void (^actionBlock)(void);
@property(nonatomic, copy, nullable) NSString *urlString; // For WSettingLink type
@property(nonatomic, copy, nullable)
    NSString *imageURL; // For WSettingHeader type (remote image)
@property(nonatomic, copy, nullable)
    NSString *imageName; // For WSettingHeader type (local asset)
@property(nonatomic, copy, nullable)
    NSString *iconURL; // For WSettingLink type (small icon)
@property(nonatomic, copy, nullable)
    NSString *buttonTitle; // Trailing action label for WSettingLink
/// When NO, control is grayed out and non-interactive (still visible).
@property(nonatomic, assign) BOOL interactive;

+ (instancetype)itemWithTitle:(NSString *)title
                          key:(nullable NSString *)key
                         type:(WWNSettingType)type
                      default:(nullable id)def
                         desc:(nullable NSString *)desc;
@end

@interface WWNPreferencesSection : NSObject
@property(nonatomic, copy) NSString *title;
/// Stable agent-device / XCUITest id (e.g. `wwn.settings.display`).
@property(nonatomic, copy, nullable) NSString *accessibilityIdentifier;
@property(nonatomic, copy, nullable) NSString *icon;
#if TARGET_OS_IPHONE
@property(nonatomic, strong) UIColor *iconColor;
#else
@property(nonatomic, strong) NSColor *iconColor;
#endif
@property(nonatomic, strong) NSArray<WWNSettingItem *> *items;
@end

NS_ASSUME_NONNULL_END
