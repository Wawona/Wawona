#import <Foundation/Foundation.h>

/// Posted on iPhone when the Watch sends a normalized touch.
/// userInfo: phase (down|move|up), x, y in 0...1.
NSNotificationName const WWNWatchDisplayTouchNotification =
    @"WWNWatchDisplayTouchNotification";
