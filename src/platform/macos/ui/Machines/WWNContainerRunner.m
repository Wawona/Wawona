#import "WWNContainerRunner.h"

#import "WWNVirtualMachineRunner.h"
#import "WWNCompositorBridge.h"
#import "WWNPlatformCallbacks.h"
#import "../Settings/WWNPreferencesManager.h"

#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <dispatch/dispatch.h>
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

// Pull an int out of a containerSettings dict (JSON passthrough): NSNumber
// directly, or an NSString holding digits. Absent/wrong types yield nil.
static NSNumber *WWNContainerNumber(NSDictionary *dict, NSString *key) {
  id value = dict[key];
  if ([value isKindOfClass:[NSNumber class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSString class]]) {
    NSInteger parsed = [(NSString *)value integerValue];
    return @(parsed);
  }
  return nil;
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
// Per-machine polling timers that watch the backend's ready/done marker files.
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, dispatch_source_t> *pollTimersByMachineId;
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
    _pollTimersByMachineId = [NSMutableDictionary dictionary];
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

  // Unique container id per machine, so a crashed previous run can never
  // leave stale state that blocks the next launch.
  NSString *containerId = profile.machineId.length > 0
      ? [@"wawona-" stringByAppendingString:
             [profile.machineId stringByReplacingOccurrencesOfString:@"/"
                                                         withString:@"_"]]
      : @"wawona";
  [parts addObject:[NSString stringWithFormat:@"--id %@", containerId]];

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

  // Desktop session: attach the container's Wayland session to Wawona via the
  // waypipe vsock bridge (wwn-containerd injects the guest waypipe and wraps
  // the command; the host side dials the port). The bundled aarch64-linux
  // waypipe is passed explicitly so no system install is needed.
  if (WWNContainerBool(cs, @"desktopSession")) {
    NSInteger vsockPort = 0;
    NSNumber *portNum = WWNContainerNumber(cs, @"vsockPort");
    if (portNum != nil) {
      vsockPort = portNum.integerValue;
    }
    if (vsockPort <= 0) {
      vsockPort = [prefs.containerVsockPort integerValue];
    }
    if (vsockPort <= 0) {
      vsockPort = 1024;
    }
    [parts addObject:[NSString stringWithFormat:@"--wayland-vsock-port %ld",
                                                (long)vsockPort]];
    NSString *guestWaypipe = WWNWawonaFindBundledExecutable(@"waypipe-guest");
    if (guestWaypipe.length > 0) {
      [parts addObject:[NSString
                           stringWithFormat:@"--waypipe-guest-bin %@",
                                            WWNContainerShellQuote(guestWaypipe)]];
      NSString *guestRoot =
          [[guestWaypipe stringByDeletingLastPathComponent]
              stringByAppendingPathComponent:@"waypipe-guest-root"];
      NSString *guestRootExec =
          [guestRoot stringByAppendingPathComponent:@"bin/waypipe"];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:guestRootExec]) {
        [parts addObject:[NSString
                             stringWithFormat:@"--waypipe-guest-root %@",
                                              WWNContainerShellQuote(guestRoot)]];
      } else {
        NSString *closurePath =
            [guestWaypipe stringByAppendingString:@".closure"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:closurePath]) {
          [parts addObject:[NSString
                               stringWithFormat:@"--waypipe-guest-closure %@",
                                                WWNContainerShellQuote(closurePath)]];
        }
      }
    }
  }

  // Local image from disk: run from the imported OCI layout directory instead
  // of pulling the reference from a registry (wwn-containerd --image-archive).
  NSString *archive = WWNContainerString(cs, @"imageArchivePath");
  if (archive.length > 0) {
    [parts addObject:[NSString
                         stringWithFormat:@"--image-archive %@",
                                          WWNContainerShellQuote(archive)]];
  }

  [parts addObject:WWNContainerShellQuote(ref)];
  [parts addObject:WWNContainerShellQuote(command)];
  return [parts componentsJoinedByString:@" "];
}

