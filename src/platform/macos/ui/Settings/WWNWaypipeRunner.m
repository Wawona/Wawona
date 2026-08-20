#import "WWNWaypipeRunner.h"
#import "WWNPreferencesManager.h"
#import "../../../../util/WWNLog.h"
#import "../../WWNPlatformCallbacks.h"
#import "../../WWNCompositorBridge.h"
#import "../../WWNSettings.h"
#if __has_include("../Machines/WWNMachineProfileStore.h")
#import "../Machines/WWNMachineProfileStore.h"
#import "../Machines/WWNMachineSessionBridge.h"
#endif
#import "../Machines/WWNPlatformCapabilities.h"
#if TARGET_OS_IPHONE
#import "../../platform/macos/WWNRootfsProvider.h"
#endif
#import <errno.h>
#import <stdlib.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <signal.h>
#import <unistd.h>
#import <string.h>
#import <math.h>
#import <os/log.h>
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <pwd.h>
#endif

extern volatile sig_atomic_t wwn_weston_compositor_shutdown_requested;

extern char **environ;

/* Weak: Apple mobile / macOS link wwn-wasm; missing → skip Runtime clients. */
extern int wawona_wasm_run(int argc, char **argv) __attribute__((weak_import));
extern int wawona_wasm_can_run(const char *path) __attribute__((weak_import));

static NSString *const kWWNClientIdWasm = @"wawona-wasm";
static NSString *const kWWNRuntimeWasmModulePath = @"wasmModulePath";

// Global for signal handler safety
volatile pid_t g_active_waypipe_pgid = 0;

// Internal waypipe entry point (statically linked from Rust)
extern int waypipe_main(int argc, char **argv);
extern int weston_simple_shm_main(int argc, char **argv);
#if TARGET_OS_IPHONE
extern void wwn_weston_client_log_init(void);
extern void wwn_mobile_clear_wayland_socket_fd(void);
extern void wwn_propagate_mobile_env(void);
extern void wwn_launch_host_client(char *const *argp, char *const *envp);
extern int foot_main(int argc, char **argv);
extern int simple_egl_main(int argc, char **argv) __attribute__((weak));
/* opengl_cube_main / vkcube_main: resolved via dlsym in WWNClientMainForId so
 * tvOS (no cube archives) does not get undefined symbols from &weak_import. */
#endif
extern int wwn_weston_is_compat_shim(void) __attribute__((weak));
extern int wwn_weston_terminal_is_compat_shim(void) __attribute__((weak));
extern int wwn_foot_is_compat_shim(void) __attribute__((weak));
extern int weston_compositor_main(int argc, char **argv) __attribute__((weak_import));
extern int niri_main(void) __attribute__((weak_import));
extern int weston_terminal_main(int argc, char **argv);
#if TARGET_OS_IPHONE
extern int flower_main(int argc, char **argv);
extern int clickdot_main(int argc, char **argv);
extern int smoke_main(int argc, char **argv);
extern int eventdemo_main(int argc, char **argv);
extern int resizor_main(int argc, char **argv);
extern int cliptest_main(int argc, char **argv);
extern int transformed_main(int argc, char **argv);
extern int stacking_main(int argc, char **argv);
extern int dnd_main(int argc, char **argv);
extern int image_main(int argc, char **argv);
extern int scaler_main(int argc, char **argv);
extern int editor_main(int argc, char **argv);
extern int constraints_main(int argc, char **argv);
#endif

/// Cube clients that render through the in-process iland virtual DRM and are
/// composited by WWNIlandPresenter, rather than launched as ordinary Wayland
/// clients. Keep in sync with the table in WWNIlandPresenter.m.
///
/// opengl-cube / vkcube are deliberately absent: they are Wayland clients
/// (winsys posts IOSurface dmabuf buffers), so routing them through the iland
/// KMS presenter waited for page flips that never came.
static BOOL WWNIsIlandGpuCubeClientId(NSString *clientId) {
  return [clientId isEqualToString:@"kmscube"] ||
         [clientId isEqualToString:@"gbm-es2-demo"];
}

/// Clients whose first frame requires a real GL or Vulkan driver.
static BOOL WWNIsGpuFamilyClientId(NSString *clientId) {
  return WWNIsIlandGpuCubeClientId(clientId) ||
         [clientId isEqualToString:@"opengl-cube"] ||
         [clientId isEqualToString:@"vkcube"] ||
         [clientId isEqualToString:@"weston-simple-egl"];
}

/// Why this GPU client cannot run here, or nil if it can. A GPU-capable
/// platform is not enough: `OpenGLDriver=none` / `VulkanDriver=none` is a
/// supported efficiency mode (docs/iland-graphics-stack.md), and a client
/// started under it can never get past its first EGL/Vulkan call. Refuse with a
/// reason instead, so the log points at the setting rather than at the driver.
static NSString *WWNGpuClientRefusalReason(NSString *clientId) {
  if (!WWNIsGpuFamilyClientId(clientId)) {
    return nil;
  }
  if (!WWNPlatformAllowsGpuStack()) {
    return @"platform has no GPU stack (tvOS/watchOS)";
  }
  WWNGraphicsDriverSelection selection =
      WWNSettings_ResolveGraphicsDriverSelection();
  if ([clientId isEqualToString:@"vkcube"]) {
    return selection.vulkanEnabled
               ? nil
               : @"Settings → Graphics → Vulkan driver is None";
  }
  return selection.openGLEnabled ? nil
                                 : @"Settings → Graphics → OpenGL driver is None";
}

/// Log module for bundled native clients. Do not use "WESTON" for non-Weston
/// clients. The startup log overlays these tags and misled users into thinking
/// Weston was launching kmscube/niri/foot/etc.
static const char *WWNBundledClientLogModule(NSString *clientId) {
  if (clientId.length == 0) {
    return "CLIENT";
  }
  if ([clientId hasPrefix:@"weston"]) {
    return "WESTON";
  }
  if ([clientId isEqualToString:@"kmscube"]) {
    return "KMSCUBE";
  }
  if ([clientId isEqualToString:@"gbm-es2-demo"]) {
    return "GBM_ES2_DEMO";
  }
  if ([clientId isEqualToString:@"opengl-cube"]) {
    return "OPENGL_CUBE";
  }
  if ([clientId isEqualToString:@"vkcube"]) {
    return "VKCUBE";
  }
  if ([clientId isEqualToString:@"niri"]) {
    return "NIRI";
  }
  if ([clientId isEqualToString:@"foot"]) {
    return "FOOT";
  }
  if ([clientId isEqualToString:@"fuzzel"]) {
    return "FUZZEL";
  }
  return "CLIENT";
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static NSString *WWNPreferredHostShellPath(void) {
  const char *override = getenv("WAWONA_SHELL");
  if (override && override[0] && access(override, X_OK) == 0) {
    return @(override);
  }
  struct passwd *pw = getpwuid(getuid());
  if (pw && pw->pw_shell && pw->pw_shell[0] &&
      access(pw->pw_shell, X_OK) == 0) {
    return @(pw->pw_shell);
  }
  const char *envShell = getenv("SHELL");
  if (envShell && envShell[0] && access(envShell, X_OK) == 0) {
    return @(envShell);
  }
  if (access("/bin/zsh", X_OK) == 0) {
    return @"/bin/zsh";
  }
  return @"/bin/sh";
}
#endif

#if !TARGET_OS_IPHONE
@interface WWNNativeClientRecord : NSObject
@property(nonatomic, copy) NSString *clientId;
@property(nonatomic, copy, nullable) NSString *machineId;
@property(nonatomic, strong) NSTask *task;
@end
@implementation WWNNativeClientRecord
@end
#endif

@interface WWNWaypipeRunner ()
@property(nonatomic, assign) pid_t currentPid;
#if !TARGET_OS_IPHONE
@property(nonatomic, strong) NSTask *currentTask;
#endif
@property(nonatomic, assign) BOOL running;
@property(nonatomic, assign) BOOL stopping;

@property(nonatomic, assign) BOOL westonSimpleSHMRunning;
@property(nonatomic, assign) BOOL westonRunning;
@property(nonatomic, assign) BOOL westonTerminalRunning;
@property(nonatomic, assign) BOOL footRunning;
#if TARGET_OS_IPHONE
// Count of concurrent in-process launches (not a singleton mutex).
@property(nonatomic, assign) NSInteger iosNativeClientInFlightCount;
@property(nonatomic, copy) NSString *activeIOSBundledClientId;
// Machines profile ids with an in-process client still running.
@property(nonatomic, strong) NSMutableSet<NSString *> *iosRunningMachineIds;
#endif
#if !TARGET_OS_IPHONE
// Multi-instance registry: every launched NSTask is one record. Machines
// bind via machineId so Stop only kills that copy.
@property(nonatomic, strong)
    NSMutableArray<WWNNativeClientRecord *> *nativeClientRecords;
@property(nonatomic, strong) NSTask *westonTask; // nested compositor (singleton OK)
@property(nonatomic, copy, nullable) NSString *westonMachineId;
#endif
#if TARGET_OS_IPHONE
@property(nonatomic, assign)
    int stderrReadFd; // Pipe read end for stderr capture
@property(nonatomic, assign)
    int stdoutReadFd; // Pipe read end for stdout capture
@property(nonatomic, assign) int savedStderr; // Saved original stderr fd
@property(nonatomic, assign) int savedStdout; // Saved original stdout fd
@property(nonatomic, strong) NSLock *fdLock;  // Protects fd close/access
#endif

- (void)_launchWestonTerminalWithMachineId:(NSString *)machineId;
- (void)_launchWestonSimpleSHMWithMachineId:(NSString *)machineId;
- (void)_launchFootWithMachineId:(NSString *)machineId;
@end

@implementation WWNWaypipeRunner

+ (instancetype)sharedRunner {
  static WWNWaypipeRunner *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (void)stopAllNativeClients {
  [self stopWaypipe];
#if TARGET_OS_IPHONE
  [self stopWestonSimpleSHM];
  [self stopWestonTerminal];
  [self stopWeston];
  [self stopFoot];
#else
  NSArray<WWNNativeClientRecord *> *snapshot =
      [self.nativeClientRecords copy] ?: @[];
  for (WWNNativeClientRecord *rec in snapshot) {
    if (rec.task.isRunning) {
      [rec.task terminate];
    }
  }
  [self.nativeClientRecords removeAllObjects];
  [self _refreshRunningFlagsFromRecords];
  if (self.westonTask.isRunning) {
    [self.westonTask terminate];
  }
  self.westonTask = nil;
  self.westonMachineId = nil;
  self.westonRunning = NO;
#endif
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _running = NO;
    _stopping = NO;
#if TARGET_OS_IPHONE
    _stderrReadFd = -1;
    _stdoutReadFd = -1;
    _savedStderr = -1;
    _savedStdout = -1;
    _fdLock = [[NSLock alloc] init];
    _iosNativeClientInFlightCount = 0;
    _iosRunningMachineIds = [NSMutableSet set];
#else
    _nativeClientRecords = [NSMutableArray array];
#endif
  }
  return self;
}

- (BOOL)isRunning {
  return self.running;
}

- (BOOL)isAnyNativeClientRunning {
#if TARGET_OS_IPHONE
  return self.westonRunning || self.westonTerminalRunning ||
         self.isWestonSimpleSHMRunning || self.footRunning ||
         self.iosNativeClientInFlightCount > 0;
#else
  if (self.westonTask.isRunning) {
    return YES;
  }
  for (WWNNativeClientRecord *rec in self.nativeClientRecords) {
    if (rec.task.isRunning) {
      return YES;
    }
  }
  return NO;
#endif
}

- (BOOL)isWestonSimpleSHMRunning {
  return self.westonSimpleSHMRunning;
}

#if !TARGET_OS_IPHONE
- (void)_refreshRunningFlagsFromRecords {
  BOOL shm = NO, term = NO, foot = NO, weston = self.westonTask.isRunning;
  for (WWNNativeClientRecord *rec in self.nativeClientRecords) {
    if (!rec.task.isRunning) {
      continue;
    }
    if ([rec.clientId isEqualToString:@"weston-simple-shm"]) {
      shm = YES;
    } else if ([rec.clientId isEqualToString:@"weston-terminal"]) {
      term = YES;
    } else if ([rec.clientId isEqualToString:@"foot"]) {
      foot = YES;
    } else if ([rec.clientId isEqualToString:@"weston"]) {
      weston = YES;
    }
  }
  self.westonSimpleSHMRunning = shm;
  self.westonTerminalRunning = term;
  self.footRunning = foot;
  self.westonRunning = weston;
}

- (void)_registerNativeTask:(NSTask *)task
                   clientId:(NSString *)clientId
                  machineId:(NSString *)machineId {
  if (!task || clientId.length == 0) {
    return;
  }
  WWNNativeClientRecord *rec = [[WWNNativeClientRecord alloc] init];
  rec.clientId = clientId;
  rec.machineId = machineId.length > 0 ? [machineId copy] : nil;
  rec.task = task;
  [self.nativeClientRecords addObject:rec];
  [self _refreshRunningFlagsFromRecords];
  [self _installNativeClientTerminationHandler:task kind:clientId];
}

- (WWNNativeClientRecord *)_recordForMachineId:(NSString *)machineId {
  if (machineId.length == 0) {
    return nil;
  }
  for (WWNNativeClientRecord *rec in self.nativeClientRecords) {
    if ([rec.machineId isEqualToString:machineId] && rec.task.isRunning) {
      return rec;
    }
  }
  return nil;
}

- (WWNNativeClientRecord *)_recordForTask:(NSTask *)task {
  for (WWNNativeClientRecord *rec in self.nativeClientRecords) {
    if (rec.task == task) {
      return rec;
    }
  }
  return nil;
}

- (NSUInteger)runningInstanceCountForClientId:(NSString *)clientId {
  if (clientId.length == 0) {
    return 0;
  }
  NSUInteger n = 0;
  for (WWNNativeClientRecord *rec in self.nativeClientRecords) {
    if ([rec.clientId isEqualToString:clientId] && rec.task.isRunning) {
      n++;
    }
  }
  if ([clientId isEqualToString:@"weston"] && self.westonTask.isRunning) {
    n++;
  }
  return n;
}

- (BOOL)isBundledClientRunningForMachineId:(NSString *)machineId {
  if ([self _recordForMachineId:machineId] != nil) {
    return YES;
  }
  return self.westonTask.isRunning &&
         machineId.length > 0 &&
         [self.westonMachineId isEqualToString:machineId];
}

- (void)stopBundledClientForMachineId:(NSString *)machineId {
  if (self.westonTask.isRunning && machineId.length > 0 &&
      [self.westonMachineId isEqualToString:machineId]) {
    [self.westonTask terminate];
    self.westonTask = nil;
    self.westonMachineId = nil;
    self.westonRunning = NO;
    return;
  }
  WWNNativeClientRecord *rec = [self _recordForMachineId:machineId];
  if (!rec) {
    return;
  }
  if (rec.task.isRunning) {
    [rec.task terminate];
  }
  [self.nativeClientRecords removeObject:rec];
  [self _refreshRunningFlagsFromRecords];
}

- (void)_terminateAllNativeTasksWithClientId:(NSString *)clientId {
  if (clientId.length == 0) {
    return;
  }
  NSMutableArray<WWNNativeClientRecord *> *dead = [NSMutableArray array];
  for (WWNNativeClientRecord *rec in self.nativeClientRecords) {
    if (![rec.clientId isEqualToString:clientId]) {
      continue;
    }
    if (rec.task.isRunning) {
      [rec.task terminate];
    }
    [dead addObject:rec];
  }
  [self.nativeClientRecords removeObjectsInArray:dead];
  [self _refreshRunningFlagsFromRecords];
}
#endif

#if TARGET_OS_IPHONE
- (NSUInteger)runningInstanceCountForClientId:(NSString *)clientId {
  (void)clientId;
  // iOS tracks aggregate in-flight count; per-id counts are not retained.
  return (NSUInteger)MAX(0, self.iosNativeClientInFlightCount);
}

- (BOOL)isBundledClientRunningForMachineId:(NSString *)machineId {
  if (machineId.length == 0) {
    return self.iosNativeClientInFlightCount > 0;
  }
  return [self.iosRunningMachineIds containsObject:machineId];
}

- (void)stopBundledClientForMachineId:(NSString *)machineId {
  if (machineId.length > 0) {
    [self.iosRunningMachineIds removeObject:machineId];
  }
  // In-process clients share one compositor view stack today. Stopping one
  // machine tears down views only when nothing else remains bound.
  if (self.iosRunningMachineIds.count == 0) {
    [self stopActiveIOSBundledClient];
  }
}
#endif

#if TARGET_OS_IPHONE
/// Thread-safe cleanup of all redirected file descriptors.
/// Uses fdLock to ensure only one caller (completion block or stopWaypipe)
/// can close the fds, preventing double-close crashes.
- (void)cleanupFileDescriptors {
  [self.fdLock lock];

  if (self.savedStderr >= 0) {
    dup2(self.savedStderr, STDERR_FILENO);
    close(self.savedStderr);
    self.savedStderr = -1;
  }
  if (self.savedStdout >= 0) {
    dup2(self.savedStdout, STDOUT_FILENO);
    close(self.savedStdout);
    self.savedStdout = -1;
  }
  if (self.stderrReadFd >= 0) {
    close(self.stderrReadFd);
    self.stderrReadFd = -1;
  }
  if (self.stdoutReadFd >= 0) {
    close(self.stdoutReadFd);
    self.stdoutReadFd = -1;
  }

  [self.fdLock unlock];
}
#endif

// MARK: - Binary Discovery

- (NSString *)findWaypipeBinary {
  return WWNWawonaFindBundledExecutable(@"waypipe");
}

- (NSString *)findWestonSimpleSHMBinary {
  return WWNWawonaFindBundledExecutable(@"weston-simple-shm");
}

- (NSString *)findSshpassBinary {
  return WWNWawonaFindBundledExecutable(@"sshpass");
}

// MARK: - Argument Building

- (NSArray<NSString *> *)buildWaypipeArguments:(WWNPreferencesManager *)prefs {
  NSMutableArray *args = [NSMutableArray array];
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];

  NSString * (^trimmed)(NSString *) = ^NSString *(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
      return @"";
    }
    return [value stringByTrimmingCharactersInSet:ws];
  };

  BOOL (^isNonEmpty)(NSString *) = ^BOOL(NSString *value) {
    return trimmed(value).length > 0;
  };

  NSInteger (^intValueOrDefault)(NSString *, NSInteger) =
      ^NSInteger(NSString *value, NSInteger fallback) {
        NSString *clean = trimmed(value);
        return clean.length > 0 ? clean.integerValue : fallback;
      };

  // SSH Destination
  NSString *sshTarget = nil;
  NSString *targetHost =
      prefs.waypipeSSHHost.length > 0 ? prefs.waypipeSSHHost : prefs.sshHost;
  NSString *targetUser =
      prefs.waypipeSSHUser.length > 0 ? prefs.waypipeSSHUser : prefs.sshUser;
  BOOL usingSSHMode = (prefs.waypipeSSHEnabled && targetHost.length > 0);
  NSString *remoteCommandHint = trimmed(prefs.waypipeRemoteCommand);
  BOOL isRemoteSwayLaunch =
      usingSSHMode &&
      [[remoteCommandHint lowercaseString] containsString:@"sway"];

  // 1. Waypipe Global Options (MUST come before 'ssh')
  NSString *compress = [[trimmed(prefs.waypipeCompress) lowercaseString] copy];
  if (compress.length == 0) {
    compress = @"lz4";
  }
  NSString *compressLevel = trimmed(prefs.waypipeCompressLevel);
  NSString *compressArg = compress;
  if (compressLevel.length > 0 && ![compress isEqualToString:@"none"]) {
    compressArg = [NSString stringWithFormat:@"%@=%@", compress, compressLevel];
  }
  BOOL shouldAddCompress = (compressArg.length > 0);
