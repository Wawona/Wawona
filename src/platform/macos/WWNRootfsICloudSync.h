#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// User preference key — also used by settings UI (`WSettingSwitch`).
FOUNDATION_EXPORT NSString *const WWNRootfsICloudSyncPreferenceKey;

/// Optional iCloud Drive sync for shell HOME (Apple platforms, user opt-in).
@interface WWNRootfsICloudSync : NSObject

+ (BOOL)isSupported;

+ (BOOL)isEnabled;

+ (BOOL)isContainerAvailable;

+ (nullable NSString *)icloudHomePath;

+ (nullable NSString *)statusSummary;

+ (void)prepareICloudLayout;

/// Enable/disable sync and migrate HOME contents between local and iCloud storage.
+ (BOOL)setEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
