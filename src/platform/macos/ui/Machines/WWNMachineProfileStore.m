#import "WWNMachineProfileStore.h"
#import "../Settings/WWNPreferencesManager.h"

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
    _type = kWWNMachineTypeSSHWaypipe;
    _sshEnabled = YES;
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
    _vmSubtype = @"qemu";
    _containerSubtype = @"docker";
    _waypipeCompress = @"lz4";
    _waypipeThreads = @"0";
    _waypipeVideo = @"none";
    _waypipeDebug = NO;
    _waypipeOneshot = NO;
    _waypipeDisableGpu = NO;
    _waypipeLoginShell = NO;
    _waypipeTitlePrefix = @"";
    _waypipeSecCtx = @"";
    _settingsOverrides = @{};
    _runtimeOverrides = @{};
    _favorite = NO;
    _createdAtMs = now;
    _updatedAtMs = now;
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
    @"type" : self.type ?: kWWNMachineTypeSSHWaypipe,
    @"sshHost" : self.sshHost ?: @"",
    @"sshUser" : self.sshUser ?: @"",
    @"sshPort" : @(self.sshPort > 0 ? self.sshPort : 22),
    @"sshPassword" : self.sshPassword ?: @"",
    @"remoteCommand" : self.remoteCommand ?: @"",
    @"vmSubtype" : self.vmSubtype ?: @"qemu",
    @"containerSubtype" : self.containerSubtype ?: @"docker",
    @"launchers" : @[],
    kWWNMachineRuntimeOverrides : runtimeOverrides,
    @"favorite" : @(self.favorite),
  };
}

@end

@implementation WWNMachineProfileStore

+ (NSArray<NSString *> *)machineScopedSettingsKeys {
  return @[
    kWWNPrefsUniversalClipboard,
    kWWNPrefsForceServerSideDecorations,
    kWWNPrefsAutoScale,
    kWWNPrefsColorOperations,
    kWWNPrefsNestedCompositorsSupport,
    kWWNPrefsRenderMacOSPointer,
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
    kWWNPrefsMachineVMProviderStub,
    kWWNPrefsMachineVMDefaultVsockStub,
    kWWNPrefsMachineContainerRuntimeStub,
    kWWNPrefsMachineContainerNamespaceStub,
    kWWNPrefsSSHHost,
    kWWNPrefsSSHUser,
    kWWNPrefsSSHAuthMethod,
    kWWNPrefsSSHPassword,
    kWWNPrefsSSHKeyPath,
    kWWNPrefsSSHKeyPassphrase,
    kWWNPrefsWaypipeUseSSHConfig,
  ];
}

