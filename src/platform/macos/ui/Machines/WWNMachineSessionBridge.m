#import "WWNMachineSessionBridge.h"
#import "../Settings/WWNWaypipeRunner.h"
#import "../Settings/WWNPreferencesManager.h"
#import "../Settings/WWNEnvironmentOverrides.h"
#import "WWNVirtualMachineRunner.h"
#import "WWNContainerRunner.h"
#import "WWNPlatformCapabilities.h"
#import "../../WWNSettings.h"
#if TARGET_OS_OSX
#import "WWNSwingingBridgeController.h"
#import "WWNDesktopReplacementController.h"
#endif

@implementation WWNMachineSessionBridge

+ (BOOL)profileRequiresWaypipeTransport:(WWNMachineProfile *)profile {
  return [profile.type isEqualToString:kWWNMachineTypeSSHWaypipe] ||
         [profile.type isEqualToString:kWWNMachineTypeSSHTerminal];
}

+ (BOOL)profileUsesVirtualMachineBackend:(WWNMachineProfile *)profile {
  return [profile.type isEqualToString:kWWNMachineTypeVirtualMachine];
}

+ (BOOL)profileUsesContainerBackend:(WWNMachineProfile *)profile {
  return [profile.type isEqualToString:kWWNMachineTypeContainer];
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
  [[WWNContainerRunner sharedRunner] stopAll];
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

#if TARGET_OS_IPHONE
  // Native Wayland clients may run concurrently (multiple weston-terminal,
  // flower, …). VM / waypipe / container backends on mobile still share a
  // single in-process engine. Tear those down before switching.
  if (![self profileUsesNativeCompositorClient:profile]) {
    [self stopAllActiveTransports];
  }
#endif
  // Every native client instance is tracked independently (macOS: NSTask
  // records keyed by machineId; iOS/Android: concurrent in-process threads).
  // Connecting one profile must never stop an unrelated native client.

  [[WWNPreferencesManager sharedManager] syncFromCanonicalWawonaPreferences];
  [WWNMachineProfileStore applyMachineToRuntimePrefs:profile];
  [WWNMachineProfileStore setActiveMachineId:profile.machineId];
  WWNSettings_ApplyGraphicsDriverSelection();
  // Re-apply env overrides after graphics setenv so user values win (#157).
  {
    NSDictionary *machineEnv = nil;
    id runtime = profile.runtimeOverrides;
    if ([runtime isKindOfClass:[NSDictionary class]]) {
      id env = runtime[@"environment"];
      if ([env isKindOfClass:[NSDictionary class]]) {
        machineEnv = env;
      }
    }
    WWNEnvironmentOverridesApply(machineEnv);
  }

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
    if (!WWNPlatformAllowsGpuStack() &&
        ([clientId isEqualToString:@"kmscube"] ||
         [clientId isEqualToString:@"gbm-es2-demo"] ||
         [clientId isEqualToString:@"opengl-cube"] ||
         [clientId isEqualToString:@"vkcube"] ||
         [clientId isEqualToString:@"weston-simple-egl"])) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"WWNMachineSessionBridge"
                       code:3
                   userInfo:@{
                     NSLocalizedDescriptionKey : [NSString
                         stringWithFormat:
                             @"%@ requires a GPU stack unavailable on this "
                             @"platform.",
                             clientId]
                   }];
      }
      return NO;
    }
#if TARGET_OS_OSX
    // Mode B Desktop Replacement: SIP + Desktop prefs + desktop machine →
    // DYLD_INSERT libwayland-mac.dylib (not Mode A in-window present).
    WWNDesktopReplacementController *desktop =
        [WWNDesktopReplacementController sharedController];
    if ([desktop shouldEngageModeB] && [desktop isDesktopMachine:profile] &&
        [clientId isEqualToString:@"weston"]) {
      NSError *modeBError = nil;
      if (![desktop engageForProfile:profile error:&modeBError]) {
        if (error) {
          *error = modeBError;
        }
        return NO;
      }
      if (WWNPlatformAllowsSwingingBridge()) {
        [[WWNSwingingBridgeController sharedController] attachForProfile:profile];
      }
      return YES;
    }
#endif
    [[WWNWaypipeRunner sharedRunner] launchBundledClientWithId:clientId
                                                     machineId:profile.machineId];
