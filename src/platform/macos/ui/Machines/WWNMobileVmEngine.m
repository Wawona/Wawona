#import "WWNMobileVmEngine.h"

@implementation WWNMobileVmEngine

+ (instancetype)sharedEngine {
  static WWNMobileVmEngine *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [WWNMobileVmEngine new];
  });
  return shared;
}

- (BOOL)isEngineAvailable {
  return NO;
}

- (BOOL)launchProfileWithKernelPath:(NSString *)kernelPath
                         rootfsPath:(NSString *)rootfsPath
                           memoryMB:(unsigned)memoryMB
                              error:(NSError *_Nullable *_Nullable)error {
  return [self launchProfileWithKernelPath:kernelPath
                                rootfsPath:rootfsPath
                                  memoryMB:memoryMB
                             ociBundlePath:nil
                                     error:error];
}

- (BOOL)launchProfileWithKernelPath:(NSString *)kernelPath
                         rootfsPath:(NSString *)rootfsPath
                           memoryMB:(unsigned)memoryMB
                      ociBundlePath:(NSString *)ociBundlePath
                              error:(NSError *_Nullable *_Nullable)error {
  (void)kernelPath;
  (void)rootfsPath;
  (void)memoryMB;
  (void)ociBundlePath;
  if (error) {
    *error = [NSError
        errorWithDomain:@"WWNMobileVmEngine"
                   code:1
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     @"Use WWNRelay. iOS Linux guests start on Relay static CPU. No QEMU."
               }];
  }
  return NO;
}

- (void)stop {
}

@end
