#import <Foundation/Foundation.h>
#import <WatchKit/WatchKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presents native WatchKit global Wawona Settings (not SwiftUI).
@interface WWNWatchPreferencesCoordinator : NSObject

+ (instancetype)sharedCoordinator;

/// Registers the SwiftUI hosting controller when visible; used to present WatchKit settings modals.
+ (void)setHostInterfaceController:(nullable WKInterfaceController *)controller;

/// Present the WatchKit settings interface modally when a host controller is available.
- (void)showSettings;

/// Dismiss the topmost presented WatchKit settings controller.
- (void)dismissSettings;

@end

NS_ASSUME_NONNULL_END
