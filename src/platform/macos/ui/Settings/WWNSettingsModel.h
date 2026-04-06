#import "WWNSettingsDefines.h"
#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

@interface WWNSettingItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *desc;
@property(nonatomic, assign) WWNSettingType type;
@property(nonatomic, strong) id defaultValue;
@property(nonatomic, strong) NSArray *options;       // Display titles
@property(nonatomic, strong) NSArray *optionValues;   // Stored values (optional; if nil, options used for both)
@property(nonatomic, copy) void (^actionBlock)(void);
@property(nonatomic, copy) NSString *urlString; // For WSettingLink type
@property(nonatomic, copy)
    NSString *imageURL; // For WSettingHeader type (remote image)
@property(nonatomic, copy)
    NSString *imageName; // For WSettingHeader type (local asset)
@property(nonatomic, copy)
    NSString *iconURL; // For WSettingLink type (small icon)

+ (instancetype)itemWithTitle:(NSString *)title
                          key:(NSString *)key
                         type:(WWNSettingType)type
                      default:(id)def
                         desc:(NSString *)desc;
@end

@interface WWNPreferencesSection : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *icon;
#if TARGET_OS_IPHONE
@property(nonatomic, strong) UIColor *iconColor;
#else
@property(nonatomic, strong) NSColor *iconColor;
#endif
@property(nonatomic, strong) NSArray<WWNSettingItem *> *items;
@end