#if TARGET_OS_IPHONE
  // iOS libssh2 SSH path currently brings up remote waypipe server with default
  // compression. Forcing local "--compress none" causes header mismatch.
  if (usingSSHMode && [compress isEqualToString:@"none"]) {
    shouldAddCompress = NO;
  }
#endif
  if (shouldAddCompress) {
    [args addObject:@"--compress"];
    [args addObject:compressArg];
  }

  if (prefs.waypipeDebug) {
    [args addObject:@"--debug"];
  }
  // wlroots/sway over waypipe can produce blank/broken windows on the
  // GPU/IOSurface fast path. Default to CPU transport for remote sway unless
  // the user already chose no-gpu explicitly.
  // p15: waypipe's GPU (dmabuf/Vulkan) transport needs a working Vulkan ICD.
  // main.m sets VK_DRIVER_FILES when a bundled ICD (MoltenVK/KosmicKrisp) was
  // resolved; if it's absent there is no ICD, so force CPU/SHM transport
  // (--no-gpu) to avoid empty-IOSurface / failed-import frames.
  BOOL haveVulkanICD = (getenv("VK_DRIVER_FILES") != NULL);
  BOOL forceNoGpu = prefs.waypipeNoGpu || isRemoteSwayLaunch || !haveVulkanICD;
  if (forceNoGpu) {
    [args addObject:@"--no-gpu"];
    if (isRemoteSwayLaunch && !prefs.waypipeNoGpu) {
      WWNLog("WAYPIPE",
             @"Auto-enabling --no-gpu for remote sway launch to avoid empty "
             @"IOSurface frames");
    }
    if (!haveVulkanICD && !prefs.waypipeNoGpu && !isRemoteSwayLaunch) {
      WWNLog("WAYPIPE",
             @"No Vulkan ICD (VK_DRIVER_FILES unset); forcing --no-gpu SHM "
             @"transport");
    }
  }
#if TARGET_OS_IPHONE
  // iOS App Store compliance: ALWAYS force --oneshot in SSH mode.
  // The static libssh2 code path (oneshot) handles SSH in-process;
  // without it waypipe tries to exec an external "ssh" binary which
  // is forbidden on iOS.  The user toggle still works for non-SSH
  // (local) usage.
  if (prefs.waypipeOneshot || usingSSHMode) {
    [args addObject:@"--oneshot"];
  }
#else
  if (prefs.waypipeOneshot) {
    [args addObject:@"--oneshot"];
  }
#endif
  if (prefs.waypipeUnlinkSocket) {
    [args addObject:@"--unlink-socket"];
  }
  if (prefs.waypipeLoginShell) {
    [args addObject:@"--login-shell"];
  }
  if (prefs.waypipeVsock) {
    [args addObject:@"--vsock"];
  }
  if (prefs.waypipeXwls) {
    [args addObject:@"--xwls"];
  }

  NSInteger threadCount = intValueOrDefault(prefs.waypipeThreads, 0);
  if (threadCount >= 0) {
    [args addObject:@"--threads"];
    [args addObject:[NSString stringWithFormat:@"%ld", (long)threadCount]];
  }

  NSString *titlePrefix = trimmed(prefs.waypipeTitlePrefix);
  if (titlePrefix.length > 0) {
    [args addObject:@"--title-prefix"];
    [args addObject:titlePrefix];
  }

  NSString *secCtx = trimmed(prefs.waypipeSecCtx);
  if (secCtx.length > 0) {
    [args addObject:@"--secctx"];
    [args addObject:secCtx];
  }

  NSString *videoCodec = [[trimmed(prefs.waypipeVideo) lowercaseString] copy];
  if (videoCodec.length == 0) {
    videoCodec = @"none";
  }
  NSMutableArray<NSString *> *videoParts = [NSMutableArray array];
  [videoParts addObject:videoCodec];
  if (![videoCodec isEqualToString:@"none"]) {
    NSString *enc =
        [[trimmed(prefs.waypipeVideoEncoding) lowercaseString] copy];
    NSString *dec =
        [[trimmed(prefs.waypipeVideoDecoding) lowercaseString] copy];
    if (enc.length > 0) {
      [videoParts addObject:enc];
    }
    if (dec.length > 0) {
      [videoParts addObject:dec];
    }

    NSString *bpf = trimmed(prefs.waypipeVideoBpf);
    if (bpf.length > 0 && bpf.doubleValue > 0) {
      [videoParts addObject:[NSString stringWithFormat:@"bpf=%@", bpf]];
    }
  }
  if (videoParts.count > 0) {
    [args addObject:@"--video"];
    [args addObject:[videoParts componentsJoinedByString:@","]];
  }

#if !TARGET_OS_IPHONE
  NSString *sshBinary = trimmed(prefs.waypipeSSHBinary);
  if (sshBinary.length > 0 && ![sshBinary isEqualToString:@"ssh"]) {
    [args addObject:@"--ssh-bin"];
    [args addObject:sshBinary];
  }
#endif

#if TARGET_OS_IPHONE
  // iOS sandbox paths are very long (~85 chars for XDG_RUNTIME_DIR).
  // waypipe appends random suffixes to the socket prefix, easily exceeding
  // the Unix socket SUN_LEN limit of 104 bytes.
  // Use a compact path for the socket prefix.
  if (!prefs.waypipeVsock) {
#if TARGET_OS_SIMULATOR
    NSString *tmpDir = @"/tmp";
#else
    NSString *tmpDir = NSTemporaryDirectory();
    if (!tmpDir)
      tmpDir = @"/tmp";
#endif
    NSString *socketPrefix = [tmpDir stringByAppendingPathComponent:@"wp"];
    [args addObject:@"-s"];
    [args addObject:socketPrefix];
  }

#endif

  // In ssh mode, forcing --display to "wayland-0" makes the remote
  // waypipe-server try to bind an existing compositor socket and fail
  // with EADDRINUSE. Let waypipe choose its remote display by default.
  if (!usingSSHMode) {
    NSString *display = trimmed(prefs.waypipeDisplay);
    if (display.length > 0) {
      [args addObject:@"--display"];
      [args addObject:display];
    }
  }

  if (usingSSHMode) {
    // 2. SSH Subcommand (Only if we have a target)
    [args addObject:@"ssh"];

#if !TARGET_OS_IPHONE
    // iOS uses libssh2 in-process (not openssh), so -F is meaningless and
    // can confuse the SSH argument parser in the libssh2 bridge code.
    if (!prefs.waypipeUseSSHConfig) {
      [args addObject:@"-F"];
      [args addObject:@"/dev/null"];
    }
#endif

    NSInteger sshPort = [prefs sshPort];
    if (sshPort > 0 && sshPort <= 65535) {
      [args addObject:@"-p"];
      [args addObject:[NSString stringWithFormat:@"%ld", (long)sshPort]];
    }

    // SSH Safety options
    [args addObject:@"-o"];
    [args addObject:@"StrictHostKeyChecking=accept-new"];
    [args addObject:@"-o"];
    [args addObject:@"BatchMode=no"];

    if (prefs.waypipeSSHAuthMethod == 1 &&
        isNonEmpty(prefs.waypipeSSHKeyPath)) {
      [args addObject:@"-i"];
      [args addObject:trimmed(prefs.waypipeSSHKeyPath)];
    }

    if (targetUser.length > 0) {
      sshTarget = [NSString stringWithFormat:@"%@@%@", targetUser, targetHost];
    } else {
      sshTarget = targetHost;
    }
    [args addObject:sshTarget];
  }

  // 3. Remote command for ssh mode
  NSString *remoteCommand = trimmed(prefs.waypipeRemoteCommand);
  if (prefs.waypipeLoginShell && remoteCommand.length == 0) {
    // waypipe server will open a login shell when no command is provided
    // and --login-shell is set.
    return args;
  }
  if (remoteCommand.length > 0) {
    if (isRemoteSwayLaunch) {
      NSString *lower = [remoteCommand lowercaseString];
      BOOL hasRenderer = [lower containsString:@"wlr_renderer="];
      BOOL hasNoHwCursor = [lower containsString:@"wlr_no_hardware_cursors="];
      if (!hasRenderer || !hasNoHwCursor) {
        NSMutableArray<NSString *> *prefix = [NSMutableArray array];
        if (!hasRenderer) {
          [prefix addObject:@"WLR_RENDERER=pixman"];
        }
        if (!hasNoHwCursor) {
          [prefix addObject:@"WLR_NO_HARDWARE_CURSORS=1"];
        }
        NSString *joined = [prefix componentsJoinedByString:@" "];
        // Prefix with `env` so the assignments run through a real executable.
        // A bare `VAR=val cmd` prefix is only honored when a shell interprets
        // it; if waypipe exec()s the command directly the first token is taken
        // as the program name and fails with "No such file or directory"
        // (issue #54). `env` is always a valid argv[0], applies the
        // assignments, then execs the command in both shell and direct paths.
        remoteCommand =
            [NSString stringWithFormat:@"env %@ %@", joined, remoteCommand];
        WWNLog("WAYPIPE",
               @"Applied remote sway software-render fallback env via env(1): %@",
               joined);
      }
    }
    // Pass the remote command as a raw argv token.
    // Quoting here adds literal quote characters and can break execution
    // for commands like `sway` in SSH mode.
    [args addObject:remoteCommand];
  } else if (prefs.waypipeSSHEnabled) {
    [args addObject:@"weston-simple-shm"]; // Default remote command
  }

  return args;
}

- (NSString *)generateWaypipePreviewString:(WWNPreferencesManager *)prefs {
  NSString *bin = [self findWaypipeBinary] ?: @"waypipe";
  NSArray *args = [self buildWaypipeArguments:prefs];

  NSString *cmd = [NSString
      stringWithFormat:@"%@ %@", bin, [args componentsJoinedByString:@" "]];

  NSString *targetPass = prefs.waypipeSSHPassword.length > 0
                             ? prefs.waypipeSSHPassword
                             : prefs.sshPassword;

  if (prefs.waypipeSSHAuthMethod == 0 && targetPass.length > 0) {
    NSString *sshpass = [self findSshpassBinary];
    if (sshpass) {
      cmd = [NSString stringWithFormat:@"SSHPASS=**** %@ -e %@",
                                       [sshpass lastPathComponent], cmd];
    }
  }

  return cmd;
}

// MARK: - Pre-flight Validation

- (NSString *)validatePreflightForPrefs:(WWNPreferencesManager *)prefs {
  // 1. Check if already running
  if (self.running) {
    return @"Waypipe is already running. Stop it first.";
  }

  // 2. Check Wayland socket exists
  NSString *display = prefs.waypipeDisplay;
  if (!display || display.length == 0) {
    const char *envDisplay = getenv("WAYLAND_DISPLAY");
    if (envDisplay) {
      display = [NSString stringWithUTF8String:envDisplay];
    } else {
      display = @"wayland-0";
    }
  }

#if TARGET_OS_IPHONE
  NSString *socketDir = prefs.waylandSocketDir;
  if (!socketDir || socketDir.length == 0) {
    const char *envDir = getenv("XDG_RUNTIME_DIR");
    if (envDir) {
      socketDir = [NSString stringWithUTF8String:envDir];
    }
  }
  if (!socketDir || socketDir.length == 0) {
    return @"XDG_RUNTIME_DIR is not set. The compositor may not be running.";
  }

  NSString *socketPath = [socketDir stringByAppendingPathComponent:display];
  if (![[NSFileManager defaultManager] fileExistsAtPath:socketPath]) {
    return [NSString
        stringWithFormat:
            @"Wayland socket not found at: %@\n\nThe compositor may not be "
            @"running, or the display name is incorrect.",
            socketPath];
  }
#else
  NSMutableArray<NSString *> *candidateDirs = [NSMutableArray array];
  const char *envDir = getenv("XDG_RUNTIME_DIR");
  if (envDir) {
    [candidateDirs addObject:[NSString stringWithUTF8String:envDir]];
  }
  if (prefs.waylandSocketDir.length > 0) {
    [candidateDirs addObject:prefs.waylandSocketDir];
  }
  [candidateDirs
      addObject:[NSString stringWithFormat:@"/tmp/wawona-%d", getuid()]];

  NSMutableOrderedSet<NSString *> *uniqueDirs =
      [NSMutableOrderedSet orderedSetWithArray:candidateDirs];
  BOOL socketFound = NO;
  NSString *firstChecked = nil;

  for (NSString *dir in uniqueDirs) {
    if (dir.length == 0) {
      continue;
    }
    NSString *candidatePath = [dir stringByAppendingPathComponent:display];
    if (!firstChecked) {
      firstChecked = candidatePath;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidatePath]) {
      socketFound = YES;
      break;
    }
  }

  if (!socketFound) {
    NSString *fallbackPath =
        firstChecked ?: [@"/tmp" stringByAppendingPathComponent:display];
    return [NSString
        stringWithFormat:
            @"Wayland socket not found at: %@\n\nThe compositor may not be "
            @"running, or the display name is incorrect.",
            fallbackPath];
  }
#endif

  // 3. Check SSH settings are configured (when SSH is enabled)
  if (prefs.waypipeSSHEnabled) {
    NSString *targetHost =
        prefs.waypipeSSHHost.length > 0 ? prefs.waypipeSSHHost : prefs.sshHost;
    if (!targetHost || targetHost.length == 0) {
      return @"SSH host is not configured. Set it in the SSH section or "
             @"Waypipe SSH settings.";
    }

    NSString *targetPass = prefs.waypipeSSHPassword.length > 0
                               ? prefs.waypipeSSHPassword
                               : prefs.sshPassword;
    NSInteger authMethod = prefs.waypipeSSHAuthMethod;
    if (authMethod == 0 && (!targetPass || targetPass.length == 0)) {
      return @"SSH password is not configured. Set it in SSH settings or "
             @"Waypipe SSH password field.\n\nWaypipe on iOS uses libssh2 "
             @"and requires a password for authentication.";
    }
  }

  return nil; // All checks passed
}

// MARK: - Launch

- (void)launchWaypipe:(WWNPreferencesManager *)prefs {
#if __has_include("../Machines/WWNMachineProfileStore.h")
  WWNMachineProfile *activeProfile =
      [WWNMachineProfileStore profileById:[WWNMachineProfileStore activeMachineId]];
  if (activeProfile &&
      [WWNMachineSessionBridge profileUsesNativeCompositorClient:activeProfile]) {
    WWNLog("WAYPIPE",
           @"Refusing waypipe launch: active machine '%@' is native and must use "
           @"the local compositor with a bundled client.",
           activeProfile.name ?: activeProfile.machineId);
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              @"Waypipe is for remote machines only. Connect a native machine "
              @"profile to launch a bundled client on the local compositor."];
    }
    return;
  }
#endif
#if !TARGET_OS_IPHONE
  NSString *waypipePath = [self findWaypipeBinary];
  if (!waypipePath) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              @"Waypipe binary not found. Please ensure it is installed."];
    }
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:@"Error: Waypipe binary not found.\n"
                         isError:YES];
    }
    return;
  }

  WWNLog("WAYPIPE", @"Using waypipe binary at: %@", waypipePath);
#endif

#if TARGET_OS_IPHONE && TARGET_OS_SIMULATOR
  WWNLog("WAYPIPE", @"NOTE: Running on iOS Simulator. Local networking may be "
                    @"restricted.");
#endif

  // Pre-flight validation
  NSString *preflightError = [self validatePreflightForPrefs:prefs];
  if (preflightError) {
    WWNLog("WAYPIPE", @"Pre-flight check failed: %@", preflightError);
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:[NSString
                                     stringWithFormat:@"[PRE-FLIGHT] %@\n",
                                                      preflightError]
                         isError:YES];
    }
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate runnerDidReceiveSSHError:preflightError];
    }
    return;
  }

#if TARGET_OS_IPHONE
  [self launchWaypipeInProcess:prefs];
  return;
