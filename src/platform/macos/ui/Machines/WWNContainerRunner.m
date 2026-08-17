#import "WWNContainerRunner.h"

#import "WWNVirtualMachineRunner.h"
#import "../Settings/WWNPreferencesManager.h"

#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <unistd.h>

// Pull a string/bool out of a containerSettings dict (JSON passthrough),
// tolerating absent keys and wrong types the way the rest of the store does.
static NSString *WWNContainerString(NSDictionary *dict, NSString *key) {
  id value = dict[key];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static BOOL WWNContainerBool(NSDictionary *dict, NSString *key) {
  id value = dict[key];
  return [value respondsToSelector:@selector(boolValue)] ? [value boolValue]
                                                         : NO;
}

// Single-quote a value for the /bin/sh -lc command line.
static NSString *WWNContainerShellQuote(NSString *value) {
  NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'"
                                                       withString:@"'\"'\"'"];
  return [NSString stringWithFormat:@"'%@'", escaped];
}

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
  // Advanced escape hatch: a custom script always wins.
  NSString *script = profile.customScript ?: @"";
  script = [script stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (script.length > 0) {
    return script;
  }

  // Otherwise build `container run` from per-machine containerSettings, with
  // every empty field inheriting the global Settings → Containers default.
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  NSDictionary *cs = profile.containerSettings ?: @{};

  NSString *ref = WWNContainerString(cs, @"containerRef");
  if (ref.length == 0) {
    ref = prefs.containerDefaultImage;
  }
  if (ref.length == 0) {
    ref = @"alpine:3.20";
  }
  NSString *command = WWNContainerString(cs, @"entryCommand");
  if (command.length == 0) {
    command = prefs.containerDefaultCommand;
  }
  if (command.length == 0) {
    command = @"/bin/sh";
  }

  NSMutableArray<NSString *> *parts =
      [NSMutableArray arrayWithObject:@"container run --rm"];

  // --memory: per-machine wins, else global; wwn-containerd takes MiB.
  NSString *memory = WWNContainerString(cs, @"memory");
  if (memory.length == 0) {
    memory = prefs.containerMemory;
  }
  if (memory.length > 0) {
    [parts addObject:[NSString stringWithFormat:@"--memory %@", memory]];
  }

  // Kernel / initfs: per-machine flags win, else global env (set in the
  // environment below), else the CLI's own discovery.
  NSString *kernel = WWNContainerString(cs, @"kernelPath");
  if (kernel.length > 0) {
    [parts addObject:[NSString
                         stringWithFormat:@"--kernel %@",
                                          WWNContainerShellQuote(kernel)]];
  }
  NSString *initfs = WWNContainerString(cs, @"initfsPath");
  if (initfs.length > 0) {
    [parts addObject:[NSString
                         stringWithFormat:@"--initfs %@",
                                          WWNContainerShellQuote(initfs)]];
  }

  if (WWNContainerBool(cs, @"readOnly")) {
    [parts addObject:@"--read-only"];
  }
  if (WWNContainerBool(cs, @"initProcess")) {
    [parts addObject:@"--init"];
  }

  [parts addObject:WWNContainerShellQuote(ref)];
  [parts addObject:WWNContainerShellQuote(command)];
  return [parts componentsJoinedByString:@" "];
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

  // Global Settings → Containers env: image store, kernel, initfs. Per-machine
  // kernel/initfs overrides are already in the command line (flags beat env).
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  NSString *imageStore = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsMachineContainerImageStore];
  if (imageStore.length > 0) {
    env[@"WWN_OCI_ROOT"] =
        [imageStore stringByExpandingTildeInPath];
  }
  if (prefs.containerKernelPath.length > 0) {
    env[@"WAWONA_VM_KERNEL"] =
        [prefs.containerKernelPath stringByExpandingTildeInPath];
  }
  if (prefs.containerInitfsPath.length > 0) {
    env[@"WAWONA_VM_INITFS"] =
        [prefs.containerInitfsPath stringByExpandingTildeInPath];
  }
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
  // Container-in-VM on Apple mobile: boot the bundled NixOS guest (same engine
  // as virtual_machine); OCI execution runs inside the guest over virtiofs.
  return [[WWNVirtualMachineRunner sharedRunner] launchProfile:profile error:error];
}

- (void)stopProfileWithMachineId:(NSString *)machineId {
  [[WWNVirtualMachineRunner sharedRunner] stopProfileWithMachineId:machineId];
}

- (void)stopAll {
  [[WWNVirtualMachineRunner sharedRunner] stopAll];
}

@end

#endif  // TARGET_OS_OSX
