//
//  WWNExternalDisplaySupport.m
//  Wawona — iOS AirPlay / external display mirroring. See header.
//

#import "WWNExternalDisplaySupport.h"
#import "../../util/WWNLog.h"
#import "WWNCompositorBridge.h"

NSNotificationName const WWNExternalDisplayDidConnectNotification =
    @"WWNExternalDisplayDidConnectNotification";
NSNotificationName const WWNExternalDisplayDidDisconnectNotification =
    @"WWNExternalDisplayDidDisconnectNotification";
NSNotificationName const WWNVirtualCursorStateNotification =
    @"WWNVirtualCursorStateNotification";

static BOOL gExternalDisplayConnected = NO;

BOOL WWNExternalDisplayIsConnected(void) { return gExternalDisplayConnected; }

// ---------------------------------------------------------------------------
#pragma mark - WWNExternalMirrorView
// ---------------------------------------------------------------------------

@implementation WWNExternalMirrorView {
  NSMutableDictionary<NSNumber *, CALayer *> *_windowLayers;
  CALayer *_cursorLayer;
  CGSize _lastContainerSize;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.blackColor;
    self.userInteractionEnabled = NO;
    _windowLayers = [NSMutableDictionary dictionary];
    _lastContainerSize = CGSizeZero;

    _cursorLayer = [CALayer layer];
    _cursorLayer.zPosition = 10000;
    _cursorLayer.hidden = YES;
    _cursorLayer.contentsGravity = kCAGravityResize;
    [self.layer addSublayer:_cursorLayer];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_cursorStateChanged:)
               name:WWNVirtualCursorStateNotification
             object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Aspect-fit mapping from container space to this view's bounds.
- (CGAffineTransform)_fitTransformForContainerSize:(CGSize)containerSize
                                          outScale:(CGFloat *)outScale {
  CGSize bounds = self.bounds.size;
  if (containerSize.width <= 0 || containerSize.height <= 0 ||
      bounds.width <= 0 || bounds.height <= 0) {
    if (outScale) {
      *outScale = 1.0;
    }
    return CGAffineTransformIdentity;
  }
  CGFloat scale = MIN(bounds.width / containerSize.width,
                      bounds.height / containerSize.height);
  CGFloat offsetX = (bounds.width - containerSize.width * scale) / 2.0;
  CGFloat offsetY = (bounds.height - containerSize.height * scale) / 2.0;
  if (outScale) {
    *outScale = scale;
  }
  CGAffineTransform t = CGAffineTransformMakeTranslation(offsetX, offsetY);
  return CGAffineTransformScale(t, scale, scale);
}

- (void)mirrorWindow:(uint64_t)windowId
               image:(CGImageRef)image
               frame:(CGRect)frame
         contentRect:(CGRect)contentRect
       containerSize:(CGSize)containerSize
       contentsScale:(CGFloat)contentsScale
     contentsGravity:(NSString *)contentsGravity {
  if (!image) {
    [self removeWindow:windowId];
    return;
  }
  _lastContainerSize = containerSize;
  NSNumber *key = @(windowId);
  CALayer *layer = _windowLayers[key];
  if (!layer) {
    layer = [CALayer layer];
    layer.masksToBounds = YES;
    layer.minificationFilter = kCAFilterLinear;
    layer.magnificationFilter = kCAFilterLinear;
    _windowLayers[key] = layer;
    [self.layer insertSublayer:layer below:_cursorLayer];
  }
  CGAffineTransform fit =
      [self _fitTransformForContainerSize:containerSize outScale:NULL];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  layer.frame = CGRectApplyAffineTransform(frame, fit);
  layer.contentsGravity = contentsGravity;
  layer.contentsScale = contentsScale > 0 ? contentsScale : 1.0;
  layer.contentsRect = contentRect;
  layer.contents = (__bridge id)image;
  [CATransaction commit];
}

- (void)removeWindow:(uint64_t)windowId {
  NSNumber *key = @(windowId);
  CALayer *layer = _windowLayers[key];
  if (layer) {
    [layer removeFromSuperlayer];
    [_windowLayers removeObjectForKey:key];
  }
}

- (void)_cursorStateChanged:(NSNotification *)note {
  NSDictionary *info = note.userInfo;
  NSNumber *hidden = info[@"hidden"];
  if (hidden.boolValue) {
    _cursorLayer.hidden = YES;
    return;
  }
  NSValue *posVal = info[@"position"];
  CGFloat w = [info[@"width"] doubleValue];
  CGFloat h = [info[@"height"] doubleValue];
  id contents = info[@"contents"];
  CGFloat scale = 1.0;
  CGAffineTransform fit =
      [self _fitTransformForContainerSize:_lastContainerSize outScale:&scale];
  CGPoint pos = CGPointApplyAffineTransform(posVal.CGPointValue, fit);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (contents) {
    _cursorLayer.contents = contents;
  }
  if (w > 0 && h > 0) {
    _cursorLayer.bounds = CGRectMake(0, 0, w * scale, h * scale);
  }
  _cursorLayer.position = pos;
  _cursorLayer.hidden = (_cursorLayer.contents == nil);
  [CATransaction commit];
}

@end

// ---------------------------------------------------------------------------
#pragma mark - WWNExternalSceneDelegate
// ---------------------------------------------------------------------------

@implementation WWNExternalSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
  (void)session;
  (void)connectionOptions;
  if (![scene isKindOfClass:[UIWindowScene class]]) {
    return;
  }
  UIWindowScene *windowScene = (UIWindowScene *)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  WWNExternalMirrorView *mirror =
      [[WWNExternalMirrorView alloc] initWithFrame:self.window.bounds];
  mirror.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view = mirror;
  self.window.rootViewController = vc;
  [self.window makeKeyAndVisible];

  gExternalDisplayConnected = YES;
  [WWNCompositorBridge sharedBridge].externalMirrorView = mirror;
  // TODO: set self.window to external display window, use external display bounds
  // Or discard these changes if WWNCompositorBridge changes makes this redundant
  WWNLog("EXTDISPLAY", @"External display connected: %.0fx%.0f",
         self.window.bounds.size.width, self.window.bounds.size.height);
  [[NSNotificationCenter defaultCenter]
      postNotificationName:WWNExternalDisplayDidConnectNotification
                    object:nil];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
  (void)scene;
  gExternalDisplayConnected = NO;
  [WWNCompositorBridge sharedBridge].externalMirrorView = nil;
  self.window = nil;
  WWNLog("EXTDISPLAY", @"External display disconnected");
  [[NSNotificationCenter defaultCenter]
      postNotificationName:WWNExternalDisplayDidDisconnectNotification
                    object:nil];
}

@end