#else
  // macOS NSTask Implementation
  NSArray *args = [self buildWaypipeArguments:prefs];
  NSTask *task = [[NSTask alloc] init];

  NSString *targetPass = prefs.waypipeSSHPassword.length > 0
                             ? prefs.waypipeSSHPassword
                             : prefs.sshPassword;
  BOOL useSshpass = (prefs.waypipeSSHAuthMethod == 0 && targetPass.length > 0);
  NSString *sshpassPath = useSshpass ? [self findSshpassBinary] : nil;
  NSString *askpassScriptPath = nil;

  if (sshpassPath) {
    task.executableURL = [NSURL fileURLWithPath:sshpassPath];
    NSMutableArray *sshpassArgs = [NSMutableArray arrayWithObject:@"-e"];
    [sshpassArgs addObject:waypipePath];
    [sshpassArgs addObjectsFromArray:args];
    task.arguments = sshpassArgs;
  } else {
    task.executableURL = [NSURL fileURLWithPath:waypipePath];
    task.arguments = args;
  }

  // Env
  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];

  // Waypipe needs to know where the socket IS, and it needs to be an absolute
  // path. We prioritize the environment because main.m sets it correctly.
  const char *envRuntime = getenv("XDG_RUNTIME_DIR");
  NSString *socketDirTask =
      (envRuntime) ? [NSString stringWithUTF8String:envRuntime] : nil;

  if (!socketDirTask || socketDirTask.length == 0) {
    socketDirTask = prefs.waylandSocketDir;
  }

  if (!socketDirTask || socketDirTask.length == 0) {
    socketDirTask = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
    WWNLog("WAYPIPE", @"waylandSocketDir was empty, using default: %@",
           socketDirTask);
  }

  const char *envDisplay = getenv("WAYLAND_DISPLAY");
  NSString *displayNameTask =
      (envDisplay) ? [NSString stringWithUTF8String:envDisplay] : nil;

  if (!displayNameTask || displayNameTask.length == 0) {
    displayNameTask = prefs.waypipeDisplay;
  }

  if (!displayNameTask || displayNameTask.length == 0) {
    displayNameTask = @"wayland-0";
    WWNLog("WAYPIPE", @"waypipeDisplay was empty, using default: %@",
           displayNameTask);
  }

#if !TARGET_OS_IPHONE
  NSString *configuredSocketPath =
      [socketDirTask stringByAppendingPathComponent:displayNameTask];
  if (![[NSFileManager defaultManager] fileExistsAtPath:configuredSocketPath]) {
    NSString *runtimeFallback =
        [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
    NSString *fallbackSocketPath =
        [runtimeFallback stringByAppendingPathComponent:displayNameTask];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fallbackSocketPath]) {
      WWNLog("WAYPIPE", @"Using compositor runtime fallback: %@",
             runtimeFallback);
      socketDirTask = runtimeFallback;
    }
  }
#endif

  WWNLog("WAYPIPE",
         @"Setting environment: XDG_RUNTIME_DIR=%@, "
         @"WAYLAND_DISPLAY=%@, XDG_CURRENT_DESKTOP=Wawona",
         socketDirTask, displayNameTask);

  env[@"XDG_RUNTIME_DIR"] = socketDirTask;
  env[@"WAYLAND_DISPLAY"] = displayNameTask;
  env[@"XDG_CURRENT_DESKTOP"] = @"Wawona";

  // Sanitize PATH to ensure /usr/bin is available for ssh
  NSString *currentPath = env[@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
  if (![currentPath containsString:@"/usr/bin"]) {
    currentPath = [@"/usr/bin:" stringByAppendingString:currentPath];
  }
  env[@"PATH"] = currentPath;

  if (useSshpass) {
    env[@"SSHPASS"] = targetPass;
  } else if (prefs.waypipeSSHAuthMethod == 0 && targetPass.length > 0) {
    // Password auth fallback without sshpass: force SSH_ASKPASS so ssh does
    // not require /dev/tty (non-interactive app launch context).
    NSString *scriptName =
        [NSString stringWithFormat:@"wawona-waypipe-askpass-%@.sh",
                                   [[NSUUID UUID] UUIDString]];
    askpassScriptPath =
        [NSTemporaryDirectory() stringByAppendingPathComponent:scriptName];
    NSString *script = @"#!/bin/sh\n"
                        "printf '%s\\n' \"$WAWONA_SSH_PASSWORD\"\n";
    NSError *scriptError = nil;
    BOOL wrote = [script writeToFile:askpassScriptPath
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&scriptError];
    if (wrote &&
        chmod([askpassScriptPath fileSystemRepresentation], 0700) == 0) {
      env[@"SSH_ASKPASS"] = askpassScriptPath;
      env[@"SSH_ASKPASS_REQUIRE"] = @"force";
      env[@"DISPLAY"] = env[@"DISPLAY"] ?: @"wawona-waypipe";
      env[@"WAWONA_SSH_PASSWORD"] = targetPass;
      WWNLog("WAYPIPE", @"Using temporary SSH_ASKPASS helper");
    } else {
      WWNLog("WAYPIPE", @"Failed to create SSH_ASKPASS helper: %@",
             scriptError.localizedDescription ?: @"unknown error");
      askpassScriptPath = nil;
    }
  }

  task.environment = env;
  if (askpassScriptPath.length > 0) {
    task.terminationHandler = ^(NSTask *finishedTask) {
      (void)finishedTask;
      [[NSFileManager defaultManager] removeItemAtPath:askpassScriptPath
                                                 error:nil];
    };
  }

  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  task.standardOutput = outPipe;
  task.standardError = errPipe;

  self.running = YES;

  outPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    if (d.length > 0) {
      NSString *s =
          [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
      [self parseOutput:s isError:NO];
    }
  };
  errPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    if (d.length > 0) {
      NSString *s =
          [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
      [self parseOutput:s isError:YES];
    }
  };

  NSError *err;
  if ([task launchAndReturnError:&err]) {
    self.currentPid = task.processIdentifier;
    self.currentTask = task;
    g_active_waypipe_pgid = self.currentPid;
    WWNLog("WAYPIPE", @"Waypipe launched via NSTask PID: %d", self.currentPid);
  } else {
    self.running = NO;
    if (askpassScriptPath.length > 0) {
      [[NSFileManager defaultManager] removeItemAtPath:askpassScriptPath
                                                 error:nil];
    }
    WWNLog("WAYPIPE", @"Launch failed: %@", err);
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:
              [NSString stringWithFormat:@"Failed to launch waypipe: %@\n",
                                         err.localizedDescription]
                         isError:YES];
    }
  }
#endif
}

// MARK: - Output Monitoring

- (void)monitorDescriptor:(int)fd isError:(BOOL)isError {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 ^{
                   char buffer[4096];
                   ssize_t count;
                   while ((count = read(fd, buffer, sizeof(buffer) - 1)) > 0) {
                     buffer[count] = 0;
                     NSString *s = [NSString stringWithUTF8String:buffer];
                     dispatch_async(dispatch_get_main_queue(), ^{
                       [self parseOutput:s isError:isError];
                     });
                   }
                   // Do NOT close(fd) here. The fd is owned by the launch/stop
                   // code paths which handle closing. Closing here races with
                   // the completion block and stopWaypipe, causing double-close
                   // crashes (EXC_BAD_ACCESS / EBADF).
                 });
}

- (void)parseOutput:(NSString *)text isError:(BOOL)isError {
  if (self.stopping)
    return;

  // Write to the saved (original) stderr to avoid feedback loop.
  // When stderr is redirected to a pipe, NSLog may write to the pipe
  // which causes the monitor thread to read it back, creating an infinite loop.
#if TARGET_OS_IPHONE
  [self.fdLock lock];
  int fd = self.savedStderr;
  [self.fdLock unlock];
  if (fd >= 0) {
    WWNLogFd(fd, "WAYPIPE", "[Waypipe %s] %s", isError ? "stderr" : "stdout",
             [text UTF8String]);
  } else {
    WWNLog("WAYPIPE", @"[Waypipe %@] %@", isError ? @"stderr" : @"stdout",
           text);
  }
#else
  WWNLog("WAYPIPE", @"[Waypipe %@] %@", isError ? @"stderr" : @"stdout", text);
#endif

  if ([self.delegate
          respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
    [self.delegate runnerDidReceiveOutput:text isError:isError];
  }

  if ([text containsString:@"password:"] ||
      [text containsString:@"Password:"]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHPasswordPrompt:)]) {
      [self.delegate runnerDidReceiveSSHPasswordPrompt:text];
    }
  } else if ([text containsString:@"Permission denied"] ||
             [text containsString:@"Host key verification failed"]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate runnerDidReceiveSSHError:text];
    }
  } else if ([text containsString:@"Password auth failed"] ||
             [text containsString:@"SSH auth failed"] ||
             [text containsString:@"libssh2 failed"]) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate runnerDidReceiveSSHError:text];
    }
  }
}

// MARK: - iOS In-Process Launch

#if TARGET_OS_IPHONE
- (void)launchWaypipeInProcess:(WWNPreferencesManager *)prefs {
  // Build arguments
  NSArray *args = [self buildWaypipeArguments:prefs];

  // App Store compliance / iOS sandbox safety:
  // Never allow paths that require spawning a local external ssh binary.
  BOOL hasSshBinOverride = [args containsObject:@"--ssh-bin"];
  if (hasSshBinOverride) {
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
      [self.delegate
          runnerDidReceiveOutput:
              @"[SAFETY] Blocked launch: iOS forbids external process exec. "
              @"--ssh-bin is not allowed in iOS mode.\n"
                         isError:YES];
    }
    if ([self.delegate
            respondsToSelector:@selector(runnerDidReceiveSSHError:)]) {
      [self.delegate
          runnerDidReceiveSSHError:
              @"Blocked unsafe iOS launch mode (external process execution)."];
    }
    self.running = NO;
    return;
  }

  NSMutableArray *fullArgs = [NSMutableArray arrayWithObject:@"waypipe"];
  [fullArgs addObjectsFromArray:args];

  // Convert to C arguments
  int argc = (int)fullArgs.count;
  char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
  for (int i = 0; i < argc; i++) {
    argv[i] = strdup([fullArgs[i] UTF8String]);
  }
  argv[argc] = NULL;

  // Resolve environment variables
  NSString *socketDir = prefs.waylandSocketDir;
  if (!socketDir || socketDir.length == 0) {
    const char *envDir = getenv("XDG_RUNTIME_DIR");
    if (envDir) {
      socketDir = [NSString stringWithUTF8String:envDir];
    } else {
      socketDir = NSTemporaryDirectory();
    }
  }

  NSString *display = prefs.waypipeDisplay;
  if (!display || display.length == 0) {
    const char *envDisplay = getenv("WAYLAND_DISPLAY");
    if (envDisplay) {
      display = [NSString stringWithUTF8String:envDisplay];
    } else {
      display = @"wayland-0";
    }
  }

  setenv("XDG_RUNTIME_DIR", [socketDir UTF8String], 1);
  setenv("WAYLAND_DISPLAY", [display UTF8String], 1);
  setenv("USER", "mobile", 1);

  NSString *password = prefs.waypipeSSHPassword.length > 0
                           ? prefs.waypipeSSHPassword
                           : prefs.sshPassword;
  if (password && password.length > 0) {
    setenv("WAYPIPE_SSH_PASSWORD", [password UTF8String], 1);
  }

  // Report configuration to delegate
  NSString *socketPath = [socketDir stringByAppendingPathComponent:display];
  NSString *configInfo = [NSString
      stringWithFormat:@"[CONFIG] XDG_RUNTIME_DIR = %@\n"
                       @"[CONFIG] WAYLAND_DISPLAY = %@\n"
                       @"[CONFIG] Socket path    = %@\n"
                       @"[CONFIG] SSH password   = %@\n"
                       @"[CONFIG] Arguments      = %@\n",
                       socketDir, display, socketPath,
                       (password.length > 0 ? @"(set)" : @"(not set)"),
                       [fullArgs componentsJoinedByString:@" "]];

  if ([self.delegate
          respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
    [self.delegate runnerDidReceiveOutput:configInfo isError:NO];
  }

  WWNLog("WAYPIPE", @"Launching statically linked Waypipe (args: %@)...",
         fullArgs);

  self.running = YES;
  self.stopping = NO;

  // Set up stderr/stdout capture BEFORE calling waypipe_main.
  // We redirect stderr/stdout to pipes so we can read the Rust output
  // and show it in the UI. We also save the original FDs so crash
  // diagnostics and our own logging still work.
  int stderrPipe[2] = {-1, -1};
  int stdoutPipe[2] = {-1, -1};

  if (pipe(stderrPipe) != 0) {
    WWNLog("WAYPIPE", @"WARNING: Failed to create stderr pipe: %s",
           strerror(errno));
  }
  if (pipe(stdoutPipe) != 0) {
    WWNLog("WAYPIPE", @"WARNING: Failed to create stdout pipe: %s",
           strerror(errno));
  }

  // Save original file descriptors so we can log to them directly
  int savedStderr = dup(STDERR_FILENO);
  int savedStdout = dup(STDOUT_FILENO);
  self.savedStderr = savedStderr;
  self.savedStdout = savedStdout;

  // Redirect stderr and stdout to our pipes
  if (stderrPipe[1] >= 0) {
    dup2(stderrPipe[1], STDERR_FILENO);
    close(stderrPipe[1]); // Close write end (stderr now writes to pipe)
    self.stderrReadFd = stderrPipe[0];
  }
  if (stdoutPipe[1] >= 0) {
    dup2(stdoutPipe[1], STDOUT_FILENO);
    close(stdoutPipe[1]); // Close write end (stdout now writes to pipe)
    self.stdoutReadFd = stdoutPipe[0];
  }

  // Start monitoring threads for the pipe read ends
  if (self.stderrReadFd >= 0) {
    [self monitorDescriptor:self.stderrReadFd isError:YES];
  }
  if (self.stdoutReadFd >= 0) {
    [self monitorDescriptor:self.stdoutReadFd isError:NO];
  }

  if ([self.delegate
          respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
    [self.delegate
        runnerDidReceiveOutput:@"[LAUNCH] Starting waypipe_main()...\n"
                       isError:NO];
  }

  // Run waypipe_main on a Utility-QoS background thread.
  // Using QOS_CLASS_UTILITY (not DEFAULT) avoids a priority inversion:
  // the UI thread dispatches at User-initiated QoS, waypipe's internal
  // Rust scoped threads run at Default QoS.  If we dispatched to DEFAULT,
  // GCD would promote this block → higher-QoS thread waiting on lower-QoS
  // Rust threads → hang risk.  Utility QoS is ≤ Default, so no inversion.
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    // Use WWNLogFd to saved stderr - NSLog writes to redirected stderr
    // which would go to the pipe and create a feedback loop
    if (savedStderr >= 0) {
      WWNLogFd(savedStderr, "WAYPIPE",
               "Starting execution via waypipe_main...");
    }

    // Set RUST_BACKTRACE for better diagnostics
    setenv("RUST_BACKTRACE", "1", 1);

    // Verify the function symbol is actually linked (not null)
    void *fn_addr = (void *)waypipe_main;
    if (fn_addr == NULL) {
      if (savedStderr >= 0) {
        WWNLogFd(savedStderr, "WAYPIPE",
                 "FATAL: waypipe_main symbol is NULL! "
                 "The Rust static library may not be linked correctly.");
      }
      [self cleanupFileDescriptors];
      for (int i = 0; i < argc; i++) {
        free(argv[i]);
      }
      free(argv);
      self.running = NO;
      return;
    }

    int result = waypipe_main(argc, argv);
    if (savedStderr >= 0) {
      WWNLogFd(savedStderr, "WAYPIPE", "Execution finished. Exit code: %d",
               result);
    }

    // Flush stderr/stdout so pipe readers get all data
    fflush(stderr);
    fflush(stdout);

    // Small delay to let pipe readers finish draining
    usleep(100000); // 100ms

    // Restore original fds and close pipe ends (thread-safe)
    [self cleanupFileDescriptors];

    // Cleanup C args
    for (int i = 0; i < argc; i++) {
      free(argv[i]);
    }
    free(argv);

    self.running = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *exitMsg = [NSString
          stringWithFormat:@"\n[EXIT] waypipe_main returned %d\n", result];

      if ([self.delegate
              respondsToSelector:@selector(runnerDidReceiveOutput:isError:)]) {
        [self.delegate runnerDidReceiveOutput:exitMsg isError:(result != 0)];
      }

      if ([self.delegate
              respondsToSelector:@selector(runnerDidFinishWithExitCode:)]) {
        [self.delegate runnerDidFinishWithExitCode:result];
      }
    });
  });
}
#endif

// MARK: - Stop

- (void)stopWaypipe {
  self.stopping = YES;

#if !TARGET_OS_IPHONE
  if (self.currentTask) {
    [self.currentTask terminate];
    self.currentTask = nil;
  }
#endif

  if (self.currentPid > 0) {
    kill(-self.currentPid, SIGTERM);
    pid_t pidToKill = self.currentPid;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          kill(-pidToKill, SIGKILL);
        });
    self.currentPid = 0;
    g_active_waypipe_pgid = 0;
  }

#if TARGET_OS_IPHONE
  // On iOS, waypipe runs in-process. We can't kill a thread, but we can
  // restore file descriptors to stop capturing output and signal cleanup.
  [self cleanupFileDescriptors];
#endif

  self.running = NO;
  self.stopping = NO;
}

/// Resolve the display backend for a bundled client: `wayland` (nested Wayland
/// client of Wawona) or `drm` (wwn-iland userspace DRM/KMS/GBM).
///
/// Clients that support both must never hardcode one. niri and weston each have
/// a real DRM backend, and running them nested when they could drive iland's
/// userspace KMS throws away the path iland exists to provide. `auto` keeps the
/// nested default because it needs no GPU stack, but the user's choice. Global
/// preference or per-machine override. Always wins where the platform allows.
static NSString *g_cliCompositorBackendOverride = nil;

void WWNSetCompositorBackendCLIOverride(NSString *backend) {
  g_cliCompositorBackendOverride = backend.length > 0 ? [backend copy] : nil;
}

NSString *WWNCompositorBackendCLIOverride(void) {
  return g_cliCompositorBackendOverride;
}

