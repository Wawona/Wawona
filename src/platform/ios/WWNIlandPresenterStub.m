// watchOS: no Metal, so no iland GPU presenter (platform-targets matrix).
// tvOS compiles the real WWNIlandPresenter.m (Vulkan/MoltenVK Phase 1).
// Keep this stub so watchOS WWNCompositorView_ios links; methods are no-ops.

#import "WWNIlandPresenter.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if TARGET_OS_WATCH

@implementation WWNIlandPresenter

- (instancetype)initWithLayer:(CAMetalLayer *)layer
                       device:(id<MTLDevice>)device {
  (void)layer;
  (void)device;
  return [super init];
}

- (void)invalidate {
}

- (BOOL)launchNestedIlandGpuClient:(NSString *)clientId
                             width:(int)width
                            height:(int)height {
  (void)clientId;
  (void)width;
  (void)height;
  return NO;
}

- (NSString *)runningClientId {
  return nil;
}

- (BOOL)launchNestedKmscubeWithWidth:(int)width height:(int)height {
  (void)width;
  (void)height;
  return NO;
}

@end

#endif
