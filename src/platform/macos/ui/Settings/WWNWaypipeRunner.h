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

+ (instancetype)sharedRunner;

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
- (void)stopWeston;

- (void)launchWestonTerminal;
- (void)stopWestonTerminal;

@end
