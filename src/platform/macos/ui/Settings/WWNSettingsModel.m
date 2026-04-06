#import "WWNSettingsModel.h"

@implementation WWNSettingItem
+ (instancetype)itemWithTitle:(NSString *)title
                          key:(NSString *)key
                         type:(WWNSettingType)type
                      default:(id)def
                         desc:(NSString *)desc {
  WWNSettingItem *item = [[WWNSettingItem alloc] init];
  item.title = title;
  item.key = key;
  item.type = type;
  item.defaultValue = def;
  item.desc = desc;
  return item;
}
@end

@implementation WWNPreferencesSection
@end
