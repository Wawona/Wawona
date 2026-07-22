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
/// YES while at least one weston-terminal instance is running.
@property(nonatomic, readonly) BOOL westonTerminalRunning;
/// YES while at least one foot terminal instance is running.
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
/// Always starts a new instance — multiple copies of the same client are allowed.
- (void)launchBundledClientWithId:(NSString *)clientId;

/// Launch a bundled client and associate it with a Machines profile so Stop
/// only terminates that instance (other copies of the same client keep running).
- (void)launchBundledClientWithId:(NSString *)clientId
                        machineId:(nullable NSString *)machineId;

/// Terminate only the native client instance bound to `machineId`.
- (void)stopBundledClientForMachineId:(NSString *)machineId;

/// YES if a running instance is bound to this machine id.
- (BOOL)isBundledClientRunningForMachineId:(NSString *)machineId;

/// Count of running instances for a client id (0 if none).
- (NSUInteger)runningInstanceCountForClientId:(NSString *)clientId;

#if TARGET_OS_IPHONE
/// Disconnect in-process clients and reset iOS native launch state.
- (void)stopActiveIOSBundledClient;
/// Most recently launched bundled client id (e.g. @"niri"). Not exclusive —
/// multiple in-process clients may run concurrently.
@property(nonatomic, copy, readonly) NSString *activeIOSBundledClientId;
#endif

/// Terminate all bundled native Wayland clients (weston, foot, etc.).
- (void)stopAllNativeClients;

/// YES while any bundled native client or in-process iOS launch is active.
- (BOOL)isAnyNativeClientRunning;

@end