NSString *WWNResolveCompositorBackend(NSString *overrideValue) {
  NSString *choice = nil;
  if (overrideValue.length > 0) {
    choice = overrideValue;
  } else if (g_cliCompositorBackendOverride.length > 0) {
    choice = g_cliCompositorBackendOverride;
  } else {
    choice = [[WWNPreferencesManager sharedManager] compositorBackend];
  }

  if ([choice isEqualToString:@"drm"]) {
    // The DRM backend presents through iland; without the GL stack there is
    // nothing behind it, so fall back rather than launch a client that hangs.
    NSString *gl = [[WWNPreferencesManager sharedManager] openglDriver];
    if ([gl isEqualToString:@"none"]) {
      WWNLog("BACKEND",
             @"drm backend requested but OpenGLDriver=none; using wayland");
      return @"wayland";
    }
    return @"drm";
  }

  if ([choice isEqualToString:@"wayland"]) {
    return @"wayland";
  }

  return @"wayland"; // auto
}

#if TARGET_OS_IPHONE
/// Ensure writable XDG dirs for fuzzel locks/cache and point discovery at the
/// bundled Freedesktop catalog (share/applications + hicolor). Desktop entries
/// are packaged by applications-catalog.nix; do not re-seed them here (#78).
static void wwnEnsureFuzzelXdgEnv(void) {
  WWNEnsureFuzzelXdgEnv();
}

/// Env niri needs on Apple mobile (GLES via ANGLE EGL), honouring the
/// configured backend rather than assuming nested.
static void wwnConfigureNiriNestedEnv(void) {
  // niri names its DRM/KMS backend "tty" and its nested one "winit"/"nested".
  NSString *backend = WWNResolveCompositorBackend(nil);
  setenv("NIRI_BACKEND",
         [backend isEqualToString:@"drm"] ? "tty" : "nested", 1);
  NSString *kdl = WWNWawonaBundledSharePath(@"niri/default-config.kdl");
  if ([[NSFileManager defaultManager] fileExistsAtPath:kdl]) {
    setenv("NIRI_CONFIG", kdl.UTF8String, 1);
  }
  // smithay dlopen's libEGL.dylib at runtime. ANGLE ships in the app
  // Frameworks directory; without this path eglInitialize fails and niri panics
  // during nested-backend init. Mirrors macOS NSTask env and niri-smoke-macos.sh.
  NSString *frameworksDir = [[[NSBundle mainBundle] bundlePath]
      stringByAppendingPathComponent:@"Frameworks"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksDir]) {
    setenv("DYLD_LIBRARY_PATH", frameworksDir.UTF8String, 1);
  }
  const char *icd = getenv("VK_ICD_FILENAMES");
  if (!icd || !icd[0]) {
    icd = getenv("VK_DRIVER_FILES");
  }
  if (!icd || !icd[0]) {
    NSString *bundleRes = [[NSBundle mainBundle] resourcePath];
    NSString *icdJson = [bundleRes
        stringByAppendingPathComponent:@"vulkan/icd.d/MoltenVK_icd.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:icdJson]) {
      setenv("VK_ICD_FILENAMES", icdJson.UTF8String, 1);
      setenv("VK_DRIVER_FILES", icdJson.UTF8String, 1);
    }
  }
  wwnEnsureFuzzelXdgEnv();
}

typedef int (*WWNClientMainFn)(int, char **);

static WWNClientMainFn WWNClientMainForId(NSString *clientId) {
  static NSDictionary<NSString *, NSValue *> *map;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    map = @{
      @"weston-simple-shm" :
          [NSValue valueWithPointer:(void *)weston_simple_shm_main],
      @"weston" : [NSValue valueWithPointer:(void *)weston_compositor_main],
      @"weston-terminal" :
          [NSValue valueWithPointer:(void *)weston_terminal_main],
      @"foot" : [NSValue valueWithPointer:(void *)foot_main],
      @"weston-flower" : [NSValue valueWithPointer:(void *)flower_main],
      @"weston-clickdot" : [NSValue valueWithPointer:(void *)clickdot_main],
      @"weston-smoke" : [NSValue valueWithPointer:(void *)smoke_main],
      @"weston-eventdemo" : [NSValue valueWithPointer:(void *)eventdemo_main],
      @"weston-resizor" : [NSValue valueWithPointer:(void *)resizor_main],
      @"weston-cliptest" : [NSValue valueWithPointer:(void *)cliptest_main],
      @"weston-transformed" :
          [NSValue valueWithPointer:(void *)transformed_main],
      @"weston-stacking" : [NSValue valueWithPointer:(void *)stacking_main],
      @"weston-dnd" : [NSValue valueWithPointer:(void *)dnd_main],
      @"weston-image" : [NSValue valueWithPointer:(void *)image_main],
      @"weston-scaler" : [NSValue valueWithPointer:(void *)scaler_main],
      @"weston-editor" : [NSValue valueWithPointer:(void *)editor_main],
      @"weston-constraints" :
          [NSValue valueWithPointer:(void *)constraints_main],
      @"weston-simple-egl" :
          [NSValue valueWithPointer:(void *)simple_egl_main],
      /* Cubes: dlsym so targets without the archives (tvOS) still link. */
      @"opengl-cube" :
          [NSValue valueWithPointer:dlsym(RTLD_DEFAULT, "opengl_cube_main")],
      @"vkcube" : [NSValue valueWithPointer:dlsym(RTLD_DEFAULT, "vkcube_main")],
    };
  });
  NSValue *entry = map[clientId];
  /* Weakly-linked / dlsym entry points are NULL when their archive is absent;
   * treat that as "no such client" rather than calling through a null pointer. */
  return entry ? (WWNClientMainFn)[entry pointerValue] : NULL;
}

- (BOOL)wwnBeginIOSNativeClientLaunch:(NSString *)clientId {
  if (clientId.length == 0) {
    return NO;
  }
  // Multiple concurrent in-process clients are allowed (including two
  // weston-terminal instances). Each launch gets its own GCD worker; do not
  // serialize behind a singleton "in flight" mutex.
  self.iosNativeClientInFlightCount += 1;
  self.activeIOSBundledClientId = [clientId copy];
#if TARGET_OS_IPHONE
  wwn_weston_client_log_init();
  // Reset global in-process shutdown latch on every client launch.  Some
  // bundled clients consult this flag and will immediately exit if it remains
  // set from a prior stop/close action.
  wwn_weston_compositor_shutdown_requested = 0;
  wwn_ios_refresh_bundle_env();
  wwn_propagate_mobile_env();
  // Only clear inherited socket state for the first concurrent client. A
  // second launch must not tear down WAYLAND_SOCKET / FD wiring used by an
  // already-running in-process client.
  if (self.iosNativeClientInFlightCount == 1) {
    wwn_mobile_clear_wayland_socket_fd();
    unsetenv("WAYLAND_SOCKET");
  }
#endif
  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];
  // Every in-process client (toys, cubes, terminals, nested compositors) must
  // see the same sandbox FS: HOME + XDG_* under the writable rootfs. Terminal
  // / foot / niri / weston launchers already call this; apply here so the
  // generic *_main path cannot race ahead with unset WAWONA_ROOTFS.
  [WWNRootfsProvider applyShellEnvironment];
  [[WWNCompositorBridge sharedBridge]
      prepareOutputSizeForNativeClientLaunchWithClientId:clientId];
  return YES;
}

- (void)wwnEndIOSNativeClientLaunch {
  if (self.iosNativeClientInFlightCount > 0) {
    self.iosNativeClientInFlightCount -= 1;
  }
  if (self.iosNativeClientInFlightCount == 0) {
    self.activeIOSBundledClientId = nil;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"WWNNativeClientProcessDidTerminateNotification"
                      object:self];
  });
}

- (void)stopActiveIOSBundledClient {
  wwn_weston_compositor_shutdown_requested = 1;
  [[WWNCompositorBridge sharedBridge] tearDownActiveIOSCompositorViews];
  self.westonRunning = NO;
  self.westonTerminalRunning = NO;
  self.westonSimpleSHMRunning = NO;
  self.footRunning = NO;
  self.iosNativeClientInFlightCount = 0;
  self.activeIOSBundledClientId = nil;
  [self.iosRunningMachineIds removeAllObjects];
}
#endif

// MARK: - Generic bundled client launcher

- (void)launchBundledClientWithId:(NSString *)clientId {
  [self launchBundledClientWithId:clientId machineId:nil];
}

- (void)launchBundledClientWithId:(NSString *)clientId
                        machineId:(NSString *)machineId {
  if (clientId.length == 0)
    return;

  if ([clientId isEqualToString:kWWNClientIdWasm]) {
    NSString *wasmPath = [self wwnResolveWasmModulePathForMachineId:machineId];
    [self launchWasmModuleAtPath:wasmPath machineId:machineId];
    return;
  }

#if !TARGET_OS_IPHONE
  // Idempotent per machine: reconnecting the same profile must not spawn a
  // duplicate while that profile's instance is still alive. A *different*
  // machine with the same client id always gets a new process.
  if (machineId.length > 0 && [self _recordForMachineId:machineId]) {
    WWNLog(WWNBundledClientLogModule(clientId),
           @"%@ already running for machine %@. Keeping existing instance",
           clientId, machineId);
    return;
  }
#endif

#if TARGET_OS_IPHONE
  if (machineId.length > 0) {
    [self.iosRunningMachineIds addObject:machineId];
  }
  if ([clientId isEqualToString:@"weston"]) {
    [self launchWeston];
    return;
  }
  if ([clientId isEqualToString:@"weston-terminal"]) {
    [self _launchWestonTerminalWithMachineId:machineId];
    return;
  }
  if ([clientId isEqualToString:@"weston-simple-shm"]) {
    [self _launchWestonSimpleSHMWithMachineId:machineId];
    return;
  }
  if ([clientId isEqualToString:@"foot"]) {
    [self _launchFootWithMachineId:machineId];
    return;
  }
  if ([clientId isEqualToString:@"niri"]) {
    [self launchNiri];
    return;
  }
  NSString *gpuRefusal = WWNGpuClientRefusalReason(clientId);
  if (gpuRefusal) {
    WWNLog(WWNBundledClientLogModule(clientId),
           @"Refusing GPU client %@. %@", clientId, gpuRefusal);
    if (machineId.length > 0) {
      [self.iosRunningMachineIds removeObject:machineId];
    }
    return;
  }
  if (WWNIsIlandGpuCubeClientId(clientId)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
      [bridge prepareOutputSizeForNativeClientLaunchWithClientId:clientId];
      BOOL ok = [bridge launchNestedIlandGpuClientOnPrimaryView:clientId];
      const char *logMod = WWNBundledClientLogModule(clientId);
      if (!ok) {
        WWNLog(logMod,
               @"%@ launch failed (no compositor view or entry point "
               @"unavailable)", clientId);
      } else {
        WWNLog(logMod, @"%@ started via iland Metal presenter", clientId);
      }
    });
    return;
  }

  WWNClientMainFn entry = WWNClientMainForId(clientId);
  if (!entry) {
    WWNLog(WWNBundledClientLogModule(clientId),
           @"Unknown bundled client id: %@", clientId);
    if (machineId.length > 0) {
      [self.iosRunningMachineIds removeObject:machineId];
    }
    return;
  }

  NSString *boundMachineId = [machineId copy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    if (![self wwnBeginIOSNativeClientLaunch:clientId]) {
      if (boundMachineId.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.iosRunningMachineIds removeObject:boundMachineId];
        });
      }
      return;
    }

    char *argv[] = {(char *)clientId.UTF8String, NULL};
    char saved_cwd[512] = "";
    const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_dir) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      chdir(xdg_dir);
    }

    const char *logMod = WWNBundledClientLogModule(clientId);
    // Apply the resolved graphics-driver env immediately before entry() so the
    // in-process client sees the correct Vulkan provider. On the iOS Simulator
    // this coerces the Vulkan driver to the bundled SwiftShader CPU ICD (see
    // WWNSettings_ResolveGraphicsDriverSelection): MoltenVK's Metal pipeline
    // bring-up fatally aborts the whole app on headless CI, so vkcube must load
    // SwiftShader via WWN_VULKAN_LIBRARY and never touch Metal.
    WWNSettings_ApplyGraphicsDriverSelection();
    WWNLog(logMod, @"Launching in-process %@...", clientId);

    // Capture the client's own stdout/stderr into the app log. Bundled clients
    // (vkcube, weston demos) write plain fprintf(stderr) diagnostics. E.g.
    // "vkcube: no Vulkan physical device from any provider". And on Apple
    // mobile raw fd 1/2 are NOT routed to os_log, so those lines (and any crash
    // output) were invisible in the bundled-clients matrix artifacts. Redirect
    // fd 1/2 to a pipe for the duration of entry() and relog each line via the
    // saved fd (WWNLogFd, never WWNLog, to avoid a feedback loop). If the client
    // crashes without returning, whatever it printed before the fault is still
    // flushed to the log, which is exactly what we need to root-cause it.
    int savedOut = dup(STDOUT_FILENO);
    int savedErr = dup(STDERR_FILENO);
    int capPipe[2] = {-1, -1};
    dispatch_semaphore_t capDone = NULL;
    if (pipe(capPipe) == 0) {
      dup2(capPipe[1], STDOUT_FILENO);
      dup2(capPipe[1], STDERR_FILENO);
      close(capPipe[1]);
      int readFd = capPipe[0];
      NSString *capTag = clientId;
      // Emit via os_log, NOT the raw saved fd: the bundled-clients matrix
      // captures the simulator's unified log (simctl log stream), where raw
      // stdout/stderr writes never appear. That is why the earlier WWNLogFd
      // capture was invisible in the artifacts. os_log also never writes back to
      // fd 2, so there is no feedback loop while fd 1/2 are redirected here.
      capDone = dispatch_semaphore_create(0);
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char buf[1024];
        NSMutableData *line = [NSMutableData data];
        ssize_t n;
        while ((n = read(readFd, buf, sizeof(buf))) > 0) {
          for (ssize_t i = 0; i < n; i++) {
            if (buf[i] == '\n') {
              if (line.length > 0) {
                NSString *s = [[NSString alloc] initWithData:line
                                                    encoding:NSUTF8StringEncoding];
                if (s.length > 0)
                  os_log(OS_LOG_DEFAULT, "[CLIENTIO %{public}s] %{public}s",
                         capTag.UTF8String, s.UTF8String);
                [line setLength:0];
              }
            } else {
              [line appendBytes:&buf[i] length:1];
            }
          }
        }
        if (line.length > 0) {
          NSString *s = [[NSString alloc] initWithData:line
                                              encoding:NSUTF8StringEncoding];
          if (s.length > 0)
            os_log(OS_LOG_DEFAULT, "[CLIENTIO %{public}s] %{public}s",
                   capTag.UTF8String, s.UTF8String);
        }
        close(readFd);
        dispatch_semaphore_signal(capDone);
      });
    }

    int result = entry(1, argv);

    // Restore fd 1/2 and drain the reader. Closing our write-side dups (the
    // dup2-back replaces the pipe write-ends in this process's fd table) gives
    // the reader EOF so it can finish logging any tail line.
    fflush(stdout);
    fflush(stderr);
    if (savedOut >= 0) { dup2(savedOut, STDOUT_FILENO); close(savedOut); }
    if (savedErr >= 0) { dup2(savedErr, STDERR_FILENO); }
    if (capDone) {
      dispatch_semaphore_wait(
          capDone, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
    }
    if (savedErr >= 0) close(savedErr);
    WWNLog(logMod, @"%@ exit code: %d", clientId, result);

    if (saved_cwd[0])
      chdir(saved_cwd);

    [self wwnEndIOSNativeClientLaunch];
    if (boundMachineId.length > 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.iosRunningMachineIds removeObject:boundMachineId];
      });
    }
    if (result != 0) {
      NSString *reason =
          [NSString stringWithFormat:@"%@ exited %d", clientId, result];
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"WWNNativeClientLaunchFailedNotification"
                          object:self
                        userInfo:@{
                          @"clientId" : clientId,
                          @"reason" : reason,
                          @"exitCode" : @(result),
                        }];
      });
    }
  });
#else
  // Apply this machine's OpenGLDriver / VulkanDriver *before* the refusal
  // check. Otherwise Start consulted stale global prefs (e.g. leftover
  // VulkanDriver=none after a vkcube run) and refused ANGLE clients that the
  // machine profile actually enables.
  if (machineId.length > 0) {
    [WWNMachineProfileStore setActiveMachineId:machineId];
  }
  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];
  WWNSettings_ApplyGraphicsDriverSelection();
  NSString *gpuRefusal = WWNGpuClientRefusalReason(clientId);
  if (gpuRefusal) {
    WWNLog(WWNBundledClientLogModule(clientId),
           @"Refusing GPU client %@. %@", clientId, gpuRefusal);
    return;
  }
  // Product Start path: in-process iland Metal presenter (not an NSTask).
  if (WWNIsIlandGpuCubeClientId(clientId)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
      [bridge prepareOutputSizeForNativeClientLaunchWithClientId:clientId];
      BOOL ok = [bridge launchNestedIlandGpuClientOnPrimaryView:clientId];
      const char *logMod = WWNBundledClientLogModule(clientId);
      if (!ok) {
        WWNLog(logMod,
               @"%@ launch failed (no compositor view or entry point "
               @"unavailable)", clientId);
      } else {
        WWNLog(logMod, @"%@ started via iland Metal presenter", clientId);
      }
    });
    return;
  }
  if ([clientId isEqualToString:@"weston"]) {
    // Nested Weston remains a singleton (shared nested socket). Reuse the
    // existing process when already running; still bind ownership to this
    // machine so Stop targets the right profile.
    if (self.westonTask.isRunning || self.westonRunning) {
      if (machineId.length > 0) {
        self.westonMachineId = [machineId copy];
      }
      return;
    }
    if (machineId.length > 0) {
      self.westonMachineId = [machineId copy];
    }
    [self launchWeston];
    return;
  }
  if ([clientId isEqualToString:@"weston-terminal"]) {
    [self _launchWestonTerminalWithMachineId:machineId];
    return;
  }
  if ([clientId isEqualToString:@"weston-simple-shm"]) {
    [self _launchWestonSimpleSHMWithMachineId:machineId];
    return;
  }
  if ([clientId isEqualToString:@"foot"]) {
    [self _launchFootWithMachineId:machineId];
    return;
  }
  // Cubes / weston-simple-egl ship as Resources/bin executables on macOS.
  // In-process *_main fallback is the Apple-mobile path (above); do not call
  // WWNClientMainForId here. That helper and its weak symbols are iOS-only.
  BOOL running = YES;
  NSTask *task = nil;
  [self launchGenericWestonClient:clientId taskInOut:&task runningFlagIn:&running];
  if (task) {
    [self _registerNativeTask:task clientId:clientId machineId:machineId];
  }
