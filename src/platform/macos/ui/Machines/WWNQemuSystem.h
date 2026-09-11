#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Leftover lab helper. Not the product VM engine. Machines Start fail-closes
/// on Relay. Do not wire this back into WWNRelay or WWNMobileVmEngine.
@interface WWNQemuSystem : NSObject

@property(nonatomic, copy) NSArray<NSString *> *arguments;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;
@property(nonatomic, copy, nullable) NSString *currentDirectoryPath;
@property(nonatomic, readonly) pid_t childPid;

- (void)pushArgv:(NSString *)arg;
- (void)clearArgv;

- (BOOL)startTrampolineWithError:(NSError *_Nullable *_Nullable)error;
- (void)stopQemu;
- (void)waitInBackground;

@end

NS_ASSUME_NONNULL_END
