#import "WWNMachineProfileStore.h"
#import "../Settings/WWNPreferencesManager.h"
#import "../Settings/WWNEnvironmentOverrides.h"
#import "../../WWNCompositorBridge.h"
#import "../../../../util/WWNLog.h"
#import <TargetConditionals.h>

NSString *const kWWNMachineTypeSSHWaypipe = @"ssh_waypipe";
NSString *const kWWNMachineTypeSSHTerminal = @"ssh_terminal";
NSString *const kWWNMachineTypeNative = @"native";
NSString *const kWWNMachineTypeVirtualMachine = @"virtual_machine";
NSString *const kWWNMachineTypeContainer = @"container";

static NSString *const kWWNMachineProfilesJSON = @"wawona.machineProfiles.v1";
static NSString *const kWWNActiveMachineId = @"wawona.activeMachineId.v1";
static NSString *const kWWNMachineProfilesMigrated = @"wawona.machineProfilesMigrated.v1";
static NSString *const kWWNMachineSettingsOverrides = @"settingsOverrides";
static NSString *const kWWNMachineRuntimeOverrides = @"runtimeOverrides";
static NSString *const kWWNRuntimeRenderer = @"renderer";
static NSString *const kWWNRuntimeInputProfile = @"inputProfile";
static NSString *const kWWNRuntimeUseBundledApp = @"useBundledApp";
static NSString *const kWWNRuntimeBundledAppID = @"bundledAppID";
static NSString *const kWWNRuntimeWaypipeEnabled = @"waypipeEnabled";
static NSString *const kWWNRuntimeMachineThumbnailEnabledOverride =
    @"machineThumbnailEnabledOverride";
static NSString *const kWWNRuntimeShakeToCloseEnabled = @"shakeToCloseEnabled";
static NSString *const kWWNRuntimeSwipeBackToCloseEnabled = @"swipeBackToCloseEnabled";
static NSString *const kWWNRuntimeAlwaysOnTop = @"alwaysOnTop";
static NSString *const kWWNPrefShakeToCloseEnabled = @"wawona.pref.shakeToCloseEnabled";
static NSString *const kWWNPrefSwipeBackToCloseEnabled = @"wawona.pref.swipeBackToCloseEnabled";

@implementation WWNMachineProfile

+ (instancetype)defaultProfile {
  return [[WWNMachineProfile alloc] initDefaultProfile];
}

- (instancetype)initDefaultProfile {
  self = [super init];
  if (self) {
    long long now = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    _machineId = [NSUUID UUID].UUIDString;
    _name = @"Default Machine";
    _type = kWWNMachineTypeNative;
    _sshEnabled = NO;
    _sshHost = @"";
    _sshUser = @"";
    _sshPort = 22;
    _sshPassword = @"";
    _sshBinary = @"ssh";
    _sshAuthMethod = 0;
    _sshKeyPath = @"";
    _sshKeyPassphrase = @"";
    _remoteCommand = @"";
    _customScript = @"";
    _waypipeCompress = @"lz4";
    _waypipeThreads = @"0";
    _waypipeVideo = @"none";
    _waypipeDebug = NO;
    _waypipeOneshot = NO;
    _waypipeDisableGpu = NO;
    _waypipeLoginShell = NO;
    _waypipeTitlePrefix = @"";
    _waypipeSecCtx = @"";
    _runtimeOverrides = @{};
    _favorite = NO;
    _createdAtMs = now;
    _updatedAtMs = now;
    _settingsOverrides = @{
      @"NativeClientId" : @"weston-terminal",
      @"EnableLauncher" : @YES,
      @"WestonSimpleSHMEnabled" : @NO,
      @"WestonEnabled" : @NO,
      @"WestonTerminalEnabled" : @YES,
      @"FootEnabled" : @NO,
    };
  }
  return self;
}

- (NSDictionary *)serialize {
  NSString *bundledClientID =
      [self.settingsOverrides[@"NativeClientId"] isKindOfClass:[NSString class]]
          ? self.settingsOverrides[@"NativeClientId"]
          : @"";
  BOOL useBundledApp = bundledClientID.length > 0;
  NSMutableDictionary *runtimeOverrides = [NSMutableDictionary dictionary];
  if ([self.runtimeOverrides isKindOfClass:[NSDictionary class]]) {
    [runtimeOverrides addEntriesFromDictionary:self.runtimeOverrides];
  }
  runtimeOverrides[kWWNRuntimeBundledAppID] = bundledClientID;
  runtimeOverrides[kWWNRuntimeUseBundledApp] = @(useBundledApp);
  runtimeOverrides[kWWNRuntimeWaypipeEnabled] = @(self.sshEnabled);
  runtimeOverrides[@"legacySettingsOverrides"] = self.settingsOverrides ?: @{};

  return @{
    @"id" : self.machineId ?: @"",
    @"name" : self.name ?: @"Unnamed Machine",
    @"type" : self.type ?: kWWNMachineTypeNative,
    @"sshHost" : self.sshHost ?: @"",
    @"sshUser" : self.sshUser ?: @"",
    @"sshPort" : @(self.sshPort > 0 ? self.sshPort : 22),
    @"sshPassword" : self.sshPassword ?: @"",
    @"sshBinary" : self.sshBinary ?: @"ssh",
    @"sshAuthMethod" : @(self.sshAuthMethod),
    @"sshKeyPath" : self.sshKeyPath ?: @"",
    @"sshKeyPassphrase" : self.sshKeyPassphrase ?: @"",
    @"remoteCommand" : self.remoteCommand ?: @"",
    @"launchers" : @[],
    kWWNMachineRuntimeOverrides : runtimeOverrides,
    @"favorite" : @(self.favorite),
  };
}

@end

@implementation WWNMachineProfileStore

+ (NSString *)normalizeTouchInputType:(NSString *)raw {
  if (raw.length == 0) {
    return @"Multi-Touch";
  }
  NSString *lower = raw.lowercaseString;
  if ([lower isEqualToString:@"touchpad"] ||
      [lower isEqualToString:@"pointer"] ||
      [lower isEqualToString:@"virtual"] ||
      [lower isEqualToString:@"virtual-pointer"] ||
      [lower isEqualToString:@"trackpad"]) {
    return @"Touchpad";
  }
  return @"Multi-Touch";
}

