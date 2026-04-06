#import "WWNImageLoader.h"
#import <CommonCrypto/CommonDigest.h>

@interface WWNImageLoader ()
@property(nonatomic, strong) NSString *cachePath;
@end

@implementation WWNImageLoader

+ (instancetype)sharedLoader {
  static WWNImageLoader *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                         NSUserDomainMask, YES);
    NSString *baseCache = [paths firstObject];
    _cachePath = [baseCache stringByAppendingPathComponent:@"Wawona/Images"];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:_cachePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
  }
  return self;
}

- (void)loadImageFromURL:(NSString *)urlString
              completion:(void (^)(WImage _Nullable image))completion {
  if (!urlString || urlString.length == 0) {
    if (completion) {
      completion(nil);
    }
    return;
  }

  // Handle local files
  if ([urlString hasPrefix:@"/"] || [urlString hasPrefix:@"./"]) {
    NSString *fullPath = urlString;
    if ([urlString hasPrefix:@"./"]) {
      // Assuming relative to current directory (Wawona root)
      fullPath = [[NSFileManager defaultManager].currentDirectoryPath
          stringByAppendingPathComponent:[urlString substringFromIndex:2]];
    }

    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
#if TARGET_OS_IPHONE
          WImage image = [[UIImage alloc] initWithContentsOfFile:fullPath];
#else
          WImage image = [[NSImage alloc] initWithContentsOfFile:fullPath];
#endif
          dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
              completion(image);
            }
          });
        });
    return;
  }

  // Handle remote URLs
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) {
    if (completion) {
      completion(nil);
    }
    return;
  }

  NSString *cacheFile = [self cachePathForURL:urlString];

  // Check cache first
  if ([[NSFileManager defaultManager] fileExistsAtPath:cacheFile]) {
    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
#if TARGET_OS_IPHONE
          WImage image = [[UIImage alloc] initWithContentsOfFile:cacheFile];
#else
          WImage image = [[NSImage alloc] initWithContentsOfFile:cacheFile];
#endif
          dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
              completion(image);
            }
          });
        });
    return;
  }

  // Download
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [request setValue:@"Wawona-App/1.0" forHTTPHeaderField:@"User-Agent"];

  NSURLSessionDataTask *task = [[NSURLSession sharedSession]
      dataTaskWithRequest:request
        completionHandler:^(NSData *_Nullable data,
                            NSURLResponse *_Nullable response,
                            NSError *_Nullable error) {
          if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
              if (completion) {
                completion(nil);
              }
            });
            return;
          }

          // Save to cache
          [data writeToFile:cacheFile atomically:YES];

#if TARGET_OS_IPHONE
          WImage image = [[UIImage alloc] initWithData:data];
#else
        WImage image = [[NSImage alloc] initWithData:data];
#endif
          dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
              completion(image);
            }
          });
        }];
  [task resume];
}

- (NSString *)cachePathForURL:(NSString *)urlString {
  const char *str = [urlString UTF8String];
  unsigned char r[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(str, (CC_LONG)strlen(str), r);
  NSMutableString *hash =
      [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
    [hash appendFormat:@"%02x", r[i]];
  }

  // Try to preserve extension for debugging
  NSString *ext = [urlString pathExtension];
  if (ext.length > 0 && ext.length < 5) {
    return [[self.cachePath stringByAppendingPathComponent:hash]
        stringByAppendingPathExtension:ext];
  }
  return [self.cachePath stringByAppendingPathComponent:hash];
}

- (void)clearCache {
  [[NSFileManager defaultManager] removeItemAtPath:self.cachePath error:nil];
  [[NSFileManager defaultManager] createDirectoryAtPath:self.cachePath
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
}

@end
