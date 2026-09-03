#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// In-process QEMU engine for iOS and iPadOS.
/// Mode A uses TCTI. The separate Mode B product uses TCG JIT.
@interface WWNMobileVmEngine : NSObject

+ (instancetype)sharedEngine;

- (BOOL)isEngineAvailable;

- (BOOL)launchProfileWithKernelPath:(NSString *)kernelPath
                         rootfsPath:(NSString *)rootfsPath
                           memoryMB:(unsigned)memoryMB
                              error:(NSError *_Nullable *_Nullable)error;

/// Same as launchProfileWithKernelPath:… plus optional OCI layout shared into
/// the guest as mount_tag `oci-bundle` (9p; guest crun path).
- (BOOL)launchProfileWithKernelPath:(NSString *)kernelPath
                         rootfsPath:(NSString *)rootfsPath
                           memoryMB:(unsigned)memoryMB
                      ociBundlePath:(nullable NSString *)ociBundlePath
                              error:(NSError *_Nullable *_Nullable)error;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
