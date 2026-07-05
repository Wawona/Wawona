#import <Foundation/Foundation.h>
#import "WWNMachineProfileStore.h"

NS_ASSUME_NONNULL_BEGIN

// p26-vm-nixos: launches a `virtual_machine` (and `container`) machine profile
// on macOS by running its configured boot command as a tracked subprocess and
// letting the guest's Wayland session bridge into Wawona over vsock+waypipe.
//
// The command comes from the profile's `customScript` (a shell command). For the
// microvm.nix / vfkit developer flow this is typically:
//
//   nix run .#wawona-microvm & nix run .#wawona-vm-bridge
//
// run from the Wawona repo. When no command is configured, connect fails with an
// actionable error naming those flake apps. A future revision will drive the
// embedded `wawona-vz` launcher + bundled guest artifacts directly (no nix).
@interface WWNVirtualMachineRunner : NSObject

+ (instancetype)sharedRunner;

// Launch the VM/container for `profile`. Returns NO and fills `error` when the
// profile has no boot command configured or the command cannot be started.
- (BOOL)launchProfile:(WWNMachineProfile *)profile
                error:(NSError *_Nullable *_Nullable)error;

// Terminate the subprocess started for `machineId`, if any.
- (void)stopProfileWithMachineId:(NSString *)machineId;

// Terminate all VM/container subprocesses (used on teardown / switch).
- (void)stopAll;

@end

NS_ASSUME_NONNULL_END
