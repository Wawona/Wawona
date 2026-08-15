/*
 * WWNStartupLogger — captures WWNLog output during the client-launch
 * transition and forwards it to the native startup log view.
 *
 * Usage:
 *   [WWNStartupLogger beginCapture];          // enable sink; call before launch
 *   [WWNStartupLogger appendRaw:@"..."];      // inject a message from any code
 *   [WWNStartupLogger endCapture];            // disable sink; call after reveal
 *
 * Captured entries are threaded to subscribers via the delegate on the main
 * queue; the delegate is typically WWNStartupLogViewController (iOS/tvOS) or
 * WatchStartupLogModel (watchOS SwiftUI).
 */

#ifndef WWNStartupLogger_h
#define WWNStartupLogger_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WWNStartupLoggerDelegate <NSObject>
- (void)startupLogger:(id)logger didAppendLine:(NSString *)line;
@end

@interface WWNStartupLogger : NSObject

+ (instancetype)shared;

@property (nonatomic, weak, nullable) id<WWNStartupLoggerDelegate> delegate;

/// Start routing WWNLog output to this logger.
- (void)beginCapture;

/// Stop routing WWNLog output; the sink function is cleared.
- (void)endCapture;

/// Manually inject a formatted log line (e.g. from Weston-log callbacks).
- (void)appendLine:(NSString *)line;

/// All captured lines since the last beginCapture, in order.
@property (nonatomic, readonly, copy) NSArray<NSString *> *capturedLines;

@end

NS_ASSUME_NONNULL_END

#endif /* WWNStartupLogger_h */
