#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// ObjC/C entry points for applying persisted environment overrides (#157).
/// Reads `wawona.pref.environment.v1` and optional machine `runtimeOverrides.environment`.
/// Call after platform setenv so user overrides win.

/// Apply global + optional machine override JSON (NSDictionary name → {action,value}).
void WWNEnvironmentOverridesApply(NSDictionary *_Nullable machineEnvironment);

/// Apply overrides for the active machine profile (looks up runtimeOverrides.environment).
void WWNEnvironmentOverridesApplyForActiveMachine(void);

/// Merge override dicts into an NSMutableDictionary suitable for NSTask.environment.
void WWNEnvironmentOverridesMergeIntoTaskEnvironment(NSMutableDictionary *env,
                                                     NSDictionary *_Nullable machineEnvironment);

NS_ASSUME_NONNULL_END
