#import "WWNWatchCompanionBridge.h"

#import <TargetConditionals.h>

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST && !TARGET_OS_WATCH && !TARGET_OS_TV && !TARGET_OS_VISION
#import <WatchConnectivity/WatchConnectivity.h>

static NSString *const kWWNWatchLastTransferNameKey =
    @"wawona.pref.watchCompanionLastTransferName";
static NSString *const kWWNWatchLastTransferStatusKey =
    @"wawona.pref.watchCompanionLastTransferStatus";
static NSString *const kWWNWatchLastTransferAtKey =
    @"wawona.pref.watchCompanionLastTransferAt";

@interface WWNWatchCompanionBridge () <WCSessionDelegate>
@end

@implementation WWNWatchCompanionBridge

+ (instancetype)sharedBridge {
  static WWNWatchCompanionBridge *bridge;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    bridge = [[WWNWatchCompanionBridge alloc] init];
  });
  return bridge;
}

- (void)activate {
  if (![WCSession isSupported]) {
    return;
  }
  WCSession *session = [WCSession defaultSession];
  if (session.delegate != self) {
    session.delegate = self;
  }
  [session activateSession];
}

- (NSString *)statusSummary {
  if (![WCSession isSupported]) {
    return @"WatchConnectivity unavailable on this platform.";
  }
  WCSession *session = [WCSession defaultSession];
  if (!session.isPaired) {
    return @"No paired Apple Watch.";
  }
  if (!session.isWatchAppInstalled) {
    return @"Wawona is not installed on the paired Watch.";
  }
  if (session.isReachable) {
    return @"Watch reachable. Transfers deliver immediately when possible.";
  }
  return @"Watch paired; not reachable. Transfers queue until the Watch wakes.";
}

- (NSString *)lastTransferSummary {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  NSString *name = [defaults stringForKey:kWWNWatchLastTransferNameKey] ?: @"";
  NSString *status =
      [defaults stringForKey:kWWNWatchLastTransferStatusKey] ?: @"";
  NSTimeInterval at = [defaults doubleForKey:kWWNWatchLastTransferAtKey];
  if (name.length == 0) {
    return @"No transfers yet.";
  }
  if (at > 0) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:at];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateStyle = NSDateFormatterShortStyle;
    fmt.timeStyle = NSDateFormatterShortStyle;
    return [NSString stringWithFormat:@"%@. %@ (%@)", name, status,
                                      [fmt stringFromDate:date]];
  }
  return [NSString stringWithFormat:@"%@. %@", name, status];
}

- (nullable NSString *)sendDocumentAtURL:(NSURL *)fileURL {
  if (!fileURL) {
    return @"No file selected.";
  }
  if (![WCSession isSupported]) {
    return @"WatchConnectivity unsupported.";
  }
  [self activate];
  WCSession *session = [WCSession defaultSession];
  if (!session.isPaired) {
    return @"No paired Apple Watch.";
  }
  if (!session.isWatchAppInstalled) {
    return @"Wawona Watch app not installed.";
  }
  NSString *name = fileURL.lastPathComponent ?: @"document";
  NSDictionary *meta = @{@"name" : name, @"kind" : @"document"};
  [session transferFile:fileURL metadata:meta];
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setObject:name forKey:kWWNWatchLastTransferNameKey];
  [defaults setObject:@"queued" forKey:kWWNWatchLastTransferStatusKey];
  [defaults setDouble:NSDate.date.timeIntervalSince1970
               forKey:kWWNWatchLastTransferAtKey];
  return nil;
}

- (void)session:(WCSession *)session
    activationDidCompleteWithState:(WCSessionActivationState)activationState
                             error:(NSError *)error {
  (void)session;
  (void)activationState;
  (void)error;
}

- (void)sessionDidBecomeInactive:(WCSession *)session {
  (void)session;
}

- (void)sessionDidDeactivate:(WCSession *)session {
  [session activateSession];
}

@end

#else

@implementation WWNWatchCompanionBridge

+ (instancetype)sharedBridge {
  static WWNWatchCompanionBridge *bridge;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    bridge = [[WWNWatchCompanionBridge alloc] init];
  });
  return bridge;
}

- (void)activate {
}

- (NSString *)statusSummary {
  return @"Apple Watch companion is available on iPhone.";
}

- (NSString *)lastTransferSummary {
  return @"No transfers yet.";
}

- (nullable NSString *)sendDocumentAtURL:(NSURL *)fileURL {
  (void)fileURL;
  return @"Apple Watch transfer requires iPhone.";
}

@end

#endif