+ (NSArray<NSString *> *)machineTransportOverrideKeys {
  return @[
    kWWNPrefsForceServerSideDecorations,
    kWWNPrefsAutoScale,
    kWWNPrefsRenderMacOSPointer,
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
    if (value != nil) {
      [defaults setObject:value forKey:key];
    }
  }
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
  profile.type = type.length > 0 ? type : kWWNMachineTypeSSHWaypipe;
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
  profile.vmSubtype = [obj[@"vmSubtype"] isKindOfClass:[NSString class]] ? obj[@"vmSubtype"] : @"qemu";
  profile.containerSubtype = [obj[@"containerSubtype"] isKindOfClass:[NSString class]] ? obj[@"containerSubtype"] : @"docker";
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
  profile.name = prefs.waypipeSSHHost.length > 0 ? [NSString stringWithFormat:@"Migrated %@", prefs.waypipeSSHHost] : @"Default Machine";
  profile.type = kWWNMachineTypeSSHWaypipe;
  profile.sshEnabled = prefs.waypipeSSHEnabled;
  profile.sshHost = prefs.waypipeSSHHost ?: @"";
  profile.sshUser = prefs.waypipeSSHUser ?: @"";
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
  profile.settingsOverrides = legacySnapshot;
  profile.runtimeOverrides = @{
    kWWNRuntimeUseBundledApp : @([legacySnapshot[@"EnableLauncher"] boolValue]),
    kWWNRuntimeBundledAppID :
        ([legacySnapshot[@"NativeClientId"] isKindOfClass:[NSString class]]
             ? legacySnapshot[@"NativeClientId"]
             : @""),
    kWWNRuntimeWaypipeEnabled : @(prefs.waypipeSSHEnabled),
    @"legacySettingsOverrides" : legacySnapshot,
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

+ (void)applyMachineToRuntimePrefs:(WWNMachineProfile *)profile {
  [self ensureObserverRegistered];
  NSDictionary<NSString *, id> *resolved = [self resolvedRuntimeSettingsForProfile:profile];
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  [prefs setWaypipeSSHEnabled:[resolved[@"waypipeEnabled"] boolValue]];
  [prefs setWaypipeSSHHost:[resolved[@"sshHost"] isKindOfClass:[NSString class]] ? resolved[@"sshHost"] : @""];
  [prefs setWaypipeSSHUser:[resolved[@"sshUser"] isKindOfClass:[NSString class]] ? resolved[@"sshUser"] : @""];
  [prefs setWaypipeSSHPassword:[resolved[@"sshPassword"] isKindOfClass:[NSString class]] ? resolved[@"sshPassword"] : @""];
  [prefs setWaypipeRemoteCommand:[resolved[@"remoteCommand"] isKindOfClass:[NSString class]] ? resolved[@"remoteCommand"] : @""];
  [prefs setWaypipeSSHAuthMethod:profile.sshAuthMethod];
  [prefs setWaypipeSSHKeyPath:profile.sshKeyPath ?: @""];
  [prefs setWaypipeSSHKeyPassphrase:profile.sshKeyPassphrase ?: @""];
  [prefs setWaypipeCompress:profile.waypipeCompress ?: @"lz4"];
  [prefs setWaypipeThreads:profile.waypipeThreads ?: @"0"];
  [prefs setWaypipeVideo:profile.waypipeVideo ?: @"none"];
  [prefs setWaypipeDebug:profile.waypipeDebug];
  [prefs setWaypipeNoGpu:profile.waypipeDisableGpu];
  [prefs setWaypipeOneshot:profile.waypipeOneshot];
  [prefs setWaypipeLoginShell:profile.waypipeLoginShell];
  [prefs setWaypipeTitlePrefix:profile.waypipeTitlePrefix ?: @""];
  [prefs setWaypipeSecCtx:profile.waypipeSecCtx ?: @""];
  [prefs setTouchInputType:[resolved[@"inputProfile"] isKindOfClass:[NSString class]] ? resolved[@"inputProfile"] : @"Multi-Touch"];

  NSDictionary<NSString *, id> *overrides =
      [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
          ? profile.settingsOverrides
          : @{};
  NSMutableDictionary<NSString *, id> *transportSnapshot =
      [NSMutableDictionary dictionary];
  for (NSString *key in [self machineTransportOverrideKeys]) {
    id value = overrides[key];
    if (value != nil) {
      transportSnapshot[key] = value;
    }
  }
  [self applySettingsSnapshot:transportSnapshot];

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
  NSString *resolvedSSHPassword =
      profile.sshPassword.length > 0 ? profile.sshPassword : [prefs waypipeSSHPassword];
  NSString *resolvedCommand =
      profile.remoteCommand.length > 0 ? profile.remoteCommand : @"weston-terminal";

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
  if (inputProfile.length == 0) {
    inputProfile = [prefs touchInputType];
  }

  BOOL waypipeEnabled = [runtimeOverrides[kWWNRuntimeWaypipeEnabled]
      respondsToSelector:@selector(boolValue)]
      ? [runtimeOverrides[kWWNRuntimeWaypipeEnabled] boolValue]
      : [prefs waypipeSSHEnabled];

  NSString *renderer =
      [runtimeOverrides[kWWNRuntimeRenderer] isKindOfClass:[NSString class]]
          ? runtimeOverrides[kWWNRuntimeRenderer]
          : @"";
  if (renderer.length == 0) {
    renderer = [prefs vulkanDriver];
  }

  return @{
    @"machineID" : profile.machineId ?: @"",
    @"machineName" : profile.name ?: @"",
    @"machineType" : profile.type ?: kWWNMachineTypeNative,
    @"renderer" : renderer ?: @"",
    @"waylandDisplay" : [prefs waypipeDisplay] ?: @"wayland-0",
    @"sshHost" : resolvedSSHHost ?: @"",
    @"sshUser" : resolvedSSHUser ?: @"",
    @"sshPort" : @(profile.sshPort > 0 ? profile.sshPort : 22),
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

@end
