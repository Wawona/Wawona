#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// ObjC bridge to `wawona.pref.*` UserDefaults — same keys as Swift `WawonaPreferences`.
/// Used by WatchKit settings interface controllers (not SwiftUI).
/// Field set must match `GlobalSettingsCatalog` for watchOS.
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
@property (nonatomic, assign) BOOL renderMacOSPointer;
@property (nonatomic, copy) NSString *nestedCompositorCursor;
@property (nonatomic, assign) BOOL resizeDisplayForVirtualKeyboard;
@property (nonatomic, assign) BOOL swapCmdWithAlt;
@property (nonatomic, assign) BOOL universalClipboard;
@property (nonatomic, copy) NSString *compositorBackend;
@property (nonatomic, assign) BOOL nestedCompositorsSupport;
@property (nonatomic, assign) BOOL multipleClients;
@property (nonatomic, assign) BOOL xwaylandSupport;
@property (nonatomic, copy) NSString *waypipeCompress;
@property (nonatomic, copy) NSString *waypipeVideo;
@property (nonatomic, copy) NSString *waypipeRemoteCommand;
@property (nonatomic, assign) BOOL waypipeDebug;
@property (nonatomic, assign) BOOL waypipeNoGpu;
@property (nonatomic, copy) NSString *waypipeSSHPassword;
@property (nonatomic, copy) NSString *sshHost;
@property (nonatomic, copy) NSString *sshUser;
@property (nonatomic, assign) NSInteger sshPort;
@property (nonatomic, copy) NSString *sshPassword;
@property (nonatomic, assign) NSInteger sshAuthMethod;
@property (nonatomic, copy) NSString *sshKeyPath;
@property (nonatomic, copy) NSString *sshKeyPassphrase;
@property (nonatomic, copy) NSString *sshKeyType;
@property (nonatomic, copy) NSString *logLevel;
@property (nonatomic, assign) BOOL shakeToCloseEnabled;
@property (nonatomic, assign) BOOL swipeBackToCloseEnabled;

/// Re-read properties from UserDefaults (call when presenting settings UI).
- (void)reloadFromDefaults;

/// Persist all properties to UserDefaults and post `WawonaPreferencesDidSave`.
- (void)synchronize;

@end

NS_ASSUME_NONNULL_END
