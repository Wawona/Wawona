// WWNWatchCompositorBridge.h
// Wayland compositor bridge for watchOS.
// Wraps libwawona.a (Rust compositor core) and provides a rendering surface
// as a stream of CGImage frames that SwiftUI can display.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue when a new compositor frame is ready.
/// The notification's object is the WWNWatchCompositorBridge singleton.
extern NSNotificationName const WWNWatchCompositorFrameReadyNotification;

/// Manages the in-process Wayland compositor for watchOS.
/// Presents frames as CGImage snapshots that SwiftUI displays via Canvas.
@interface WWNWatchCompositorBridge : NSObject

/// Singleton accessor.
+ (instancetype)sharedBridge;

// MARK: - Lifecycle

/// Start the compositor and create the Wayland socket.
/// @param socketName Wayland socket name (e.g. "wayland-0"). Pass nil for default.
/// @return YES on success.
- (BOOL)startWithSocketName:(nullable NSString *)socketName;

/// Stop the compositor and all running clients.
- (void)stop;

/// YES while the compositor event loop is running.
@property(nonatomic, readonly) BOOL isRunning;

/// YES when a Wayland compositor backend is active (mini server or Rust).
@property(nonatomic, readonly) BOOL isCompositorAvailable;

/// The Wayland socket path clients should connect to.
@property(nonatomic, readonly, nullable) NSString *socketPath;

// MARK: - Native Client Launch

/// Launch weston-simple-shm in-process.
- (void)launchWestonSimpleSHM;

/// Launch the weston compositor in-process.
- (void)launchWeston;

/// Launch weston-terminal in-process.
- (void)launchWestonTerminal;

/// Launch foot terminal in-process.
- (void)launchFoot;

/// Stop any running in-process client.
- (void)stopClient;

/// YES while an in-process client is running.
@property(nonatomic, readonly) BOOL isClientRunning;

// MARK: - Waypipe (SSH + Waypipe)

/// Launch waypipe in-process with libssh2 for SSH tunneling.
/// @param host SSH hostname
/// @param user SSH username
/// @param port SSH port (typically 22)
/// @param password SSH password (or empty string for key auth)
/// @param remoteCommand Remote command to run (e.g. "weston-terminal")
- (void)launchWaypipeWithHost:(NSString *)host
                         user:(NSString *)user
                         port:(NSInteger)port
                     password:(NSString *)password
                remoteCommand:(NSString *)remoteCommand;

/// Stop the running waypipe session.
- (void)stopWaypipe;

/// YES while waypipe is running.
@property(nonatomic, readonly) BOOL isWaypipeRunning;

// MARK: - Frame Output

/// The most recently rendered compositor frame, or nil if nothing has been drawn yet.
/// This image is updated on the main thread every time a new frame is committed.
@property(nonatomic, readonly, nullable) CGImageRef latestFrame;

/// Width of the compositor output in points.
@property(nonatomic, assign) uint32_t outputWidth;

/// Height of the compositor output in points.
@property(nonatomic, assign) uint32_t outputHeight;

@end

NS_ASSUME_NONNULL_END
