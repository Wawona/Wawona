/*
 * WWNStartupLogger.m
 *
 * Bridges the C-level wwn_startup_log_sink function pointer (declared in
 * WWNLog.h) to the ObjC WWNStartupLogger singleton.  The sink is set/cleared
 * by -beginCapture / -endCapture and must be safe to call from any thread.
 */

#import "WWNStartupLogger.h"
#import "WWNLog.h"

/*
 * wwn_startup_log_sink is declared extern in WWNLog.h and DEFINED here
 * for iOS/tvOS/visionOS.  For macOS the NULL definition lives in
 * WWNSettings.c (a platform-shared C file) under a !TARGET_OS_IPHONE guard
 * so that WWNLog() calls on macOS simply skip the in-process sink.
 */
void (*wwn_startup_log_sink)(const char *module, const char *msg) = NULL;

/* Forward to the shared instance — C-callable, any thread. */
static void wwn_startup_log_sink_impl(const char *module, const char *msg)
{
    NSString *line = [NSString stringWithFormat:@"[%s] %s",
                      module ? module : "?", msg ? msg : ""];
    [[WWNStartupLogger shared] appendLine:line];
}

@implementation WWNStartupLogger {
    NSMutableArray<NSString *> *_lines;
    dispatch_queue_t            _queue;    /* serial, protects _lines */
}

+ (instancetype)shared
{
    static WWNStartupLogger *s;
    static dispatch_once_t   once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _queue = dispatch_queue_create("com.aspauldingcode.wawona.startuplog",
                                       DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)beginCapture
{
    dispatch_sync(_queue, ^{
        [self->_lines removeAllObjects];
    });
    wwn_startup_log_sink = wwn_startup_log_sink_impl;
}

- (void)endCapture
{
    wwn_startup_log_sink = NULL;
}

- (void)appendLine:(NSString *)line
{
    if (!line) return;
    dispatch_async(_queue, ^{
        [self->_lines addObject:line];
        id<WWNStartupLoggerDelegate> delegate = self.delegate;
        if (delegate) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate startupLogger:self didAppendLine:line];
            });
        }
    });
}

- (NSArray<NSString *> *)capturedLines
{
    __block NSArray<NSString *> *snapshot;
    dispatch_sync(_queue, ^{
        snapshot = [self->_lines copy];
    });
    return snapshot;
}

@end