#if TARGET_OS_OSX
    // Wawona Swinging Bridge: macOS-only (platform-targets matrix).
    if (WWNPlatformAllowsSwingingBridge() && [clientId isEqualToString:@"weston"]) {
      [[WWNSwingingBridgeController sharedController] attachForProfile:profile];
    }
#endif
    return YES;
  }

  if ([self profileRequiresWaypipeTransport:profile]) {
    [[WWNWaypipeRunner sharedRunner]
        launchWaypipe:[WWNPreferencesManager sharedManager]];
    return YES;
  }

  // p26-vm-nixos: boot a NixOS guest (wwn-vms: microvm/vfkit or the native
  // wawona-vz launcher) whose Wayland session bridges into Wawona over
  // vsock+waypipe. The profile's custom script is the boot command.
  if ([self profileUsesVirtualMachineBackend:profile]) {
    if (!WWNPlatformAllowsVirtualMachine()) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"WWNMachineSessionBridge"
                       code:4
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"Virtual machines are not available on this platform."
                   }];
      }
      return NO;
    }
    return [[WWNVirtualMachineRunner sharedRunner] launchProfile:profile
                                                          error:error];
  }

  // OCI containers (wwn-containers): Apple Containerization on macOS, or
  // container-in-VM on other targets. Delegates to the container runner.
  if ([self profileUsesContainerBackend:profile]) {
    if (!WWNPlatformAllowsContainer()) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"WWNMachineSessionBridge"
                       code:5
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"Containers are not available on this platform."
                   }];
      }
      return NO;
    }
    return [[WWNContainerRunner sharedRunner] launchProfile:profile
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

#if TARGET_OS_OSX
  // Lockscreen → Desktop handoff: when the greeter machine stops and Desktop
  // Replacement is armed, start the desktop machine (Mode B if SIP allows).
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  BOOL wasLockscreen =
      [defs boolForKey:kWWNPrefsLockscreenReplacementEnabled] &&
      [[defs stringForKey:kWWNPrefsLockscreenReplacementMachineId]
          isEqualToString:profile.machineId ?: @""];
#endif

  if ([self profileUsesNativeCompositorClient:profile]) {
    WWNWaypipeRunner *runner = [WWNWaypipeRunner sharedRunner];
    NSString *clientId = [self nativeClientIdForProfile:profile];
#if TARGET_OS_OSX
    WWNDesktopReplacementController *desktop =
        [WWNDesktopReplacementController sharedController];
    if ([desktop isDesktopMachine:profile]) {
      [desktop disengage];
    }
    if (WWNPlatformAllowsSwingingBridge() && [clientId isEqualToString:@"weston"]) {
      [[WWNSwingingBridgeController sharedController] detach];
    }
#endif
    // Stop only this machine's instance. Other copies of the same client
    // (and other machines) keep running.
    [runner stopBundledClientForMachineId:profile.machineId];
#if TARGET_OS_IPHONE
    // iOS in-process clients are not yet keyed by machineId; if nothing else
    // is in flight, fully reset native launch state.
    if (![runner isAnyNativeClientRunning]) {
      [runner stopActiveIOSBundledClient];
    }
#endif
  } else if ([self profileRequiresWaypipeTransport:profile]) {
    [[WWNWaypipeRunner sharedRunner] stopWaypipe];
  } else if ([self profileUsesVirtualMachineBackend:profile]) {
    [[WWNVirtualMachineRunner sharedRunner]
        stopProfileWithMachineId:profile.machineId];
  } else if ([self profileUsesContainerBackend:profile]) {
    [[WWNContainerRunner sharedRunner]
        stopProfileWithMachineId:profile.machineId];
  }

  if ([[WWNMachineProfileStore activeMachineId] isEqualToString:profile.machineId]) {
    [WWNMachineProfileStore setActiveMachineId:nil];
  }

#if TARGET_OS_OSX
  if (wasLockscreen &&
      [defs boolForKey:kWWNPrefsDesktopReplacementEnabled]) {
    NSString *desktopId =
        [defs stringForKey:kWWNPrefsDesktopReplacementMachineId];
    if (desktopId.length > 0) {
      WWNMachineProfile *desktopProfile =
          [WWNMachineProfileStore profileById:desktopId];
      if (desktopProfile) {
        NSError *handoffErr = nil;
        if (![self connectProfile:desktopProfile error:&handoffErr]) {
          NSLog(@"[DesktopReplacement] lockscreen handoff failed: %@",
                handoffErr);
        }
      }
    }
  }
#endif
}

@end
