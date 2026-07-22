#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// ObjC bridge to `wawona.pref.*` UserDefaults — same keys as Swift `WawonaPreferences`.
/// Used by WatchKit settings interface controllers (not SwiftUI).
@interface WWNWatchSettingsBridge : NSObject

+ (instancetype)sharedBridge;

@property (nonatomic, assign) BOOL autoScale;
@property (nonatomic, assign) BOOL forceSSD;
@property (nonatomic, assign) BOOL colorOperations;
@property (nonatomic, copy) NSString *renderer;
@property (nonatomic, copy) NSString *waylandDisplay;
@property (nonatomic, copy) NSString *defaultInputProfile;
@property (nonatomic, copy) NSString *defaultBundledAppID;
@property (nonatomic, assign) BOOL defaultWaypipeEnabled;
@property (nonatomic, copy) NSString *sshHost;
@property (nonatomic, copy) NSString *sshUser;
@property (nonatomic, assign) NSInteger sshPort;
@property (nonatomic, copy) NSString *sshPassword;
@property (nonatomic, copy) NSString *logLevel;
@property (nonatomic, assign) BOOL shakeToCloseEnabled;
@property (nonatomic, assign) BOOL swipeBackToCloseEnabled;

/// Re-read properties from UserDefaults (call when presenting settings UI).
- (void)reloadFromDefaults;

/// Persist all properties to UserDefaults and post `WawonaPreferencesDidSave`.
- (void)synchronize;

@end

NS_ASSUME_NONNULL_END
