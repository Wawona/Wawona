#import "WWNVirtualMachineRunner.h"

#import "WWNMobileVmEngine.h"

#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <unistd.h>

@interface WWNVirtualMachineRunner ()
// Keyed by machineId so each VM/container has its own tracked subprocess and a
// disconnect can terminate exactly the right one.
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, NSTask *> *tasksByMachineId;
@end

@implementation WWNVirtualMachineRunner

+ (instancetype)sharedRunner {
  static WWNVirtualMachineRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[WWNVirtualMachineRunner alloc] init];
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
  // The boot command is the profile's customScript. Trim so an all-whitespace
  // value is treated as "unconfigured".
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
          errorWithDomain:@"WWNVirtualMachineRunner"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Missing machine profile."
                 }];
    }
    return NO;
  }

  NSString *command = [self bootCommandForProfile:profile];
  if (!command) {
    // Default developer lane: microvm guest + vsock/waypipe bridge into Wawona.
    command =
        @"wawona-microvm >/tmp/wawona-microvm.log 2>&1 & "
         "sleep 2; exec wawona-vm-bridge";
  }

  // Replace any existing subprocess for this machine before starting a new one.
  [self stopProfileWithMachineId:profile.machineId];

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
  task.arguments = @[ @"-lc", command ];

  // Give the guest bridge a hint for Wawona's Wayland runtime dir. The
  // wawona-vm-bridge script honors WAWONA_RUNTIME; default to Wawona's per-uid
  // runtime so `waypipe client` lands where the compositor advertises wayland-0.
  NSMutableDictionary<NSString *, NSString *> *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  if (!env[@"WAWONA_RUNTIME"]) {
    env[@"WAWONA_RUNTIME"] =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  }
  task.environment = env;

  NSString *machineId = profile.machineId ?: @"";
  __weak WWNVirtualMachineRunner *weakSelf = self;
  task.terminationHandler = ^(NSTask *finished) {
    (void)finished;
    dispatch_async(dispatch_get_main_queue(), ^{
      WWNVirtualMachineRunner *strongSelf = weakSelf;
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
                   ?: [NSError errorWithDomain:@"WWNVirtualMachineRunner"
                                          code:3
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Failed to start VM boot command."
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

// iOS/iPadOS/tvOS/visionOS/watchOS: no NSTask / subprocess spawning is available
// (and it would violate App Store rules). VM/container machine types use the
// in-process UTM SE backend (p27) on these platforms, not this runner.
@implementation WWNVirtualMachineRunner

+ (instancetype)sharedRunner {
  static WWNVirtualMachineRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[WWNVirtualMachineRunner alloc] init];
  });
  return shared;
}

- (BOOL)launchProfile:(WWNMachineProfile *)profile
                error:(NSError *_Nullable *_Nullable)error {
  if (!profile) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNVirtualMachineRunner" code:1
                               userInfo:@{NSLocalizedDescriptionKey : @"Missing machine profile."}];
    }
    return NO;
  }

  NSString *custom = [profile.customScript
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (custom.length > 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNVirtualMachineRunner"
                     code:101
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Custom shell scripts are not supported for VMs on iOS. "
                       @"Use the bundled NixOS mobile guest (wawona-mobile-guest)."
                 }];
    }
    return NO;
  }

  NSString *guestDir = [[NSBundle mainBundle] pathForResource:@"wawona-mobile-guest" ofType:nil];
  if (guestDir.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNVirtualMachineRunner"
                     code:102
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Bundled mobile guest (wawona-mobile-guest) is not embedded. "
                       @"Build wawona-mobile-guest-artifacts and enable the Xcode embed phase."
                 }];
    }
    return NO;
  }

  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *kernel = nil;
  for (NSString *name in @[ @"Image", @"zImage", @"vmlinuz", @"vmlinux" ]) {
    NSString *candidate = [guestDir stringByAppendingPathComponent:name];
    if ([fm fileExistsAtPath:candidate]) {
      kernel = candidate;
      break;
    }
  }
  if (kernel == nil) {
    kernel = [guestDir stringByAppendingPathComponent:@"Image"];
  }
  NSString *rootfs = [guestDir stringByAppendingPathComponent:@"rootfs.img"];
  unsigned memoryMB = 768;
  id memOverride = profile.runtimeOverrides[@"memoryMB"];
  if ([memOverride respondsToSelector:@selector(unsignedIntegerValue)]) {
    memoryMB = (unsigned)[memOverride unsignedIntegerValue];
  }

  return [[WWNMobileVmEngine sharedEngine] launchProfileWithKernelPath:kernel
                                                            rootfsPath:rootfs
                                                              memoryMB:memoryMB
                                                                 error:error];
}

- (void)stopProfileWithMachineId:(NSString *)machineId {
  (void)machineId;
  [[WWNMobileVmEngine sharedEngine] stop];
}

- (void)stopAll {
  [[WWNMobileVmEngine sharedEngine] stop];
}

@end

#endif  // TARGET_OS_OSX
