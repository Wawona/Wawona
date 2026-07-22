#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared SSH keypair generation / GPG-SSH import for all Apple targets.
/// Uses libwwn-ssh-cli (`ssh_keygen_main`) on iOS family; OpenSSH on macOS.
@interface WWNSSHKeygen : NSObject

/// Generate ed25519|ecdsa|rsa under Documents/ssh (or ~/Documents/ssh).
/// Sets SSHKeyPath / WaypipeSSHKeyPath / SSHAuthMethod=1 and dual-syncs.
/// @return Absolute private key path, or nil on failure.
+ (nullable NSString *)generateKeyType:(NSString *)type
                            passphrase:(nullable NSString *)passphrase
                                 error:(NSError *_Nullable *_Nullable)error;

/// Install an OpenSSH private key (including `gpg --export-ssh-key` output).
/// Copies into Documents/ssh and syncs prefs like generate.
+ (nullable NSString *)installOpenSSHPrivateKeyAtURL:(NSURL *)url
                                              error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSString *)installOpenSSHPrivateKeyData:(NSData *)data
                                      preferredName:(nullable NSString *)name
                                             error:(NSError *_Nullable *_Nullable)error;

/// Dual-write SSH* ↔ WaypipeSSH* key path / auth / passphrase.
+ (void)syncKeyPrefsWithPath:(NSString *)keyPath
                 passphrase:(nullable NSString *)passphrase;

@end

NS_ASSUME_NONNULL_END
