#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bitmask of Local Shell / WWN-ROOTFS features supported on this platform.
typedef NS_OPTIONS(NSUInteger, WWNRootfsCapabilities) {
    WWNRootfsCapabilityNone = 0,
    /// Show the Local Shell settings section (always paired with at least read-only paths).
    WWNRootfsCapabilitySettings = 1 << 0,
    /// User can browse shell files via the platform file manager (Files, Finder, SAF, etc.).
    WWNRootfsCapabilityBrowseUserFiles = 1 << 1,
    /// Import/copy a file into shell HOME from a document picker.
    WWNRootfsCapabilityImportFile = 1 << 2,
    /// Reset .zshenv / .zshrc / .zlogin from bundled templates.
    WWNRootfsCapabilityResetDotfiles = 1 << 3,
    /// Re-copy etc/ + usr/ from the app bundle (bundled-rootfs platforms only).
    WWNRootfsCapabilityReinstallSystemTree = 1 << 4,
    /// Optional iCloud Drive sync for shell HOME (Apple platforms, user opt-in).
    WWNRootfsCapabilityICloudSync = 1 << 5,
};

/// Snapshot keys (NSString values unless noted):
///   mode. @"bundled" | @"host"
///   filesRoot. User-visible files root (may equal home on desktop)
///   home. Shell $HOME
///   systemRoot. WAWONA_ROOTFS or host note
///   bundleTemplateVersion
///   appliedTemplateVersion
///   filesHint. One-line browse instruction for this platform
///   platformLabel. Short OS name for settings copy
///   iCloudSync. @"On" | @"Off"
///   iCloudStatus. Human-readable sync state
@interface WWNRootfsProvider : NSObject

+ (WWNRootfsCapabilities)capabilities;

+ (NSDictionary<NSString *, NSString *> *)snapshot;

/// Create user-writable layout (Documents/Wawona on iOS, etc.). No-op on host-shell platforms.
+ (void)prepareUserAccess;

+ (BOOL)refreshShellDotfiles:(NSError * _Nullable * _Nullable)error;

+ (BOOL)reinstallSystemTree:(NSError * _Nullable * _Nullable)error;

/// Apply WAWONA_ROOTFS / HOME / XDG_* before launching in-process or nested shell.
+ (void)applyShellEnvironment;

/// Open the user files location in the platform file manager when supported.
+ (BOOL)openUserFilesLocation;

#if (TARGET_OS_IPHONE || TARGET_OS_OSX) && !TARGET_OS_TV
+ (BOOL)isICloudSyncSupported;
+ (BOOL)isICloudSyncEnabled;
+ (BOOL)setICloudSyncEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
#endif

@end

NS_ASSUME_NONNULL_END