#endif
}

- (NSString *)wwnResolveWasmModulePathForMachineId:(NSString *)machineId {
  if (machineId.length == 0) {
    return nil;
  }
#if __has_include("../Machines/WWNMachineProfileStore.h")
  WWNMachineProfile *profile = [WWNMachineProfileStore profileById:machineId];
  if (!profile) {
    return nil;
  }
  NSDictionary *runtime =
      [profile.runtimeOverrides isKindOfClass:[NSDictionary class]]
          ? profile.runtimeOverrides
          : @{};
  id path = runtime[kWWNRuntimeWasmModulePath];
  if ([path isKindOfClass:[NSString class]] && [(NSString *)path length] > 0) {
    return [(NSString *)path stringByExpandingTildeInPath];
  }
  NSDictionary *settings =
      [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
          ? profile.settingsOverrides
          : @{};
  id legacy = settings[@"WasmModulePath"];
  if ([legacy isKindOfClass:[NSString class]] && [(NSString *)legacy length] > 0) {
    return [(NSString *)legacy stringByExpandingTildeInPath];
  }
#endif
  return nil;
}

- (void)launchWasmModuleAtPath:(NSString *)wasmModulePath
                     machineId:(NSString *)machineId {
  const char *logMod = "WASM";
  NSString *path =
      wasmModulePath.length > 0
          ? [wasmModulePath stringByExpandingTildeInPath]
          : [self wwnResolveWasmModulePathForMachineId:machineId];
  if (path.length == 0) {
    WWNLog(logMod,
           @"No wasmModulePath on machine %@. Pick a .wasm in Machine Settings.",
           machineId ?: @"(none)");
    return;
  }
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    WWNLog(logMod, @"Wasm module missing at %@", path);
    return;
  }
  if (wawona_wasm_can_run != NULL && !wawona_wasm_can_run(path.UTF8String)) {
    WWNLog(logMod, @"Not a readable WASM module: %@", path);
    return;
  }

#if !TARGET_OS_IPHONE
  if (machineId.length > 0 && [self _recordForMachineId:machineId]) {
    WWNLog(logMod, @"wasm already running for machine %@. Keeping existing instance",
           machineId);
    return;
  }
  if (machineId.length > 0) {
    [WWNMachineProfileStore setActiveMachineId:machineId];
  }
  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];
  [[WWNCompositorBridge sharedBridge]
      prepareOutputSizeForNativeClientLaunchWithClientId:kWWNClientIdWasm];

  NSString *wasmBin = [self findBinaryNamed:@"wasm"];
  if (!wasmBin) {
    WWNLog(logMod, @"Bundled Runtime `wasm` CLI missing from app bundle.");
    return;
  }
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:wasmBin];
  task.arguments = @[ path ];
  NSMutableDictionary *env = [self wwnMutableHostWaylandEnvironment];
  task.environment = env;
  task.currentDirectoryURL = [NSURL fileURLWithPath:[path stringByDeletingLastPathComponent]];
  [self _installNativeClientTerminationHandler:task kind:kWWNClientIdWasm];
  @try {
    [task launch];
    [self _registerNativeTask:task clientId:kWWNClientIdWasm machineId:machineId];
    WWNLog(logMod, @"Runtime launched %@ (pid %d) machine=%@", path, task.processIdentifier,
           machineId ?: @"-");
    [self wwnPumpHostCompositorAfterNativeClientLaunch];
  } @catch (NSException *ex) {
    WWNLog(logMod, @"Failed to launch Runtime: %@", ex);
  }
#else
  if (machineId.length > 0) {
    [self.iosRunningMachineIds addObject:machineId];
  }
  if (wawona_wasm_run == NULL) {
    WWNLog(logMod, @"wawona_wasm_run not linked; cannot run %@", path);
    if (machineId.length > 0) {
      [self.iosRunningMachineIds removeObject:machineId];
    }
    return;
  }
  NSString *boundMachineId = [machineId copy];
  NSString *boundPath = [path copy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    if (![self wwnBeginIOSNativeClientLaunch:kWWNClientIdWasm]) {
      if (boundMachineId.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.iosRunningMachineIds removeObject:boundMachineId];
        });
      }
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      [[WWNCompositorBridge sharedBridge]
          prepareOutputSizeForNativeClientLaunchWithClientId:kWWNClientIdWasm];
    });
    char *argv[] = {(char *)"wasm", (char *)boundPath.UTF8String, NULL};
    WWNLog(logMod, @"Launching in-process Runtime %@", boundPath);
    int rc = wawona_wasm_run(2, argv);
    WWNLog(logMod, @"Runtime exited code=%d for %@", rc, boundPath);
    [self wwnEndIOSNativeClientLaunch];
    if (boundMachineId.length > 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.iosRunningMachineIds removeObject:boundMachineId];
      });
    }
  });
#endif
}

// MARK: - Weston Simple SHM

- (void)launchWestonSimpleSHM {
  [self _launchWestonSimpleSHMWithMachineId:nil];
}

- (void)_launchWestonSimpleSHMWithMachineId:(NSString *)machineId {
#if TARGET_OS_IPHONE
  NSString *boundMachineId = [machineId copy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    if (![self wwnBeginIOSNativeClientLaunch:@"weston-simple-shm"]) {
      if (boundMachineId.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.iosRunningMachineIds removeObject:boundMachineId];
        });
      }
      return;
    }
    self.westonSimpleSHMRunning = YES;

    void *fn_addr = (void *)weston_simple_shm_main;
    if (fn_addr == NULL) {
      WWNLog("WESTON_SHM", @"FATAL: weston_simple_shm_main symbol is NULL!");
      self.westonSimpleSHMRunning = NO;
      [self wwnEndIOSNativeClientLaunch];
      if (boundMachineId.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.iosRunningMachineIds removeObject:boundMachineId];
        });
      }
      return;
    }

    char *argv_shm[] = {"weston-simple-shm", NULL};
    int argc_shm = 1;

    char saved_cwd[512] = "";
    const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_dir) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      chdir(xdg_dir);
    }

    WWNLog("WESTON_SHM", @"Launching in-process weston-simple-shm...");
    int result = weston_simple_shm_main(argc_shm, argv_shm);
    WWNLog("WESTON_SHM", @"weston_simple_shm_main exit code: %d", result);

    if (saved_cwd[0])
      chdir(saved_cwd);

    [self wwnEndIOSNativeClientLaunch];
    if (boundMachineId.length > 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.iosRunningMachineIds removeObject:boundMachineId];
      });
    }
    if (self.iosNativeClientInFlightCount == 0) {
      self.westonSimpleSHMRunning = NO;
    }
  });
#else
  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];
  [[WWNCompositorBridge sharedBridge]
      prepareOutputSizeForNativeClientLaunchWithClientId:@"weston-simple-shm"];
  NSString *path = [self findWestonSimpleSHMBinary];
  if (!path) {
    WWNLog("WESTON_SHM",
           @"Could not find weston-simple-shm executable in app bundle.");
    return;
  }

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:path];
  task.environment = [self wwnMutableHostWaylandEnvironment];

  NSError *err;
  if ([task launchAndReturnError:&err]) {
    WWNLog("WESTON_SHM", @"Launched weston-simple-shm with PID %d",
           task.processIdentifier);
    [self wwnPumpHostCompositorAfterNativeClientLaunch];
    [self _registerNativeTask:task
                     clientId:@"weston-simple-shm"
                    machineId:machineId];
  } else {
    WWNLog("WESTON_SHM", @"Failed to launch weston-simple-shm: %@", err);
  }
#endif
}

- (void)stopWestonSimpleSHM {
#if TARGET_OS_IPHONE
  [[WWNCompositorBridge sharedBridge] tearDownActiveIOSCompositorViews];
  self.westonSimpleSHMRunning = NO;
  self.iosNativeClientInFlightCount = 0;
  self.activeIOSBundledClientId = nil;
#else
  [self _terminateAllNativeTasksWithClientId:@"weston-simple-shm"];
#endif
}

// MARK: - Generic Weston Launch Helpers
#if !TARGET_OS_IPHONE
- (NSString *)findBinaryNamed:(NSString *)name {
  return WWNWawonaFindBundledExecutable(name);
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (NSMutableDictionary<NSString *, NSString *> *)
    wwnMutableHostWaylandEnvironment {
  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
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
  } else {
    const char *envRuntime = getenv("XDG_RUNTIME_DIR");
    if (!envRuntime) {
      env[@"XDG_RUNTIME_DIR"] =
          [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
    }
  }
  const char *westonData = getenv("WESTON_DATA_DIR");
  if (westonData && westonData[0]) {
    env[@"WESTON_DATA_DIR"] = @(westonData);
  }
  const char *westonModules = getenv("WESTON_MODULE_DIR");
  if (westonModules && westonModules[0]) {
    env[@"WESTON_MODULE_DIR"] = @(westonModules);
  }
  const char *westonBackends = getenv("WESTON_BACKEND_DIR");
  if (westonBackends && westonBackends[0]) {
    env[@"WESTON_BACKEND_DIR"] = @(westonBackends);
  }
  const char *fontConfig = getenv("FONTCONFIG_FILE");
  if (fontConfig && fontConfig[0]) {
    env[@"FONTCONFIG_FILE"] = @(fontConfig);
  }
  const char *fontConfigPath = getenv("FONTCONFIG_PATH");
  if (fontConfigPath && fontConfigPath[0]) {
    env[@"FONTCONFIG_PATH"] = @(fontConfigPath);
  }
  const char *xcursorPath = getenv("XCURSOR_PATH");
  if (xcursorPath && xcursorPath[0]) {
    env[@"XCURSOR_PATH"] = @(xcursorPath);
  }
  const char *xcursorTheme = getenv("XCURSOR_THEME");
  if (xcursorTheme && xcursorTheme[0]) {
    env[@"XCURSOR_THEME"] = @(xcursorTheme);
  }
  const char *bundleRoot = getenv("WAWONA_APP_BUNDLE_ROOT");
  if (bundleRoot && bundleRoot[0]) {
    env[@"WAWONA_APP_BUNDLE_ROOT"] = @(bundleRoot);
  }
  const char *shareRoot = getenv("WAWONA_SHARE_ROOT");
  if (shareRoot && shareRoot[0]) {
    env[@"WAWONA_SHARE_ROOT"] = @(shareRoot);
  }
  const char *libRoot = getenv("WAWONA_LIB_ROOT");
  if (libRoot && libRoot[0]) {
    env[@"WAWONA_LIB_ROOT"] = @(libRoot);
  }
  return env;
}

- (void)wwnPumpHostCompositorAfterNativeClientLaunch {
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  [bridge pumpHostCompositorEvents];
  [bridge scheduleFollowUpHostCompositorPumps:4 interval:0.05];
}
#endif

/// Client-specific env overlays shared by nested NSTask launches and Mode B
/// framebufferd exec. Does not choose WAYLAND_DISPLAY vs DRM; the caller
/// supplies the base dictionary.
- (void)wwnApplyBundledClientEnvironment:(NSMutableDictionary<NSString *, NSString *> *)env
                             forClientId:(NSString *)name {
  if (!env || name.length == 0) {
    return;
  }
  BOOL needsFrameworks =
      [name isEqualToString:@"vkcube"] ||
      [name isEqualToString:@"opengl-cube"] ||
      [name isEqualToString:@"weston-simple-egl"] ||
      [name isEqualToString:@"kmscube"] ||
      [name isEqualToString:@"niri"] ||
      [name isEqualToString:@"weston"];
  NSString *frameworksDir = [[[NSBundle mainBundle] bundlePath]
      stringByAppendingPathComponent:@"Contents/Frameworks"];
  if (needsFrameworks &&
      [[NSFileManager defaultManager] fileExistsAtPath:frameworksDir]) {
    env[@"DYLD_LIBRARY_PATH"] = frameworksDir;
  }
  if ([name isEqualToString:@"vkcube"]) {
    const char *vkLib = getenv("WWN_VULKAN_LIBRARY");
    if (vkLib && vkLib[0])
      env[@"WWN_VULKAN_LIBRARY"] = @(vkLib);
    if (!env[@"WWN_VULKAN_LIBRARY"] &&
        [[NSFileManager defaultManager] fileExistsAtPath:frameworksDir]) {
      NSString *mvk =
          [frameworksDir stringByAppendingPathComponent:@"libMoltenVK.dylib"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:mvk])
        env[@"WWN_VULKAN_LIBRARY"] = mvk;
    }
  }
  if ([name isEqualToString:@"opengl-cube"] ||
      [name isEqualToString:@"weston-simple-egl"] ||
      [name isEqualToString:@"kmscube"]) {
    const char *anglePlat = getenv("ANGLE_DEFAULT_PLATFORM");
    if (anglePlat && anglePlat[0])
      env[@"ANGLE_DEFAULT_PLATFORM"] = @(anglePlat);
    const char *glDriver = getenv("WWN_OPENGL_DRIVER");
    if (glDriver && glDriver[0])
      env[@"WWN_OPENGL_DRIVER"] = @(glDriver);
  }
  if ([name isEqualToString:@"niri"]) {
    NSString *backend = WWNResolveCompositorBackend(nil);
    env[@"NIRI_BACKEND"] =
        [backend isEqualToString:@"drm"] ? @"tty" : @"nested";
    WWNLog("NIRI", @"backend=%@ (NIRI_BACKEND=%@)", backend,
           env[@"NIRI_BACKEND"]);
    env[@"ANGLE_DEFAULT_PLATFORM"] = @"metal";
    NSString *shareRoot = env[@"WAWONA_SHARE_ROOT"];
    if (shareRoot.length == 0) {
      shareRoot = WWNWawonaShareRoot();
      if (shareRoot.length > 0) {
        env[@"WAWONA_SHARE_ROOT"] = shareRoot;
      }
    }
    if (shareRoot.length > 0) {
      NSString *kdl = [shareRoot
          stringByAppendingPathComponent:@"niri/default-config.kdl"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:kdl]) {
        env[@"NIRI_CONFIG"] = kdl;
      } else {
        NSString *alt = [[WWNWawonaResourcesRoot()
            stringByAppendingPathComponent:@"share/niri/default-config.kdl"]
            stringByStandardizingPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:alt]) {
          env[@"NIRI_CONFIG"] = alt;
        }
      }
    }
    const char *icd = getenv("VK_ICD_FILENAMES");
    if (!icd || !icd[0]) {
      icd = getenv("VK_DRIVER_FILES");
    }
    if (icd && icd[0]) {
      env[@"VK_ICD_FILENAMES"] = @(icd);
      env[@"VK_DRIVER_FILES"] = @(icd);
    } else {
      NSString *bundleRes = [[NSBundle mainBundle] resourcePath];
      NSString *icdJson = [bundleRes
          stringByAppendingPathComponent:@"vulkan/icd.d/MoltenVK_icd.json"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:icdJson]) {
        env[@"VK_ICD_FILENAMES"] = icdJson;
        env[@"VK_DRIVER_FILES"] = icdJson;
      }
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksDir]) {
      env[@"DYLD_LIBRARY_PATH"] = frameworksDir;
    }
    NSString *bundleBin = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"Contents/Resources/bin"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:bundleBin]) {
      NSString *path = env[@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
      env[@"PATH"] = [NSString stringWithFormat:@"%@:%@", bundleBin, path];
    }
    WWNEnsureFuzzelXdgEnv();
    {
      const char *sr = getenv("WAWONA_SHARE_ROOT");
      const char *xdgDirs = getenv("XDG_DATA_DIRS");
      const char *xdgHome = getenv("XDG_DATA_HOME");
      const char *xdgCache = getenv("XDG_CACHE_HOME");
      if (sr && sr[0]) {
        env[@"WAWONA_SHARE_ROOT"] = @(sr);
      }
      if (xdgDirs && xdgDirs[0]) {
        env[@"XDG_DATA_DIRS"] = @(xdgDirs);
      }
      if (xdgHome && xdgHome[0]) {
        env[@"XDG_DATA_HOME"] = @(xdgHome);
      }
      if (xdgCache && xdgCache[0]) {
        env[@"XDG_CACHE_HOME"] = @(xdgCache);
      }
      NSString *appsDir =
          sr ? [@(sr) stringByAppendingPathComponent:@"applications"] : nil;
      if (appsDir.length > 0 &&
          [[NSFileManager defaultManager] fileExistsAtPath:appsDir]) {
        WWNLog("NIRI", @"fuzzel XDG_DATA_DIRS=%@ (catalog %@)",
               env[@"XDG_DATA_DIRS"] ?: @"(unset)", appsDir);
      } else {
        WWNLog("NIRI",
               @"No bundled share/applications. Fuzzel Mod+D list will be "
               @"empty (WAWONA_SHARE_ROOT=%s)",
               sr ? sr : "(nil)");
      }
    }
  }
}

/// Out-of-process bundled client (niri/kmscube demos/etc.). Named historically
/// for Weston demos; log module must follow the real client id. Never brand
/// non-Weston launches as [WESTON] (see GitHub issue for this mis-tag).
- (void)launchGenericWestonClient:(NSString *)name
                        taskInOut:(NSTask *__strong *)taskPtr
                    runningFlagIn:(BOOL *)runningFlag {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];
  // Machine prefs just rewrote OpenGLDriver / VulkanDriver; push them into
  // the process env (ANGLE_DEFAULT_PLATFORM, WWN_VULKAN_LIBRARY, …) before
  // the child inherits / we copy getenv into the NSTask environment.
  WWNSettings_ApplyGraphicsDriverSelection();
  [[WWNCompositorBridge sharedBridge]
      prepareOutputSizeForNativeClientLaunchWithClientId:name];
