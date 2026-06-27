#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE

NS_ASSUME_NONNULL_BEGIN

/// Manages the bundled wawona-rootfs prefix (zsh + templates) for App Store–compliant local shell.
@interface WWNRootfsManager : NSObject

/// Path to read-only rootfs inside the app bundle (`…/wawona-rootfs`).
+ (NSString *)bundleRootfsPath;

/// Writable rootfs under Application Support (`…/wawona-rootfs`).
+ (NSString *)activeRootfsPath;

/// Copy bundle rootfs into Application Support on first launch; refresh bin/share if needed.
+ (BOOL)ensureRootfsInstalled:(NSError * _Nullable * _Nullable)error;

/// Set HOME, PATH, ZDOTDIR, WAWONA_* env vars before launching weston-terminal.
+ (void)applyShellEnvironment;

@end

NS_ASSUME_NONNULL_END

#endif
