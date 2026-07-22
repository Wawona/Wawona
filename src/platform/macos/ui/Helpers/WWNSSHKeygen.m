#import "WWNSSHKeygen.h"

#include <sys/stat.h>

#if TARGET_OS_IPHONE
extern int ssh_keygen_main(int argc, char *argv[]);
#endif

#if !TARGET_OS_WATCH
#import "WWNPreferencesManager.h"
#import "WWNPlatformCallbacks.h"
#endif

@implementation WWNSSHKeygen

+ (NSString *)sshDirectory {
  NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                       NSUserDomainMask, YES)
                       .firstObject;
  NSString *sshDir = [docs stringByAppendingPathComponent:@"ssh"];
  [[NSFileManager defaultManager] createDirectoryAtPath:sshDir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  return sshDir;
}

+ (void)syncKeyPrefsWithPath:(NSString *)keyPath
                 passphrase:(NSString *)passphrase {
  NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
  [ud setObject:keyPath ?: @"" forKey:@"SSHKeyPath"];
  [ud setInteger:1 forKey:@"SSHAuthMethod"];
  [ud setObject:passphrase ?: @"" forKey:@"SSHKeyPassphrase"];
  [ud setObject:keyPath ?: @"" forKey:@"WaypipeSSHKeyPath"];
  [ud setInteger:1 forKey:@"WaypipeSSHAuthMethod"];
  [ud setObject:passphrase ?: @"" forKey:@"WaypipeSSHKeyPassphrase"];
  // Swift WawonaPreferences / WatchKit bridge namespace
  [ud setObject:keyPath ?: @"" forKey:@"wawona.pref.sshKeyPath"];
  [ud setInteger:1 forKey:@"wawona.pref.sshAuthMethod"];
  [ud setObject:passphrase ?: @"" forKey:@"wawona.pref.sshKeyPassphrase"];
  [ud synchronize];

#if !TARGET_OS_WATCH
  WWNPreferencesManager *prefs = [WWNPreferencesManager sharedManager];
  prefs.sshKeyPath = keyPath ?: @"";
  prefs.sshAuthMethod = 1;
  if (passphrase)
    prefs.sshKeyPassphrase = passphrase;
  prefs.waypipeSSHKeyPath = prefs.sshKeyPath;
  prefs.waypipeSSHAuthMethod = 1;
  prefs.waypipeSSHKeyPassphrase = prefs.sshKeyPassphrase ?: @"";
#endif
}

+ (NSString *)generateKeyType:(NSString *)type
                   passphrase:(NSString *)passphrase
                        error:(NSError **)error {
  NSString *keyType = type.length ? type : @"ed25519";
  if (![keyType isEqualToString:@"ed25519"] &&
      ![keyType isEqualToString:@"ecdsa"] &&
      ![keyType isEqualToString:@"rsa"]) {
    keyType = @"ed25519";
  }
  NSString *sshDir = [self sshDirectory];
  NSString *baseName = [NSString stringWithFormat:@"id_%@", keyType];
  NSString *keyPath = [sshDir stringByAppendingPathComponent:baseName];
  if ([[NSFileManager defaultManager] fileExistsAtPath:keyPath]) {
    keyPath = [sshDir
        stringByAppendingPathComponent:
            [NSString stringWithFormat:@"id_%@_%ld", keyType,
                                       (long)[[NSDate date] timeIntervalSince1970]]];
  }
  NSString *pass = passphrase ?: @"";
  int rc = -1;

#if TARGET_OS_IPHONE
  {
    char *argv[] = {"ssh-keygen",
                    "-t",
                    (char *)[keyType UTF8String],
                    "-f",
                    (char *)[keyPath UTF8String],
                    "-N",
                    (char *)[pass UTF8String],
                    "-q",
                    NULL};
    rc = ssh_keygen_main(8, argv);
  }
#else
  {
    NSTask *task = [[NSTask alloc] init];
    NSString *sshKeygen = WWNWawonaFindBundledExecutable(@"ssh-keygen");
    if (!sshKeygen)
      sshKeygen = @"/usr/bin/ssh-keygen";
    task.launchPath = sshKeygen;
    task.arguments =
        @[ @"-t", keyType, @"-f", keyPath, @"-N", pass, @"-q" ];
    @try {
      [task launch];
      [task waitUntilExit];
      rc = (int)task.terminationStatus;
    } @catch (NSException *ex) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"WWNSSHKeygen"
                       code:-1
                   userInfo:@{NSLocalizedDescriptionKey : ex.reason ?: @"NSTask"}];
      }
      return nil;
    }
  }
#endif

  if (rc != 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"WWNSSHKeygen"
                     code:rc
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"ssh-keygen exited %d", rc]
                 }];
    }
    return nil;
  }
  chmod([keyPath UTF8String], 0600);
  [self syncKeyPrefsWithPath:keyPath passphrase:pass];
  return keyPath;
}

+ (NSString *)installOpenSSHPrivateKeyAtURL:(NSURL *)url
                                      error:(NSError **)error {
  if (!url) {
    if (error)
      *error = [NSError errorWithDomain:@"WWNSSHKeygen"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"No file URL"
                               }];
    return nil;
  }
  NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
  if (!data)
    return nil;
  return [self installOpenSSHPrivateKeyData:data
                              preferredName:url.lastPathComponent
                                     error:error];
}

+ (NSString *)installOpenSSHPrivateKeyData:(NSData *)data
                             preferredName:(NSString *)name
                                    error:(NSError **)error {
  if (data.length == 0) {
    if (error)
      *error = [NSError errorWithDomain:@"WWNSSHKeygen"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Empty key data"
                               }];
    return nil;
  }
  NSString *text = [[NSString alloc] initWithData:data
                                         encoding:NSUTF8StringEncoding];
  if (![text containsString:@"PRIVATE KEY"] &&
      ![text containsString:@"OPENSSH PRIVATE KEY"]) {
    if (error)
      *error = [NSError
          errorWithDomain:@"WWNSSHKeygen"
                     code:3
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Not an OpenSSH/PEM private key (gpg --export-ssh-key "
                       @"or id_*)."
                 }];
    return nil;
  }
  NSString *sshDir = [self sshDirectory];
  NSString *base =
      (name.length > 0 ? name.lastPathComponent : @"id_gpg_ssh");
  if ([base hasPrefix:@"."])
    base = @"id_gpg_ssh";
  NSString *dest = [sshDir stringByAppendingPathComponent:base];
  if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) {
    dest = [sshDir
        stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@_%ld", base,
                                       (long)[[NSDate date] timeIntervalSince1970]]];
  }
  if (![data writeToFile:dest options:NSDataWritingAtomic error:error])
    return nil;
  chmod([dest UTF8String], 0600);
  [self syncKeyPrefsWithPath:dest passphrase:nil];
  return dest;
}

@end