#endif
  const char *logMod = WWNBundledClientLogModule(name);
  NSString *path = [self findBinaryNamed:name];
  if (!path) {
    WWNLog(logMod, @"Could not find executable %@ in app bundle.", name);
    *runningFlag = NO;
    return;
  }
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:path];

  NSMutableDictionary *env = [self wwnMutableHostWaylandEnvironment];
  [self wwnApplyBundledClientEnvironment:env forClientId:name];
  // weston-image is the only weston demo that takes a required positional arg:
  // one or more image paths. With no argv it prints usage and exits (status 1),
  // which read as a broken client. Feed it a bundled image so it renders.
  if ([name isEqualToString:@"weston-image"]) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *img = WWNWawonaBundledSharePath(@"weston/pattern.png");
    if (![fm fileExistsAtPath:img]) {
      img = WWNWawonaBundledSharePath(@"weston/terminal.png");
    }
    if ([fm fileExistsAtPath:img]) {
      task.arguments = @[ img ];
      WWNLog(logMod, @"weston-image argv: %@", img);
    } else {
      WWNLog(logMod, @"weston-image: no bundled image found under share/weston");
    }
  }

  task.environment = env;
  NSError *err;
  if ([task launchAndReturnError:&err]) {
    *taskPtr = task;
    WWNLog(logMod, @"Launched %@ with PID %d", name, task.processIdentifier);
    [self wwnPumpHostCompositorAfterNativeClientLaunch];
  } else {
    WWNLog(logMod, @"Failed to launch %@: %@", name, err);
    *runningFlag = NO;
  }
}

#if TARGET_OS_OSX
static NSArray<NSString *> *WWNTokenizeCommandLine(NSString *command) {
  NSMutableArray<NSString *> *tokens = [NSMutableArray array];
  NSMutableString *cur = [NSMutableString string];
  unichar quote = 0;
  NSUInteger len = command.length;
  for (NSUInteger i = 0; i < len; i++) {
    unichar c = [command characterAtIndex:i];
    if (quote != 0) {
      if (c == quote) {
        quote = 0;
      } else {
        [cur appendFormat:@"%C", c];
      }
      continue;
    }
    if (c == '\'' || c == '"') {
      quote = c;
      continue;
    }
    if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) {
      if (cur.length > 0) {
        [tokens addObject:[cur copy]];
        [cur setString:@""];
      }
      continue;
    }
    [cur appendFormat:@"%C", c];
  }
  if (cur.length > 0) {
    [tokens addObject:[cur copy]];
  }
  return tokens;
}

static void WWNCopyGetenv(NSMutableDictionary<NSString *, NSString *> *env,
                          NSString *key) {
  const char *value = getenv(key.UTF8String);
  if (value && value[0]) {
    env[key] = @(value);
  }
}

- (NSMutableDictionary<NSString *, NSString *> *)
    wwnMutableBaremetalCompositorEnvironment {
  /*
   * Whitelist only. The root helper must not inherit the GUI session
   * (WAYLAND_DISPLAY, DISPLAY, SSH_AUTH_SOCK, leftover DYLD_*).
   */
  NSMutableDictionary *env = [NSMutableDictionary dictionary];
  env[@"XDG_RUNTIME_DIR"] =
      [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  env[@"XDG_SESSION_TYPE"] = @"tty";
  env[@"ANGLE_DEFAULT_PLATFORM"] = @"metal";

  NSString *frameworksDir = [[[NSBundle mainBundle] bundlePath]
      stringByAppendingPathComponent:@"Contents/Frameworks"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksDir]) {
    env[@"DYLD_LIBRARY_PATH"] = frameworksDir;
  }
  NSString *bundleBin = [[[NSBundle mainBundle] bundlePath]
      stringByAppendingPathComponent:@"Contents/Resources/bin"];
  NSString *path = @"/usr/bin:/bin:/usr/sbin:/sbin";
  if ([[NSFileManager defaultManager] fileExistsAtPath:bundleBin]) {
    path = [NSString stringWithFormat:@"%@:%@", bundleBin, path];
  }
  env[@"PATH"] = path;

  NSArray<NSString *> *fromProcess = @[
    @"WESTON_DATA_DIR",
    @"WESTON_MODULE_DIR",
    @"WESTON_BACKEND_DIR",
    @"FONTCONFIG_FILE",
    @"FONTCONFIG_PATH",
    @"XCURSOR_PATH",
    @"XCURSOR_THEME",
    @"WAWONA_APP_BUNDLE_ROOT",
    @"WAWONA_SHARE_ROOT",
    @"WAWONA_LIB_ROOT",
    @"XDG_DATA_DIRS",
    @"XDG_DATA_HOME",
    @"XDG_CACHE_HOME",
    @"VK_ICD_FILENAMES",
    @"VK_DRIVER_FILES",
    @"WWN_VULKAN_LIBRARY",
    @"WWN_OPENGL_DRIVER",
    @"NIRI_CONFIG",
  ];
  for (NSString *key in fromProcess) {
    WWNCopyGetenv(env, key);
  }
  return env;
}

- (BOOL)baremetalCompositorLaunchSpecForProfile:(WWNMachineProfile *)profile
                                     executable:(NSString *_Nullable *_Nonnull)outPath
                                      arguments:(NSArray<NSString *> *_Nullable *_Nonnull)outArgs
                                    environment:(NSDictionary<NSString *, NSString *> *_Nullable *_Nonnull)outEnv
                                          error:(NSError *_Nullable *_Nullable)error {
  if (outPath) {
    *outPath = nil;
  }
  if (outArgs) {
    *outArgs = nil;
  }
  if (outEnv) {
    *outEnv = nil;
  }
  if (![WWNMachineProfileStore profileIndicatesNestedCompositor:profile]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNWaypipeRunner"
                     code:40
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Desktop Replacement needs a nested compositor "
                       @"(weston, niri, or a custom compositor). Demo "
                       @"clients are not a desktop."
                 }];
    }
    return NO;
  }

  NSString *clientId =
      [WWNMachineSessionBridge nativeClientIdForProfile:profile];
  if (clientId.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNWaypipeRunner"
                     code:41
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Desktop machine has no bundled compositor configured."
                 }];
    }
    return NO;
  }

  /*
   * Do not applyMachineToRuntimePrefs here. That writes the Desktop machine
   * onto the GUI prefs session and, historically, called +sharedBridge which
   * started WWNCore in `Wawona --mode-b-stage`. Mode B env is built below
   * without touching the Aqua compositor.
   */
  WWNConfigureBundledRuntimeEnvIfNeeded();
  WWNSettings_ApplyGraphicsDriverSelection();

  NSMutableDictionary *env = [self wwnMutableBaremetalCompositorEnvironment];
  [self wwnApplyBundledClientEnvironment:env forClientId:clientId];
  [env removeObjectForKey:@"WAYLAND_DISPLAY"];
  [env removeObjectForKey:@"WAYLAND_SOCKET"];
  [env removeObjectForKey:@"DISPLAY"];
  [env removeObjectForKey:@"DYLD_INSERT_LIBRARIES"];

  NSString *xdg = env[@"XDG_RUNTIME_DIR"];
  if (xdg.length > 0) {
    [[NSFileManager defaultManager] createDirectoryAtPath:xdg
                              withIntermediateDirectories:YES
                                               attributes:@{
                                                 NSFilePosixPermissions : @0700
                                               }
                                                    error:nil];
  }

  NSString *executable = nil;
  NSArray<NSString *> *args = @[];

  if ([clientId isEqualToString:@"niri"]) {
    env[@"NIRI_BACKEND"] = @"tty";
    executable = [self findBinaryNamed:@"niri"];
  } else if ([clientId isEqualToString:@"weston"]) {
    executable = [self findBinaryNamed:@"weston"];
    NSString *configPath = [xdg stringByAppendingPathComponent:@"weston.ini"];
    if (xdg.length > 0) {
      [self wwnWriteWestonIniAtPath:configPath.UTF8String usePixman:NO];
    }
    NSMutableArray<NSString *> *westonArgs = [NSMutableArray arrayWithObjects:
        @"--backend=drm",
        @"--continue-without-input",
        [NSString stringWithFormat:@"--socket=%@",
                                   [WWNPreferencesManager preferredNestedSocketName]],
        @"--shell=desktop-shell.so",
        nil];
    if (xdg.length > 0) {
      [westonArgs addObject:[NSString stringWithFormat:@"--config=%@", configPath]];
    }
    args = westonArgs;
  } else if ([clientId isEqualToString:@"custom"]) {
    NSDictionary *so =
        [profile.settingsOverrides isKindOfClass:[NSDictionary class]]
            ? profile.settingsOverrides
            : @{};
    NSString *cmd =
        [so[@"NativeCustomCommand"] isKindOfClass:[NSString class]]
            ? so[@"NativeCustomCommand"]
            : @"";
    cmd = [cmd stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *tokens = WWNTokenizeCommandLine(cmd);
    if (tokens.count == 0) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"WWNWaypipeRunner"
                       code:42
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"Custom desktop compositor command is empty."
                   }];
      }
      return NO;
    }
    NSString *first = tokens[0];
    NSString *bundled = [self findBinaryNamed:first.lastPathComponent];
    if ([first hasPrefix:@"/"] &&
        [[NSFileManager defaultManager] fileExistsAtPath:first]) {
      executable = first;
    } else if (bundled.length > 0) {
      executable = bundled;
    } else {
      executable = first;
    }
    if (tokens.count > 1) {
      args = [tokens subarrayWithRange:NSMakeRange(1, tokens.count - 1)];
    }
  } else {
    executable = [self findBinaryNamed:clientId];
  }

  if (executable.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNWaypipeRunner"
                     code:43
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"Bundled %@ executable not found.",
                                        clientId]
                 }];
    }
    return NO;
  }

  if (outPath) {
    *outPath = executable;
  }
  if (outArgs) {
    *outArgs = args;
  }
  if (outEnv) {
    *outEnv = [env copy];
  }
  WWNLog("DESKTOP", @"Mode B launch spec client=%@ exe=%@ argv=%@", clientId,
         executable, [args componentsJoinedByString:@" "]);
  return YES;
}
#endif

/// When the child exits (quit, crash, SIGKILL), drop its registry record and
/// notify so UI can clear "connected" without requiring Stop.
- (void)_installNativeClientTerminationHandler:(NSTask *)task kind:(NSString *)kind {
  if (!task || !kind)
    return;
  __weak WWNWaypipeRunner *weakSelf = self;
  task.terminationHandler = ^(NSTask *finished) {
    dispatch_async(dispatch_get_main_queue(), ^{
      WWNWaypipeRunner *s = weakSelf;
      if (!s)
        return;
      if (s.westonTask == finished) {
        s.westonTask = nil;
        s.westonMachineId = nil;
      }
      WWNNativeClientRecord *rec = [s _recordForTask:finished];
      if (rec) {
        WWNLog(WWNBundledClientLogModule(rec.clientId),
               @"%@ terminated (status %d machine=%@)", rec.clientId,
               finished.terminationStatus, rec.machineId ?: @"-");
        [s.nativeClientRecords removeObject:rec];
      }
      [s _refreshRunningFlagsFromRecords];
      [[NSNotificationCenter defaultCenter]
          postNotificationName:@"WWNNativeClientProcessDidTerminateNotification"
                        object:s];
    });
  };
}
#endif

// MARK: - Native Weston Executable

#if TARGET_OS_IPHONE || (!TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR)
- (BOOL)wwnWriteWestonIniAtPath:(const char *)configPath usePixman:(BOOL)usePixman {
  if (!configPath || !configPath[0]) {
    return NO;
  }
  NSString *terminalIcon = WWNWawonaBundledSharePath(@"weston/terminal.png");
  // Prefer background.png (RGB). pattern.png is an indexed-color PNG that
  // cairo often fails to load. Then only background-color shows (solid blue).
  NSString *backgroundImage = WWNWawonaBundledSharePath(@"weston/background.png");
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL hasPattern = [fm fileExistsAtPath:backgroundImage];
  if (!hasPattern) {
    backgroundImage = WWNWawonaBundledSharePath(@"weston/pattern.png");
    hasPattern = [fm fileExistsAtPath:backgroundImage];
  }
  BOOL hasTerminalIcon = [fm fileExistsAtPath:terminalIcon];
  if (!hasPattern) {
    WWNLog("WESTON", @"background-image missing in bundle: %@",
           backgroundImage);
  }
  if (!hasTerminalIcon) {
    WWNLog("WESTON", @"launcher icon missing in bundle: %@", terminalIcon);
  }
  NSString *backgroundImageLine =
      hasPattern
          ? [NSString stringWithFormat:@"background-image=%@\n", backgroundImage]
          : @"";
  // desktop-shell.so spawns the weston-desktop-shell helper (panel / background
  // / launcher). Its compiled-in default is a build-time nix-store libexec path
  // that does not exist at runtime ("Couldn't launch client … cannot run at
  // all"). Point [shell] client= at the copy we bundle next to the app binary
  // so the shell UI actually comes up. Same idea for the on-screen keyboard.
  //
  // macOS only: this spawns separate helper executables via desktop-shell.so.
  // Apple mobile has no fork/exec and runs weston fully in-process, so
  // findBinaryNamed: is not compiled there. Leave client=/input-method= unset
  // and let weston use its in-process defaults.
  NSString *shellClientLine = @"";
  NSString *keyboardLine = @"";
#if !TARGET_OS_IPHONE
  NSString *shellClient = [self findBinaryNamed:@"weston-desktop-shell"];
  shellClientLine =
      (shellClient.length > 0 && [fm isExecutableFileAtPath:shellClient])
          ? [NSString stringWithFormat:@"client=%@\n", shellClient]
          : @"";
  if (shellClientLine.length == 0) {
    WWNLog("WESTON",
           @"weston-desktop-shell helper not bundled. Desktop-shell will fall "
           @"back to its baked libexec path and the panel/background will be "
           @"missing");
  } else {
    WWNLog("WESTON", @"weston.ini [shell] client=%@", shellClient);
  }
  NSString *keyboardClient = [self findBinaryNamed:@"weston-keyboard"];
  keyboardLine =
      (keyboardClient.length > 0 && [fm isExecutableFileAtPath:keyboardClient])
          ? [NSString stringWithFormat:@"input-method=%@\n", keyboardClient]
          : @"";
#endif
#if TARGET_OS_OSX
  CGFloat fontSize = [NSFont systemFontSize];
#elif TARGET_OS_IOS
  CGFloat fontSize = [UIFont systemFontSize];
#else
  CGFloat fontSize = 17.0;
#endif
  NSString *ini = [NSString
      stringWithFormat:@"[core]\n"
                       @"use-pixman=%s\n"
                       @"\n"
                       @"[shell]\n"
                       @"%@"
                       @"%@"
                       @"background-color=0xff1a1a2e\n"
                       @"%@"
                       @"background-type=scale\n"
                       @"panel-color=0xff101010\n"
                       @"panel-position=top\n"
                       @"clock-format=seconds\n"
                       @"\n"
                       @"[launcher]\n"
                       @"icon=%@\n"
                       @"path=weston-terminal\n"
                       @"\n"
                       @"[terminal]\n"
                       @"font=DejaVuSansM Nerd Font Mono\n"
                       @"font-size=%.0f\n",
                       usePixman ? "true" : "false", shellClientLine,
                       keyboardLine, backgroundImageLine,
                       hasTerminalIcon ? terminalIcon : @"", fontSize];
  NSError *iniErr = nil;
  BOOL wrote = [ini writeToFile:@(configPath)
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:&iniErr];
  if (wrote) {
    setenv("WESTON_CONFIG_FILE", configPath, 1);
    WWNLog("WESTON", @"Wrote weston.ini + WESTON_CONFIG_FILE: %s", configPath);
    WWNLog("WESTON", @"weston.ini background-image=%@", backgroundImage);
  } else {
    WWNLog("WESTON", @"Failed to write weston.ini (%s): %@", configPath,
           iniErr.localizedDescription);
  }
  return wrote;
}
#endif

