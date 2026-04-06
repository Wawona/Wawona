// Wawona Launcher Client - Header
// A GUI Launcher for bundled Wayland client applications
// Supports iOS, macOS, and Android

#import <Foundation/Foundation.h>
#include <pthread.h>

@class WWNAppDelegate;

// Forward declare wayland-client types
struct wl_display;

// Application metadata for launcher display
@interface WWNLauncherApp : NSObject
@property (nonatomic, strong) NSString *appId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *executablePath;
@property (nonatomic, strong) NSString *iconPath;
@property (nonatomic, strong) NSString *description;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@property (nonatomic, assign) BOOL isBlacklisted;
@end

// Start the launcher client thread with a pre-connected socket file descriptor
pthread_t startLauncherClientThread(WWNAppDelegate *delegate, int client_fd);

// Get the client display (returns wayland-client wl_display*, not wayland-server)
struct wl_display *getLauncherClientDisplay(WWNAppDelegate *delegate);

// Disconnect and cleanup the launcher client
void disconnectLauncherClient(WWNAppDelegate *delegate);

// Get list of available applications (excluding blacklisted)
NSArray<WWNLauncherApp *> *getLauncherApplications(void);

// Launch an application by app ID
BOOL launchLauncherApplication(NSString *appId);

// Refresh the application list
void refreshLauncherApplicationList(void);

