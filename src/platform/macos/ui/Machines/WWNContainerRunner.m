#import "WWNContainerRunner.h"

#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <unistd.h>

@interface WWNContainerRunner ()
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, NSTask *> *tasksByMachineId;
@end

@implementation WWNContainerRunner

+ (instancetype)sharedRunner {
  static WWNContainerRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[WWNContainerRunner alloc] init];
  });
  return shared;
}

- (instancetype)init {
  if ((self = [super init])) {
    _tasksByMachineId = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSString *)bootCommandForProfile:(WWNMachineProfile *)profile {
  NSString *script = profile.customScript ?: @"";
  script = [script stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return script.length > 0 ? script : nil;
}

- (BOOL)launchProfile:(WWNMachineProfile *)profile
                error:(NSError *_Nullable *_Nullable)error {
  if (!profile) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNContainerRunner"
                     code:1
                 userInfo:@{NSLocalizedDescriptionKey : @"Missing machine profile."}];
    }
    return NO;
  }

  NSString *command = [self bootCommandForProfile:profile];
  if (!command) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNContainerRunner"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"No container command configured. On macOS set the "
                       @"machine's custom script to a wwn-containers command, "
                       @"e.g. from the Wawona repo:\n"
                       @"  nix run .#wwn-containerd -- run -i alpine:3.20 -k "
                       @"<kernel>\n"
                       @"or pull an image first with `wwn-oci pull <ref>`."
                 }];
    }
    return NO;
  }

  [self stopProfileWithMachineId:profile.machineId];

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
  task.arguments = @[ @"-lc", command ];

  NSMutableDictionary<NSString *, NSString *> *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  if (!env[@"WAWONA_RUNTIME"]) {
    env[@"WAWONA_RUNTIME"] =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  }
  // Tell the container backend this is the macOS (Apple Containerization) lane.
  env[@"WAWONA_CONTAINER_BACKEND"] = @"containerization";
  task.environment = env;

  NSString *machineId = profile.machineId ?: @"";
  __weak WWNContainerRunner *weakSelf = self;
  task.terminationHandler = ^(NSTask *finished) {
    (void)finished;
    dispatch_async(dispatch_get_main_queue(), ^{
      WWNContainerRunner *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      @synchronized(strongSelf.tasksByMachineId) {
        if (strongSelf.tasksByMachineId[machineId] == finished) {
          [strongSelf.tasksByMachineId removeObjectForKey:machineId];
        }
      }
    });
  };

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    if (error) {
      *error = launchError
                   ?: [NSError errorWithDomain:@"WWNContainerRunner"
                                          code:3
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Failed to start container command."
                                      }];
    }
    return NO;
  }

  @synchronized(self.tasksByMachineId) {
    self.tasksByMachineId[machineId] = task;
  }
  return YES;
}

- (void)stopProfileWithMachineId:(NSString *)machineId {
  if (machineId.length == 0) {
    return;
  }
  NSTask *task = nil;
  @synchronized(self.tasksByMachineId) {
    task = self.tasksByMachineId[machineId];
    [self.tasksByMachineId removeObjectForKey:machineId];
  }
  if (task.isRunning) {
    [task terminate];
  }
}

- (void)stopAll {
  NSArray<NSTask *> *tasks = nil;
  @synchronized(self.tasksByMachineId) {
    tasks = self.tasksByMachineId.allValues;
    [self.tasksByMachineId removeAllObjects];
  }
  for (NSTask *task in tasks) {
    if (task.isRunning) {
      [task terminate];
    }
  }
}

@end

#else  // !TARGET_OS_OSX

// iOS/iPadOS/tvOS/visionOS: container *execution* is container-in-VM (driven by
// the VM runner / wwn-vms guest), not a host subprocess. watchOS is image
// management only. No NSTask spawning here (App Store rules).
@implementation WWNContainerRunner

+ (instancetype)sharedRunner {
  static WWNContainerRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[WWNContainerRunner alloc] init];
  });
  return shared;
}

- (BOOL)launchProfile:(WWNMachineProfile *)profile
                error:(NSError *_Nullable *_Nullable)error {
  (void)profile;
  if (error) {
    *error = [NSError
        errorWithDomain:@"WWNContainerRunner"
                   code:100
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     @"On this platform containers run in-VM (wwn-vms guest) via "
                     @"the VM backend, or are image-management-only (watchOS)."
               }];
  }
  return NO;
}

- (void)stopProfileWithMachineId:(NSString *)machineId {
  (void)machineId;
}

- (void)stopAll {
}

@end

#endif  // TARGET_OS_OSX