#if TARGET_OS_IPHONE
- (void)wwnLaunchWestonCompositorWithBackend:(const char *)backend
                                  usePixman:(BOOL)usePixman
                               prepareIland:(BOOL)prepareIland {
  if (self.westonRunning) {
    return;
  }
  self.westonRunning = YES;

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    CFAbsoluteTime launchStart = CFAbsoluteTimeGetCurrent();
    WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
    [WWNRootfsProvider applyShellEnvironment];
    // Re-apply the graphics driver selection right before the in-process
    // compositor starts, exactly like the iland GPU-client launch paths. This
    // pins ANGLE to Metal (ANGLE_DEFAULT_PLATFORM=metal) and points the Vulkan
    // loader at the bundled ICD, so nested weston's GL/EGL renderer initializes
    // on the iOS Simulator instead of falling through to a Vulkan device it
    // cannot create. Settings may have changed since app startup.
    WWNSettings_ApplyGraphicsDriverSelection();
    if (![self wwnBeginIOSNativeClientLaunch:@"weston"]) {
      self.westonRunning = NO;
      return;
    }
    WWNLog("WESTON", @"prepareOutputSize: %.0fms",
           (CFAbsoluteTimeGetCurrent() - launchStart) * 1000.0);

    if (prepareIland) {
      if (![bridge prepareIlandMetalPresentationOnPrimaryView]) {
        WWNLog("WESTON",
               @"Failed to prepare iland Metal presentation for Weston DRM. "
               @"falling back to nested --backend=wayland --use-pixman");
        self.westonRunning = NO;
        [self wwnEndIOSNativeClientLaunch];
        // Recurse onto the nested Wayland path so Start still paints a
        // Weston desktop instead of leaving a Connected card with no surface.
        dispatch_async(dispatch_get_main_queue(), ^{
          [self wwnLaunchWestonCompositorWithBackend:"--backend=wayland"
                                           usePixman:YES
                                        prepareIland:NO];
        });
        return;
      }
    }

    if (!prepareIland) {
      const char *parent_display = getenv("WAYLAND_DISPLAY");
      if (!parent_display || parent_display[0] == '\0') {
        parent_display = "wayland-0";
      }
      setenv("WAYLAND_DISPLAY", parent_display, 1);
    }

    uint32_t outW = 0;
    uint32_t outH = 0;
    float outScale = 1.0f;
    [bridge latestOutputWidth:&outW height:&outH scale:&outScale];
    if (outW == 0 || outH == 0) {
      WWNLog("WESTON",
             @"Host output size still unset after prepare. Nested weston "
             @"will negotiate via xdg_toplevel");
    }

    unsigned hostScale =
        (unsigned)lrintf(outScale >= 1.0f ? outScale : 1.0f);
    if (hostScale < 1u) {
      hostScale = 1u;
    }
    char scaleEnv[32];
    snprintf(scaleEnv, sizeof(scaleEnv), "%u", hostScale);
    setenv("WAWONA_OUTPUT_SCALE", scaleEnv, 1);

    // Do not pass --width/--height. Nested Weston is a Wayland client of
    // Wawona; size is negotiated via xdg_toplevel / per-window wl_output.
    char scaleArg[32];
    unsigned launchScale = hostScale;
    snprintf(scaleArg, sizeof(scaleArg), "--scale=%u", launchScale);

    char saved_cwd[512] = "";
    const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_dir) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      chdir(xdg_dir);
    }

    char configPath[512] = "";
    char configArg[600] = "";
    if (xdg_dir && xdg_dir[0]) {
      snprintf(configPath, sizeof(configPath), "%s/weston.ini", xdg_dir);
      if ([self wwnWriteWestonIniAtPath:configPath usePixman:usePixman]) {
        snprintf(configArg, sizeof(configArg), "--config=%s", configPath);
      }
    }

    char *argv_weston[13];
    int argc_weston = 0;
    argv_weston[argc_weston++] = "weston";
    argv_weston[argc_weston++] = (char *)backend;
    /* Deterministic nested socket so the Swinging Bridge app bridge can attach. Keep in
     * sync with +preferredNestedSocketName and AnowawSession.NESTED_SOCKET (legacy Kotlin name). */
    static char nested_socket_arg[48];
    NSString *nestedSocket = [WWNPreferencesManager preferredNestedSocketName];
    snprintf(nested_socket_arg, sizeof(nested_socket_arg), "--socket=%s",
             nestedSocket.UTF8String);
    argv_weston[argc_weston++] = nested_socket_arg;
    /* Panel launchers connect via this named socket (not the host
     * WAYLAND_DISPLAY). Kept in sync with wwn_launch_panel_client. */
    setenv("WAWONA_NESTED_WAYLAND_DISPLAY", nestedSocket.UTF8String, 1);
    argv_weston[argc_weston++] = "--shell=desktop-shell.so";
    argv_weston[argc_weston++] = scaleArg;
    if (!prepareIland) {
      argv_weston[argc_weston++] = "--fullscreen";
    }
    if (configArg[0]) {
      argv_weston[argc_weston++] = configArg;
    }
    if (usePixman) {
      argv_weston[argc_weston++] = "--use-pixman";
    }
    argv_weston[argc_weston] = NULL;

    wwn_weston_compositor_shutdown_requested = 0;
    NSMutableString *argvLog = [NSMutableString string];
    for (int i = 0; i < argc_weston; i++) {
      if (i > 0) {
        [argvLog appendString:@" "];
      }
      [argvLog appendFormat:@"%s", argv_weston[i]];
    }
    WWNLog("WESTON", @"Launch argv: %@", argvLog);
    WWNLog("WESTON",
           @"Launching nested weston_compositor_main (%s, output %ux%u "
           @"host-scale %.1fx weston-scale %u, prep %.0fms)...",
           backend, outW, outH, outScale, launchScale,
           (CFAbsoluteTimeGetCurrent() - launchStart) * 1000.0);
    if (!weston_compositor_main) {
      WWNLog("WESTON",
             @"weston_compositor_main not linked in this build. Nested Weston "
             @"unavailable");
      if (saved_cwd[0]) {
        chdir(saved_cwd);
      }
      self.westonRunning = NO;
      [self wwnEndIOSNativeClientLaunch];
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"WWNNativeClientLaunchFailedNotification"
                          object:self
                        userInfo:@{
                          @"clientId" : @"weston",
                          @"reason" : @"weston_compositor_main not linked",
                        }];
      });
      return;
    }
    int result = weston_compositor_main(argc_weston, argv_weston);
    WWNLog("WESTON", @"weston_compositor_main exit code: %d (total %.0fms)", result,
           (CFAbsoluteTimeGetCurrent() - launchStart) * 1000.0);

    if (saved_cwd[0]) {
      chdir(saved_cwd);
    }

    self.westonRunning = NO;
    [self wwnEndIOSNativeClientLaunch];
  });
}
#endif

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
/// Fail-fast check for the bundled runtime nested Weston needs. Returns nil
/// when everything is present, otherwise a human-readable description of the
/// missing pieces (weston exits cryptically without them).
- (NSString *)wwnValidateNestedWestonEnv {
  NSMutableArray<NSString *> *missing = [NSMutableArray array];
  const char *required[] = {"WESTON_DATA_DIR", "WESTON_MODULE_DIR",
                            "WESTON_BACKEND_DIR"};
  for (size_t i = 0; i < sizeof(required) / sizeof(required[0]); i++) {
    const char *value = getenv(required[i]);
    if (!value || !value[0]) {
      [missing addObject:[NSString stringWithFormat:@"%s is unset", required[i]]];
    } else if (access(value, R_OK) != 0) {
      [missing addObject:[NSString stringWithFormat:@"%s → %s (unreadable)",
                                                    required[i], value]];
    }
  }
  if (missing.count == 0) {
    return nil;
  }
  return [missing componentsJoinedByString:@"; "];
}

- (void)launchWestonMacOSAsNestedClient {
  if (self.westonTask.isRunning || self.westonRunning) {
    return;
  }

  // Prefer CompositorBackend / CLI --backend over the legacy
  // NestedWestonBackend key. Taking the DRM in-process path when the user
  // asked for wayland hung headless CLI: westonRunning was set before the
  // branch, so launchWestonMacOSDrmInProcess returned as a silent no-op.
  NSString *resolvedBackend = WWNResolveCompositorBackend(nil);
  NSString *prefsBackend =
      [[WWNPreferencesManager sharedManager] compositorBackend];
  NSString *legacyNested =
      [[WWNPreferencesManager sharedManager] nestedWestonBackend];
  BOOL wantDrm = NO;
  if ([resolvedBackend isEqualToString:@"drm"]) {
    wantDrm = YES;
  } else if (WWNCompositorBackendCLIOverride() != nil ||
             [prefsBackend isEqualToString:@"wayland"] ||
             [prefsBackend isEqualToString:@"drm"]) {
    // Explicit CLI or Settings choice. Never fall through to legacy.
    wantDrm = [resolvedBackend isEqualToString:@"drm"];
  } else {
    // auto: NestedWestonBackend still selects weston's present path.
    wantDrm = [legacyNested isEqualToString:@"iland-drm-gl"];
  }
  if (wantDrm) {
    WWNLog("WESTON", @"backend=drm. In-process iland DRM path");
    [self launchWestonMacOSDrmInProcess];
    return;
  }

  [self launchWestonMacOSNestedSubprocess];
}

/// Out-of-process nested Weston (`NSTask`). Used for `--backend=wayland` and as
/// the fallback when in-process `weston_main` is unavailable for DRM.
- (void)launchWestonMacOSNestedSubprocess {
  if (self.westonTask.isRunning) {
    return;
  }
  if (self.westonTask && !self.westonTask.isRunning) {
    self.westonTask = nil;
    self.westonRunning = NO;
  }
  if (self.westonRunning) {
    return;
  }

  WWNConfigureBundledRuntimeEnvIfNeeded();
  NSString *envError = [self wwnValidateNestedWestonEnv];
  if (envError) {
    WWNLog("WESTON", @"Refusing to launch nested weston: %@", envError);
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSNotificationCenter defaultCenter]
          postNotificationName:@"WWNNativeClientLaunchFailedNotification"
                        object:self
                      userInfo:@{
                        @"clientId" : @"weston",
                        @"reason" : envError,
                      }];
    });
    return;
  }

  NSString *path = [self findBinaryNamed:@"weston"];
  if (!path) {
    WWNLog("WESTON", @"Could not find weston executable in app bundle.");
    return;
  }

  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];

  uint32_t outW = 1024;
  uint32_t outH = 768;
  float outScale = 1.0f;
  [bridge latestOutputWidth:&outW height:&outH scale:&outScale];
  unsigned hostScale = (unsigned)lrintf(outScale >= 1.0f ? outScale : 1.0f);
  if (hostScale < 1u) {
    hostScale = 1u;
  }

  self.westonRunning = YES;

  // Pixman only for nested Wayland; DRM needs GL against iland.
  NSString *westonBackend = WWNResolveCompositorBackend(nil);
  BOOL usePixman = ![westonBackend isEqualToString:@"drm"];

  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  char configPath[512] = "";
  if (xdg_dir && xdg_dir[0]) {
    snprintf(configPath, sizeof(configPath), "%s/weston.ini", xdg_dir);
    [self wwnWriteWestonIniAtPath:configPath usePixman:usePixman];
  }

  char scaleEnv[32];
  snprintf(scaleEnv, sizeof(scaleEnv), "%u", hostScale);
  setenv("WAWONA_OUTPUT_SCALE", scaleEnv, 1);

  // Backend is configurable, not assumed: weston can drive iland's userspace
  // DRM/KMS instead of nesting. No --width/--height either way. Nested Weston
  // sizes via xdg negotiation with Wawona.
  NSMutableArray<NSString *> *args = [NSMutableArray arrayWithObjects:
      [westonBackend isEqualToString:@"drm"] ? @"--backend=drm"
                                             : @"--backend=wayland",
      // Deterministic nested socket so the Swinging Bridge app bridge can attach. Keep
      // in sync with +preferredNestedSocketName and AnowawSession.NESTED_SOCKET (legacy Kotlin name).
      [NSString stringWithFormat:@"--socket=%@",
                                 [WWNPreferencesManager preferredNestedSocketName]],
      @"--shell=desktop-shell.so",
      [NSString stringWithFormat:@"--scale=%u", hostScale],
      nil];
  (void)outW;
  (void)outH;
  if (configPath[0]) {
    [args addObject:[NSString stringWithFormat:@"--config=%s", configPath]];
  }
  if (usePixman) {
    [args addObject:@"--use-pixman"];
  }

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:path];
  task.arguments = args;

  NSMutableDictionary *env = [self wwnMutableHostWaylandEnvironment];
  task.environment = env;

  WWNLog("WESTON", @"Launch argv: weston %@", [args componentsJoinedByString:@" "]);

  NSError *err = nil;
  if ([task launchAndReturnError:&err]) {
    self.westonTask = task;
    WWNLog("WESTON", @"Launched nested weston with PID %d",
           task.processIdentifier);
    [self wwnPumpHostCompositorAfterNativeClientLaunch];
    [self _installNativeClientTerminationHandler:task kind:@"weston"];
  } else {
    WWNLog("WESTON", @"Failed to launch nested weston: %@", err);
    self.westonRunning = NO;
  }
}

- (void)launchWestonMacOSDrmInProcess {
  if (self.westonRunning) {
    return;
  }
  WWNCompositorBridge *bridge = [WWNCompositorBridge sharedBridge];
  if (![bridge prepareIlandMetalPresentationOnPrimaryView]) {
    WWNLog("WESTON",
           @"Failed to prepare iland Metal presentation. Falling back to "
           @"nested weston subprocess");
    [self launchWestonMacOSNestedSubprocess];
    return;
  }
  typedef int (*WWNWestonMainFn)(int, char **);
  WWNWestonMainFn westonFn =
      (WWNWestonMainFn)(void *)dlsym(RTLD_DEFAULT, "weston_main");
  if (westonFn == NULL) {
    WWNLog("WESTON",
           @"weston_main not linked. Iland Metal ready (kmscube); "
           @"falling back to nested weston subprocess (--backend=drm)");
    [self launchWestonMacOSNestedSubprocess];
    return;
  }
  self.westonRunning = YES;

  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];
  uint32_t outW = 1024;
  uint32_t outH = 768;
  float outScale = 1.0f;
  [bridge latestOutputWidth:&outW height:&outH scale:&outScale];
  unsigned hostScale = (unsigned)lrintf(outScale >= 1.0f ? outScale : 1.0f);
  if (hostScale < 1u) {
    hostScale = 1u;
  }

  char scaleEnv[32];
  snprintf(scaleEnv, sizeof(scaleEnv), "%u", hostScale);
  setenv("WAWONA_OUTPUT_SCALE", scaleEnv, 1);

  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  char configPath[512] = "";
  char configArg[600] = "";
  if (xdg_dir && xdg_dir[0]) {
    snprintf(configPath, sizeof(configPath), "%s/weston.ini", xdg_dir);
    if ([self wwnWriteWestonIniAtPath:configPath usePixman:NO]) {
      snprintf(configArg, sizeof(configArg), "--config=%s", configPath);
    }
  }

  typedef struct {
    char scale[32];
    char config[600];
  } WWNWestonDrmLaunchArgs;

  WWNWestonDrmLaunchArgs *launchArgs = calloc(1, sizeof(WWNWestonDrmLaunchArgs));
  if (!launchArgs) {
    self.westonRunning = NO;
    return;
  }
  // No --width/--height: DRM/iland output size follows host view via
  // runtime wl_output updates, not launch argv.
  (void)outW;
  (void)outH;
  snprintf(launchArgs->scale, sizeof(launchArgs->scale), "--scale=%u", hostScale);
  if (configArg[0]) {
    strncpy(launchArgs->config, configArg, sizeof(launchArgs->config) - 1);
  }

  WWNWestonMainFn westonFnForBlock = westonFn;

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    WWNWestonDrmLaunchArgs *args = launchArgs;
    char *argv_weston[] = {
        (char *)"weston",
        (char *)"--backend=drm",
        /* Deterministic nested socket so the Swinging Bridge app bridge can attach
         * regardless of backend. */
        (char *)"--socket=wawona-nested",
        (char *)"--shell=desktop-shell.so",
        args->scale,
        args->config[0] ? args->config : NULL,
        NULL,
    };
    int argc_weston = args->config[0] ? 6 : 5;
    WWNLog("WESTON", @"Starting in-process nested Weston (iland DRM) on macOS");
    int rc = westonFnForBlock(argc_weston, argv_weston);
    WWNLog("WESTON", @"In-process nested Weston (DRM) exited rc=%d", rc);
    free(args);
    dispatch_async(dispatch_get_main_queue(), ^{
      self.westonRunning = NO;
    });
  });

  [self wwnPumpHostCompositorAfterNativeClientLaunch];
}
#endif

- (void)launchWeston {
  // Nested Weston keeps a single preferred nested socket; treat as singleton.
  if (self.westonRunning) {
    return;
  }
#if TARGET_OS_IPHONE
  // Legacy weston-specific key wins when explicitly set; otherwise fall back to
  // the general per-client backend choice so weston and niri behave the same.
  NSString *backend =
      [[WWNPreferencesManager sharedManager] nestedWestonBackend];
  // wayland-pixman / wayland-* → nested Wayland client of the host compositor
  // (the path that paints a Weston desktop on iOS Simulator).
  BOOL wantDrm = [backend isEqualToString:@"iland-drm-gl"] ||
                 [backend isEqualToString:@"drm"] ||
                 [WWNResolveCompositorBackend(nil) isEqualToString:@"drm"];
  if (wantDrm) {
    [self launchWestonDrm];
    return;
  }
  [self wwnLaunchWestonCompositorWithBackend:"--backend=wayland"
                                   usePixman:YES
                                prepareIland:NO];
#else
  [self launchWestonMacOSAsNestedClient];
#endif
}

- (void)launchWestonDrm {
#if TARGET_OS_IPHONE
  [self wwnLaunchWestonCompositorWithBackend:"--backend=drm"
                                   usePixman:NO
                                prepareIland:YES];
#endif
}