+ (NSArray<NSString *> *)machineScopedSettingsKeys {
  return @[
    kWWNPrefsUniversalClipboard,
    kWWNPrefsForceServerSideDecorations,
    kWWNPrefsAutoScale,
    kWWNPrefsColorOperations,
    kWWNPrefsNestedCompositorsSupport,
    kWWNPrefsRenderMacOSPointer,
    kWWNPrefsNestedCompositorCursor,
    kWWNPrefsMultipleClients,
    kWWNPrefsSwapCmdWithAlt,
    kWWNPrefsTouchInputType,
    kWWNPrefsTCPListenerPort,
    kWWNPrefsWaylandSocketDir,
    kWWNPrefsWaylandDisplayNumber,
    kWWNPrefsEnableVulkanDrivers,
    kWWNPrefsEnableDmabuf,
    kWWNPrefsVulkanDriver,
    kWWNPrefsOpenGLDriver,
    kWWNPrefsCompositorBackend,
    kWWNPrefsRespectSafeArea,
    kWWNPrefsWaypipeDisplay,
    kWWNPrefsWaypipeSocket,
    kWWNPrefsWaypipeCompress,
    kWWNPrefsWaypipeCompressLevel,
    kWWNPrefsWaypipeThreads,
    kWWNPrefsWaypipeVideo,
    kWWNPrefsWaypipeVideoEncoding,
    kWWNPrefsWaypipeVideoDecoding,
    kWWNPrefsWaypipeVideoBpf,
    kWWNPrefsWaypipeSSHEnabled,
    kWWNPrefsWaypipeSSHHost,
    kWWNPrefsWaypipeSSHUser,
    kWWNPrefsWaypipeSSHBinary,
    kWWNPrefsWaypipeSSHAuthMethod,
    kWWNPrefsWaypipeSSHKeyPath,
    kWWNPrefsWaypipeSSHKeyPassphrase,
    kWWNPrefsWaypipeSSHPassword,
    kWWNPrefsWaypipeRemoteCommand,
    kWWNPrefsWaypipeCustomScript,
    kWWNPrefsWaypipeDebug,
    kWWNPrefsWaypipeNoGpu,
    kWWNPrefsWaypipeOneshot,
    kWWNPrefsWaypipeUnlinkSocket,
    kWWNPrefsWaypipeLoginShell,
    kWWNPrefsWaypipeVsock,
    kWWNPrefsWaypipeXwls,
    kWWNPrefsWaypipeTitlePrefix,
    kWWNPrefsWaypipeSecCtx,
    // MachineVMProvider / MachineContainerRuntime are no longer user-scoped:
    // the engine is fixed per build target (Residual E).
    kWWNPrefsMachineVMVsockPort,
    kWWNPrefsMachineContainerImageStore,
    kWWNPrefsSSHHost,
    kWWNPrefsSSHUser,
    kWWNPrefsSSHPort,
    kWWNPrefsSSHAuthMethod,
    kWWNPrefsSSHPassword,
    kWWNPrefsSSHKeyPath,
    kWWNPrefsSSHKeyPassphrase,
    kWWNPrefsWaypipeUseSSHConfig,
    kWWNPrefsMachineSessionThumbnailsEnabled,
  ];
}

+ (NSArray<NSString *> *)machineTransportOverrideKeys {
  return @[
    kWWNPrefsForceServerSideDecorations,
    kWWNPrefsAutoScale,
    kWWNPrefsRenderMacOSPointer,
    kWWNPrefsNestedCompositorCursor,
    kWWNPrefsTouchInputType,
    kWWNPrefsSwapCmdWithAlt,
    kWWNPrefsUniversalClipboard,
    kWWNPrefsVulkanDriver,
    kWWNPrefsOpenGLDriver,
    kWWNPrefsEnableDmabuf,
    kWWNPrefsColorOperations,
    kWWNPrefsWaylandDisplayNumber,
    kWWNPrefsWaypipeCompress,
    kWWNPrefsWaypipeCompressLevel,
    kWWNPrefsWaypipeThreads,
    kWWNPrefsWaypipeVideo,
    kWWNPrefsWaypipeVideoEncoding,
    kWWNPrefsWaypipeVideoDecoding,
    kWWNPrefsWaypipeVideoBpf,
    kWWNPrefsWaypipeUseSSHConfig,
    kWWNPrefsWaypipeRemoteCommand,
    kWWNPrefsWaypipeDebug,
    kWWNPrefsWaypipeNoGpu,
    kWWNPrefsWaypipeOneshot,
    kWWNPrefsWaypipeUnlinkSocket,
    kWWNPrefsWaypipeLoginShell,
    kWWNPrefsWaypipeVsock,
    kWWNPrefsWaypipeXwls,
    kWWNPrefsWaypipeTitlePrefix,
    kWWNPrefsWaypipeSecCtx,
    kWWNPrefsSSHHost,
    kWWNPrefsSSHUser,
    kWWNPrefsSSHPort,
    kWWNPrefsSSHAuthMethod,
    kWWNPrefsSSHPassword,
    kWWNPrefsSSHKeyPath,
    kWWNPrefsSSHKeyPassphrase,
  ];
}

+ (NSDictionary<NSString *, id> *)captureSettingsSnapshot {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
  for (NSString *key in [self machineScopedSettingsKeys]) {
    id value = [defaults objectForKey:key];
    if (value != nil) {
      snapshot[key] = value;
    }
  }
  return snapshot;
}

+ (void)applySettingsSnapshot:(NSDictionary<NSString *, id> *)snapshot {
  if (snapshot.count == 0) {
    return;
  }
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  for (NSString *key in snapshot) {
    id value = snapshot[key];
    if (value == nil) {
      continue;
    }
    id current = [defaults objectForKey:key];
    if (current == value || [current isEqual:value]) {
      continue;
    }
    [defaults setObject:value forKey:key];
  }
}

+ (NSDictionary<NSString *, id> *)normalizedSettingsOverridesForProfile:
    (WWNMachineProfile *)profile {
  NSDictionary<NSString *, id> *currentGlobalSnapshot = [self captureSettingsSnapshot];
  NSMutableDictionary<NSString *, id> *merged = [NSMutableDictionary dictionary];
  [merged addEntriesFromDictionary:currentGlobalSnapshot];

  if ([profile.settingsOverrides isKindOfClass:[NSDictionary class]]) {
    for (NSString *key in profile.settingsOverrides) {
      id value = profile.settingsOverrides[key];
      if (value != nil) {
        merged[key] = value;
      }
    }
  }

  return merged;
}

+ (void)ensureObserverRegistered {
  // No-op: persisting machine snapshots from global prefs causes data divergence.
}

