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
// On macOS the boot command is built from the profile's per-machine
// `containerSettings` (image ref, command, memory, kernel/initfs, read-only,
// init) with every empty field inheriting the global Settings → Containers
// default; a profile `customScript` (advanced escape hatch) always wins. The
// command runs inside Wawona's bundled terminal (weston-terminal): the
// terminal spawns the bundled `wawona-container-shell` as its $SHELL, which
// execs the `container` CLI (Apple Containerization,
// WAWONA_CONTAINER_BACKEND=containerization). The backend writes ready/done
// marker files (WAWONA_CONTAINER_READY_FILE / _DONE_FILE) that this runner
// polls to drive the GUI status.
@interface WWNContainerRunner : NSObject

+ (instancetype)sharedRunner;

- (BOOL)launchProfile:(WWNMachineProfile *)profile
                error:(NSError *_Nullable *_Nullable)error;

- (void)stopProfileWithMachineId:(NSString *)machineId;

- (void)stopAll;

@end

NS_ASSUME_NONNULL_END
