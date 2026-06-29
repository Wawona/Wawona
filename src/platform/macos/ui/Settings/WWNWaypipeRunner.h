#import "WWNPreferencesManager.h"
#import <Foundation/Foundation.h>

typedef void (^WaypipeOutputHandler)(NSString *output);

@protocol WWNWaypipeRunnerDelegate <NSObject>
- (void)runnerDidReceiveSSHPasswordPrompt:(NSString *)prompt;
- (void)runnerDidReceiveSSHError:(NSString *)error;
- (void)runnerDidReadData:(NSData *)data;
- (void)runnerDidReceiveOutput:(NSString *)output isError:(BOOL)isError;
- (void)runnerDidFinishWithExitCode:(int)exitCode;
@end

@interface WWNWaypipeRunner : NSObject

@property(nonatomic, weak) id<WWNWaypipeRunnerDelegate> delegate;
@property(nonatomic, readonly) BOOL isRunning;
@property(nonatomic, readonly) BOOL isWestonSimpleSHMRunning;
/// YES while the in-process weston compositor client is running.
@property(nonatomic, readonly) BOOL westonRunning;
/// YES while the in-process weston-terminal client is running.
@property(nonatomic, readonly) BOOL westonTerminalRunning;
/// YES while the in-process foot terminal client is running.
@property(nonatomic, readonly) BOOL footRunning;

+ (instancetype)sharedRunner NS_SWIFT_NAME(shared());

// Logic Helpers
- (NSString *)findWaypipeBinary;
- (NSArray<NSString *> *)buildWaypipeArguments:(WWNPreferencesManager *)prefs;
- (NSString *)generateWaypipePreviewString:(WWNPreferencesManager *)prefs;

// Pre-flight validation (returns nil if OK, or an error description)
- (NSString *)validatePreflightForPrefs:(WWNPreferencesManager *)prefs;

// Execution
- (void)launchWaypipe:(WWNPreferencesManager *)prefs;
- (void)stopWaypipe;

- (void)launchWestonSimpleSHM;
- (void)stopWestonSimpleSHM;

- (void)launchWeston;
- (void)launchWestonDrm;
- (void)stopWeston;

- (void)launchWestonTerminal;
- (void)stopWestonTerminal;

- (void)launchFoot;
- (void)stopFoot;

/// Launch any bundled Wayland client by id (weston-flower, weston-smoke, …).
- (void)launchBundledClientWithId:(NSString *)clientId;

#if TARGET_OS_IPHONE
/// Disconnect in-process clients and reset iOS native launch state.
- (void)stopActiveIOSBundledClient;
#endif

/// Terminate all bundled native Wayland clients (weston, foot, etc.).
- (void)stopAllNativeClients;

/// YES while any bundled native client or in-process iOS launch is active.
- (BOOL)isAnyNativeClientRunning;

@end
