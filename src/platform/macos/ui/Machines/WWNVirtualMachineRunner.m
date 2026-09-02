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

/// Default macOS Machines VM: QEMU + Hypervisor.framework (HVF).
- (NSString *)defaultQemuHvfCommandForProfile:(WWNMachineProfile *)profile {
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
      @"if command -v wawona-vm-launch >/dev/null 2>&1 && [ -d \"%@\" ]; then "
       "exec wawona-vm-launch --guest-dir \"%@\" --memory %u; fi; ",
      guestArg, guestArg, memoryMB];
  [cmd appendFormat:
      @"if command -v wawona-qemu-hvf >/dev/null 2>&1 && [ -d \"%@\" ]; then "
       "exec wawona-qemu-hvf \"%@\" %u; fi; ",
      guestArg, guestArg, memoryMB];
  [cmd appendFormat:
      @"QEMU=$(command -v qemu-system-aarch64 || command -v qemu-system-x86_64 || true); "
       "if [ -z \"$QEMU\" ] || [ ! -d \"%@\" ]; then "
       "echo 'Wawona VM: embed wwn-vms macOS QEMU+HVF engine and guest "
       "(wawona-qemu-hvf + Image/rootfs.img), or set customScript.' >&2; exit 1; fi; "
       "KERN=\"\"; for n in Image zImage vmlinuz vmlinux; do "
       "[ -f \"%@/$n\" ] && KERN=\"%@/$n\" && break; done; "
       "ROOT=\"%@/rootfs.img\"; "
       "test -n \"$KERN\" -a -f \"$ROOT\" || { echo 'incomplete guest' >&2; exit 1; }; "
       "case \"$QEMU\" in *aarch64*) MACH=virt,accel=hvf ;; *) MACH=q35,accel=hvf ;; esac; "
       "echo \"[Wawona] QEMU + HVF (Hypervisor.framework) $QEMU\" >&2; "
       "exec \"$QEMU\" -machine \"$MACH\" -cpu host -m %u "
       "-kernel \"$KERN\" -drive \"file=$ROOT,if=virtio,format=raw\" "
       "-device virtio-rng-pci -nographic -no-reboot",
      guestArg, guestArg, guestArg, guestArg, memoryMB];
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
    // Product default: QEMU + Hypervisor.framework (HVF), not VZ/microvm.
    command = [self defaultQemuHvfCommandForProfile:profile];
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

// iOS family: in-process QEMU-TCTI (UTM SE), not NSTask.
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
                       @"Build wawona-mobile-guest-artifacts, set WAWONA_MOBILE_GUEST_DIR, "
                       @"and enable the Xcode embed phase. Required for VMs and "
                       @"container-in-VM on iOS Mode A."
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

  NSString *ociBundle = nil;
  id ociOverride = profile.runtimeOverrides[@"ociBundlePath"];
  if ([ociOverride isKindOfClass:[NSString class]] &&
      [(NSString *)ociOverride length] > 0) {
    ociBundle = (NSString *)ociOverride;
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
