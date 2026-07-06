#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// In-process jitless QEMU-TCTI engine for iOS/iPadOS/tvOS/visionOS (UTM SE model).
@interface WWNMobileVmEngine : NSObject

+ (instancetype)sharedEngine;

- (BOOL)isEngineAvailable;

- (BOOL)launchProfileWithKernelPath:(NSString *)kernelPath
                         rootfsPath:(NSString *)rootfsPath
                           memoryMB:(unsigned)memoryMB
                              error:(NSError *_Nullable *_Nullable)error;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
