#import "WWNRelay.h"

#import "WWNContainerRunner.h"
#import "WWNVirtualMachineRunner.h"
#import "WWNWaypipeRunner.h"

#import <TargetConditionals.h>
#import <string.h>
#import <unistd.h>
#if TARGET_OS_IPHONE && defined(WWN_MODE_B) && WWN_MODE_B
#import "../../../ios/WWNModeBDesktop.h"
#import <IOSurface/IOSurfaceRef.h>
#endif

#if __has_include("wawona_relay.h")
#include "wawona_relay.h"
#define WWN_RELAY_ABI 1
#else
#define WWN_RELAY_ABI 0
#endif

@interface WWNRelay ()
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, NSString *> *backendsByMachineId;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, NSString *> *handlesByMachineId;
#if TARGET_OS_IPHONE && defined(WWN_MODE_B) && WWN_MODE_B
@property(nonatomic, strong) dispatch_source_t frameSource;
@property(nonatomic, copy) NSString *frameHandle;
@property(nonatomic, assign) NSInteger frameFails;
@property(nonatomic, assign) NSInteger framePresents;
@property(nonatomic, assign) IOSurfaceRef frameSurface;
@property(nonatomic, assign) uint32_t frameSurfaceW;
@property(nonatomic, assign) uint32_t frameSurfaceH;
#endif
@end

@implementation WWNRelay

+ (instancetype)sharedRelay {
  static WWNRelay *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [WWNRelay new];
  });
  return shared;
}

- (instancetype)init {
  if ((self = [super init])) {
    _backendsByMachineId = [NSMutableDictionary dictionary];
    _handlesByMachineId = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSString *)platformToken {
#if TARGET_OS_OSX
  return @"macos";
#elif TARGET_OS_IOS
  return @"ios";
#elif TARGET_OS_TV
  return @"tvos";
#elif TARGET_OS_WATCH
  return @"watchos";
#elif TARGET_OS_VISION
  return @"visionos";
#else
  return @"ios";
#endif
}

- (NSString *)artifactClass {
#if defined(WWN_MODE_B) && WWN_MODE_B
  return @"mode_b";
#else
  return @"mode_a";
#endif
}

- (NSString *)kindForProfile:(WWNMachineProfile *)profile {
  NSString *t = profile.type ?: @"";
  if ([t isEqualToString:@"virtual_machine"])
    return @"vm";
  if ([t isEqualToString:@"container"])
    return @"container";
  if ([t isEqualToString:@"wasm"])
    return @"wasm";
  id bundled = profile.runtimeOverrides[@"bundledAppID"];
  NSString *client = [bundled isKindOfClass:[NSString class]] ? (NSString *)bundled : @"";
  if ([client isEqualToString:@"wawona-wasm"] ||
      [client isEqualToString:@"hello-wasi-gui"])
    return @"wasm";
  return @"";
}

- (NSString *)specJSONForProfile:(WWNMachineProfile *)profile kind:(NSString *)kind {
  NSString *image = @"";
  id img = profile.runtimeOverrides[@"imageRef"];
  if ([img isKindOfClass:[NSString class]])
    image = (NSString *)img;
  if (image.length == 0 && [kind isEqualToString:@"container"]) {
    id cref = profile.containerSettings[@"containerRef"];
    if ([cref isKindOfClass:[NSString class]])
      image = (NSString *)cref;
  }
  NSMutableDictionary *obj = [@{
    @"kind" : kind,
    @"platform" : [self platformToken],
    @"artifact" : [self artifactClass],
    @"image" : image ?: @"",
  } mutableCopy];
  if (profile.machineId.length > 0) {
    obj[@"machine_id"] = profile.machineId;
  }
#if TARGET_OS_OSX
  // Relay VZ owns the guest when the app bundle ships launcher + guest.
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *resources = bundle.resourcePath ?: @"";
  NSString *binDir = [resources stringByAppendingPathComponent:@"bin"];
  NSString *launcher =
      [binDir stringByAppendingPathComponent:@"wawona-vz-run"];
  NSString *guestDir =
      [bundle pathForResource:@"wawona-macos-guest" ofType:nil];
  if (guestDir.length == 0) {
    guestDir = [bundle pathForResource:@"wawona-mobile-guest" ofType:nil];
  }
  id guestOverride = profile.runtimeOverrides[@"guestDir"];
  if ([guestOverride isKindOfClass:[NSString class]] &&
      [(NSString *)guestOverride length] > 0) {
    guestDir = (NSString *)guestOverride;
  }
  NSString *stateDir = [NSString
      stringWithFormat:@"/tmp/wawona-%d/relay-state", getuid()];
  NSString *manifestPath =
      [guestDir stringByAppendingPathComponent:@"manifest.json"];
  NSData *manifestData =
      guestDir.length > 0 ? [NSData dataWithContentsOfFile:manifestPath] : nil;
  id manifestJSON =
      manifestData
          ? [NSJSONSerialization JSONObjectWithData:manifestData
                                            options:0
                                              error:nil]
          : nil;
  if ([kind isEqualToString:@"vm"] || [kind isEqualToString:@"container"]) {
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:launcher] &&
        [manifestJSON isKindOfClass:[NSDictionary class]]) {
      obj[@"guest"] = manifestJSON;
      obj[@"resources"] = @{
        @"launcher" : launcher,
        @"state_directory" : stateDir,
        @"guest_directory" : guestDir,
        @"allow_unsigned_guest" : @YES,
      };
      unsigned memoryMB = 2048;
      id memOverride = profile.runtimeOverrides[@"memoryMB"];
      if ([memOverride respondsToSelector:@selector(unsignedIntegerValue)]) {
        memoryMB = (unsigned)[memOverride unsignedIntegerValue];
      }
      obj[@"memory_mb"] = @(memoryMB);
    }
  }
