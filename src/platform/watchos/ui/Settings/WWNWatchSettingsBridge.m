#import "WWNWatchSettingsBridge.h"

static NSString *const kWWNPrefPrefix = @"wawona.pref.";

@implementation WWNWatchSettingsBridge {
    NSUserDefaults *_defaults;
}

+ (instancetype)sharedBridge {
    static WWNWatchSettingsBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WWNWatchSettingsBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = NSUserDefaults.standardUserDefaults;
        [self reloadFromDefaults];
    }
    return self;
}

- (NSString *)prefKey:(NSString *)suffix {
    return [kWWNPrefPrefix stringByAppendingString:suffix];
}

- (void)reloadFromDefaults {
    _autoScale = [_defaults objectForKey:[self prefKey:@"autoScale"]]
                     ? [_defaults boolForKey:[self prefKey:@"autoScale"]]
                     : YES;
    if ([_defaults objectForKey:@"ForceServerSideDecorations"] != nil) {
        _forceSSD = [_defaults boolForKey:@"ForceServerSideDecorations"];
    } else {
        _forceSSD = [_defaults boolForKey:[self prefKey:@"forceSSD"]];
    }
    _colorOperations = [_defaults objectForKey:[self prefKey:@"colorOperations"]]
                           ? [_defaults boolForKey:[self prefKey:@"colorOperations"]]
                           : NO;
    _renderer = [_defaults stringForKey:[self prefKey:@"renderer"]] ?: @"metal";
    _waylandDisplay = [_defaults stringForKey:[self prefKey:@"waylandDisplay"]] ?: @"wayland-0";
    _defaultInputProfile =
        [_defaults stringForKey:[self prefKey:@"defaultInputProfile"]] ?: @"direct";
    _defaultBundledAppID =
        [_defaults stringForKey:[self prefKey:@"defaultBundledAppID"]] ?: @"weston-terminal";
    _defaultWaypipeEnabled = [_defaults objectForKey:[self prefKey:@"defaultWaypipeEnabled"]]
                                 ? [_defaults boolForKey:[self prefKey:@"defaultWaypipeEnabled"]]
                                 : YES;
    _sshHost = [_defaults stringForKey:[self prefKey:@"sshHost"]] ?: @"";
    _sshUser = [_defaults stringForKey:[self prefKey:@"sshUser"]] ?: @"";
    NSInteger port = [_defaults integerForKey:[self prefKey:@"sshPort"]];
    _sshPort = port > 0 ? port : 22;
    _sshPassword = [_defaults stringForKey:[self prefKey:@"sshPassword"]] ?: @"";
    _logLevel = [_defaults stringForKey:[self prefKey:@"logLevel"]] ?: @"info";
    _shakeToCloseEnabled = [_defaults objectForKey:[self prefKey:@"shakeToCloseEnabled"]]
                               ? [_defaults boolForKey:[self prefKey:@"shakeToCloseEnabled"]]
                               : YES;
    _swipeBackToCloseEnabled =
        [_defaults objectForKey:[self prefKey:@"swipeBackToCloseEnabled"]]
            ? [_defaults boolForKey:[self prefKey:@"swipeBackToCloseEnabled"]]
            : YES;
}

- (void)synchronize {
    [_defaults setBool:_autoScale forKey:[self prefKey:@"autoScale"]];
    [_defaults setBool:_forceSSD forKey:@"ForceServerSideDecorations"];
    [_defaults setBool:_forceSSD forKey:[self prefKey:@"forceSSD"]];
    [_defaults setBool:_colorOperations forKey:[self prefKey:@"colorOperations"]];
    [_defaults setObject:_renderer ?: @"metal" forKey:[self prefKey:@"renderer"]];
    [_defaults setObject:_waylandDisplay ?: @"wayland-0" forKey:[self prefKey:@"waylandDisplay"]];
    [_defaults setObject:_defaultInputProfile ?: @"direct"
                  forKey:[self prefKey:@"defaultInputProfile"]];
    [_defaults setObject:_defaultBundledAppID ?: @"weston-terminal"
                  forKey:[self prefKey:@"defaultBundledAppID"]];
    [_defaults setBool:_defaultWaypipeEnabled forKey:[self prefKey:@"defaultWaypipeEnabled"]];
    [_defaults setObject:_sshHost ?: @"" forKey:[self prefKey:@"sshHost"]];
    [_defaults setObject:_sshUser ?: @"" forKey:[self prefKey:@"sshUser"]];
    [_defaults setInteger:_sshPort > 0 ? _sshPort : 22 forKey:[self prefKey:@"sshPort"]];
    [_defaults setObject:_sshPassword ?: @"" forKey:[self prefKey:@"sshPassword"]];
    [_defaults setObject:_logLevel ?: @"info" forKey:[self prefKey:@"logLevel"]];
    [_defaults setBool:_shakeToCloseEnabled forKey:[self prefKey:@"shakeToCloseEnabled"]];
    [_defaults setBool:_swipeBackToCloseEnabled forKey:[self prefKey:@"swipeBackToCloseEnabled"]];
    [_defaults synchronize];

    // Keep Swift `WawonaPreferences` in sync when WatchKit toggles prefs.
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"WawonaPreferencesDidSave"
                      object:self];
}

@end
