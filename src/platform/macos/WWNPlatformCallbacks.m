//  WWNPlatformCallbacks.m
//  Implementation of platform callbacks for Rust compositor

#import "WWNPlatformCallbacks.h"
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import "WWNWindow.h"
#endif
#import "../../util/WWNLog.h"

@implementation WWNPlatformCallbacks

+ (instancetype)sharedCallbacks {
  static WWNPlatformCallbacks *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[WWNPlatformCallbacks alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    _windowRegistry = [NSMutableDictionary dictionary];
#else
    _windowRegistry = [NSMutableDictionary dictionary];
#endif
  }
  return self;
}

#pragma mark - Window Management

- (void)createNativeWindowWithId:(uint64_t)windowId
                           width:(int32_t)width
                          height:(int32_t)height
                           title:(NSString *)title
                          useSSD:(BOOL)useSSD {
  dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    // macOS window creation
    NSWindowStyleMask styleMask =
        useSSD ? (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
               : (NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable);

    NSRect contentRect = NSMakeRect(100, 100, width, height);
    NSWindow *window =
        [[WWNWindow alloc] initWithContentRect:contentRect
                                     styleMask:styleMask
                                       backing:NSBackingStoreBuffered
                                         defer:NO];

    // Create and set WWNView as content view to handle input
    WWNView *contentView =
        [[WWNView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    [window setContentView:contentView];

    window.title = title ?: @"WWN Client";
    window.delegate = (id<NSWindowDelegate>)self; // For window lifecycle events

    [self.windowRegistry setObject:window forKey:@(windowId)];
    [window makeKeyAndOrderFront:nil];

    WWNLog("PLATFORM", @"Created native window %llu: %@", windowId, title);
#else
        // iOS window creation (simplified for now).
        // Use the first connected UIWindowScene if available.
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                break;
            }
        }
        if (!window) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            window = [[UIWindow alloc] init];
#pragma clang diagnostic pop
        }
        window.backgroundColor = [UIColor blackColor];
        [self.windowRegistry setObject:window forKey:@(windowId)];
        [window makeKeyAndVisible];
        
        WWNLog("PLATFORM", @"Created native window %llu", windowId);
#endif
  });
}

- (void)destroyNativeWindowWithId:(uint64_t)windowId {
  dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    NSWindow *window = [self.windowRegistry objectForKey:@(windowId)];
    if (window) {
      [window close];
      [self.windowRegistry removeObjectForKey:@(windowId)];
      WWNLog("PLATFORM", @"Destroyed native window %llu", windowId);
    }
#else
        UIWindow *window = [self.windowRegistry objectForKey:@(windowId)];
        if (window) {
            window.hidden = YES;
            [self.windowRegistry removeObjectForKey:@(windowId)];
            WWNLog("PLATFORM", @"Destroyed native window %llu", windowId);
        }
#endif
  });
}

- (void)setWindowTitle:(NSString *)title forWindowId:(uint64_t)windowId {
  dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    NSWindow *window = [self.windowRegistry objectForKey:@(windowId)];
    if (window) {
      window.title = title;
    }
#endif
  });
}

- (void)setWindowSize:(CGSize)size forWindowId:(uint64_t)windowId {
  dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    NSWindow *window = [self.windowRegistry objectForKey:@(windowId)];
    if (window) {
      NSRect frame = window.frame;
      NSRect contentRect =
          NSMakeRect(frame.origin.x, frame.origin.y, size.width, size.height);
      NSRect newFrame = [window frameRectForContentRect:contentRect];
      [window setFrame:newFrame display:YES animate:YES];
    }
#else
        UIWindow *window = [self.windowRegistry objectForKey:@(windowId)];
        if (window) {
            CGRect frame = window.frame;
            frame.size = size;
            window.frame = frame;
        }
#endif
  });
}

- (void)requestRenderForWindowId:(uint64_t)windowId {
  // TODO: Trigger Metal rendering for this window
  // For now, this is a stub
}

@end
