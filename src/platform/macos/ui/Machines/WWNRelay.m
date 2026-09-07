#import "WWNRelay.h"

#import "WWNContainerRunner.h"
#import "WWNVirtualMachineRunner.h"
#import "WWNWaypipeRunner.h"

#import <TargetConditionals.h>

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
  NSDictionary *obj = @{
    @"kind" : kind,
    @"platform" : [self platformToken],
    @"artifact" : [self artifactClass],
    @"image" : image,
  };
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
  rc = relay_start(spec.UTF8String, &handle);
  if (handle) {
    NSString *hid = [NSString stringWithUTF8String:handle];
    relay_string_free(handle);
    if (profile.machineId.length > 0 && hid.length > 0) {
      self.handlesByMachineId[profile.machineId] = hid;
    }
  }
  if (rc < 0 && ![kind isEqualToString:@"wasm"] &&
      ![backend isEqualToString:@"vz"]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNRelay"
                     code:4
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Relay could not start this guest. No QEMU fallback."
                 }];
    }
    return NO;
  }
#else
  backend = @"unlinked";
#endif

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
}

- (void)stopProfileWithMachineId:(NSString *)machineId {
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