#endif
  NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
              : @"{}";
}

- (BOOL)startProfile:(WWNMachineProfile *)profile
               error:(NSError *_Nullable *_Nullable)error {
  NSString *kind = [self kindForProfile:profile];
  if (kind.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNRelay"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Relay only starts vm, container, or wasm kinds."
                 }];
    }
    return NO;
  }

  NSString *backend = nil;
#if WWN_RELAY_ABI
  NSString *spec = [self specJSONForProfile:profile kind:kind];
  char *out = NULL;
  int rc = relay_resolve_backend(spec.UTF8String, &out);
  if (out) {
    backend = [NSString stringWithUTF8String:out];
    relay_string_free(out);
    out = NULL;
  }
  if (rc == -1) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNRelay"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       backend ?: @"Relay forbids this backend (no QEMU, no UTM)."
                 }];
    }
    return NO;
  }
  if (rc == -2) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNRelay"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       backend ?: @"Relay backend is planned. Fail closed. No QEMU."
                 }];
    }
    return NO;
  }
  if (profile.machineId.length > 0 && backend.length > 0) {
    self.backendsByMachineId[profile.machineId] = backend;
  }
  char *handle = NULL;
  {
    NSString *line =
        [NSString stringWithFormat:@"relay_start begin kind=%@ backend=%@\n",
                                   kind, backend ?: @"(nil)"];
    NSFileHandle *fh =
        [NSFileHandle fileHandleForWritingAtPath:@"/tmp/wwn-modeb-scene.log"];
    if (fh) {
      [fh seekToEndOfFile];
      [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
      [fh closeFile];
    }
  }
  rc = relay_start(spec.UTF8String, &handle);
  NSString *handleOrError = nil;
  if (handle) {
    handleOrError = [NSString stringWithUTF8String:handle];
    relay_string_free(handle);
    handle = NULL;
  }
  {
    NSString *line = [NSString
        stringWithFormat:@"relay_start done rc=%d handle=%@\n", rc,
                         handleOrError ?: @"(null)"];
    NSFileHandle *fh =
        [NSFileHandle fileHandleForWritingAtPath:@"/tmp/wwn-modeb-scene.log"];
    if (fh) {
      [fh seekToEndOfFile];
      [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
      [fh closeFile];
    }
  }
  if (rc == 0) {
    if (profile.machineId.length > 0 && handleOrError.length > 0) {
      self.handlesByMachineId[profile.machineId] = handleOrError;
    }
    // Relay owns the live session. Never fall through to QEMU / legacy runners.
    if ([kind isEqualToString:@"wasm"]) {
      return YES;
    }
    if ([backend isEqualToString:@"vz"] ||
        [backend isEqualToString:@"kvm-ch"] ||
        [backend isEqualToString:@"kvm-crosvm"] ||
        [backend isEqualToString:@"static-cpu"] ||
        [backend isEqualToString:@"mode-b-jit"] ||
        [backend isEqualToString:@"ios-hv"]) {
      if ([backend isEqualToString:@"static-cpu"] ||
          [backend isEqualToString:@"mode-b-jit"]) {
#if TARGET_OS_IPHONE && defined(WWN_MODE_B) && WWN_MODE_B
        NSString *hid = profile.machineId.length > 0
                            ? self.handlesByMachineId[profile.machineId]
                            : nil;
        [self startPresentingHandle:hid];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (self.framePresents == 0) {
            [self startPresentingHandle:hid];
          }
        });
#endif
      }
      return YES;
    }
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNRelay"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:
                           @"Relay started an unknown backend `%@`. No legacy fallback.",
                           backend ?: @"(nil)"]
                 }];
    }
    return NO;
  }
  if (error) {
    *error = [NSError
        errorWithDomain:@"WWNRelay"
                   code:4
               userInfo:@{
                 NSLocalizedDescriptionKey : handleOrError.length > 0
                     ? handleOrError
                     : @"Relay could not start this guest. No QEMU fallback."
               }];
  }
  return NO;
