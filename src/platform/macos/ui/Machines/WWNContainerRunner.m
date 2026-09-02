#import "WWNContainerRunner.h"

#import "WWNVirtualMachineRunner.h"
#import "WWNCompositorBridge.h"
#import "WWNPlatformCallbacks.h"
#import "WWNMachineProfileStore.h"
#import "../Settings/WWNPreferencesManager.h"
#import "../../../../util/WWNLog.h"

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

/// Desktop session (vsock + waypipe → Wawona compositor) is the product default
/// for container machines. Absent key → YES so older profiles still bridge.
static BOOL WWNContainerWantsDesktopSession(NSDictionary *dict) {
  if (dict[@"desktopSession"] == nil) {
    return YES;
  }
  return WWNContainerBool(dict, @"desktopSession");
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
  // Dev-only signal: product recipes must use prebaked images. A custom
  // profile may still nix-build in-guest; never treat that as the default UX.
  if ([command rangeOfString:@"nix shell"].location != NSNotFound ||
      [command rangeOfString:@"nix build"].location != NSNotFound ||
      [command rangeOfString:@"nixos/nix"].location != NSNotFound) {
    WWNLog("CONTAINER",
           @"WARNING: unbaked recipe entryCommand still uses nix "
           @"(machine=%@). Prefer wawona-container-desktop + plain entry.",
           profile.machineId ?: @"?");
  }

  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  // Prefer the bundled CLI by absolute path so Apple's /usr/local/bin/container
  // (different flags) cannot win when PATH is polluted.
  NSString *containerBin = WWNWawonaFindBundledExecutable(@"container");
  if (containerBin.length > 0) {
    [parts addObject:WWNContainerShellQuote(containerBin)];
    [parts addObject:@"run"];
    [parts addObject:@"--rm"];
  } else {
    [parts addObject:@"container run --rm"];
  }

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
  if (WWNContainerWantsDesktopSession(cs)) {
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
  if (archive.length == 0 &&
      [ref rangeOfString:@"wawona-container-desktop"].location != NSNotFound) {
    // Prefer a local `container import` layout so Start never hits Docker Hub
    // for the prebaked desktop image (short refs resolve to library/…).
    NSString *root = NSProcessInfo.processInfo.environment[@"WWN_OCI_ROOT"];
    if (root.length == 0) {
      root = [NSHomeDirectory()
          stringByAppendingPathComponent:@".local/share/wwn-oci"];
    }
    NSString *imagesDir = [root stringByAppendingPathComponent:@"images"];
    for (NSString *name in [[NSFileManager defaultManager]
             contentsOfDirectoryAtPath:imagesDir
                                 error:nil]) {
      if (![name.pathExtension isEqualToString:@"json"]) {
        continue;
      }
      NSData *data = [NSData
          dataWithContentsOfFile:[imagesDir stringByAppendingPathComponent:name]];
      id json = data.length
                    ? [NSJSONSerialization JSONObjectWithData:data
                                                      options:0
                                                        error:nil]
                    : nil;
      if (![json isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSString *cref = json[@"reference"] ?: json[@"canonical"];
      if (![cref isKindOfClass:[NSString class]] ||
          [cref rangeOfString:@"wawona-container-desktop"].location ==
              NSNotFound) {
        continue;
      }
      NSString *digest = json[@"manifest_digest"];
      if (![digest isKindOfClass:[NSString class]] ||
          ![digest hasPrefix:@"sha256:"] || digest.length <= 7) {
        continue;
      }
      NSString *layout = [[root stringByAppendingPathComponent:@"oci-layout"]
          stringByAppendingPathComponent:[digest substringFromIndex:7]];
      if ([[NSFileManager defaultManager]
              fileExistsAtPath:[layout stringByAppendingPathComponent:
                                           @"index.json"]]) {
        archive = layout;
        break;
      }
    }
  }
  if (archive.length > 0) {
    [parts addObject:[NSString
                         stringWithFormat:@"--image-archive %@",
                                          WWNContainerShellQuote(archive)]];
  }

  [parts addObject:WWNContainerShellQuote(ref)];
  // Multi-word entry commands must not be a single guest argv0. End option
  // parsing with `--` (stripped in wwn-containerd) then `/bin/sh -c`.
  [parts addObject:@"--"];
  [parts addObject:@"/bin/sh"];
  [parts addObject:@"-c"];
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
  NSDictionary *cs = profile.containerSettings ?: @{};
  BOOL desktopSession = WWNContainerWantsDesktopSession(cs);

  NSString *shellScript =
      WWNWawonaFindBundledExecutable(@"wawona-container-shell");
  if (shellScript.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNContainerRunner"
                     code:4
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Bundled wawona-container-shell not found in the app "
                       @"bundle."
                 }];
    }
    return NO;
  }

  // Non-desktop: interactive shell in weston-terminal (PTY + ANSI). Desktop
  // session: NSTask the container wrapper directly. weston-terminal is a
  // Wayland client that can tear down (cairo) before the container is ready,
  // which marked Machines Start as Error even when the OCI run was fine.
  NSString *terminal = nil;
  if (!desktopSession) {
    terminal = WWNWawonaFindBundledExecutable(@"weston-terminal");
    if (terminal.length == 0) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"WWNContainerRunner"
                       code:4
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"Bundled weston-terminal not found in the app bundle."
                   }];
      }
      return NO;
    }
  }

  NSString *readyFile = [self markerFilePathForMachineId:machineId
                                                   kind:@"ready"];
  NSString *doneFile = [self markerFilePathForMachineId:machineId kind:@"done"];
  [[NSFileManager defaultManager] removeItemAtPath:readyFile error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:doneFile error:nil];

  NSTask *task = [[NSTask alloc] init];
  if (desktopSession) {
    task.executableURL = [NSURL fileURLWithPath:shellScript];
    task.arguments = @[];
  } else {
    task.executableURL = [NSURL fileURLWithPath:terminal];
    task.arguments = @[];
  }

  NSMutableDictionary<NSString *, NSString *> *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  NSString *runtimeDir =
      [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  if (!env[@"WAWONA_RUNTIME"]) {
    env[@"WAWONA_RUNTIME"] = runtimeDir;
  }
  env[@"WAWONA_CONTAINER_BACKEND"] = @"containerization";

  // Host waypipe-fds needs a live compositor socket. Prefer the bridge path
  // when it exists on disk; otherwise fall back to WAWONA_RUNTIME (Machines
  // group sockets can be empty before Focus).
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  NSString *socketName = [bridge socketName];
  NSString *socketPath = [bridge socketPath];
  NSFileManager *fmProbe = [NSFileManager defaultManager];
  BOOL bridgeSocketLive =
      (socketPath.length > 0 && [fmProbe fileExistsAtPath:socketPath]);
  if (!bridgeSocketLive) {
    NSString *fallbackSocket =
        [runtimeDir stringByAppendingPathComponent:@"wayland-0"];
    if ([fmProbe fileExistsAtPath:fallbackSocket]) {
      socketPath = fallbackSocket;
      socketName = @"wayland-0";
      bridgeSocketLive = YES;
    }
  }
  if (socketName.length > 0) {
    env[@"WAYLAND_DISPLAY"] = socketName;
  } else if (!env[@"WAYLAND_DISPLAY"]) {
    env[@"WAYLAND_DISPLAY"] = @"wayland-0";
  }
  if (socketPath.length > 0) {
    env[@"XDG_RUNTIME_DIR"] = [socketPath stringByDeletingLastPathComponent];
  } else {
    env[@"XDG_RUNTIME_DIR"] = runtimeDir;
  }

  if (!desktopSession) {
    env[@"SHELL"] = shellScript;
  }
  env[@"WAWONA_CONTAINER_CMD"] = command;
  env[@"WAWONA_CONTAINER_READY_FILE"] = readyFile;
  env[@"WAWONA_CONTAINER_DONE_FILE"] = doneFile;

  NSString *resourcesBin =
      [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"bin"];
  if (resourcesBin.length > 0) {
    NSString *existingPath =
        env[@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
    env[@"PATH"] =
        [NSString stringWithFormat:@"%@:%@", resourcesBin, existingPath];
  }

  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  NSString *imageStore = [[NSUserDefaults standardUserDefaults]
      stringForKey:kWWNPrefsMachineContainerImageStore];
  if (imageStore.length > 0) {
    env[@"WWN_OCI_ROOT"] = [imageStore stringByExpandingTildeInPath];
  }
  if (prefs.containerKernelPath.length > 0) {
    env[@"WAWONA_VM_KERNEL"] =
        [prefs.containerKernelPath stringByExpandingTildeInPath];
  }
  if (prefs.containerInitfsPath.length > 0) {
    env[@"WAWONA_VM_INITFS"] =
        [prefs.containerInitfsPath stringByExpandingTildeInPath];
  }

  if (desktopSession) {
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
      NSString *guestRoot =
          [[guestWaypipe stringByDeletingLastPathComponent]
              stringByAppendingPathComponent:@"waypipe-guest-root"];
      NSString *guestRootExec =
          [guestRoot stringByAppendingPathComponent:@"bin/waypipe"];
      if ([fmProbe isExecutableFileAtPath:guestRootExec]) {
        env[@"WAWONA_WAYPIPE_GUEST_ROOT"] = guestRoot;
      }
      NSString *closurePath =
          [guestWaypipe stringByAppendingString:@".closure"];
      if ([fmProbe fileExistsAtPath:closurePath]) {
        env[@"WAWONA_WAYPIPE_GUEST_CLOSURE"] = closurePath;
      }
    }
    // GPU/dmabuf is default for container waypipe. Disable GPU (profile)
    // opts into SHM via wwn-containerd's WAWONA_WAYPIPE_NO_GPU. Never inherit
    // a stale WAWONA_WAYPIPE_NO_GPU from the process environment (NSTask
    // copies NSProcessInfo.environment), or OpenGL/Vulkan clients stay on
    // SHM and fail (Ghostty: unable to acquire an OpenGL context).
    [env removeObjectForKey:@"WAWONA_WAYPIPE_NO_GPU"];
    BOOL disableGpu =
        [WWNMachineProfileStore resolvedWaypipeDisableGpuForProfile:profile];
    profile.waypipeDisableGpu = disableGpu;
    if (disableGpu) {
      env[@"WAWONA_WAYPIPE_NO_GPU"] = @"1";
      NSLog(@"[WWNContainerRunner] Disable GPU on for %@: SHM waypipe",
            machineId);
    } else {
      NSLog(@"[WWNContainerRunner] GPU waypipe for %@ (dmabuf/IOSurface)",
            machineId);
      const char *icd = getenv("VK_DRIVER_FILES");
      if (!icd || !icd[0]) {
        icd = getenv("VK_ICD_FILENAMES");
      }
      if (icd && icd[0]) {
        env[@"VK_DRIVER_FILES"] = @(icd);
        env[@"VK_ICD_FILENAMES"] = @(icd);
      } else {
        NSString *icdJson = [NSBundle.mainBundle.resourcePath
            stringByAppendingPathComponent:@"vulkan/icd.d/MoltenVK_icd.json"];
        NSString *kkJson = [NSBundle.mainBundle.resourcePath
            stringByAppendingPathComponent:@"vulkan/icd.d/kosmickrisp_icd.json"];
        if ([fmProbe fileExistsAtPath:kkJson]) {
          env[@"VK_DRIVER_FILES"] = kkJson;
          env[@"VK_ICD_FILENAMES"] = kkJson;
        } else if ([fmProbe fileExistsAtPath:icdJson]) {
          env[@"VK_DRIVER_FILES"] = icdJson;
          env[@"VK_ICD_FILENAMES"] = icdJson;
        }
      }
    }
  }
  task.environment = env;
  NSLog(@"[WWNContainerRunner] launch machineId=%@ desktop=%d cmd=%@",
        machineId, desktopSession ? 1 : 0, command);

  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;
  stdoutPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *fh) {
    NSData *data = fh.availableData;
    if (data.length == 0) {
      fh.readabilityHandler = nil;
      return;
    }
    NSString *line =
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (line.length > 0) {
      NSLog(@"[WWNContainerRunner] stdout: %@", line);
    }
  };
  stderrPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *fh) {
    NSData *data = fh.availableData;
    if (data.length == 0) {
      fh.readabilityHandler = nil;
      return;
    }
    NSString *line =
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (line.length > 0) {
      NSLog(@"[WWNContainerRunner] stderr: %@", line);
    }
  };

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
    NSInteger status = finished.terminationStatus;
    dispatch_async(dispatch_get_main_queue(), ^{
      WWNContainerRunner *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      NSLog(@"[WWNContainerRunner] task exited machineId=%@ status=%ld",
            machineId, (long)status);
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

  if (!desktopSession) {
    [bridge prepareOutputSizeForNativeClientLaunchWithClientId:@"weston-terminal"];
  }

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    [self cleanupMarkersForMachineId:machineId];
    if (error) {
      *error = launchError
                   ?: [NSError errorWithDomain:@"WWNContainerRunner"
                                          code:3
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Failed to start container session."
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

/// Stage an OCI layout directory into Application Support so the guest can
/// mount it (virtiofs tag `oci-bundle`). Prefer imageArchivePath; else a
/// bundled Resources/oci/wawona-container-desktop layout.
- (nullable NSString *)stageOciBundleForProfile:(WWNMachineProfile *)profile
                                          error:(NSError *_Nullable *_Nullable)error {
  NSDictionary *cs = profile.containerSettings ?: @{};
  NSString *archive = cs[@"imageArchivePath"];
  if (![archive isKindOfClass:[NSString class]] || archive.length == 0) {
    archive = [[NSBundle mainBundle] pathForResource:@"wawona-container-desktop"
                                              ofType:nil
                                         inDirectory:@"oci"];
  }
  if (archive.length == 0) {
    // No local layout: guest still boots; in-guest crun waits for a shared
    // bundle. Surface a soft path via runtimeOverrides when present later.
    return nil;
  }
  NSString *index = [archive stringByAppendingPathComponent:@"index.json"];
  NSString *config = [archive stringByAppendingPathComponent:@"config.json"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:index] &&
      ![[NSFileManager defaultManager] fileExistsAtPath:config]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNContainerRunner"
                     code:20
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Container image archive at %@ is not an OCI layout "
                           @"(missing index.json / config.json).",
                           archive]
                 }];
    }
    return nil;
  }

  NSArray<NSURL *> *urls = [[NSFileManager defaultManager]
      URLsForDirectory:NSApplicationSupportDirectory
             inDomains:NSUserDomainMask];
  NSURL *base = urls.firstObject;
  if (!base) {
    return archive;
  }
  NSString *dest =
      [[[base URLByAppendingPathComponent:@"Wawona" isDirectory:YES]
          URLByAppendingPathComponent:@"oci-bundles"
                          isDirectory:YES]
          URLByAppendingPathComponent:profile.machineId.length > 0
                                         ? profile.machineId
                                         : @"default"
                         isDirectory:YES]
          .path;
  NSError *copyErr = nil;
  [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
  [[NSFileManager defaultManager] createDirectoryAtPath:[dest stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  if (![[NSFileManager defaultManager] copyItemAtPath:archive
                                               toPath:dest
                                                error:&copyErr]) {
    // Fall back to the source path (may already be app-local).
    (void)copyErr;
    return archive;
  }
  return dest;
}

- (BOOL)launchProfile:(WWNMachineProfile *)profile
                error:(NSError *_Nullable *_Nullable)error {
  // Container-in-VM on Apple mobile: boot the bundled NixOS guest (same engine
  // as virtual_machine); OCI execution runs inside the guest over virtiofs.
  NSError *stageErr = nil;
  NSString *bundlePath = [self stageOciBundleForProfile:profile error:&stageErr];
  if (stageErr && error) {
    *error = stageErr;
    return NO;
  }
  if (bundlePath.length > 0) {
    NSMutableDictionary *ro =
        [profile.runtimeOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
    ro[@"ociBundlePath"] = bundlePath;
    NSDictionary *cs = profile.containerSettings ?: @{};
    NSString *entry = cs[@"entryCommand"];
    if ([entry isKindOfClass:[NSString class]] && entry.length > 0) {
      ro[@"containerEntryCommand"] = entry;
    }
    profile.runtimeOverrides = ro;
  }
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
