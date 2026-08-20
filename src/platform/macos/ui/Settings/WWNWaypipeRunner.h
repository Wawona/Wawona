#import "WWNPreferencesManager.h"
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

@class WWNMachineProfile;

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
/// Always starts a new instance. Multiple copies of the same client are allowed.
- (void)launchBundledClientWithId:(NSString *)clientId;

/// Launch a bundled client and associate it with a Machines profile so Stop
/// only terminates that instance (other copies of the same client keep running).
- (void)launchBundledClientWithId:(NSString *)clientId
                        machineId:(nullable NSString *)machineId;

/// Launch a Wayland `.wasm` via the bundled Wawona Runtime (`wasm` CLI /
/// in-process `wawona_wasm_run`). Path comes from the machine profile
/// `runtimeOverrides.wasmModulePath` when `machineId` is set, else from
/// `wasmModulePath` argument.
- (void)launchWasmModuleAtPath:(NSString *)wasmModulePath
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
/// Most recently launched bundled client id (e.g. @"niri"). Not exclusive -
/// multiple in-process clients may run concurrently.
@property(nonatomic, copy, readonly) NSString *activeIOSBundledClientId;
#endif

/// Terminate all bundled native Wayland clients (weston, foot, etc.).
- (void)stopAllNativeClients;

/// YES while any bundled native client or in-process iOS launch is active.
- (BOOL)isAnyNativeClientRunning;

#if TARGET_OS_OSX
/**
 * Argv and environment to run a nested compositor as the Mode B display
 * server (wwn-iland framebufferd). Forces that client's own DRM/KMS backend,
 * clears WAYLAND_DISPLAY so it does not nest inside Wawona, and leaves
 * compositor-specific flags to that client (weston --backend=drm, niri
 * NIRI_BACKEND=tty, custom command exec as-is). Does not start the process.
 */
- (BOOL)baremetalCompositorLaunchSpecForProfile:(WWNMachineProfile *)profile
                                     executable:(NSString *_Nullable *_Nonnull)outPath
                                      arguments:(NSArray<NSString *> *_Nullable *_Nonnull)outArgs
                                    environment:(NSDictionary<NSString *, NSString *> *_Nullable *_Nonnull)outEnv
                                          error:(NSError *_Nullable *_Nullable)error;
#endif

@end

/// Resolves the display backend a bundled compositor should run against:
/// @"wayland" to nest it inside Wawona, or @"drm" to run it against
/// wwn-iland's userland KMS the way it would run on bare metal. Pass the
/// machine's CompositorBackend override, or nil to take the CLI override /
/// global setting. Falls back to @"wayland" when the choice is unavailable
/// (notably OpenGLDriver=none, which leaves nothing behind iland to present
/// with).
FOUNDATION_EXPORT NSString *_Nonnull WWNResolveCompositorBackend(
    NSString *_Nullable overrideValue);

/// Process-wide backend override from `Wawona --backend=…` (cleared with nil).
FOUNDATION_EXPORT void WWNSetCompositorBackendCLIOverride(
    NSString *_Nullable backend);

/// Current CLI `--backend` override, or nil if unset.
FOUNDATION_EXPORT NSString *_Nullable WWNCompositorBackendCLIOverride(void);