+ (WWNMachineProfile *)profileFromDictionary:(NSDictionary *)obj {
  WWNMachineProfile *profile = [[WWNMachineProfile alloc] initDefaultProfile];
  NSString *machineId = [obj[@"id"] isKindOfClass:[NSString class]] ? obj[@"id"] : @"";
  profile.machineId = machineId.length > 0 ? machineId : [NSUUID UUID].UUIDString;
  NSString *name = [obj[@"name"] isKindOfClass:[NSString class]] ? obj[@"name"] : @"";
  profile.name = name.length > 0 ? name : @"Unnamed Machine";
  NSString *type = [obj[@"type"] isKindOfClass:[NSString class]] ? obj[@"type"] : @"";
  profile.type = type.length > 0 ? type : kWWNMachineTypeNative;
  profile.sshEnabled = [obj[@"sshEnabled"] respondsToSelector:@selector(boolValue)] ? [obj[@"sshEnabled"] boolValue] : YES;
  profile.sshHost = [obj[@"sshHost"] isKindOfClass:[NSString class]] ? obj[@"sshHost"] : @"";
  profile.sshUser = [obj[@"sshUser"] isKindOfClass:[NSString class]] ? obj[@"sshUser"] : @"";
  profile.sshPort = [obj[@"sshPort"] respondsToSelector:@selector(integerValue)] ? [obj[@"sshPort"] integerValue] : 22;
  profile.sshPassword = [obj[@"sshPassword"] isKindOfClass:[NSString class]] ? obj[@"sshPassword"] : @"";
  profile.sshBinary = [obj[@"sshBinary"] isKindOfClass:[NSString class]] ? obj[@"sshBinary"] : @"ssh";
  profile.sshAuthMethod = [obj[@"sshAuthMethod"] respondsToSelector:@selector(integerValue)] ? [obj[@"sshAuthMethod"] integerValue] : 0;
  profile.sshKeyPath = [obj[@"sshKeyPath"] isKindOfClass:[NSString class]] ? obj[@"sshKeyPath"] : @"";
  profile.sshKeyPassphrase = [obj[@"sshKeyPassphrase"] isKindOfClass:[NSString class]] ? obj[@"sshKeyPassphrase"] : @"";
  profile.remoteCommand = [obj[@"remoteCommand"] isKindOfClass:[NSString class]] ? obj[@"remoteCommand"] : @"";
  profile.customScript = [obj[@"customScript"] isKindOfClass:[NSString class]] ? obj[@"customScript"] : @"";
  profile.waypipeCompress = [obj[@"waypipeCompress"] isKindOfClass:[NSString class]] ? obj[@"waypipeCompress"] : @"lz4";
  profile.waypipeThreads = [obj[@"waypipeThreads"] isKindOfClass:[NSString class]] ? obj[@"waypipeThreads"] : @"0";
  profile.waypipeVideo = [obj[@"waypipeVideo"] isKindOfClass:[NSString class]] ? obj[@"waypipeVideo"] : @"none";
  profile.waypipeDebug = [obj[@"waypipeDebug"] respondsToSelector:@selector(boolValue)] ? [obj[@"waypipeDebug"] boolValue] : NO;
  profile.waypipeOneshot = [obj[@"waypipeOneshot"] respondsToSelector:@selector(boolValue)] ? [obj[@"waypipeOneshot"] boolValue] : NO;
  profile.waypipeDisableGpu = [obj[@"waypipeDisableGpu"] respondsToSelector:@selector(boolValue)] ? [obj[@"waypipeDisableGpu"] boolValue] : NO;
  profile.waypipeLoginShell = [obj[@"waypipeLoginShell"] respondsToSelector:@selector(boolValue)] ? [obj[@"waypipeLoginShell"] boolValue] : NO;
  profile.waypipeTitlePrefix = [obj[@"waypipeTitlePrefix"] isKindOfClass:[NSString class]] ? obj[@"waypipeTitlePrefix"] : @"";
  profile.waypipeSecCtx = [obj[@"waypipeSecCtx"] isKindOfClass:[NSString class]] ? obj[@"waypipeSecCtx"] : @"";
  NSDictionary *runtimeOverrides =
      [obj[kWWNMachineRuntimeOverrides] isKindOfClass:[NSDictionary class]]
          ? obj[kWWNMachineRuntimeOverrides]
          : @{};
  NSDictionary *legacySettingsOverrides =
      [runtimeOverrides[@"legacySettingsOverrides"] isKindOfClass:[NSDictionary class]]
          ? runtimeOverrides[@"legacySettingsOverrides"]
          : @{};
  if (legacySettingsOverrides.count == 0 &&
      [obj[kWWNMachineSettingsOverrides] isKindOfClass:[NSDictionary class]]) {
    legacySettingsOverrides = obj[kWWNMachineSettingsOverrides];
  }
  // Migrate legacy Server-Side Decorations (issue #53): older profiles stored
  // the SSD toggle under settingsOverrides["ForceServerSideDecorations"], but
  // the canonical per-machine key is runtimeOverrides["forceSSD"] (machine
  // override first, global fallback second). Normalize on load so the resolved
  // precedence path (applyMachineToRuntimePrefs) honors saved values.
  if (runtimeOverrides[@"forceSSD"] == nil &&
      [legacySettingsOverrides[kWWNPrefsForceServerSideDecorations]
          respondsToSelector:@selector(boolValue)]) {
    NSMutableDictionary *migrated = [runtimeOverrides mutableCopy];
    migrated[@"forceSSD"] = @([legacySettingsOverrides[kWWNPrefsForceServerSideDecorations]
        boolValue]);
    runtimeOverrides = migrated;
  }
  // Migrate legacy SSH port (issue #48): older profiles persisted the port
  // under settingsOverrides["SSHPort"] rather than the canonical top-level
  // "sshPort" key. Honor the legacy value only when the modern key is absent,
  // so an explicit top-level port always wins and the resolved precedence path
  // (applyMachineToRuntimePrefs) never silently falls back to 22.
  if (obj[@"sshPort"] == nil &&
      [legacySettingsOverrides[kWWNPrefsSSHPort]
          respondsToSelector:@selector(integerValue)]) {
    NSInteger legacyPort = [legacySettingsOverrides[kWWNPrefsSSHPort] integerValue];
    if (legacyPort > 0) {
      profile.sshPort = legacyPort;
    }
  }
  profile.runtimeOverrides = runtimeOverrides;
  profile.settingsOverrides = legacySettingsOverrides;
  if ([runtimeOverrides[kWWNRuntimeWaypipeEnabled]
          respondsToSelector:@selector(boolValue)]) {
    profile.sshEnabled = [runtimeOverrides[kWWNRuntimeWaypipeEnabled] boolValue];
  }
  NSString *bundledAppID =
      [runtimeOverrides[kWWNRuntimeBundledAppID] isKindOfClass:[NSString class]]
          ? runtimeOverrides[kWWNRuntimeBundledAppID]
          : @"";
  if (bundledAppID.length > 0) {
    NSMutableDictionary *merged = [legacySettingsOverrides mutableCopy];
    merged[@"NativeClientId"] = bundledAppID;
    merged[@"WestonEnabled"] = @([bundledAppID isEqualToString:@"weston"]);
    merged[@"WestonTerminalEnabled"] =
        @([bundledAppID isEqualToString:@"weston-terminal"]);
    merged[@"WestonSimpleSHMEnabled"] =
        @([bundledAppID isEqualToString:@"weston-simple-shm"]);
    merged[@"FootEnabled"] = @([bundledAppID isEqualToString:@"foot"]);
    merged[@"NiriEnabled"] = @([bundledAppID isEqualToString:@"niri"]);
    profile.settingsOverrides = merged;
  }
  profile.favorite = [obj[@"favorite"] respondsToSelector:@selector(boolValue)] ? [obj[@"favorite"] boolValue] : NO;
  profile.createdAtMs = [obj[@"createdAtMs"] respondsToSelector:@selector(longLongValue)] ? [obj[@"createdAtMs"] longLongValue] : profile.createdAtMs;
  profile.updatedAtMs = [obj[@"updatedAtMs"] respondsToSelector:@selector(longLongValue)] ? [obj[@"updatedAtMs"] longLongValue] : profile.updatedAtMs;
  return profile;
}

