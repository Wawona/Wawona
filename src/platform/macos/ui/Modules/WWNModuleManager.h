//
//  WWNModuleManager.h
//  Wawona — App Store module manager (wwn-apt host bridge).
//
//  Host-side implementation of the wwn-apt integration spec (W2/W3):
//  loads the embedded module catalog, tracks installs in installed.json,
//  performs StoreKit purchases + On-Demand Resource fetches, and serves the
//  JSON-lines IPC socket the in-shell `apt` CLI connects to.
//
//  Spec: github.com/Wawona/wwn-apt docs/INTEGRATION-SPEC.md
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const WWNModuleManagerErrorDomain;

@interface WWNModuleManager : NSObject

+ (instancetype)sharedManager;

/// Load the catalog, start the module-manager IPC socket, and export
/// WAWONA_MODULE_MANAGER=1 for shells. Idempotent.
- (void)start;

/// Module ids recorded in installed.json.
- (NSArray<NSString *> *)installedModuleIds;

/// Parsed catalog entries (raw dictionaries from catalog.json), empty when no
/// catalog is embedded.
- (NSArray<NSDictionary *> *)catalogModules;

/// StoreKit purchase (when the module has a product id) + ODR fetch + record
/// in installed.json. Completion is invoked on the main queue.
- (void)installModuleWithId:(NSString *)moduleId
                 completion:(void (^)(NSError *_Nullable error))completion;

/// Remove a module from installed.json and delete its extracted payload.
- (void)removeModuleWithId:(NSString *)moduleId
                completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
