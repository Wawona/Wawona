#import <Foundation/Foundation.h>
#import "WWNQemuProcess.h"

NS_ASSUME_NONNULL_BEGIN

@interface WWNQemuSystem : WWNQemuProcess

@property(nonatomic, copy, readonly) NSString *architecture;
@property(nonatomic, copy) NSArray<NSURL *> *resources;

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments
                     architecture:(NSString *)architecture;

- (void)startQemuWithCompletion:(void (^)(NSError *_Nullable error))completion;
- (void)stopQemu;

@end

NS_ASSUME_NONNULL_END