+ (NSArray<WWNMachineProfile *> *)parseProfilesData:(NSData *)data {
  if (!data || data.length == 0) {
    return @[];
  }

  NSError *err = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
  if (err || ![parsed isKindOfClass:[NSArray class]]) {
    return @[];
  }

  NSMutableArray<WWNMachineProfile *> *profiles = [NSMutableArray array];
  for (id entry in (NSArray *)parsed) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    [profiles addObject:[self profileFromDictionary:(NSDictionary *)entry]];
  }
  return profiles;
}

+ (void)saveProfiles:(NSArray<WWNMachineProfile *> *)profiles {
  NSMutableArray *arr = [NSMutableArray arrayWithCapacity:profiles.count];
  for (WWNMachineProfile *profile in profiles) {
    [arr addObject:[profile serialize]];
  }

  NSError *err = nil;
  NSData *json = [NSJSONSerialization dataWithJSONObject:arr options:0 error:&err];
  if (err || !json) {
    return;
  }

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject:json forKey:kWWNMachineProfilesJSON];
  [defaults removeObjectForKey:[kWWNMachineProfilesJSON stringByAppendingString:@".legacyString"]];
}

+ (void)migrateFromLegacyPrefsIfNeeded {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  BOOL migrated = [defaults boolForKey:kWWNMachineProfilesMigrated];
  NSData *existingData = [defaults dataForKey:kWWNMachineProfilesJSON];
  NSString *existingLegacy = [defaults stringForKey:kWWNMachineProfilesJSON];
  if (migrated || existingData.length > 0 || existingLegacy.length > 0) {
    if (existingLegacy.length > 0 && existingData.length == 0) {
      NSData *legacyData = [existingLegacy dataUsingEncoding:NSUTF8StringEncoding];
      NSArray<WWNMachineProfile *> *parsed = [self parseProfilesData:legacyData];
      if (parsed.count > 0) {
        [self saveProfiles:parsed];
      }
    }
    return;
  }

  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  WWNMachineProfile *profile = [[WWNMachineProfile alloc] initDefaultProfile];
  BOOL hasSSHHost = prefs.waypipeSSHHost.length > 0;
  profile.name =
      hasSSHHost ? [NSString stringWithFormat:@"Migrated %@", prefs.waypipeSSHHost] : @"Default Machine";
  profile.type = hasSSHHost ? kWWNMachineTypeSSHWaypipe : kWWNMachineTypeNative;
  profile.sshEnabled = hasSSHHost ? prefs.waypipeSSHEnabled : NO;
  profile.sshHost = prefs.waypipeSSHHost ?: @"";
  profile.sshUser = prefs.waypipeSSHUser ?: @"";
  profile.sshPort = [prefs sshPort];
  profile.sshPassword = prefs.waypipeSSHPassword ?: @"";
  profile.sshBinary = prefs.waypipeSSHBinary ?: @"ssh";
  profile.sshAuthMethod = prefs.waypipeSSHAuthMethod;
  profile.sshKeyPath = prefs.waypipeSSHKeyPath ?: @"";
  profile.sshKeyPassphrase = prefs.waypipeSSHKeyPassphrase ?: @"";
  profile.remoteCommand = prefs.waypipeRemoteCommand ?: @"";
  profile.customScript = prefs.waypipeCustomScript ?: @"";
  profile.waypipeCompress = prefs.waypipeCompress ?: @"lz4";
  profile.waypipeThreads = prefs.waypipeThreads ?: @"0";
  profile.waypipeVideo = prefs.waypipeVideo ?: @"none";
  profile.waypipeDebug = prefs.waypipeDebug;
  profile.waypipeOneshot = prefs.waypipeOneshot;
  profile.waypipeDisableGpu = prefs.waypipeNoGpu;
  profile.waypipeLoginShell = prefs.waypipeLoginShell;
  profile.waypipeTitlePrefix = prefs.waypipeTitlePrefix ?: @"";
  profile.waypipeSecCtx = prefs.waypipeSecCtx ?: @"";
  NSDictionary<NSString *, id> *legacySnapshot = [self captureSettingsSnapshot];
  NSMutableDictionary<NSString *, id> *mergedOverrides = [legacySnapshot mutableCopy];
  if (!hasSSHHost) {
    mergedOverrides[@"NativeClientId"] = @"weston-terminal";
    mergedOverrides[@"EnableLauncher"] = @YES;
    mergedOverrides[@"WestonSimpleSHMEnabled"] = @NO;
    mergedOverrides[@"WestonEnabled"] = @NO;
    mergedOverrides[@"WestonTerminalEnabled"] = @YES;
    mergedOverrides[@"FootEnabled"] = @NO;
  }
  profile.settingsOverrides = mergedOverrides;
  NSString *bundledId =
      [mergedOverrides[@"NativeClientId"] isKindOfClass:[NSString class]]
          ? mergedOverrides[@"NativeClientId"]
          : @"";
  profile.runtimeOverrides = @{
    kWWNRuntimeUseBundledApp : @(bundledId.length > 0 || [mergedOverrides[@"EnableLauncher"] boolValue]),
    kWWNRuntimeBundledAppID : bundledId.length > 0 ? bundledId : @"weston-terminal",
    kWWNRuntimeWaypipeEnabled : @(hasSSHHost ? prefs.waypipeSSHEnabled : NO),
    @"legacySettingsOverrides" : mergedOverrides,
  };

  [self saveProfiles:@[ profile ]];
  [self setActiveMachineId:profile.machineId];
  [defaults setBool:YES forKey:kWWNMachineProfilesMigrated];
}

+ (NSArray<WWNMachineProfile *> *)loadProfiles {
  [self ensureObserverRegistered];
  [self migrateFromLegacyPrefsIfNeeded];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSData *rawData = [defaults dataForKey:kWWNMachineProfilesJSON];
  if (rawData.length > 0) {
    return [self parseProfilesData:rawData];
  }
  NSString *legacy = [defaults stringForKey:kWWNMachineProfilesJSON];
  if (legacy.length > 0) {
    NSData *legacyData = [legacy dataUsingEncoding:NSUTF8StringEncoding];
    NSArray<WWNMachineProfile *> *profiles = [self parseProfilesData:legacyData];
    if (profiles.count > 0) {
      [self saveProfiles:profiles];
    }
    return profiles;
  }
  return @[];
}

