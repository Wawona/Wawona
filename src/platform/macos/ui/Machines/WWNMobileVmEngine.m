#import "WWNMobileVmEngine.h"

#import "WWNQemuSystem.h"

#import <TargetConditionals.h>

#if TARGET_OS_OSX
@implementation WWNMobileVmEngine
+ (instancetype)sharedEngine { return [WWNMobileVmEngine new]; }
- (BOOL)isEngineAvailable { return NO; }
- (BOOL)launchProfileWithKernelPath:(NSString *)k rootfsPath:(NSString *)r memoryMB:(unsigned)m
                              error:(NSError **)e {
  (void)k; (void)r; (void)m;
  if (e) {
    *e = [NSError errorWithDomain:@"WWNMobileVmEngine" code:0
                         userInfo:@{NSLocalizedDescriptionKey : @"Use WWNVirtualMachineRunner on macOS."}];
  }
  return NO;
}
- (void)stop {}
@end
#else

#import <pthread.h>
#import <unistd.h>
#import <os/log.h>

extern int waypipe_main(int argc, char **argv);

static NSString *WWNMobileGuestBundlePath(void) {
  NSURL *url = [[NSBundle mainBundle] URLForResource:@"wawona-mobile-guest" withExtension:nil];
  return url.path;
}

@interface WWNMobileVmEngine ()
@property(nonatomic, strong, nullable) WWNQemuSystem *qemu;
@property(nonatomic, assign) pthread_t waypipeThread;
@property(nonatomic, assign) BOOL waypipeRunning;
@end

@implementation WWNMobileVmEngine

+ (instancetype)sharedEngine {
  static WWNMobileVmEngine *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [WWNMobileVmEngine new];
  });
  return shared;
}

- (BOOL)isEngineAvailable {
  NSString *fw = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:
          @"Frameworks/qemu-aarch64-softmmu.framework/qemu-aarch64-softmmu"];
  return [[NSFileManager defaultManager] fileExistsAtPath:fw];
}

static void *WWNMobileWaypipeThread(void *ctx) {
  char *socketPath = (char *)ctx;
  const char *display = getenv("WAYLAND_DISPLAY");
  if (!display) {
    display = "wayland-0";
  }
  char *argv[] = {"waypipe", "client", "--socket", socketPath, "--display",
                  (char *)display, NULL};
  waypipe_main(5, argv);
  free(socketPath);
  return NULL;
}

- (BOOL)launchProfileWithKernelPath:(NSString *)kernelPath
                         rootfsPath:(NSString *)rootfsPath
                           memoryMB:(unsigned)memoryMB
                              error:(NSError *_Nullable *_Nullable)error {
  if (![self isEngineAvailable]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNMobileVmEngine"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"QEMU-TCTI engine frameworks are not embedded in this build. "
                       @"Build wwn-vms-mobile-engine-ios-tci and run the Xcode embed phase."
                 }];
    }
    return NO;
  }
  if (kernelPath.length == 0 || rootfsPath.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"WWNMobileVmEngine" code:2
                               userInfo:@{NSLocalizedDescriptionKey : @"Missing guest kernel or rootfs."}];
    }
    return NO;
  }

  [self stop];

  NSString *vsockSocket =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"wawona-mobile-vsock.sock"];
  [[NSFileManager defaultManager] removeItemAtPath:vsockSocket error:nil];

  {
    self.waypipeRunning = YES;
    char *socketPath = strdup(vsockSocket.UTF8String);
    // pthread_create needs the address of the backing ivar; &self.waypipeThread
    // (a property expression) is not addressable.
    pthread_create(&_waypipeThread, NULL, WWNMobileWaypipeThread, socketPath);
  }

  WWNQemuSystem *qemu = [[WWNQemuSystem alloc] initWithArguments:@[]
                                                    architecture:@"aarch64"];
  qemu.currentDirectoryUrl = [NSURL fileURLWithPath:
      [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks"]];
  [qemu clearArgv];
  [qemu pushArgv:@"-machine"];
  [qemu pushArgv:@"virt"];
  [qemu pushArgv:@"-cpu"];
  [qemu pushArgv:@"max"];
  [qemu pushArgv:@"-m"];
  [qemu pushArgv:[NSString stringWithFormat:@"%u", memoryMB]];
  [qemu pushArgv:@"-kernel"];
  [qemu pushArgv:kernelPath];
  [qemu pushArgv:@"-drive"];
  [qemu pushArgv:[NSString stringWithFormat:@"file=%@,if=virtio,format=raw", rootfsPath]];
  [qemu pushArgv:@"-device"];
  [qemu pushArgv:@"virtio-rng-pci"];
  [qemu pushArgv:@"-chardev"];
  [qemu pushArgv:[NSString stringWithFormat:@"socket,path=%@,server=on,wait=off,id=vsock0",
                                            vsockSocket]];
  [qemu pushArgv:@"-device"];
  [qemu pushArgv:@"vhost-user-vsock-pci,chardev=vsock0"];
  [qemu pushArgv:@"-nographic"];
  [qemu pushArgv:@"-no-reboot"];

  NSMutableDictionary<NSString *, NSString *> *env = [@{
    @"ANGLE_DEFAULT_PLATFORM" : @"metal",
  } mutableCopy];
  NSString *runtime = [NSString stringWithFormat:@"/tmp/wawona-%d", getuid()];
  env[@"XDG_RUNTIME_DIR"] = runtime;
  qemu.environment = env;

  self.qemu = qemu;
  [qemu startQemuWithCompletion:^(NSError *err) {
    if (err) {
      os_log_error(OS_LOG_DEFAULT, "QEMU exited: %{public}@", err.localizedDescription);
    }
  }];
  return YES;
}

- (void)stop {
  [self.qemu stopQemu];
  self.qemu = nil;
  self.waypipeRunning = NO;
}

@end
#endif
