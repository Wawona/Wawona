#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNLaunchAgentManager : NSObject

+ (instancetype)sharedManager;

- (BOOL)installCompositorAndMenuAgents:(NSError * _Nullable * _Nullable)error;
- (BOOL)ensureCompositorAndMenuAgents:(NSError * _Nullable * _Nullable)error;
- (BOOL)ensureCompositorAgent:(NSError * _Nullable * _Nullable)error;
- (BOOL)ensureMenuBarAgent:(NSError * _Nullable * _Nullable)error;

- (BOOL)restartCompositorAgent;
- (BOOL)stopCompositorAgent;
- (BOOL)startCompositorAgent;

- (BOOL)isCompositorAgentLoaded;
- (BOOL)isAppLaunchAgentLoaded;

- (BOOL)enableAppLaunchAtLogin;
- (BOOL)disableAppLaunchAtLogin;

@end

NS_ASSUME_NONNULL_END
