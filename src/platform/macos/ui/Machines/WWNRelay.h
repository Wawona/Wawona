#import <Foundation/Foundation.h>
#import "WWNMachineProfileStore.h"

NS_ASSUME_NONNULL_BEGIN

/// One Machines entry point for `virtual_machine`, `container`, and wasm.
/// Backend choice lives in Wawona Relay. Never QEMU. Never UTM.
@interface WWNRelay : NSObject

+ (instancetype)sharedRelay;

/// Resolve and start. Mode A vs Mode B is which binary this is, not a pref.
- (BOOL)startProfile:(WWNMachineProfile *)profile
               error:(NSError *_Nullable *_Nullable)error;

- (void)stopProfileWithMachineId:(NSString *)machineId;

- (void)stopAll;

/// Last resolved backend label (vz, kvm-ch, wasm-pulley, …) or nil.
- (nullable NSString *)resolvedBackendForMachineId:(NSString *)machineId;

@end

NS_ASSUME_NONNULL_END
