#import <Foundation/Foundation.h>
#import "WWNMachineProfileStore.h"

NS_ASSUME_NONNULL_BEGIN

/// One Machines entry point for `virtual_machine`, `container`, and wasm.
/// Backend choice lives in Wawona Relay. Never QEMU. Never UTM.
@interface WWNRelay : NSObject

+ (instancetype)sharedRelay;

/// Native editor bridge; Relay owns templates and highlighting.
+ (nullable NSString *)nixEditorDocument:(NSString *)name source:(nullable NSString *)source;

/// Resolve and start. Mode A vs Mode B is which binary this is, not a pref.
- (BOOL)startProfile:(WWNMachineProfile *)profile
               error:(NSError *_Nullable *_Nullable)error;

- (void)stopProfileWithMachineId:(NSString *)machineId;

- (void)stopAll;

/// Rust session ownership, including boot and a pending Stop retry. Not readiness.
- (BOOL)hasOwnedSessions;
- (BOOL)hasOwnedSessionForMachineId:(NSString *)machineId;

/// Last resolved backend label (vz, kvm-ch, wasm-pulley, …) or nil.
- (nullable NSString *)resolvedBackendForMachineId:(NSString *)machineId;

/// Append-only guest console (PL011 plus hvc0). Nil when that machine has no
/// live Relay handle.
- (nullable NSData *)consoleLogForMachineId:(NSString *)machineId;

@end

/// Posted on the main queue after a VM or container Relay session starts.
/// userInfo machineId. The iOS scene shows libghostty until the first frame.
FOUNDATION_EXPORT NSNotificationName const WWNRelayGuestConsoleNeededNotification;

NS_ASSUME_NONNULL_END
