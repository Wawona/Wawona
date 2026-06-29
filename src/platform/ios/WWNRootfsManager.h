#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE

NS_ASSUME_NONNULL_BEGIN

/// Manages bundled shell data (wawona-rootfs templates + static-linked zsh) for App Store local shell.
@interface WWNRootfsManager : NSObject

/// Path to read-only template tree inside the app bundle (`…/wawona-rootfs`).
+ (NSString *)bundleRootfsPath;

/// Logical shell path passed to weston-terminal (`/usr/bin/zsh`; zsh is static-linked).
+ (NSString *)bundledShellPath;

/// Bundled zsh function/share tree (`…/wawona-rootfs/usr/share/zsh`).
+ (NSString *)bundledZshSharePath;

/// Path to read-only Neovim runtime prefix inside the app bundle (`…/neovim-rootfs`).
+ (NSString *)bundleNeovimRootfsPath;

/// Writable Neovim config dir under Application Support (`…/neovim-rootfs/home/.config`).
+ (NSString *)activeNeovimConfigPath;

/// Bundled Neovim runtime tree (`…/neovim-rootfs/usr/share/nvim/runtime`).
+ (NSString *)bundledNeovimRuntimePath;

/// Writable rootfs under Application Support (`…/wawona-rootfs`).
+ (NSString *)activeRootfsPath;

/// Copy bundle rootfs into Application Support on first launch; refresh bin/share if needed.
+ (BOOL)ensureRootfsInstalled:(NSError * _Nullable * _Nullable)error;

/// Set HOME, PATH, ZDOTDIR, WAWONA_* env vars before launching weston-terminal.
+ (void)applyShellEnvironment;

@end

NS_ASSUME_NONNULL_END

#endif