// Marker files live in /tmp, keyed by machine id. The backend (wwn-containerd)
// creates them when the VM boots ("ready") and when the container process
// exits ("done"); this runner polls them to drive the GUI status.
- (NSString *)markerFilePathForMachineId:(NSString *)machineId
                                   kind:(NSString *)kind {
  NSString *safeId = [machineId stringByReplacingOccurrencesOfString:@"/"
                                                          withString:@"_"];
  return [NSTemporaryDirectory()
      stringByAppendingPathComponent:
          [NSString stringWithFormat:@"wawona-container-%@-%@", kind, safeId]];
}

- (void)cleanupMarkersForMachineId:(NSString *)machineId {
  if (machineId.length == 0) {
    return;
  }
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm removeItemAtPath:[self markerFilePathForMachineId:machineId kind:@"ready"]
                error:nil];
  [fm removeItemAtPath:[self markerFilePathForMachineId:machineId kind:@"done"]
                error:nil];
  dispatch_source_t pollTimer = nil;
  @synchronized(self.pollTimersByMachineId) {
    pollTimer = self.pollTimersByMachineId[machineId];
    [self.pollTimersByMachineId removeObjectForKey:machineId];
  }
  if (pollTimer) {
    dispatch_source_cancel(pollTimer);
  }
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

  // Replace any existing session for this machine before starting a new one.
  [self stopProfileWithMachineId:profile.machineId];

  NSString *machineId = profile.machineId ?: @"";
  NSString *shellScript =
      WWNWawonaFindBundledExecutable(@"wawona-container-shell");
  NSString *terminal = WWNWawonaFindBundledExecutable(@"weston-terminal");
  if (shellScript.length == 0 || terminal.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNContainerRunner"
                     code:4
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Bundled terminal (weston-terminal) or "
                       @"wawona-container-shell not found in the app bundle."
                 }];
    }
    return NO;
  }

  NSString *readyFile = [self markerFilePathForMachineId:machineId
                                                   kind:@"ready"];
  NSString *doneFile = [self markerFilePathForMachineId:machineId kind:@"done"];
  [[NSFileManager defaultManager] removeItemAtPath:readyFile error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:doneFile error:nil];

  // The container runs inside Wawona's terminal: weston-terminal spawns $SHELL
  // (execl($SHELL, $SHELL, NULL) in weston 13), and we point SHELL at the
  // bundled wrapper, which execs the container command. The container's
  // stdin/stdout/ANSI flow through the terminal's PTY into the Wawona window.
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:terminal];

  NSMutableDictionary<NSString *, NSString *> *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  if (!env[@"WAWONA_RUNTIME"]) {
    env[@"WAWONA_RUNTIME"] =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  }
  // Tell the container backend this is the macOS (Apple Containerization) lane.
  env[@"WAWONA_CONTAINER_BACKEND"] = @"containerization";

  // Wayland socket: the terminal must connect to Wawona's compositor.
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  NSString *socketName = [bridge socketName];
  if (socketName.length > 0) {
    env[@"WAYLAND_DISPLAY"] = socketName;
  } else if (!env[@"WAYLAND_DISPLAY"]) {
    env[@"WAYLAND_DISPLAY"] = @"wayland-0";
  }
  NSString *socketPath = [bridge socketPath];
  if (socketPath.length > 0) {
    env[@"XDG_RUNTIME_DIR"] = [socketPath stringByDeletingLastPathComponent];
  } else if (!env[@"XDG_RUNTIME_DIR"]) {
    env[@"XDG_RUNTIME_DIR"] =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  }

  env[@"SHELL"] = shellScript;
  env[@"WAWONA_CONTAINER_CMD"] = command;
  env[@"WAWONA_CONTAINER_READY_FILE"] = readyFile;
  env[@"WAWONA_CONTAINER_DONE_FILE"] = doneFile;

  // Resolve the bundled `container` CLI (Contents/Resources/bin) before the
  // user PATH, so the wrapper finds it without a system install.
  NSString *resourcesBin =
      [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"bin"];
  if (resourcesBin.length > 0) {
    NSString *existingPath =
        env[@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
    env[@"PATH"] =
        [NSString stringWithFormat:@"%@:%@", resourcesBin, existingPath];
  }

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

  // Desktop session: host waypipe-fds (--socket-fds SplitFD transport for vsock).
  // Guest aarch64-linux waypipe is passed on the command line as well.
  NSDictionary *desktopCs = profile.containerSettings ?: @{};
  if (WWNContainerBool(desktopCs, @"desktopSession")) {
    NSString *hostWaypipe = WWNWawonaFindBundledExecutable(@"waypipe-fds");
    if (hostWaypipe.length == 0) {
      hostWaypipe = WWNWawonaFindBundledExecutable(@"waypipe");
    }
    if (hostWaypipe.length > 0) {
      env[@"WWNP_WAYPIPE_BIN"] = hostWaypipe;
    }
    NSString *guestWaypipe = WWNWawonaFindBundledExecutable(@"waypipe-guest");
    if (guestWaypipe.length > 0) {
      env[@"WAWONA_WAYPIPE_GUEST"] = guestWaypipe;
      NSString *closurePath =
          [guestWaypipe stringByAppendingString:@".closure"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:closurePath]) {
        env[@"WAWONA_WAYPIPE_GUEST_CLOSURE"] = closurePath;
      }
    }
  }
  task.environment = env;

  // Capture the terminal's own stdout/stderr (the container's output flows
  // through the PTY, not here) and drain them so a full pipe can never stall
  // the terminal process.
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;
  stdoutPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *fh) {
    if (fh.availableData.length == 0) {
      fh.readabilityHandler = nil;
    }
  };
  stderrPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *fh) {
    if (fh.availableData.length == 0) {
      fh.readabilityHandler = nil;
    }
  };

  // Poll the marker files the backend writes: "ready" once the VM is booted
  // (stop showing "compiling backend"), "done" once the container process
  // exits (one-shot runs return the card to Disconnected). Cheap fixed poll
  // on /tmp; each marker posts exactly once.
  NSFileManager *fm = [NSFileManager defaultManager];
  dispatch_queue_t pollQueue = dispatch_queue_create(
      "com.aspauldingcode.wawona.container-markers", DISPATCH_QUEUE_SERIAL);
  dispatch_source_t pollTimer =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, pollQueue);
  __block BOOL readyPosted = NO;
  __block BOOL donePosted = NO;
  dispatch_source_set_timer(pollTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                            250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
  dispatch_source_set_event_handler(pollTimer, ^{
    if (!readyPosted && [fm fileExistsAtPath:readyFile]) {
      readyPosted = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"WWNContainerBackendDidBecomeReadyNotification"
                          object:nil
                        userInfo:@{@"machineId" : machineId}];
      });
    }
    if (!donePosted && [fm fileExistsAtPath:doneFile]) {
      donePosted = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"WWNContainerBackendDidStopNotification"
                          object:nil
                        userInfo:@{@"machineId" : machineId}];
      });
    }
  });
  dispatch_resume(pollTimer);
  @synchronized(self.pollTimersByMachineId) {
    self.pollTimersByMachineId[machineId] = pollTimer;
  }

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
      [strongSelf cleanupMarkersForMachineId:machineId];
      [[NSNotificationCenter defaultCenter]
          postNotificationName:@"WWNContainerBackendDidStopNotification"
                        object:nil
                      userInfo:@{@"machineId" : machineId}];
    });
  };

  // Same sizing/prep the bundled native clients get, so the terminal window
  // lands at the compositor's current output size.
  [bridge prepareOutputSizeForNativeClientLaunchWithClientId:@"weston-terminal"];

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    [self cleanupMarkersForMachineId:machineId];
    if (error) {
      *error = launchError
                   ?: [NSError errorWithDomain:@"WWNContainerRunner"
                                          code:3
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Failed to start container terminal."
                                      }];
    }
    return NO;
  }

  [bridge pumpHostCompositorEvents];
  [bridge scheduleFollowUpHostCompositorPumps:4 interval:0.05];

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
  [self cleanupMarkersForMachineId:machineId];
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
  NSArray<NSString *> *machineIds = nil;
  @synchronized(self.pollTimersByMachineId) {
    machineIds = self.pollTimersByMachineId.allKeys;
    [self.pollTimersByMachineId removeAllObjects];
  }
  for (NSString *machineId in machineIds) {
    [self cleanupMarkersForMachineId:machineId];
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
