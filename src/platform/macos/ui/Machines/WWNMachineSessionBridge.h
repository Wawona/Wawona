#import "WWNMachineProfileStore.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Connect / disconnect machine sessions with correct transport:
/// native profiles → in-process bundled client on local compositor;
/// ssh_waypipe / ssh_terminal → waypipe only.
@interface WWNMachineSessionBridge : NSObject

+ (BOOL)profileRequiresWaypipeTransport:(WWNMachineProfile *)profile;
+ (BOOL)profileUsesNativeCompositorClient:(WWNMachineProfile *)profile;
+ (nullable NSString *)nativeClientIdForProfile:(WWNMachineProfile *)profile;

+ (BOOL)connectProfile:(WWNMachineProfile *)profile error:(NSError *_Nullable *_Nullable)error;
+ (void)disconnectProfile:(WWNMachineProfile *)profile;
+ (void)stopAllActiveTransports;

@end

NS_ASSUME_NONNULL_END
