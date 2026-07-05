#import "WWNMachineSessionBridge.h"
#import "../Settings/WWNWaypipeRunner.h"
#import "../Settings/WWNPreferencesManager.h"
#import "WWNVirtualMachineRunner.h"

@implementation WWNMachineSessionBridge

+ (BOOL)profileRequiresWaypipeTransport:(WWNMachineProfile *)profile {
  return [profile.type isEqualToString:kWWNMachineTypeSSHWaypipe] ||
         [profile.type isEqualToString:kWWNMachineTypeSSHTerminal];
}

+ (BOOL)profileUsesVirtualMachineBackend:(WWNMachineProfile *)profile {
  return [profile.type isEqualToString:kWWNMachineTypeVirtualMachine] ||
         [profile.type isEqualToString:kWWNMachineTypeContainer];
}

+ (BOOL)profileUsesNativeCompositorClient:(WWNMachineProfile *)profile {
  return [profile.type isEqualToString:kWWNMachineTypeNative];
}

+ (NSString *)nativeClientIdForProfile:(WWNMachineProfile *)profile {
  if (![self profileUsesNativeCompositorClient:profile]) {
    return nil;
  }

  NSDictionary *runtimeOverrides =
      [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
          ? profile.runtimeOverrides
          : @{};
  id bundled = runtimeOverrides[@"bundledAppID"];
  if ([bundled isKindOfClass:[NSString class]] && [(NSString *)bundled length] > 0) {
    return (NSString *)bundled;
  }

  NSDictionary *overrides =
      [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
          ? profile.settingsOverrides
          : @{};
  id nativeClientId = overrides[@"NativeClientId"];
  if ([nativeClientId isKindOfClass:[NSString class]] &&
      [(NSString *)nativeClientId length] > 0) {
    return (NSString *)nativeClientId;
  }

  static NSDictionary<NSString *, NSString *> *legacyKeys = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    legacyKeys = @{
      @"WestonSimpleSHMEnabled" : @"weston-simple-shm",
      @"WestonEnabled" : @"weston",
      @"WestonTerminalEnabled" : @"weston-terminal",
      @"FootEnabled" : @"foot",
    };
  });
  for (NSString *key in legacyKeys) {
    if ([overrides[key] respondsToSelector:@selector(boolValue)] &&
        [overrides[key] boolValue]) {
      return legacyKeys[key];
    }
  }

  return nil;
}

+ (void)stopAllActiveTransports {
  WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
#if TARGET_OS_IPHONE
  [runner stopActiveIOSBundledClient];
#endif
  [runner stopAllNativeClients];
  if (runner.isRunning) {
    [runner stopWaypipe];
  }
  [[WWNVirtualMachineRunner sharedRunner] stopAll];
}

+ (BOOL)connectProfile:(WWNMachineProfile *)profile
                 error:(NSError *_Nullable *_Nullable)error {
  if (!profile) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNMachineSessionBridge"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Missing machine profile."
                               }];
    }
    return NO;
  }

  [self stopAllActiveTransports];

  [[WWNPreferencesManager sharedManager] syncFromCanonicalWawonaPreferences];
  [WWNMachineProfileStore applyMachineToRuntimePrefs:profile];
  [WWNMachineProfileStore setActiveMachineId:profile.machineId];

  if ([self profileUsesNativeCompositorClient:profile]) {
    NSString *clientId = [self nativeClientIdForProfile:profile];
    if (clientId.length == 0) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"WWNMachineSessionBridge"
                       code:2
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"Native machine has no bundled client configured."
                   }];
      }
      return NO;
    }
    [[WWNWaypipeRunner sharedRunner] launchBundledClientWithId:clientId];
    return YES;
  }

  if ([self profileRequiresWaypipeTransport:profile]) {
    [[WWNWaypipeRunner sharedRunner]
        launchWaypipe:[WWNPreferencesManager sharedManager]];
    return YES;
  }

  // p26-vm-nixos / p25-macos-containers: boot a Linux guest (NixOS microvm via
  // vfkit, or a container) whose Wayland session bridges into Wawona over
  // vsock+waypipe. The profile's custom script is the boot command.
  if ([self profileUsesVirtualMachineBackend:profile]) {
    return [[WWNVirtualMachineRunner sharedRunner] launchProfile:profile
                                                          error:error];
  }

  if (error) {
    *error = [NSError
        errorWithDomain:@"WWNMachineSessionBridge"
                   code:3
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     @"Machine type does not support connect on this platform yet."
               }];
  }
  return NO;
}

+ (void)disconnectProfile:(WWNMachineProfile *)profile {
  if (!profile) {
    return;
  }

  if ([self profileUsesNativeCompositorClient:profile]) {
#if TARGET_OS_IPHONE
    [[WWNWaypipeRunner sharedRunner] stopActiveIOSBundledClient];
#else
    WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
    NSString *clientId = [self nativeClientIdForProfile:profile];
    if ([clientId isEqualToString:@"weston"]) {
      [runner stopWeston];
    } else if ([clientId isEqualToString:@"weston-terminal"]) {
      [runner stopWestonTerminal];
    } else if ([clientId isEqualToString:@"weston-simple-shm"]) {
      [runner stopWestonSimpleSHM];
    } else if ([clientId isEqualToString:@"foot"]) {
      [runner stopFoot];
    } else {
      [runner stopAllNativeClients];
    }
#endif
  } else if ([self profileRequiresWaypipeTransport:profile]) {
    [[WWNWaypipeRunner sharedRunner] stopWaypipe];
  } else if ([self profileUsesVirtualMachineBackend:profile]) {
    [[WWNVirtualMachineRunner sharedRunner]
        stopProfileWithMachineId:profile.machineId];
  }

  if ([[WWNMachineProfileStore activeMachineId] isEqualToString:profile.machineId]) {
    [WWNMachineProfileStore setActiveMachineId:nil];
  }
}

@end
