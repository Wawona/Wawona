#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kWWNMachineTypeSSHWaypipe;
extern NSString *const kWWNMachineTypeSSHTerminal;
extern NSString *const kWWNMachineTypeNative;
extern NSString *const kWWNMachineTypeVirtualMachine;
extern NSString *const kWWNMachineTypeContainer;

@interface WWNMachineProfile : NSObject

@property(nonatomic, copy) NSString *machineId;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *type;
@property(nonatomic, assign) BOOL sshEnabled;
@property(nonatomic, copy) NSString *sshHost;
@property(nonatomic, copy) NSString *sshUser;
@property(nonatomic, assign) NSInteger sshPort;
@property(nonatomic, copy) NSString *sshPassword;
@property(nonatomic, copy) NSString *sshBinary;
@property(nonatomic, assign) NSInteger sshAuthMethod;
@property(nonatomic, copy) NSString *sshKeyPath;
@property(nonatomic, copy) NSString *sshKeyPassphrase;
@property(nonatomic, copy) NSString *remoteCommand;
@property(nonatomic, copy) NSString *customScript;
@property(nonatomic, copy) NSString *waypipeCompress;
@property(nonatomic, copy) NSString *waypipeThreads;
@property(nonatomic, copy) NSString *waypipeVideo;
@property(nonatomic, assign) BOOL waypipeDebug;
@property(nonatomic, assign) BOOL waypipeOneshot;
@property(nonatomic, assign) BOOL waypipeDisableGpu;
@property(nonatomic, assign) BOOL waypipeLoginShell;
@property(nonatomic, copy) NSString *waypipeTitlePrefix;
@property(nonatomic, copy) NSString *waypipeSecCtx;
@property(nonatomic, copy) NSDictionary<NSString *, id> *settingsOverrides;
@property(nonatomic, copy) NSDictionary<NSString *, id> *runtimeOverrides;
/// Container machine settings (nil/empty = inherit global Wawona settings).
/// Keys mirror the cross-platform `containerSettings` JSON object:
/// runtime, containerRef, entryCommand, notes, memory, shmSize, mounts, ports,
/// platform, readOnly, remove, kernelPath, initfsPath, vsockPort.
@property(nonatomic, copy) NSDictionary<NSString *, id> *containerSettings;
@property(nonatomic, assign) BOOL favorite;
@property(nonatomic, assign) long long createdAtMs;
@property(nonatomic, assign) long long updatedAtMs;

+ (instancetype)defaultProfile;
- (instancetype)initDefaultProfile;
- (NSDictionary *)serialize;

@end

@interface WWNMachineProfileStore : NSObject

+ (NSArray<WWNMachineProfile *> *)loadProfiles;
+ (NSArray<WWNMachineProfile *> *)upsertProfile:(WWNMachineProfile *)profile;
+ (NSArray<WWNMachineProfile *> *)deleteProfileById:(NSString *)machineId;
+ (NSArray<WWNMachineProfile *> *)deleteAllProfiles;
+ (nullable NSString *)activeMachineId;
+ (void)setActiveMachineId:(nullable NSString *)machineId;
+ (nullable WWNMachineProfile *)profileById:(NSString *)machineId;
+ (void)applyMachineToRuntimePrefs:(WWNMachineProfile *)profile;
+ (void)applyActiveMachineToRuntimePrefs;
+ (void)persistActiveMachineSettings;
+ (NSDictionary<NSString *, id> *)resolvedRuntimeSettingsForProfile:(WWNMachineProfile *)profile;
+ (BOOL)isMachineThumbnailEnabledForProfile:(WWNMachineProfile *)profile;
+ (BOOL)resolvedShakeToCloseForProfile:(nullable WWNMachineProfile *)profile;
+ (BOOL)resolvedSwipeBackToCloseForProfile:(nullable WWNMachineProfile *)profile;
+ (BOOL)resolvedRenderMacOSPointerForProfile:
    (nullable WWNMachineProfile *)profile;
+ (BOOL)resolvedRenderMacOSPointerActive;
/// @"virtual" or @"host". Which cursor nested compositors grab when virtual
/// cursor is enabled. Falls back to global NestedCompositorCursor.
+ (NSString *)resolvedNestedCompositorCursorForProfile:
    (nullable WWNMachineProfile *)profile;
+ (NSString *)resolvedNestedCompositorCursorActive;
/// Effective host (macOS NSCursor) visibility for the active machine.
+ (BOOL)resolvedShowHostCursorActive;
/// Effective virtual pointer overlay visibility for the active machine.
+ (BOOL)resolvedShowVirtualPointerActive;
/// macOS-only per-machine window override: keep this machine's window above
/// all other windows, even when unfocused. Defaults to NO. There is no
/// global fallback preference for this (unlike shake/swipe-to-close), it is
/// purely a per-machine choice.
+ (BOOL)resolvedAlwaysOnTopForProfile:(nullable WWNMachineProfile *)profile;
+ (BOOL)profileIndicatesNestedWithNativeClientId:(NSString *)clientId
                                   customCommand:(NSString *)customCommand
    NS_SWIFT_NAME(profileIndicatesNested(nativeClientId:customCommand:));
+ (BOOL)profileIndicatesNestedCompositor:(WWNMachineProfile *)profile;

/// App Bridge (anowaW) eligibility: YES only when the profile is a local-only
/// native machine whose client is the **nested Weston** compositor
/// (`weston` running `--backend=wayland`), never a plain demo client. This is
/// stricter than -profileIndicatesNestedCompositor: (which also accepts
/// sway/niri/etc.) because anowaW v1 supports weston nested only.
+ (BOOL)profileEligibleForAppBridge:(WWNMachineProfile *)profile;

@end

NS_ASSUME_NONNULL_END