+ (NSArray<WWNMachineProfile *> *)upsertProfile:(WWNMachineProfile *)profile {
  long long now = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
  profile.updatedAtMs = now;
  if (profile.createdAtMs == 0) {
    profile.createdAtMs = now;
  }
  if (profile.machineId.length == 0) {
    profile.machineId = [NSUUID UUID].UUIDString;
  }
  profile.settingsOverrides = [self normalizedSettingsOverridesForProfile:profile];

  NSMutableArray<WWNMachineProfile *> *profiles = [[self loadProfiles] mutableCopy];
  NSUInteger idx = [profiles indexOfObjectPassingTest:^BOOL(WWNMachineProfile *obj, NSUInteger idx, BOOL *stop) {
    (void)idx;
    (void)stop;
    return [obj.machineId isEqualToString:profile.machineId];
  }];
  if (idx == NSNotFound) {
    [profiles addObject:profile];
  } else {
    profiles[idx] = profile;
  }
  [self saveProfiles:profiles];
  return profiles;
}

+ (NSArray<WWNMachineProfile *> *)deleteProfileById:(NSString *)machineId {
  NSArray<WWNMachineProfile *> *current = [self loadProfiles];
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(WWNMachineProfile *obj, NSDictionary *bindings) {
    (void)bindings;
    return ![obj.machineId isEqualToString:machineId];
  }];
  NSArray<WWNMachineProfile *> *filtered = [current filteredArrayUsingPredicate:predicate];
  [self saveProfiles:filtered];
  if ([[self activeMachineId] isEqualToString:machineId]) {
    [self setActiveMachineId:nil];
  }
  return filtered;
}

+ (NSArray<WWNMachineProfile *> *)deleteAllProfiles {
  [self saveProfiles:@[]];
  [self setActiveMachineId:nil];
  return @[];
}

+ (NSString *)activeMachineId {
  return [[NSUserDefaults standardUserDefaults] stringForKey:kWWNActiveMachineId];
}

+ (void)setActiveMachineId:(NSString *)machineId {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if (machineId.length > 0) {
    [defaults setObject:machineId forKey:kWWNActiveMachineId];
  } else {
    [defaults removeObjectForKey:kWWNActiveMachineId];
  }
}

+ (WWNMachineProfile *)profileById:(NSString *)machineId {
  if (machineId.length == 0) {
    return nil;
  }
  for (WWNMachineProfile *profile in [self loadProfiles]) {
    if ([profile.machineId isEqualToString:machineId]) {
      return profile;
    }
  }
  return nil;
}

