#import "WWNMachineProfileStore.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted after CLI auto-create/update of a machine profile so the Machines
/// grid reloads without restarting the app.
extern NSNotificationName const WWNMachineProfilesChangedNotification;

/// Keys stored in runtimeOverrides / containerSettings for CLI↔GUI sync.
extern NSString *const kWWNCLIRecipeKey;
extern NSString *const kWWNMachineOrigin;
extern NSString *const kWWNMachineOriginCLI;
extern NSString *const kWWNMachineOriginManual;

@interface WWNCLIMachineRecipes : NSObject

/// Known recipe ids (flower, sway, weston, niri, …).
+ (NSArray<NSString *> *)allRecipeIds;

/// Ensure a Machines profile exists for this recipe (create if missing),
/// post WWNMachineProfilesChangedNotification, and return it. Never starts
/// the session; caller uses WWNMachineSessionBridge.
+ (nullable WWNMachineProfile *)ensureProfileForRecipe:(NSString *)recipe
                                                 error:(NSError *_Nullable *_Nullable)error;

/// Resolve --machine / machines show by id or case-insensitive name.
+ (nullable WWNMachineProfile *)profileMatchingIdOrName:(NSString *)query;

/// Print recipe list for `Wawona run --help` / unknown recipe.
+ (void)printRecipeHelp;

@end

NS_ASSUME_NONNULL_END
