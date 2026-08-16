//
// WWNSwingingBridgeController.m. See header.
//
#import "WWNSwingingBridgeController.h"

#import "WWNMachineProfileStore.h"
#import "WWNPreferencesManager.h"

// The bridge shim ships in Wawona-Swinging-Bridge and is linked via the Nix
// `anowaw-macos` static lib (legacy recipe key). Compile the wiring only when
// the header is present so the Wawona tree still builds if the dependency has
// not been vendored yet.
#if __has_include("AnowawMacBridge.h")
#import "AnowawMacBridge.h"
#define WWN_HAVE_SWINGING_BRIDGE 1
#else
#define WWN_HAVE_SWINGING_BRIDGE 0
#endif

NSString *const kWWNSwingingBridgeNestedSocket = @"wawona-nested";
NSString *const kWWNAnowaWNestedSocket = @"wawona-nested";

@interface WWNSwingingBridgeController ()
#if WWN_HAVE_SWINGING_BRIDGE
@property (nonatomic, strong, nullable) AnowawMacBridge *bridge;
#endif
@end

@implementation WWNSwingingBridgeController

+ (instancetype)sharedController {
  static WWNSwingingBridgeController *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[WWNSwingingBridgeController alloc] init];
  });
  return shared;
}

- (BOOL)active {
#if WWN_HAVE_SWINGING_BRIDGE
  return self.bridge != nil;
#else
  return NO;
#endif
}

- (void)attachForProfile:(WWNMachineProfile *)profile {
#if WWN_HAVE_SWINGING_BRIDGE
  if (self.bridge) {
    return;
  }
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  BOOL enabled = [defaults boolForKey:kWWNPrefsSwingingBridgeEnabled];
  if (!enabled) {
    // Migrate former preference key.
    enabled = [defaults boolForKey:kWWNPrefsAnowaWEnabled];
  }
  if (!enabled) {
    return;
  }
  if (![WWNMachineProfileStore profileEligibleForAppBridge:profile]) {
    return;
  }
  if (![AnowawMacBridge hasCapturePermission]) {
    NSLog(@"[SwingingBridge] Screen Recording permission not granted; skipping attach");
    return;
  }
  AnowawMacBridge *bridge = [[AnowawMacBridge alloc]
      initWithSocketName:[WWNPreferencesManager preferredNestedSocketName]];
  if (!bridge) {
    NSLog(@"[SwingingBridge] failed to attach bridge to socket %@",
          [WWNPreferencesManager preferredNestedSocketName]);
    return;
  }
  self.bridge = bridge;
  NSLog(@"[SwingingBridge] attached to nested Weston socket %@",
        [WWNPreferencesManager preferredNestedSocketName]);
#else
  (void)profile;
#endif
}

- (void)bridgeAppWithBundleId:(NSString *)bundleId {
#if WWN_HAVE_SWINGING_BRIDGE
  AnowawMacBridge *bridge = self.bridge;
  if (!bridge) {
    NSLog(@"[SwingingBridge] bridgeApp requested with no active bridge");
    return;
  }
  [bridge bridgeAppWithBundleId:bundleId
                     completion:^(uint64_t handle, NSError *_Nullable error) {
                       if (error || handle == 0) {
                         NSLog(@"[SwingingBridge] failed to bridge %@: %@", bundleId,
                               error.localizedDescription ?: @"unknown error");
                       }
                     }];
#else
  (void)bundleId;
#endif
}

- (void)detach {
#if WWN_HAVE_SWINGING_BRIDGE
  [self.bridge stop];
  self.bridge = nil;
#endif
}

@end
