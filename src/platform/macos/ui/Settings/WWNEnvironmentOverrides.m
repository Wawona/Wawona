#import "WWNEnvironmentOverrides.h"
#import "WWNMachineProfileStore.h"

#import <stdlib.h>

static NSString *const kWWNEnvStorageKey = @"wawona.pref.environment.v1";

static BOOL WWNEnvKeyBanned(NSString *name) {
  return [name hasPrefix:@"DYLD_"] || [name hasPrefix:@"LD_"];
}

static NSDictionary *WWNEnvLoadGlobalOverrides(void) {
  NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kWWNEnvStorageKey];
  if (![data isKindOfClass:[NSData class]] || data.length == 0) {
    return @{};
  }
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

static void WWNEnvApplyOne(NSString *name, NSDictionary *entry, BOOL stripBanned) {
  if (![name isKindOfClass:[NSString class]] || name.length == 0) {
    return;
  }
  if (stripBanned && WWNEnvKeyBanned(name)) {
    unsetenv(name.UTF8String);
    return;
  }
  if (![entry isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSString *action = entry[@"action"];
  if (![action isKindOfClass:[NSString class]]) {
    return;
  }
  if ([action isEqualToString:@"unset"]) {
    unsetenv(name.UTF8String);
    return;
  }
  if ([action isEqualToString:@"set"]) {
    id value = entry[@"value"];
    NSString *str = [value isKindOfClass:[NSString class]] ? value : @"";
    setenv(name.UTF8String, str.UTF8String, 1);
  }
}

static NSDictionary *WWNEnvMergedOverrides(NSDictionary *_Nullable machineEnvironment) {
  NSMutableDictionary *merged = [WWNEnvLoadGlobalOverrides() mutableCopy] ?: [NSMutableDictionary dictionary];
  if ([machineEnvironment isKindOfClass:[NSDictionary class]]) {
    [merged addEntriesFromDictionary:machineEnvironment];
  }
  return merged;
}

void WWNEnvironmentOverridesApply(NSDictionary *_Nullable machineEnvironment) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  const BOOL stripBanned = YES;
#else
  const BOOL stripBanned = NO;
#endif
  NSDictionary *merged = WWNEnvMergedOverrides(machineEnvironment);
  for (NSString *name in merged) {
    WWNEnvApplyOne(name, merged[name], stripBanned);
  }
}

void WWNEnvironmentOverridesApplyForActiveMachine(void) {
  NSDictionary *machineEnv = nil;
  NSString *activeId = [WWNMachineProfileStore activeMachineId];
  if (activeId.length > 0) {
    WWNMachineProfile *profile = [WWNMachineProfileStore profileById:activeId];
    id runtime = profile.runtimeOverrides;
    if ([runtime isKindOfClass:[NSDictionary class]]) {
      id env = runtime[@"environment"];
      if ([env isKindOfClass:[NSDictionary class]]) {
        machineEnv = env;
      }
    }
  }
  WWNEnvironmentOverridesApply(machineEnv);
}

void WWNEnvironmentOverridesMergeIntoTaskEnvironment(NSMutableDictionary *env,
                                                     NSDictionary *_Nullable machineEnvironment) {
  if (![env isKindOfClass:[NSMutableDictionary class]]) {
    return;
  }
  NSDictionary *merged = WWNEnvMergedOverrides(machineEnvironment);
  for (NSString *name in merged) {
    NSDictionary *entry = merged[name];
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *action = entry[@"action"];
    if ([action isEqualToString:@"unset"]) {
      [env removeObjectForKey:name];
    } else if ([action isEqualToString:@"set"]) {
      id value = entry[@"value"];
      env[name] = [value isKindOfClass:[NSString class]] ? value : @"";
    }
  }
}