#else
  backend = @"unlinked";

  if ([kind isEqualToString:@"wasm"]) {
    [[WWNWaypipeRunner sharedRunner] launchBundledClientWithId:@"wawona-wasm"
                                                     machineId:profile.machineId];
    return YES;
  }
  if ([kind isEqualToString:@"container"]) {
    return [[WWNContainerRunner sharedRunner] launchProfile:profile error:error];
  }
  return [[WWNVirtualMachineRunner sharedRunner] launchProfile:profile
                                                        error:error];
#endif
}

#if TARGET_OS_IPHONE && defined(WWN_MODE_B) && WWN_MODE_B
- (void)releaseFrameSurface {
  if (self.frameSurface) {
    CFRelease(self.frameSurface);
    self.frameSurface = NULL;
    self.frameSurfaceW = 0;
    self.frameSurfaceH = 0;
  }
}

- (void)stopFrameSource {
  if (self.frameSource) {
    dispatch_source_cancel(self.frameSource);
    self.frameSource = nil;
  }
  [self releaseFrameSurface];
}

- (void)startPresentingHandle:(NSString *)handle {
  {
    NSString *line = [NSString
        stringWithFormat:@"relay present enter handle=%@\n", handle ?: @"(nil)"];
    NSFileHandle *fh =
        [NSFileHandle fileHandleForWritingAtPath:@"/tmp/wwn-modeb-scene.log"];
    if (fh) {
      [fh seekToEndOfFile];
      [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
      [fh closeFile];
    }
  }
  [self stopFrameSource];
  self.frameHandle = handle;
  self.frameFails = 0;
  self.framePresents = 0;
  if (handle.length == 0) {
    NSLog(@"[WWNRelay] Mode B present: empty Relay handle");
    return;
  }
  /* NSTimer pauses once IOMFB owns the panel (scene not ForegroundActive).
     GCD timer still hops to main, same as Mode B lab select. Keep 5 fps
     and reuse one IOSurface: 30 fps full-panel recreate killed vphone. */
  __weak typeof(self) weakSelf = self;
  dispatch_source_t source =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                             dispatch_get_main_queue());
  dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, 0),
                            (uint64_t)(NSEC_PER_SEC / 5),
                            (uint64_t)(NSEC_PER_SEC / 20));
  dispatch_source_set_event_handler(source, ^{
    [weakSelf pumpGuestFrame];
  });
  self.frameSource = source;
  dispatch_resume(source);
  NSLog(@"[WWNRelay] Mode B present: start handle=%@", handle);
  [self pumpGuestFrame];
}

