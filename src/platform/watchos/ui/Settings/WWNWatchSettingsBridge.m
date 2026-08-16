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

- (BOOL)boolForPref:(NSString *)suffix objcKey:(nullable NSString *)objcKey fallback:(BOOL)fallback {
    if (objcKey && [_defaults objectForKey:objcKey] != nil) {
        return [_defaults boolForKey:objcKey];
    }
    NSString *pref = [self prefKey:suffix];
    if ([_defaults objectForKey:pref] != nil) {
        return [_defaults boolForKey:pref];
    }
    return fallback;
}

- (NSString *)stringForPref:(NSString *)suffix objcKey:(nullable NSString *)objcKey fallback:(NSString *)fallback {
    NSString *objc = objcKey ? [_defaults stringForKey:objcKey] : nil;
    if (objc.length > 0) {
        return objc;
    }
    return [_defaults stringForKey:[self prefKey:suffix]] ?: fallback;
}

- (void)reloadFromDefaults {
    _autoScale = [self boolForPref:@"autoScale" objcKey:nil fallback:YES];
    if ([_defaults objectForKey:@"ForceServerSideDecorations"] != nil) {
        _forceSSD = [_defaults boolForKey:@"ForceServerSideDecorations"];
    } else {
        _forceSSD = [_defaults boolForKey:[self prefKey:@"forceSSD"]];
    }
    _colorOperations = [self boolForPref:@"colorOperations" objcKey:@"ColorOperations" fallback:NO];
    _renderer = [self stringForPref:@"renderer" objcKey:nil fallback:@"metal"];
    _waylandDisplay = [self stringForPref:@"waylandDisplay" objcKey:nil fallback:@"wayland-0"];
    NSString *input = [_defaults stringForKey:[self prefKey:@"defaultInputProfile"]]
        ?: [_defaults stringForKey:@"TouchInputType"]
        ?: @"Multi-Touch";
    NSString *lower = input.lowercaseString;
    if ([lower isEqualToString:@"touchpad"] || [lower isEqualToString:@"pointer"] ||
        [lower isEqualToString:@"virtual"] || [lower isEqualToString:@"virtual-pointer"] ||
        [lower isEqualToString:@"trackpad"]) {
        _defaultInputProfile = @"Touchpad";
    } else {
        _defaultInputProfile = @"Multi-Touch";
    }
    _defaultBundledAppID =
        [_defaults stringForKey:[self prefKey:@"defaultBundledAppID"]] ?: @"weston-terminal";
    _defaultWaypipeEnabled = [self boolForPref:@"defaultWaypipeEnabled" objcKey:nil fallback:YES];
    _renderMacOSPointer = [self boolForPref:@"renderMacOSPointer" objcKey:@"RenderMacOSPointer" fallback:NO];
    NSString *nested = [_defaults stringForKey:@"NestedCompositorCursor"]
        ?: [_defaults stringForKey:[self prefKey:@"nestedCompositorCursor"]]
        ?: @"virtual";
    _nestedCompositorCursor = [nested isEqualToString:@"host"] ? @"host" : @"virtual";
    _resizeDisplayForVirtualKeyboard =
        [self boolForPref:@"resizeDisplayForVirtualKeyboard"
                 objcKey:@"resizeDisplayForVirtualKeyboard"
                fallback:YES];
    _swapCmdWithAlt = [self boolForPref:@"swapCmdWithAlt" objcKey:@"SwapCmdWithAlt" fallback:YES];
    _universalClipboard =
        [self boolForPref:@"universalClipboard" objcKey:@"UniversalClipboard" fallback:YES];
    _compositorBackend = [self stringForPref:@"compositorBackend" objcKey:@"CompositorBackend" fallback:@"auto"];
    _nestedCompositorsSupport =
        [self boolForPref:@"nestedCompositorsSupport" objcKey:@"NestedCompositorsSupport" fallback:YES];
    _multipleClients = [self boolForPref:@"multipleClients" objcKey:@"MultipleClients" fallback:NO];
    _xwaylandSupport = [self boolForPref:@"xwaylandSupport" objcKey:@"WaypipeXwls" fallback:NO];
    _waypipeCompress = [self stringForPref:@"waypipeCompress" objcKey:@"WaypipeCompress" fallback:@"lz4"];
    _waypipeVideo = [self stringForPref:@"waypipeVideo" objcKey:@"WaypipeVideo" fallback:@"none"];
    _waypipeRemoteCommand =
        [self stringForPref:@"waypipeRemoteCommand" objcKey:@"WaypipeRemoteCommand" fallback:@""];
    _waypipeDebug = [self boolForPref:@"waypipeDebug" objcKey:@"WaypipeDebug" fallback:NO];
    _waypipeNoGpu = [self boolForPref:@"waypipeNoGpu" objcKey:@"WaypipeNoGpu" fallback:NO];
    _waypipeSSHPassword = [_defaults stringForKey:[self prefKey:@"waypipeSSHPassword"]] ?: @"";
    _sshHost = [_defaults stringForKey:[self prefKey:@"sshHost"]] ?: @"";
    _sshUser = [_defaults stringForKey:[self prefKey:@"sshUser"]] ?: @"";
    NSInteger port = [_defaults integerForKey:[self prefKey:@"sshPort"]];
    _sshPort = port > 0 ? port : 22;
    _sshPassword = [_defaults stringForKey:[self prefKey:@"sshPassword"]] ?: @"";
    if ([_defaults objectForKey:@"SSHAuthMethod"] != nil) {
        _sshAuthMethod = [_defaults integerForKey:@"SSHAuthMethod"];
    } else {
        _sshAuthMethod = [_defaults integerForKey:[self prefKey:@"sshAuthMethod"]];
    }
    _sshKeyPath = [_defaults stringForKey:@"SSHKeyPath"]
        ?: [_defaults stringForKey:[self prefKey:@"sshKeyPath"]] ?: @"";
    _sshKeyPassphrase = [_defaults stringForKey:@"SSHKeyPassphrase"]
        ?: [_defaults stringForKey:[self prefKey:@"sshKeyPassphrase"]] ?: @"";
    _sshKeyType = [_defaults stringForKey:@"SSHKeyType"]
        ?: [_defaults stringForKey:[self prefKey:@"sshKeyType"]] ?: @"ed25519";
    _logLevel = [_defaults stringForKey:[self prefKey:@"logLevel"]] ?: @"info";
    _shakeToCloseEnabled = [self boolForPref:@"shakeToCloseEnabled" objcKey:nil fallback:YES];
    _swipeBackToCloseEnabled = [self boolForPref:@"swipeBackToCloseEnabled" objcKey:nil fallback:YES];
}

