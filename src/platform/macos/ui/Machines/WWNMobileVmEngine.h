#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// iOS Linux VMs wait on Relay CPU. Fail closed. No QEMU in Mode A or Mode B.
@interface WWNMobileVmEngine : NSObject

+ (instancetype)sharedEngine;

- (BOOL)isEngineAvailable;

- (BOOL)launchProfileWithKernelPath:(NSString *)kernelPath
                         rootfsPath:(NSString *)rootfsPath
                           memoryMB:(unsigned)memoryMB
                              error:(NSError *_Nullable *_Nullable)error;

- (BOOL)launchProfileWithKernelPath:(NSString *)kernelPath
                         rootfsPath:(NSString *)rootfsPath
                           memoryMB:(unsigned)memoryMB
                      ociBundlePath:(nullable NSString *)ociBundlePath
                              error:(NSError *_Nullable *_Nullable)error;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