- (void)pumpGuestFrame {
  NSString *handle = self.frameHandle;
  if (handle.length == 0) {
    return;
  }
  uint32_t srcW = 0;
  uint32_t srcH = 0;
  if (relay_copy_frame(handle.UTF8String, NULL, 0, &srcW, &srcH) != 0 ||
      srcW == 0 || srcH == 0) {
    self.frameFails += 1;
    if (self.frameFails == 1 || self.frameFails == 3) {
      NSString *line = [NSString
          stringWithFormat:@"relay present copy meta fail=%ld\n",
                           (long)self.frameFails];
      NSFileHandle *fh =
          [NSFileHandle fileHandleForWritingAtPath:@"/tmp/wwn-modeb-scene.log"];
      if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
      }
    }
    if (self.frameFails >= 3) {
      [self stopFrameSource];
      wwn_modeb_desktop_recover_to_greeter();
    }
    return;
  }
  size_t srcBytes = (size_t)srcW * (size_t)srcH * 4u;
  NSMutableData *pixels = [NSMutableData dataWithLength:srcBytes];
  if (relay_copy_frame(handle.UTF8String, pixels.mutableBytes, srcBytes, &srcW,
                       &srcH) != 0) {
    self.frameFails += 1;
    return;
  }
  /* Same acquire path as the greeter. Do not IOSurfaceCreate a second panel. */
  int32_t rc = wwn_modeb_desktop_present_bgra(pixels.bytes, srcW, srcH);
  if (rc != 0) {
    self.frameFails += 1;
    NSString *line = [NSString
        stringWithFormat:@"relay present bgra rc=%d fail=%ld %ux%u\n", rc,
                         (long)self.frameFails, srcW, srcH];
    NSFileHandle *fh =
        [NSFileHandle fileHandleForWritingAtPath:@"/tmp/wwn-modeb-scene.log"];
    if (fh) {
      [fh seekToEndOfFile];
      [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
      [fh closeFile];
    }
    if (self.frameFails >= 3) {
      [self stopFrameSource];
      wwn_modeb_desktop_recover_to_greeter();
    }
    return;
  }
  self.frameFails = 0;
  self.framePresents += 1;
  uint32_t dstW = 0;
  uint32_t dstH = 0;
  wwn_modeb_desktop_size(&dstW, &dstH);
  NSString *line = [NSString
      stringWithFormat:@"relay present ok #%ld %ux%u from %ux%u handle=%@\n",
                       (long)self.framePresents, dstW, dstH, srcW, srcH,
                       handle];
  NSFileHandle *fh =
      [NSFileHandle fileHandleForWritingAtPath:@"/tmp/wwn-modeb-scene.log"];
  if (!fh) {
    [[NSFileManager defaultManager]
        createFileAtPath:@"/tmp/wwn-modeb-scene.log"
                contents:nil
              attributes:nil];
    fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/wwn-modeb-scene.log"];
  }
  [fh seekToEndOfFile];
  [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
  [fh closeFile];
  NSLog(@"[WWNRelay] Mode B present: ok #%ld %ux%u from %ux%u handle=%@",
        (long)self.framePresents, dstW, dstH, srcW, srcH, handle);
  if (self.framePresents >= 1) {
    [self stopFrameSource];
  }
}
#endif

- (void)stopProfileWithMachineId:(NSString *)machineId {
#if TARGET_OS_IPHONE && defined(WWN_MODE_B) && WWN_MODE_B
  [self stopFrameSource];
  self.frameHandle = nil;
#endif
#if WWN_RELAY_ABI
  NSString *handle = self.handlesByMachineId[machineId];
  if (handle.length > 0)
    relay_stop(handle.UTF8String);
#endif
  [self.handlesByMachineId removeObjectForKey:machineId];
  [self.backendsByMachineId removeObjectForKey:machineId];
  [[WWNVirtualMachineRunner sharedRunner] stopProfileWithMachineId:machineId];
  [[WWNContainerRunner sharedRunner] stopProfileWithMachineId:machineId];
}

- (void)stopAll {
#if TARGET_OS_IPHONE && defined(WWN_MODE_B) && WWN_MODE_B
  [self stopFrameSource];
  self.frameHandle = nil;
#endif
#if WWN_RELAY_ABI
  for (NSString *handle in self.handlesByMachineId.allValues) {
    if (handle.length > 0)
      relay_stop(handle.UTF8String);
  }
#endif
  [self.handlesByMachineId removeAllObjects];
  [self.backendsByMachineId removeAllObjects];
  [[WWNVirtualMachineRunner sharedRunner] stopAll];
  [[WWNContainerRunner sharedRunner] stopAll];
}

- (NSString *)resolvedBackendForMachineId:(NSString *)machineId {
  return self.backendsByMachineId[machineId];
}

@end
