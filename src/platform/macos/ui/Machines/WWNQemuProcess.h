#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Minimal QEMU subprocess runner (adapted from UTM's UTMProcess for iOS).
/// Loads a `qemu-*-softmmu` framework from the app bundle and runs `qemu_init`
/// / `qemu_main_loop` on a background pthread (jitless TCTI, App Store safe).
@interface WWNQemuProcess : NSObject

@property(nonatomic, copy, readonly) NSArray<NSString *> *argv;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;
@property(nonatomic, nullable, copy) NSURL *currentDirectoryUrl;
@property(nonatomic, readonly) int status;

typedef int (*WWNQemuProcessEntry)(
    WWNQemuProcess *process, int argc, const char *_Nullable *_Nullable argv,
    const char *_Nullable *_Nullable envp);

@property(nonatomic) WWNQemuProcessEntry entry;

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments;

- (void)pushArgv:(nullable NSString *)arg;
- (void)clearArgv;

/// `name` is the framework base, e.g. `qemu-aarch64-softmmu`.
- (void)startProcess:(NSString *)name completion:(void (^)(NSError *_Nullable error))completion;
- (void)stopProcess;

@end

NS_ASSUME_NONNULL_END
