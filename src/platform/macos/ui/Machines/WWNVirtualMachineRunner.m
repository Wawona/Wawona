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

/// Default macOS Machines VM: Virtualization.framework (VZ). Never QEMU.
- (NSString *)defaultVzCommandForProfile:(WWNMachineProfile *)profile {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *resources = bundle.resourcePath ?: @"";
  NSString *binDir = [resources stringByAppendingPathComponent:@"bin"];
  NSString *guestDir = [bundle pathForResource:@"wawona-macos-guest" ofType:nil];
  if (guestDir.length == 0) {
    guestDir = [bundle pathForResource:@"wawona-mobile-guest" ofType:nil];
  }
  id guestOverride = profile.runtimeOverrides[@"guestDir"];
  if ([guestOverride isKindOfClass:[NSString class]] &&
      [(NSString *)guestOverride length] > 0) {
    guestDir = (NSString *)guestOverride;
  }

  unsigned memoryMB = 2048;
  id memOverride = profile.runtimeOverrides[@"memoryMB"];
  if ([memOverride respondsToSelector:@selector(unsignedIntegerValue)]) {
    memoryMB = (unsigned)[memOverride unsignedIntegerValue];
  }

  NSString *guestArg = guestDir.length > 0 ? guestDir : @"$WAWONA_VM_GUEST";
  NSMutableString *cmd = [NSMutableString string];
  [cmd appendString:@"export PATH=\""];
  [cmd appendString:binDir];
  [cmd appendString:@":$PATH\"; "];
  [cmd appendFormat:
      @"if command -v wawona-vz-run >/dev/null 2>&1 && [ -d \"%@\" ]; then "
       "exec wawona-vz-run \"%@\" %u; fi; ",
      guestArg, guestArg, memoryMB];
  [cmd appendString:
      @"echo 'Wawona VM: use Machines Start via Relay (wawona_relay). "
       "No wawona-vm-launch / QEMU fallback.' >&2; exit 1"];
  return cmd;
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
    command = [self defaultVzCommandForProfile:profile];
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

// iOS family: Relay static CPU starts from WWNRelay. This runner is leftover
// for a missing Relay ABI. No QEMU.
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

  NSString *ociBundle = nil;
  id ociOverride = profile.runtimeOverrides[@"ociBundlePath"];
  if ([ociOverride isKindOfClass:[NSString class]] &&
      [(NSString *)ociOverride length] > 0) {
    ociBundle = (NSString *)ociOverride;
  }
  NSString *guestResource = @"wawona-mobile-guest";
  if (ociBundle.length > 0 ||
      [profile.type isEqualToString:kWWNMachineTypeContainer]) {
    guestResource = @"wawona-container-guest";
  }
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *guestDir =
      [[NSBundle mainBundle] pathForResource:guestResource ofType:nil];
  /* Slim / lab inject copies the guest dir after TrollStore install.
     pathForResource only sees the signed resource map, so also accept a
     real folder next to the executable. */
  if (guestDir.length == 0) {
    NSString *beside = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:guestResource];
    if ([fm fileExistsAtPath:beside]) {
      guestDir = beside;
    }
  }
  if (guestDir.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNVirtualMachineRunner"
                     code:102
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Bundled mobile guest (%@) is not embedded. "
                           @"Build the matching VM/container guest artifact and "
                           @"enable its Xcode embed phase.",
                           guestResource]
                 }];
    }
    return NO;
  }

  NSString *kernel = nil;
  for (NSString *name in
       @[ @"Image", @"Image.vm", @"zImage", @"vmlinuz", @"vmlinux" ]) {
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
  unsigned memoryMB = 512;
  id memOverride = profile.runtimeOverrides[@"memoryMB"];
  if ([memOverride respondsToSelector:@selector(unsignedIntegerValue)]) {
    memoryMB = (unsigned)[memOverride unsignedIntegerValue];
  }

  return [[WWNMobileVmEngine sharedEngine]
      launchProfileWithKernelPath:kernel
                       rootfsPath:rootfs
                         memoryMB:memoryMB
                    ociBundlePath:ociBundle
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