- (void)synchronize {
    [_defaults setBool:_autoScale forKey:[self prefKey:@"autoScale"]];
    [_defaults setBool:_forceSSD forKey:@"ForceServerSideDecorations"];
    [_defaults setBool:_forceSSD forKey:[self prefKey:@"forceSSD"]];
    [_defaults setBool:_colorOperations forKey:[self prefKey:@"colorOperations"]];
    [_defaults setBool:_colorOperations forKey:@"ColorOperations"];
    [_defaults setObject:_renderer ?: @"metal" forKey:[self prefKey:@"renderer"]];
    [_defaults setObject:_waylandDisplay ?: @"wayland-0" forKey:[self prefKey:@"waylandDisplay"]];
    NSString *input = _defaultInputProfile.length > 0 ? _defaultInputProfile : @"Multi-Touch";
    [_defaults setObject:input forKey:[self prefKey:@"defaultInputProfile"]];
    [_defaults setObject:input forKey:@"TouchInputType"];
    [_defaults setObject:_defaultBundledAppID ?: @"weston-terminal"
                  forKey:[self prefKey:@"defaultBundledAppID"]];
    [_defaults setBool:_defaultWaypipeEnabled forKey:[self prefKey:@"defaultWaypipeEnabled"]];
    [_defaults setBool:_renderMacOSPointer forKey:@"RenderMacOSPointer"];
    [_defaults setObject:([_nestedCompositorCursor isEqualToString:@"host"] ? @"host" : @"virtual")
                  forKey:@"NestedCompositorCursor"];
    [_defaults setBool:_resizeDisplayForVirtualKeyboard forKey:@"resizeDisplayForVirtualKeyboard"];
    [_defaults setBool:_swapCmdWithAlt forKey:@"SwapCmdWithAlt"];
    [_defaults setBool:_universalClipboard forKey:@"UniversalClipboard"];
    [_defaults setObject:_compositorBackend ?: @"auto" forKey:@"CompositorBackend"];
    [_defaults setObject:_compositorBackend ?: @"auto" forKey:[self prefKey:@"compositorBackend"]];
    [_defaults setBool:_nestedCompositorsSupport forKey:@"NestedCompositorsSupport"];
    [_defaults setBool:_multipleClients forKey:@"MultipleClients"];
    [_defaults setBool:_xwaylandSupport forKey:[self prefKey:@"xwaylandSupport"]];
    [_defaults setBool:_xwaylandSupport forKey:@"WaypipeXwls"];
    [_defaults setObject:_waypipeCompress ?: @"lz4" forKey:@"WaypipeCompress"];
    [_defaults setObject:_waypipeVideo ?: @"none" forKey:@"WaypipeVideo"];
    [_defaults setObject:_waypipeRemoteCommand ?: @"" forKey:@"WaypipeRemoteCommand"];
    [_defaults setBool:_waypipeDebug forKey:@"WaypipeDebug"];
    [_defaults setBool:_waypipeNoGpu forKey:@"WaypipeNoGpu"];
    [_defaults setObject:_waypipeSSHPassword ?: @"" forKey:[self prefKey:@"waypipeSSHPassword"]];
    [_defaults setObject:_sshHost ?: @"" forKey:[self prefKey:@"sshHost"]];
    [_defaults setObject:_sshUser ?: @"" forKey:[self prefKey:@"sshUser"]];
    [_defaults setInteger:_sshPort > 0 ? _sshPort : 22 forKey:[self prefKey:@"sshPort"]];
    [_defaults setObject:_sshPassword ?: @"" forKey:[self prefKey:@"sshPassword"]];
    [_defaults setInteger:_sshAuthMethod forKey:[self prefKey:@"sshAuthMethod"]];
    [_defaults setInteger:_sshAuthMethod forKey:@"SSHAuthMethod"];
    [_defaults setObject:_sshKeyPath ?: @"" forKey:[self prefKey:@"sshKeyPath"]];
    [_defaults setObject:_sshKeyPath ?: @"" forKey:@"SSHKeyPath"];
    [_defaults setObject:_sshKeyPassphrase ?: @"" forKey:[self prefKey:@"sshKeyPassphrase"]];
    [_defaults setObject:_sshKeyPassphrase ?: @"" forKey:@"SSHKeyPassphrase"];
    [_defaults setObject:_sshKeyType ?: @"ed25519" forKey:[self prefKey:@"sshKeyType"]];
    [_defaults setObject:_sshKeyType ?: @"ed25519" forKey:@"SSHKeyType"];
    [_defaults setObject:_logLevel ?: @"info" forKey:[self prefKey:@"logLevel"]];
    [_defaults setBool:_shakeToCloseEnabled forKey:[self prefKey:@"shakeToCloseEnabled"]];
    [_defaults setBool:_swipeBackToCloseEnabled forKey:[self prefKey:@"swipeBackToCloseEnabled"]];
    [_defaults synchronize];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"WawonaPreferencesDidSave"
                      object:self];
}

@end
