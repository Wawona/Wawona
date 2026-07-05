#import <Foundation/Foundation.h>
#import "WWNMachineProfileStore.h"

NS_ASSUME_NONNULL_BEGIN

// Launches a `container` machine profile, delegating to the wwn-containers
// dependency. The execution backend is capability-driven per target:
//
//   macOS   Apple Containerization framework (wwn-containerd), per-container VM.
//   iOS/…   container-in-VM: OCI rootfs (unpacked by the wwn-oci core) run with
//           crun/podman inside a wwn-vms guest, surfaced over vsock+waypipe.
//   watchOS OCI image management only (no execution).
//
// On macOS the configured boot command (profile.customScript, e.g.
// `nix run .#wwn-containerd -- run ...` or `wwn-oci pull ...`) is run as a
// tracked subprocess. On mobile the container-in-VM guest is driven by the VM
// runner; this class reports image-management-only where execution is disallowed.
@interface WWNContainerRunner : NSObject

+ (instancetype)sharedRunner;

- (BOOL)launchProfile:(WWNMachineProfile *)profile
                error:(NSError *_Nullable *_Nullable)error;

- (void)stopProfileWithMachineId:(NSString *)machineId;

- (void)stopAll;

@end

NS_ASSUME_NONNULL_END
