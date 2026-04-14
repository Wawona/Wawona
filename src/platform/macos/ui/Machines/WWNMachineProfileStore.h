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
@property(nonatomic, copy) NSString *vmSubtype;
@property(nonatomic, copy) NSString *containerSubtype;
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
+ (nullable NSString *)activeMachineId;
+ (void)setActiveMachineId:(nullable NSString *)machineId;
+ (void)applyMachineToRuntimePrefs:(WWNMachineProfile *)profile;
+ (void)persistActiveMachineSettings;
+ (NSDictionary<NSString *, id> *)resolvedRuntimeSettingsForProfile:(WWNMachineProfile *)profile;

@end

NS_ASSUME_NONNULL_END