#if TARGET_OS_IPHONE
- (void)launchNiri {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    CFAbsoluteTime launchStart = CFAbsoluteTimeGetCurrent();
    if (![self wwnBeginIOSNativeClientLaunch:@"niri"]) {
      return;
    }

    // niri spawns its own clients (fuzzel, terminals) which need a coherent
    // rootfs HOME + XDG dirs. Mirror the in-process weston launch: without
    // this, WAWONA_ROOTFS/HOME/XDG_*_HOME are unset unless another client ran
    // first, and niri's children write to an incoherent FS.
    [WWNRootfsProvider applyShellEnvironment];

    const char *parent_display = getenv("WAYLAND_DISPLAY");
    if (!parent_display || parent_display[0] == '\0') {
      parent_display = "wayland-0";
    }
    setenv("WAYLAND_DISPLAY", parent_display, 1);
    wwnConfigureNiriNestedEnv();
    // Surface niri panics/errors in Simulator Console (host reads stderr).
    if (!getenv("RUST_BACKTRACE") || !getenv("RUST_BACKTRACE")[0]) {
      setenv("RUST_BACKTRACE", "1", 0);
    }
    if (!getenv("RUST_LOG") || !getenv("RUST_LOG")[0]) {
      setenv("RUST_LOG", "niri=debug,smithay::backend::egl=info", 0);
    }

    char saved_cwd[512] = "";
    const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_dir && xdg_dir[0]) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      if (chdir(xdg_dir) != 0) {
        WWNLog("NIRI", @"WARN: chdir(XDG_RUNTIME_DIR=%s) failed errno=%d",
               xdg_dir, errno);
      }
    }

    WWNLog("NIRI",
           @"Launching in-process niri_main (nested) WAYLAND_DISPLAY=%s "
           @"XDG_RUNTIME_DIR=%s NIRI_CONFIG=%s DYLD_LIBRARY_PATH=%s",
           getenv("WAYLAND_DISPLAY") ?: "(null)",
           getenv("XDG_RUNTIME_DIR") ?: "(null)",
           getenv("NIRI_CONFIG") ?: "(null)",
           getenv("DYLD_LIBRARY_PATH") ?: "(null)");
    if (!niri_main) {
      WWNLog("NIRI",
             @"niri_main not linked in this build. Nested niri unavailable");
      if (saved_cwd[0]) {
        chdir(saved_cwd);
      }
      [self wwnEndIOSNativeClientLaunch];
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"WWNNativeClientLaunchFailedNotification"
                          object:self
                        userInfo:@{
                          @"clientId" : @"niri",
                          @"reason" : @"niri_main not linked",
                        }];
      });
      return;
    }

    int result = niri_main();
    WWNLog("NIRI", @"niri_main exit code: %d (total %.0fms)", result,
           (CFAbsoluteTimeGetCurrent() - launchStart) * 1000.0);
    if (saved_cwd[0]) {
      chdir(saved_cwd);
    }
    [self wwnEndIOSNativeClientLaunch];
    if (result != 0) {
      NSString *reason =
          [NSString stringWithFormat:@"niri_main exited %d (see stderr for "
                                     @"niri_main: fatal/panicked)",
                                     result];
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"WWNNativeClientLaunchFailedNotification"
                          object:self
                        userInfo:@{
                          @"clientId" : @"niri",
                          @"reason" : reason,
                          @"exitCode" : @(result),
                        }];
      });
    }
  });
}
#endif

- (void)stopWeston {
#if TARGET_OS_IPHONE
  wwn_weston_compositor_shutdown_requested = 1;
  [[WWNCompositorBridge sharedBridge] tearDownActiveIOSCompositorViews];
  self.westonRunning = NO;
  self.iosNativeClientInFlightCount = 0;
  self.activeIOSBundledClientId = nil;
#else
  if (self.westonTask) {
    [self.westonTask terminate];
    self.westonTask = nil;
  }
  self.westonMachineId = nil;
  self.westonRunning = NO;
#endif
}

// MARK: - Weston Terminal
- (void)launchWestonTerminal {
  [self _launchWestonTerminalWithMachineId:nil];
}

- (void)_launchWestonTerminalWithMachineId:(NSString *)machineId {
#if TARGET_OS_IPHONE
  NSString *boundMachineId = [machineId copy];
  if (wwn_weston_terminal_is_compat_shim &&
      wwn_weston_terminal_is_compat_shim() != 0) {
    WWNLog("WESTON_TERM", @"Refusing to launch 'weston-terminal': compatibility shim routes to weston-simple-shm.");
    if (boundMachineId.length > 0) {
      [self.iosRunningMachineIds removeObject:boundMachineId];
    }
    return;
  }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    if (![self wwnBeginIOSNativeClientLaunch:@"weston-terminal"]) {
      if (boundMachineId.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.iosRunningMachineIds removeObject:boundMachineId];
        });
      }
      return;
    }
    self.westonTerminalRunning = YES;

    [WWNRootfsProvider applyShellEnvironment];

    // Ensure zsh starts in HOME so prompt shortening (%~) resolves to "~"
    // instead of showing the full sandbox absolute path.
    char saved_cwd[512] = "";
    const char *home_dir = getenv("HOME");
    if (home_dir && home_dir[0]) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      chdir(home_dir);
    }

    const char *shell = getenv("WAWONA_SHELL");
    char *argv_term[] = {
        "weston-terminal",
        "--shell",
        (char *)(shell && shell[0] ? shell : "/usr/bin/zsh"),
        NULL,
    };
    WWNLog("WESTON_TERM",
           @"Launching iOS weston-terminal instance (in-process zsh via "
           @"libwawona-zsh.a, label=%s, inFlight=%ld)...",
           argv_term[2], (long)self.iosNativeClientInFlightCount);
    // Join on this GCD worker until the client exits so in-flight count /
    // westonTerminalRunning stay accurate for the whole session. Multiple
    // workers may run concurrently for multiple Machines profiles.
    wwn_launch_host_client(argv_term, environ);
    WWNLog("WESTON_TERM", @"weston-terminal client thread finished");

    if (saved_cwd[0]) {
      chdir(saved_cwd);
    }

    [self wwnEndIOSNativeClientLaunch];
    if (boundMachineId.length > 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.iosRunningMachineIds removeObject:boundMachineId];
      });
    }
    if (self.iosNativeClientInFlightCount == 0) {
      self.westonTerminalRunning = NO;
    }
  });
#else
  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];
  NSString *path = [self findBinaryNamed:@"weston-terminal"];
  if (!path) {
    WWNLog("WESTON_TERM", @"Could not find weston-terminal in app bundle.");
    return;
  }

  // ---- Shell title environment setup ----
  // weston-terminal handles OSC 0/2 escape codes from the shell and calls
  // xdg_toplevel_set_title(), but macOS shells don't send them by default.
  // Set up ZDOTDIR (zsh) and PROMPT_COMMAND (bash) so the shell sends
  // OSC 0 title updates on every prompt, making cd/pwd visible in the
  // window title.
  NSString *zdotdir =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"wawona-zdotdir"];
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:zdotdir
      withIntermediateDirectories:YES
                      attributes:nil
                           error:nil];

  // .zshenv. Source the user's original .zshenv so PATH etc. are intact
  NSString *zshenv =
      @"_wz=\"${_WAWONA_ORIG_ZDOTDIR:-$HOME}\"\n"
      @"[ -f \"$_wz/.zshenv\" ] && . \"$_wz/.zshenv\"\n"
      @"unset _wz\n";

  // .zshrc. Source the user's original .zshrc, then add OSC 0 title hook
  NSString *zshrc =
      @"_wz=\"${_WAWONA_ORIG_ZDOTDIR:-$HOME}\"\n"
      @"[ -f \"$_wz/.zshrc\" ] && . \"$_wz/.zshrc\"\n"
      @"unset _wz\n"
      @"precmd() { print -Pn \"\\e]0;%n@%m: %~\\a\" }\n";

  [zshenv writeToFile:[zdotdir stringByAppendingPathComponent:@".zshenv"]
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];
  [zshrc writeToFile:[zdotdir stringByAppendingPathComponent:@".zshrc"]
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:path];

  NSMutableDictionary *env = [self wwnMutableHostWaylandEnvironment];
  NSString *shellPath = WWNPreferredHostShellPath();
  env[@"SHELL"] = shellPath;
  task.arguments = @[ @"--shell", shellPath ];

  // Preserve original ZDOTDIR for the .zshenv/.zshrc wrappers
  if (env[@"ZDOTDIR"])
    env[@"_WAWONA_ORIG_ZDOTDIR"] = env[@"ZDOTDIR"];
  env[@"ZDOTDIR"] = zdotdir;

  // bash: set PROMPT_COMMAND if not already set
  if (!env[@"PROMPT_COMMAND"]) {
    env[@"PROMPT_COMMAND"] =
        @"printf '\\033]0;%s@%s:%s\\007' \"$USER\" \"${HOSTNAME%%.*}\" "
        @"\"${PWD/#$HOME/~}\"";
  }

  task.environment = env;
  // AppKit process cwd is often "/"; start the shell in HOME.
  {
    NSString *homeDir = env[@"HOME"];
    if (homeDir.length == 0)
      homeDir = NSHomeDirectory();
    if (homeDir.length > 0)
      task.currentDirectoryURL = [NSURL fileURLWithPath:homeDir];
  }
  NSError *err;
  if ([task launchAndReturnError:&err]) {
    WWNLog("WESTON_TERM", @"Launched weston-terminal with PID %d (shell=%@)",
           task.processIdentifier, shellPath);
    [self wwnPumpHostCompositorAfterNativeClientLaunch];
    [self _registerNativeTask:task
                     clientId:@"weston-terminal"
                    machineId:machineId];
  } else {
    WWNLog("WESTON_TERM", @"Failed to launch weston-terminal: %@", err);
  }
#endif
}

- (void)stopWestonTerminal {
#if TARGET_OS_IPHONE
  [[WWNCompositorBridge sharedBridge] tearDownActiveIOSCompositorViews];
  self.westonTerminalRunning = NO;
  self.iosNativeClientInFlightCount = 0;
  self.activeIOSBundledClientId = nil;
#else
  [self _terminateAllNativeTasksWithClientId:@"weston-terminal"];
#endif
}

// MARK: - Foot Terminal

- (void)launchFoot {
  [self _launchFootWithMachineId:nil];
}

- (void)_launchFootWithMachineId:(NSString *)machineId {
#if TARGET_OS_IPHONE
  NSString *boundMachineId = [machineId copy];
  if (wwn_foot_is_compat_shim && wwn_foot_is_compat_shim() != 0) {
    // Legacy APKs/archives only. Refuse silent weston-terminal substitution -
    // real foot must be force_loaded (wwn_foot_is_compat_shim == 0).
    WWNLog("FOOT",
           @"Refusing foot launch: compatibility shim still linked "
           @"(rebuild with wwn-foot apple-mobile).");
    return;
  }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    if (![self wwnBeginIOSNativeClientLaunch:@"foot"]) {
      if (boundMachineId.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.iosRunningMachineIds removeObject:boundMachineId];
        });
      }
      return;
    }
    self.footRunning = YES;

    [WWNRootfsProvider applyShellEnvironment];
    WWNConfigureBundledRuntimeEnvIfNeeded();
    setenv("TERM", "xterm-256color", 1);
    setenv("COLORTERM", "truecolor", 1);

    char saved_cwd[512] = "";
    const char *home_dir = getenv("HOME");
    if (home_dir && home_dir[0]) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      chdir(home_dir);
    }

    // Match macOS/Android: explicit foot.ini + monospace face so fcft does
    // not resolve to a blank window on first frame.
    NSString *runtimeDir = NSTemporaryDirectory();
    const char *xdg = getenv("XDG_RUNTIME_DIR");
    if (xdg && xdg[0]) {
      runtimeDir = @(xdg);
    }
    NSString *iniPath =
        [runtimeDir stringByAppendingPathComponent:@"wawona-foot.ini"];
    NSString *fontDir = WWNWawonaBundledSharePath(@"fonts");
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *monoTtf = [fontDir
        stringByAppendingPathComponent:
            @"truetype/DejaVuSansMNerdFontMono-Regular.ttf"];
    if (![fm fileExistsAtPath:monoTtf]) {
      monoTtf =
          [fontDir stringByAppendingPathComponent:@"truetype/DejaVuSansMono.ttf"];
    }
#if TARGET_OS_OSX
    CGFloat fontSize = [NSFont systemFontSize];
#elif TARGET_OS_IOS
    CGFloat fontSize = [UIFont systemFontSize];
#else
    CGFloat fontSize = 17.0;
#endif
    NSString *fontSpec = [fm fileExistsAtPath:monoTtf]
                             ? [NSString stringWithFormat:@"DejaVuSansM Nerd Font Mono:size=%.1f", fontSize]
                             : [NSString stringWithFormat:@"monospace:size=%.1f", fontSize];
    NSString *ini = [NSString
        stringWithFormat:@"[main]\n"
                          "term=xterm-256color\n"
                          "font=%@\n"
                          "dpi-aware=yes\n"
                          "letter-spacing=0\n"
                          "\n"
                          "[tweak]\n"
                          "font-monospace-warn=no\n"
                          "\n"
                          "[key-bindings]\n"
                          "clipboard-copy=Super+c\n"
                          "clipboard-paste=Super+v\n",
                         fontSpec];
    [ini writeToFile:iniPath
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];

    const char *shell = getenv("WAWONA_SHELL");
    if (!shell || !shell[0]) {
      shell = "/usr/bin/zsh";
    }
    char *argv_foot[] = {
        "foot",
        "-t",
        "xterm-256color",
        "-o",
        "tweak.font-monospace-warn=no",
        "-c",
        (char *)iniPath.fileSystemRepresentation,
        (char *)shell,
        NULL,
    };
    WWNLog("FOOT", @"Launching in-process foot_main (shell=%s ini=%@)...",
           shell, iniPath);
    int result = foot_main(8, argv_foot);
    WWNLog("FOOT", @"foot_main exit code: %d", result);

    if (saved_cwd[0])
      chdir(saved_cwd);

    [self wwnEndIOSNativeClientLaunch];
    if (boundMachineId.length > 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.iosRunningMachineIds removeObject:boundMachineId];
      });
    }
    if (self.iosNativeClientInFlightCount == 0) {
      self.footRunning = NO;
    }
  });
#else
  [WWNMachineProfileStore applyActiveMachineToRuntimePrefs];

  // Prefer the real Mach-O (.foot-wrapped) over the shell wrapper. The
  // wrapper shebang points at a nix-store bash that may be unavailable when
  // the app is relocated, which surfaces as an instant black/empty session.
  NSString *path = [self findBinaryNamed:@".foot-wrapped"];
  if (!path) {
    path = [self findBinaryNamed:@"foot"];
  }
  if (!path) {
    WWNLog("FOOT", @"Could not find foot in app bundle.");
    return;
  }

  // Ensure fontconfig + DejaVu aliases exist before fcft probes monospace.
  WWNConfigureBundledRuntimeEnvIfNeeded();

  NSString *fontDir = WWNWawonaBundledSharePath(@"fonts");
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *monoTtf = [fontDir
      stringByAppendingPathComponent:
          @"truetype/DejaVuSansMNerdFontMono-Regular.ttf"];
  if (![fm fileExistsAtPath:monoTtf]) {
    monoTtf =
        [fontDir stringByAppendingPathComponent:@"truetype/DejaVuSansMono.ttf"];
  }
  if (![fm fileExistsAtPath:monoTtf]) {
    WWNLog("FOOT", @"Missing bundled mono font at %@. Text will be blank",
           monoTtf);
  }

  NSString *runtimeDir = NSTemporaryDirectory();
  const char *xdg = getenv("XDG_RUNTIME_DIR");
  if (xdg && xdg[0]) {
    runtimeDir = @(xdg);
  }
  NSString *iniPath =
      [runtimeDir stringByAppendingPathComponent:@"wawona-foot.ini"];
#if TARGET_OS_OSX
  CGFloat fontSize = [NSFont systemFontSize];
#elif TARGET_OS_IOS
  CGFloat fontSize = [UIFont systemFontSize];
#else
  CGFloat fontSize = 17.0;
#endif
  NSString *fontSpec = [fm fileExistsAtPath:monoTtf]
                           ? [NSString stringWithFormat:@"DejaVuSansM Nerd Font Mono:size=%.1f", fontSize]
                           : [NSString stringWithFormat:@"monospace:size=%.1f", fontSize];
  NSString *ini = [NSString
      stringWithFormat:
          @"[main]\n"
           "term=xterm-256color\n"
           "font=%@\n"
           "dpi-aware=yes\n"
           "letter-spacing=0\n"
           "\n"
           "[tweak]\n"
           "font-monospace-warn=no\n"
           "\n"
           "[key-bindings]\n"
           "clipboard-copy=Super+c\n"
           "clipboard-paste=Super+v\n",
          fontSpec];
  NSError *iniErr = nil;
  if (![ini writeToFile:iniPath
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&iniErr]) {
    WWNLog("FOOT", @"Failed to write %@: %@", iniPath, iniErr);
  }

  NSMutableDictionary *env = [self wwnMutableHostWaylandEnvironment];
  NSString *shellPath = WWNPreferredHostShellPath();
  env[@"SHELL"] = shellPath;
  // Foot's default TERM is "foot". macOS has no foot terminfo in the sandbox
  // (and often none on the host), so shells print "unknown terminal type" and
  // erase/clear/completion redraw break. Force a terminfo that exists.
  env[@"TERM"] = @"xterm-256color";
  env[@"COLORTERM"] = @"truecolor";
  if ([fm fileExistsAtPath:monoTtf]) {
    env[@"WAWONA_MONO_FONT"] = monoTtf;
  }
  const char *fcFile = getenv("FONTCONFIG_FILE");
  if (fcFile && fcFile[0]) {
    env[@"FONTCONFIG_FILE"] = @(fcFile);
  }
  const char *fcPath = getenv("FONTCONFIG_PATH");
  if (fcPath && fcPath[0]) {
    env[@"FONTCONFIG_PATH"] = @(fcPath);
  }

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:path];
  // -c config; -t TERM for child shell; -o suppress monospace warn; then shell.
  task.arguments = @[
    @"-t", @"xterm-256color", @"-o", @"tweak.font-monospace-warn=no", @"-c",
    iniPath, shellPath
  ];
  task.environment = env;
  // AppKit process cwd is often "/"; start the shell in HOME.
  {
    NSString *homeDir = env[@"HOME"];
    if (homeDir.length == 0)
      homeDir = NSHomeDirectory();
    if (homeDir.length > 0)
      task.currentDirectoryURL = [NSURL fileURLWithPath:homeDir];
  }

  NSError *err = nil;
  if ([task launchAndReturnError:&err]) {
    WWNLog("FOOT", @"Launched foot PID %d (bin=%@ font=%@ shell=%@)",
           task.processIdentifier, path, fontSpec, shellPath);
    [self wwnPumpHostCompositorAfterNativeClientLaunch];
    [self _registerNativeTask:task clientId:@"foot" machineId:machineId];
  } else {
    WWNLog("FOOT", @"Failed to launch foot: %@", err);
  }
#endif
}

- (void)stopFoot {
#if TARGET_OS_IPHONE
  [[WWNCompositorBridge sharedBridge] tearDownActiveIOSCompositorViews];
  self.footRunning = NO;
  self.iosNativeClientInFlightCount = 0;
  self.activeIOSBundledClientId = nil;
#else
  [self _terminateAllNativeTasksWithClientId:@"foot"];
#endif
}

@end