+ (BOOL)profileIndicatesNestedWithNativeClientId:(NSString *)clientId
                                  customCommand:(NSString *)customCommand {
  NSString *cid = [clientId isKindOfClass:[NSString class]] ? clientId : @"";
  if ([cid isEqualToString:@"weston"]) {
    return YES;
  }
  // niri (wwn-niri) always runs nested: a Wayland client of the Wawona
  // compositor hosting its own scrollable-tiling clients.
  if ([cid isEqualToString:@"niri"]) {
    return YES;
  }
  if (![cid isEqualToString:@"custom"]) {
    return NO;
  }
  NSString *cmd =
      [([customCommand isKindOfClass:[NSString class]] ? customCommand : @"")
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (cmd.length == 0) {
    return NO;
  }
  NSString *lower = cmd.lowercaseString;
  if ([lower containsString:@"weston-simple-shm"] ||
      [lower containsString:@"weston-terminal"]) {
    return NO;
  }
  if ([lower containsString:@"/foot"] || [lower isEqualToString:@"foot"] ||
      [lower hasSuffix:@" foot"]) {
    return NO;
  }
  NSArray<NSString *> *nestedHints = @[
    @"sway",
    @"cage",
    @"hyprland",
    @"wayfire",
    @"labwc",
    @"cosmic-comp",
    @"cosmic_comp",
    @"gnome-shell",
    @"mutter",
    @"kwin",
    @"niri",
    @"river",
    @"tinywl",
    @"wf-panel",
  ];
  for (NSString *hint in nestedHints) {
    if ([lower containsString:hint]) {
      return YES;
    }
  }
  if ([lower containsString:@"weston"]) {
    return YES;
  }
  return NO;
}

+ (void)resolvedNativeIdentityForProfile:(WWNMachineProfile *)profile
                                clientId:(NSString **)outCid
                           customCommand:(NSString **)outCmd {
  NSString *cid = @"";
  NSString *cmd = @"";
  if (profile) {
    NSDictionary *ro =
        [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
            ? profile.runtimeOverrides
            : @{};
    NSDictionary *so =
        [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
            ? profile.settingsOverrides
            : @{};
    id bundled = ro[@"bundledAppID"];
    if ([bundled isKindOfClass:[NSString class]] &&
        [(NSString *)bundled length] > 0) {
      cid = (NSString *)bundled;
    } else {
      id native = so[@"NativeClientId"];
      if ([native isKindOfClass:[NSString class]] &&
          [(NSString *)native length] > 0) {
        cid = (NSString *)native;
      }
    }
    id custom = so[@"NativeCustomCommand"];
    if ([custom isKindOfClass:[NSString class]]) {
      cmd = (NSString *)custom;
    }
  }
  if (outCid) {
    *outCid = cid;
  }
  if (outCmd) {
    *outCmd = cmd;
  }
}

+ (BOOL)profileIndicatesNestedCompositor:(WWNMachineProfile *)profile {
  if (![profile.type isEqualToString:kWWNMachineTypeNative]) {
    return NO;
  }
  NSString *cid = nil;
  NSString *cmd = nil;
  [self resolvedNativeIdentityForProfile:profile clientId:&cid customCommand:&cmd];
  return [self profileIndicatesNestedWithNativeClientId:cid customCommand:cmd];
}

+ (BOOL)nativeClientIdIndicatesModeBOwnDisplay:(NSString *)clientId
                                 customCommand:(NSString *)customCommand {
  NSString *cid = [clientId isKindOfClass:[NSString class]] ? clientId : @"";
  if ([cid isEqualToString:@"modeb-tty"] ||
      [cid isEqualToString:@"modeb-ttyd"] ||
      [cid isEqualToString:@"kmscube"] ||
      [cid isEqualToString:@"gbm-es2-demo"] ||
      [cid isEqualToString:@"vkcube"] ||
      [cid isEqualToString:@"vkcube-kms"]) {
    return YES;
  }
  return [self profileIndicatesNestedWithNativeClientId:cid
                                          customCommand:customCommand];
}

+ (BOOL)profileIndicatesModeBOwnDisplay:(WWNMachineProfile *)profile {
  if (![profile.type isEqualToString:kWWNMachineTypeNative]) {
    return NO;
  }
  NSString *cid = nil;
  NSString *cmd = nil;
  [self resolvedNativeIdentityForProfile:profile clientId:&cid customCommand:&cmd];
  return [self nativeClientIdIndicatesModeBOwnDisplay:cid customCommand:cmd];
}

+ (BOOL)profileEligibleForAppBridge:(WWNMachineProfile *)profile {
  return [self profileIndicatesNestedCompositor:profile];
}

+ (void)migrateTvosGpuOpenGLDriverSnapshotsIfNeeded {
#if TARGET_OS_TV
#if defined(WWN_TVOS_GPU_BUNDLED) && WWN_TVOS_GPU_BUNDLED
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSData *raw = [defaults dataForKey:kWWNMachineProfilesJSON];
  if (raw.length == 0) {
    NSString *legacy = [defaults stringForKey:kWWNMachineProfilesJSON];
    if (legacy.length > 0) {
      raw = [legacy dataUsingEncoding:NSUTF8StringEncoding];
    }
  }
  if (raw.length == 0) {
    return;
  }

  NSArray<WWNMachineProfile *> *profiles = [self parseProfilesData:raw];
  if (profiles.count == 0) {
    return;
  }

  BOOL changed = NO;
  NSMutableArray<WWNMachineProfile *> *updated =
      [NSMutableArray arrayWithCapacity:profiles.count];
  for (WWNMachineProfile *profile in profiles) {
    BOOL profileChanged = NO;
    NSMutableDictionary *settings =
        [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
            ? [profile.settingsOverrides mutableCopy]
            : [NSMutableDictionary dictionary];
    if ([settings[kWWNPrefsOpenGLDriver] isKindOfClass:[NSString class]] &&
        [settings[kWWNPrefsOpenGLDriver] isEqualToString:@"none"]) {
      settings[kWWNPrefsOpenGLDriver] = @"angle";
      profileChanged = YES;
    }

    NSMutableDictionary *runtime =
        [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
            ? [profile.runtimeOverrides mutableCopy]
            : [NSMutableDictionary dictionary];
    if ([runtime[@"openGLDriver"] isKindOfClass:[NSString class]] &&
        [runtime[@"openGLDriver"] isEqualToString:@"none"]) {
      runtime[@"openGLDriver"] = @"angle";
      profileChanged = YES;
    }
    id legacy = runtime[@"legacySettingsOverrides"];
    if ([legacy isKindOfClass:[NSDictionary class]]) {
      NSMutableDictionary *legacySettings = [legacy mutableCopy];
      if ([legacySettings[kWWNPrefsOpenGLDriver] isKindOfClass:[NSString class]] &&
          [legacySettings[kWWNPrefsOpenGLDriver] isEqualToString:@"none"]) {
        legacySettings[kWWNPrefsOpenGLDriver] = @"angle";
        runtime[@"legacySettingsOverrides"] = legacySettings;
        profileChanged = YES;
      }
    }

    if (profileChanged) {
      profile.settingsOverrides = settings;
      profile.runtimeOverrides = runtime;
      changed = YES;
    }
    [updated addObject:profile];
  }

  if (changed) {
    [self saveProfiles:updated];
  }
#endif
#endif
}

+ (void)applyMachineToRuntimePrefs:(WWNMachineProfile *)profile {
  // tvOS GPU one-shot rewrites leftover OpenGLDriver=none in the profiles JSON
  // during prefs init. Reload so this apply cannot clobber ANGLE with a stale
  // in-memory snapshot taken before that rewrite.
  (void)[WWNPreferencesManager sharedManager];
  if (profile.machineId.length > 0) {
    WWNMachineProfile *fresh = [self profileById:profile.machineId];
    if (fresh) {
      profile = fresh;
    }
  }
  [self ensureObserverRegistered];
  NSDictionary<NSString *, id> *resolved = [self resolvedRuntimeSettingsForProfile:profile];
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];

  if ([profile.type isEqualToString:kWWNMachineTypeNative]) {
    [prefs setWaypipeSSHEnabled:NO];
  } else if ([profile.type isEqualToString:kWWNMachineTypeSSHWaypipe] ||
             [profile.type isEqualToString:kWWNMachineTypeSSHTerminal]) {
    [prefs setWaypipeSSHEnabled:YES];
    [prefs setWaypipeSSHHost:[resolved[@"sshHost"] isKindOfClass:[NSString class]] ? resolved[@"sshHost"] : @""];
    [prefs setWaypipeSSHUser:[resolved[@"sshUser"] isKindOfClass:[NSString class]] ? resolved[@"sshUser"] : @""];
    [prefs setSshPort:[resolved[@"sshPort"] respondsToSelector:@selector(integerValue)] ? [resolved[@"sshPort"] integerValue] : 22];
    [prefs setWaypipeSSHPassword:[resolved[@"sshPassword"] isKindOfClass:[NSString class]] ? resolved[@"sshPassword"] : @""];
    [prefs setWaypipeRemoteCommand:[resolved[@"remoteCommand"] isKindOfClass:[NSString class]] ? resolved[@"remoteCommand"] : @""];
    [prefs setWaypipeSSHAuthMethod:profile.sshAuthMethod];
    [prefs setWaypipeSSHKeyPath:profile.sshKeyPath ?: @""];
    [prefs setWaypipeSSHKeyPassphrase:profile.sshKeyPassphrase ?: @""];
  }

  [prefs setWaypipeCompress:profile.waypipeCompress ?: @"lz4"];
  [prefs setWaypipeThreads:profile.waypipeThreads ?: @"0"];
  [prefs setWaypipeVideo:profile.waypipeVideo ?: @"none"];
  [prefs setWaypipeDebug:profile.waypipeDebug];
  [prefs setWaypipeNoGpu:profile.waypipeDisableGpu];
  [prefs setWaypipeOneshot:profile.waypipeOneshot];
  [prefs setWaypipeLoginShell:profile.waypipeLoginShell];
  [prefs setWaypipeTitlePrefix:profile.waypipeTitlePrefix ?: @""];
  [prefs setWaypipeSecCtx:profile.waypipeSecCtx ?: @""];
  NSDictionary<NSString *, id> *overrides =
      [self normalizedSettingsOverridesForProfile:profile];
  NSMutableDictionary<NSString *, id> *transportSnapshot =
      [NSMutableDictionary dictionary];
  for (NSString *key in [self machineScopedSettingsKeys]) {
    id value = overrides[key];
    if (value != nil) {
      transportSnapshot[key] = value;
    }
  }

  /* Touch Input Type: settingsOverrides TouchInputType wins, else
   * runtimeOverrides.inputProfile (Machine Settings), else global. Normalize
   * legacy labels ("direct") so Multi-Touch/Touchpad match global Settings. */
  {
    NSString *touch = nil;
    id soTouch = transportSnapshot[kWWNPrefsTouchInputType];
    if ([soTouch isKindOfClass:[NSString class]] &&
        [(NSString *)soTouch length] > 0) {
      touch = (NSString *)soTouch;
    } else if ([resolved[@"inputProfile"] isKindOfClass:[NSString class]]) {
      touch = resolved[@"inputProfile"];
    }
    touch = [self normalizeTouchInputType:touch];
    transportSnapshot[kWWNPrefsTouchInputType] = touch;
    [prefs setTouchInputType:touch];
  }

  // Swift MachineProfileStore persists per-machine overrides under
  // runtimeOverrides (e.g. forceSSD) rather than settingsOverrides.
  NSDictionary *swiftRuntime =
      [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
          ? profile.runtimeOverrides
          : @{};

  if ([profile.type isEqualToString:kWWNMachineTypeNative]) {
    BOOL hasExplicitPointerOverride =
        [profile.settingsOverrides[kWWNPrefsRenderMacOSPointer]
            respondsToSelector:@selector(boolValue)] ||
        [swiftRuntime[@"renderMacOSPointer"] respondsToSelector:@selector(boolValue)];
    if (!hasExplicitPointerOverride) {
      BOOL nested = [self profileIndicatesNestedCompositor:profile];
      transportSnapshot[kWWNPrefsRenderMacOSPointer] = @(!nested);
    }
  }

  id swiftForceSSD = swiftRuntime[@"forceSSD"];
  if ([swiftForceSSD respondsToSelector:@selector(boolValue)]) {
    transportSnapshot[kWWNPrefsForceServerSideDecorations] = swiftForceSSD;
  }
  id swiftAutoScale = swiftRuntime[@"autoScale"];
  if ([swiftAutoScale respondsToSelector:@selector(boolValue)]) {
    transportSnapshot[kWWNPrefsAutoScale] = swiftAutoScale;
  }
  id swiftVulkanDriver = swiftRuntime[@"vulkanDriver"];
  if ([swiftVulkanDriver isKindOfClass:[NSString class]] &&
      [swiftVulkanDriver length] > 0) {
    transportSnapshot[kWWNPrefsVulkanDriver] = swiftVulkanDriver;
  }
  id swiftOpenGLDriver = swiftRuntime[@"openGLDriver"];
  if ([swiftOpenGLDriver isKindOfClass:[NSString class]] &&
      [swiftOpenGLDriver length] > 0) {
    transportSnapshot[kWWNPrefsOpenGLDriver] = swiftOpenGLDriver;
  }
  id swiftDmabuf = swiftRuntime[@"dmabufEnabled"];
  if ([swiftDmabuf respondsToSelector:@selector(boolValue)]) {
    transportSnapshot[kWWNPrefsEnableDmabuf] = swiftDmabuf;
  }
  id swiftRenderPointer = swiftRuntime[@"renderMacOSPointer"];
  if ([swiftRenderPointer respondsToSelector:@selector(boolValue)]) {
    transportSnapshot[kWWNPrefsRenderMacOSPointer] = swiftRenderPointer;
  }
  id swiftNestedCursor = swiftRuntime[@"nestedCompositorCursor"];
  if ([swiftNestedCursor isKindOfClass:[NSString class]] &&
      ([swiftNestedCursor isEqualToString:@"host"] ||
       [swiftNestedCursor isEqualToString:@"virtual"])) {
    transportSnapshot[kWWNPrefsNestedCompositorCursor] = swiftNestedCursor;
  }

  [self applySettingsSnapshot:transportSnapshot];

  // Force SSD per-machine (#120): stage THIS machine's decoration policy for
  // its next client launch instead of globally re-decorating every live
  // client (the old -setForceSSD: here stomped every concurrent machine).
  // The effective value is the machine's explicit Force SSD override (from
  // settingsOverrides or runtimeOverrides, both collected into
  // transportSnapshot above) or, absent an override, the global default which
  // "seeds" new machines. The connecting client's first toplevel claims and
  // pins this, so a later machine connecting. Or a later global toggle -
  // never restyles it.
  id machineForceSSDValue = transportSnapshot[kWWNPrefsForceServerSideDecorations];
  BOOL machineForceSSD =
      [machineForceSSDValue respondsToSelector:@selector(boolValue)]
          ? [machineForceSSDValue boolValue]
          : [[WWNPreferencesManager sharedManager] forceServerSideDecorations];
  [[WWNCompositorBridge sharedBridge]
      setForceSSDForClientLaunch:machineForceSSD];

  // Environment overrides (#157): machine > global, after prefs/graphics apply.
  {
    NSDictionary *machineEnv = nil;
    id env = swiftRuntime[@"environment"];
    if ([env isKindOfClass:[NSDictionary class]]) {
      machineEnv = env;
    }
    WWNEnvironmentOverridesApply(machineEnv);
  }
}

+ (void)applyActiveMachineToRuntimePrefs {
  NSString *activeId = [self activeMachineId];
  if (wwn_log_ring_set_machine) {
    wwn_log_ring_set_machine(activeId.length > 0 ? activeId.UTF8String : "");
  }
  if (activeId.length == 0) {
    return;
  }
  WWNMachineProfile *profile = [self profileById:activeId];
  if (profile) {
    [self applyMachineToRuntimePrefs:profile];
  }
}

+ (void)persistActiveMachineSettings {
  // Intentionally disabled to avoid dual-write drift between machine profiles
  // and global preferences.
}

+ (NSDictionary<NSString *, id> *)resolvedRuntimeSettingsForProfile:
    (WWNMachineProfile *)profile {
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];

  NSDictionary<NSString *, id> *runtimeOverrides =
      [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
          ? profile.runtimeOverrides
          : @{};
  NSString *resolvedSSHHost = profile.sshHost.length > 0 ? profile.sshHost : [prefs waypipeSSHHost];
  NSString *resolvedSSHUser = profile.sshUser.length > 0 ? profile.sshUser : [prefs waypipeSSHUser];
  NSInteger resolvedSSHPort = profile.sshPort > 0 ? profile.sshPort : [prefs sshPort];
  NSString *resolvedSSHPassword =
      profile.sshPassword.length > 0 ? profile.sshPassword : [prefs waypipeSSHPassword];
  NSString *resolvedCommand =
      profile.remoteCommand.length > 0 ? profile.remoteCommand : @"weston-simple-shm";

  NSString *bundledAppID =
      [runtimeOverrides[kWWNRuntimeBundledAppID] isKindOfClass:[NSString class]]
          ? runtimeOverrides[kWWNRuntimeBundledAppID]
          : @"";
  if (bundledAppID.length == 0 &&
      [profile.settingsOverrides[@"NativeClientId"] isKindOfClass:[NSString class]]) {
    bundledAppID = profile.settingsOverrides[@"NativeClientId"];
  }
  BOOL useBundledApp = [runtimeOverrides[kWWNRuntimeUseBundledApp]
      respondsToSelector:@selector(boolValue)]
      ? [runtimeOverrides[kWWNRuntimeUseBundledApp] boolValue]
      : (bundledAppID.length > 0);

  NSString *inputProfile =
      [runtimeOverrides[kWWNRuntimeInputProfile] isKindOfClass:[NSString class]]
          ? runtimeOverrides[kWWNRuntimeInputProfile]
          : @"";
  if (inputProfile.length == 0 &&
      [profile.settingsOverrides[kWWNPrefsTouchInputType]
          isKindOfClass:[NSString class]]) {
    inputProfile = profile.settingsOverrides[kWWNPrefsTouchInputType];
  }
  if (inputProfile.length == 0) {
    inputProfile = [prefs touchInputType];
  }
  inputProfile = [self normalizeTouchInputType:inputProfile];

  BOOL waypipeEnabled = NO;
  if ([profile.type isEqualToString:kWWNMachineTypeSSHWaypipe] ||
      [profile.type isEqualToString:kWWNMachineTypeSSHTerminal]) {
    waypipeEnabled = [runtimeOverrides[kWWNRuntimeWaypipeEnabled]
        respondsToSelector:@selector(boolValue)]
        ? [runtimeOverrides[kWWNRuntimeWaypipeEnabled] boolValue]
        : [prefs waypipeSSHEnabled];
  }

  NSString *renderer =
      [runtimeOverrides[kWWNRuntimeRenderer] isKindOfClass:[NSString class]]
          ? runtimeOverrides[kWWNRuntimeRenderer]
          : @"";
  if (renderer.length == 0) {
    renderer = @"metal";
  }

  return @{
    @"machineID" : profile.machineId ?: @"",
    @"machineName" : profile.name ?: @"",
    @"machineType" : profile.type ?: kWWNMachineTypeNative,
    @"renderer" : renderer ?: @"",
    @"waylandDisplay" : [prefs waypipeDisplay] ?: @"wayland-0",
    @"sshHost" : resolvedSSHHost ?: @"",
    @"sshUser" : resolvedSSHUser ?: @"",
    @"sshPort" : @(resolvedSSHPort > 0 ? resolvedSSHPort : 22),
    @"sshPassword" : resolvedSSHPassword ?: @"",
    @"remoteCommand" : resolvedCommand,
    @"waypipeEnabled" : @(waypipeEnabled),
    kWWNRuntimeUseBundledApp : @(useBundledApp),
    kWWNRuntimeBundledAppID : bundledAppID ?: @"",
    @"inputProfile" : inputProfile ?: @"Multi-Touch",
  };
}

+ (BOOL)isMachineThumbnailEnabledForProfile:(WWNMachineProfile *)profile {
  NSDictionary<NSString *, id> *runtimeOverrides =
      [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
          ? profile.runtimeOverrides
          : @{};
  id overrideValue = runtimeOverrides[kWWNRuntimeMachineThumbnailEnabledOverride];
  if ([overrideValue respondsToSelector:@selector(boolValue)]) {
    return [overrideValue boolValue];
  }
  return [[WWNPreferencesManager sharedManager] machineSessionThumbnailsEnabled];
}

+ (BOOL)globalBoolPrefForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults objectForKey:key] == nil) {
    return defaultValue;
  }
  return [defaults boolForKey:key];
}

+ (BOOL)resolvedRuntimeBoolForProfile:(nullable WWNMachineProfile *)profile
                           overrideKey:(NSString *)overrideKey
                             globalKey:(NSString *)globalKey
                          defaultValue:(BOOL)defaultValue {
  BOOL global = [self globalBoolPrefForKey:globalKey defaultValue:defaultValue];
  if (!profile) {
    return global;
  }
  NSDictionary *runtimeOverrides =
      [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
          ? profile.runtimeOverrides
          : @{};
  id overrideValue = runtimeOverrides[overrideKey];
  if ([overrideValue respondsToSelector:@selector(boolValue)]) {
    return [overrideValue boolValue];
  }
  return global;
}

+ (BOOL)resolvedShakeToCloseForProfile:(WWNMachineProfile *)profile {
  return [self resolvedRuntimeBoolForProfile:profile
                                 overrideKey:kWWNRuntimeShakeToCloseEnabled
                                   globalKey:kWWNPrefShakeToCloseEnabled
                                defaultValue:YES];
}

+ (BOOL)resolvedSwipeBackToCloseForProfile:(WWNMachineProfile *)profile {
  return [self resolvedRuntimeBoolForProfile:profile
                                 overrideKey:kWWNRuntimeSwipeBackToCloseEnabled
                                   globalKey:kWWNPrefSwipeBackToCloseEnabled
                                defaultValue:YES];
}

+ (BOOL)resolvedRenderMacOSPointerForProfile:(WWNMachineProfile *)profile {
  return [self resolvedRuntimeBoolForProfile:profile
                                 overrideKey:@"renderMacOSPointer"
                                   globalKey:kWWNPrefsRenderMacOSPointer
                                defaultValue:NO];
}

+ (BOOL)resolvedRenderMacOSPointerActive {
  NSString *activeId = [self activeMachineId];
  WWNMachineProfile *profile = nil;
  if (activeId.length > 0) {
    profile = [self profileById:activeId];
  }
  return [self resolvedRenderMacOSPointerForProfile:profile];
}

+ (NSString *)resolvedNestedCompositorCursorForProfile:
    (WWNMachineProfile *)profile {
  NSString *global =
      [[WWNPreferencesManager sharedManager] nestedCompositorCursor];
  if (!profile) {
    return global;
  }
  NSDictionary *overrides =
      [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
          ? profile.settingsOverrides
          : @{};
  id override = overrides[kWWNPrefsNestedCompositorCursor];
  if (![override isKindOfClass:[NSString class]]) {
    NSDictionary *runtime =
        [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
            ? profile.runtimeOverrides
            : @{};
    override = runtime[@"nestedCompositorCursor"];
  }
  if ([override isKindOfClass:[NSString class]] &&
      ([override isEqualToString:@"host"] ||
       [override isEqualToString:@"virtual"])) {
    return (NSString *)override;
  }
  return global;
}

+ (NSString *)resolvedNestedCompositorCursorActive {
  NSString *activeId = [self activeMachineId];
  WWNMachineProfile *profile = nil;
  if (activeId.length > 0) {
    profile = [self profileById:activeId];
  }
  return [self resolvedNestedCompositorCursorForProfile:profile];
}

+ (nullable WWNMachineProfile *)activeProfile {
  NSString *activeId = [self activeMachineId];
  if (activeId.length == 0) {
    return nil;
  }
  return [self profileById:activeId];
}

+ (BOOL)resolvedShowHostCursorActive {
  WWNMachineProfile *profile = [self activeProfile];
  if (profile && [self profileIndicatesNestedCompositor:profile]) {
    return NO;
  }
  if (![self resolvedRenderMacOSPointerForProfile:profile]) {
    return NO;
  }
#if TARGET_OS_IPHONE
  return NO;
#else
  return YES;
#endif
}

+ (BOOL)resolvedShowVirtualPointerActive {
  WWNMachineProfile *profile = [self activeProfile];
  if (profile && [self profileIndicatesNestedCompositor:profile]) {
    return NO;
  }
#if TARGET_OS_TV
  // Siri Remote clickpad is the pointing device. Always show the host
  // cursor on non-compositor clients so Select can hit Wayland pixels.
  return YES;
#else
  if (![self resolvedRenderMacOSPointerForProfile:profile]) {
    return NO;
  }
#if TARGET_OS_IPHONE
  return YES;
#else
  return NO;
#endif
#endif
}

+ (BOOL)resolvedAlwaysOnTopForProfile:(WWNMachineProfile *)profile {
  if (!profile) {
    return NO;
  }
  NSDictionary *runtimeOverrides =
      [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
          ? profile.runtimeOverrides
          : @{};
  id value = runtimeOverrides[kWWNRuntimeAlwaysOnTop];
  return [value respondsToSelector:@selector(boolValue)] ? [value boolValue]
                                                          : NO;
}

@end
