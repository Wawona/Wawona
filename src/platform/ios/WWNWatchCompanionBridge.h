#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// iOS → Apple Watch document transfer via WatchConnectivity (#151 / #153).
@interface WWNWatchCompanionBridge : NSObject

+ (instancetype)sharedBridge;

- (void)activate;
- (NSString *)statusSummary;
- (NSString *)lastTransferSummary;

/// Queues `fileURL` for delivery. Returns nil on success, else an error string.
- (nullable NSString *)sendDocumentAtURL:(NSURL *)fileURL;

@end

NS_ASSUME_NONNULL_END
