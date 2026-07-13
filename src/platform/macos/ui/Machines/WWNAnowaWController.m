//
// WWNAnowaWController.m — see header.
//
#import "WWNAnowaWController.h"

#import "WWNMachineProfileStore.h"
#import "WWNPreferencesManager.h"

// The bridge shim ships in wwn-anowaW and is linked in via the Nix
// `anowaw-macos` static lib. Compile the wiring only when the header is present
// so the Wawona tree still builds if the dependency has not been vendored yet.
#if __has_include("AnowawMacBridge.h")
#import "AnowawMacBridge.h"
#define WWN_HAVE_ANOWAW 1
#else
#define WWN_HAVE_ANOWAW 0
#endif

NSString *const kWWNAnowaWNestedSocket = @"wawona-nested";

@interface WWNAnowaWController ()
#if WWN_HAVE_ANOWAW
@property (nonatomic, strong, nullable) AnowawMacBridge *bridge;
#endif
@end

@implementation WWNAnowaWController

+ (instancetype)sharedController {
  static WWNAnowaWController *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[WWNAnowaWController alloc] init];
  });
  return shared;
}

- (BOOL)active {
#if WWN_HAVE_ANOWAW
  return self.bridge != nil;
#else
  return NO;
#endif
}

- (void)attachForProfile:(WWNMachineProfile *)profile {
#if WWN_HAVE_ANOWAW
  if (self.bridge) {
    return;
  }
  if (![[NSUserDefaults standardUserDefaults] boolForKey:kWWNPrefsAnowaWEnabled]) {
    return;
  }
  if (![WWNMachineProfileStore profileEligibleForAppBridge:profile]) {
    return;
  }
  if (![AnowawMacBridge hasCapturePermission]) {
    NSLog(@"[anowaW] Screen Recording permission not granted; skipping attach");
    return;
  }
  AnowawMacBridge *bridge = [[AnowawMacBridge alloc]
      initWithSocketName:[WWNPreferencesManager preferredNestedSocketName]];
  if (!bridge) {
    NSLog(@"[anowaW] failed to attach bridge to socket %@",
          [WWNPreferencesManager preferredNestedSocketName]);
    return;
  }
  self.bridge = bridge;
  NSLog(@"[anowaW] attached to nested Weston socket %@",
        [WWNPreferencesManager preferredNestedSocketName]);
#else
  (void)profile;
#endif
}

- (void)bridgeAppWithBundleId:(NSString *)bundleId {
#if WWN_HAVE_ANOWAW
  AnowawMacBridge *bridge = self.bridge;
  if (!bridge) {
    NSLog(@"[anowaW] bridgeApp requested with no active bridge");
    return;
  }
  [bridge bridgeAppWithBundleId:bundleId
                     completion:^(uint64_t handle, NSError *_Nullable error) {
                       if (error || handle == 0) {
                         NSLog(@"[anowaW] failed to bridge %@: %@", bundleId,
                               error.localizedDescription ?: @"unknown error");
                       }
                     }];
#else
  (void)bundleId;
#endif
}

- (void)detach {
#if WWN_HAVE_ANOWAW
  [self.bridge stop];
  self.bridge = nil;
#endif
}

@end
