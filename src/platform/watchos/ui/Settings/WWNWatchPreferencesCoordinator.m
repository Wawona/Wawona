#import "WWNWatchPreferencesCoordinator.h"
#import <WatchKit/WatchKit.h>

static __weak WKInterfaceController *WWNWatchSettingsHostController = nil;

@implementation WWNWatchPreferencesCoordinator

+ (instancetype)sharedCoordinator {
    static WWNWatchPreferencesCoordinator *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WWNWatchPreferencesCoordinator alloc] init];
    });
    return instance;
}

+ (void)setHostInterfaceController:(WKInterfaceController *)controller {
    WWNWatchSettingsHostController = controller;
}

- (WKInterfaceController *)hostController {
    if (WWNWatchSettingsHostController) {
        return WWNWatchSettingsHostController;
    }
    WKExtension *extension = [WKExtension sharedExtension];
    if (extension.visibleInterfaceController) {
        return extension.visibleInterfaceController;
    }
    return extension.rootInterfaceController;
}

- (void)showSettings {
    WKInterfaceController *host = [self hostController];
    if (!host) {
        NSLog(@"[WWNWatchPreferences] No WKInterfaceController available to present settings");
        return;
    }
    [host presentControllerWithName:@"SettingsRoot" context:nil];
}

- (void)dismissSettings {
    WKInterfaceController *host = [self hostController];
    [host dismissController];
}

@end
