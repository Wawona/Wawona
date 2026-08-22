#import "WWNWatchSettingsInterfaceController.h"
#import "WWNWatchSettingsBridge.h"
#import "WWNWatchCompositorBridge.h"

static NSString *const kWWNWatchSettingsSectionKey = @"section";

typedef NS_ENUM(NSInteger, WWNWatchSettingsRowKind) {
    WWNWatchSettingsRowKindToggle,
    WWNWatchSettingsRowKindAction,
};

@interface WWNWatchSettingsRowModel : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) WWNWatchSettingsRowKind kind;
@property (nonatomic, copy, nullable) NSString *actionKey;
@property (nonatomic, copy, nullable) NSString *valueText;
@property (nonatomic, assign) BOOL boolValue;
@end

@implementation WWNWatchSettingsRowModel
@end

// MARK: - Root (section list)

@interface WWNWatchSettingsRootInterfaceController ()
@property (weak, nonatomic) IBOutlet WKInterfaceTable *sectionsTable;
@end

@implementation WWNWatchSettingsRootInterfaceController

- (void)awakeWithContext:(id)context {
    [super awakeWithContext:context];
    [self setTitle:@"Wawona Settings"];
    NSArray<NSString *> *sections = @[
        @"Display",
        @"Input",
        @"Graphics",
        @"Connection",
        @"Waypipe",
        @"SSH",
        @"Machines",
        @"iCloud Sync",
        @"Advanced",
        @"About",
        @"Dependencies",
    ];
    [self.sectionsTable setNumberOfRows:sections.count withRowType:@"SectionRow"];
    for (NSInteger i = 0; i < (NSInteger)sections.count; i++) {
        WWNWatchSettingsActionRowController *row =
            [self.sectionsTable rowControllerAtIndex:i];
        [row.titleLabel setText:sections[(NSUInteger)i]];
        [row.valueLabel setText:@""];
    }
}

- (void)table:(WKInterfaceTable *)table didSelectRowAtIndex:(NSInteger)rowIndex {
    (void)table;
    NSArray<NSString *> *sections = @[
        @"Display",
        @"Input",
        @"Graphics",
        @"Connection",
        @"Waypipe",
        @"SSH",
        @"Machines",
        @"iCloud Sync",
        @"Advanced",
        @"About",
        @"Dependencies",
    ];
    if (rowIndex < 0 || rowIndex >= (NSInteger)sections.count) {
        return;
    }
    [self pushControllerWithName:@"SettingsDetail"
                           context:@{kWWNWatchSettingsSectionKey : sections[(NSUInteger)rowIndex]}];
}

@end

// MARK: - Detail (section editor)

@interface WWNWatchSettingsDetailInterfaceController ()
@property (weak, nonatomic) IBOutlet WKInterfaceTable *settingsTable;
@property (nonatomic, copy) NSString *sectionTitle;
@property (nonatomic, copy) NSArray<WWNWatchSettingsRowModel *> *rows;
@end

@implementation WWNWatchSettingsDetailInterfaceController

- (WWNWatchSettingsBridge *)bridge {
    return [WWNWatchSettingsBridge sharedBridge];
}

- (void)awakeWithContext:(id)context {
    [super awakeWithContext:context];
    [[self bridge] reloadFromDefaults];
    self.sectionTitle = [(NSDictionary *)context objectForKey:kWWNWatchSettingsSectionKey] ?: @"Settings";
    [self setTitle:self.sectionTitle];
    self.rows = [self buildRowsForSection:self.sectionTitle];
    [self reloadTable];
}

- (NSArray<WWNWatchSettingsRowModel *> *)buildRowsForSection:(NSString *)section {
    WWNWatchSettingsBridge *bridge = [self bridge];
    if ([section isEqualToString:@"Display"]) {
        return @[
            [self toggleRow:@"Enable HDR" key:@"colorOperations" value:bridge.colorOperations],
        ];
    }
    if ([section isEqualToString:@"Input"]) {
        return @[
            [self toggleRow:@"Show Virtual Cursor" key:@"renderMacOSPointer" value:bridge.renderMacOSPointer],
            [self actionRow:@"Nested Compositor Cursor" key:@"nestedCompositorCursor" value:bridge.nestedCompositorCursor],
            [self actionRow:@"Touch Input Type" key:@"defaultInputProfile" value:bridge.defaultInputProfile],
            [self toggleRow:@"Resize Display for Virtual Keyboard" key:@"resizeDisplayForVirtualKeyboard" value:bridge.resizeDisplayForVirtualKeyboard],
            [self toggleRow:@"Swap CMD with ALT" key:@"swapCmdWithAlt" value:bridge.swapCmdWithAlt],
            [self toggleRow:@"Universal Clipboard" key:@"universalClipboard" value:bridge.universalClipboard],
        ];
    }
    if ([section isEqualToString:@"Graphics"]) {
        return @[
            [self actionRow:@"Renderer" key:@"renderer" value:bridge.renderer],
            [self actionRow:@"Vulkan Driver" key:@"" value:@"none"],
            [self actionRow:@"OpenGL Driver" key:@"" value:@"none"],
        ];
    }
    if ([section isEqualToString:@"Connection"]) {
        return @[
            [self actionRow:@"Wayland Display" key:@"waylandDisplay" value:bridge.waylandDisplay],
            [self actionRow:@"Default Wayland Client" key:@"defaultBundledAppID" value:bridge.defaultBundledAppID],
        ];
    }
    if ([section isEqualToString:@"Waypipe"]) {
        return @[
            [self toggleRow:@"Waypipe by Default" key:@"defaultWaypipeEnabled" value:bridge.defaultWaypipeEnabled],
            [self toggleRow:@"XWayland" key:@"xwaylandSupport" value:bridge.xwaylandSupport],
            [self actionRow:@"Compression" key:@"waypipeCompress" value:bridge.waypipeCompress],
            [self actionRow:@"Video Codec" key:@"waypipeVideo" value:bridge.waypipeVideo],
            [self actionRow:@"Remote Command" key:@"waypipeRemoteCommand" value:bridge.waypipeRemoteCommand],
            [self toggleRow:@"Debug Mode" key:@"waypipeDebug" value:bridge.waypipeDebug],
            [self toggleRow:@"Disable GPU" key:@"waypipeNoGpu" value:bridge.waypipeNoGpu],
        ];
    }
    if ([section isEqualToString:@"SSH"] || [section isEqualToString:@"SSH Defaults"]) {
        NSMutableArray<WWNWatchSettingsRowModel *> *sshRows = [NSMutableArray arrayWithArray:@[
            [self actionRow:@"Host" key:@"sshHost" value:bridge.sshHost],
            [self actionRow:@"User" key:@"sshUser" value:bridge.sshUser],
            [self actionRow:@"Port" key:@"sshPort" value:[NSString stringWithFormat:@"%ld", (long)bridge.sshPort]],
            [self actionRow:@"Auth" key:@"sshAuthMethod" value:bridge.sshAuthMethod == 1 ? @"Public Key" : @"Password"],
        ]];
        if (bridge.sshAuthMethod == 0) {
            [sshRows addObject:[self actionRow:@"Password" key:@"sshPassword" value:bridge.sshPassword.length > 0 ? @"••••••" : @""]];
        } else {
            [sshRows addObject:[self actionRow:@"Key Type" key:@"sshKeyType" value:bridge.sshKeyType]];
            [sshRows addObject:[self actionRow:@"Key Path" key:@"sshKeyPath" value:bridge.sshKeyPath]];
            [sshRows addObject:[self actionRow:@"Key Passphrase" key:@"sshKeyPassphrase" value:bridge.sshKeyPassphrase.length > 0 ? @"••••••" : @""]];
        }
        return sshRows;
    }
    if ([section isEqualToString:@"Machines"]) {
        return @[
            [self toggleRow:@"Shake to Exit Machine" key:@"shakeToCloseEnabled" value:bridge.shakeToCloseEnabled],
            [self toggleRow:@"Swipe Back to Exit Machine" key:@"swipeBackToCloseEnabled" value:bridge.swipeBackToCloseEnabled],
        ];
    }
    if ([section isEqualToString:@"iCloud Sync"]) {
        return @[
            [self actionRow:@"iCloud Status" key:@"" value:@"Not available on watchOS"],
        ];
    }
    if ([section isEqualToString:@"Advanced"]) {
        return @[
            [self toggleRow:@"Nested Compositors" key:@"nestedCompositorsSupport" value:bridge.nestedCompositorsSupport],
            [self actionRow:@"Display Backend" key:@"compositorBackend" value:bridge.compositorBackend],
            [self toggleRow:@"Multiple Clients" key:@"multipleClients" value:bridge.multipleClients],
            [self actionRow:@"Log Level" key:@"logLevel" value:bridge.logLevel],
        ];
    }
    if ([section isEqualToString:@"Dependencies"]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"SettingsDependencies"
                                                        ofType:@"json"];
        NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *packages = [json isKindOfClass:[NSDictionary class]] ? json[@"packages"] : nil;
        NSMutableArray *rows = [NSMutableArray array];
        if ([packages isKindOfClass:[NSArray class]]) {
            for (NSDictionary *pkg in packages) {
                if (![pkg isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                NSString *name = pkg[@"name"] ?: @"Package";
                NSString *version = pkg[@"version"] ?: @"";
                [rows addObject:[self actionRow:name key:@"" value:version]];
            }
        }
        if (rows.count == 0) {
            [rows addObject:[self actionRow:@"Dependencies" key:@"" value:@"unavailable"]];
        }
        return rows;
    }
    if ([section isEqualToString:@"About"]) {
        NSString *raw = [[NSBundle mainBundle]
            objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString *version = (raw.length > 0) ? raw : @"0.0.0";
        if (![version hasPrefix:@"v"]) {
            version = [@"v" stringByAppendingString:version];
        }
        return @[
            [self actionRow:@"Version" key:@"" value:version],
            [self actionRow:@"Platform" key:@"" value:@"watchOS"],
            [self actionRow:@"Author" key:@"" value:@"Alex Spaulding"],
            [self actionRow:@"Source" key:@"" value:@"github.com/wawona/wawona"],
        ];
    }
    return @[];
}

- (WWNWatchSettingsRowModel *)toggleRow:(NSString *)title key:(NSString *)key value:(BOOL)value {
    WWNWatchSettingsRowModel *row = [[WWNWatchSettingsRowModel alloc] init];
    row.title = title;
    row.kind = WWNWatchSettingsRowKindToggle;
    row.actionKey = key;
    row.boolValue = value;
    row.valueText = value ? @"On" : @"Off";
    return row;
}

- (WWNWatchSettingsRowModel *)actionRow:(NSString *)title key:(NSString *)key value:(NSString *)value {
    WWNWatchSettingsRowModel *row = [[WWNWatchSettingsRowModel alloc] init];
    row.title = title;
    row.kind = WWNWatchSettingsRowKindAction;
    row.actionKey = key;
    row.valueText = value ?: @"";
    return row;
}

- (void)reloadTable {
    [self.settingsTable setNumberOfRows:self.rows.count withRowType:@"ActionRow"];
    for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
        WWNWatchSettingsRowModel *model = self.rows[(NSUInteger)i];
        WWNWatchSettingsActionRowController *row =
            [self.settingsTable rowControllerAtIndex:i];
        [row.titleLabel setText:model.title];
        [row.valueLabel setText:model.valueText ?: @""];
    }
}

- (void)table:(WKInterfaceTable *)table didSelectRowAtIndex:(NSInteger)rowIndex {
    (void)table;
    if (rowIndex < 0 || rowIndex >= (NSInteger)self.rows.count) {
        return;
    }
    WWNWatchSettingsRowModel *model = self.rows[(NSUInteger)rowIndex];
    if (model.kind == WWNWatchSettingsRowKindToggle) {
        model.boolValue = !model.boolValue;
        [self applyToggleValue:model.boolValue forKey:model.actionKey];
        self.rows = [self buildRowsForSection:self.sectionTitle];
        [self reloadTable];
        return;
    }
    if (model.actionKey.length == 0) {
        return;
    }

    if ([model.actionKey isEqualToString:@"renderer"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"metal", @"software" ]
                     currentValue:[self bridge].renderer];
        return;
    }
    if ([model.actionKey isEqualToString:@"logLevel"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"debug", @"info", @"warn", @"error" ]
                     currentValue:[self bridge].logLevel];
        return;
    }
    if ([model.actionKey isEqualToString:@"defaultInputProfile"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"Multi-Touch", @"Touchpad" ]
                     currentValue:[self bridge].defaultInputProfile];
        return;
    }
    if ([model.actionKey isEqualToString:@"nestedCompositorCursor"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"virtual", @"host" ]
                     currentValue:[self bridge].nestedCompositorCursor];
        return;
    }
    if ([model.actionKey isEqualToString:@"compositorBackend"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"auto", @"wayland", @"drm" ]
                     currentValue:[self bridge].compositorBackend];
        return;
    }
    if ([model.actionKey isEqualToString:@"waypipeCompress"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"none", @"lz4", @"zstd" ]
                     currentValue:[self bridge].waypipeCompress];
        return;
    }
    if ([model.actionKey isEqualToString:@"waypipeVideo"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"none", @"h264", @"vp9", @"av1" ]
                     currentValue:[self bridge].waypipeVideo];
        return;
    }
    if ([model.actionKey isEqualToString:@"sshAuthMethod"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"Password", @"Public Key" ]
                     currentValue:[self bridge].sshAuthMethod == 1 ? @"Public Key" : @"Password"];
        return;
    }
    if ([model.actionKey isEqualToString:@"sshKeyType"]) {
        [self presentChoiceForKey:model.actionKey
                            title:model.title
                          options:@[ @"ed25519", @"ecdsa", @"rsa" ]
                     currentValue:[self bridge].sshKeyType];
        return;
    }

    NSString *initial = model.valueText ?: @"";
    if ([model.actionKey isEqualToString:@"sshPassword"]) {
        initial = @"";
    }
    __weak typeof(self) weakSelf = self;
    [self presentTextInputControllerWithSuggestions:nil
                                        allowedInputMode:WKTextInputModePlain
                                               completion:^(NSArray<NSString *> *results) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || results.count == 0) {
            return;
        }
        [strongSelf applyTextValue:results.firstObject forKey:model.actionKey];
        strongSelf.rows = [strongSelf buildRowsForSection:strongSelf.sectionTitle];
        [strongSelf reloadTable];
    }];
}

- (void)presentChoiceForKey:(NSString *)key
                       title:(NSString *)title
                     options:(NSArray<NSString *> *)options
                currentValue:(NSString *)currentValue {
    NSMutableArray<WKAlertAction *> *actions = [NSMutableArray arrayWithCapacity:options.count];
    __weak typeof(self) weakSelf = self;
    for (NSString *option in options) {
        WKAlertAction *action = [WKAlertAction actionWithTitle:option
                                                         style:WKAlertActionStyleDefault
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf applyTextValue:option forKey:key];
            strongSelf.rows = [strongSelf buildRowsForSection:strongSelf.sectionTitle];
            [strongSelf reloadTable];
        }];
        [actions addObject:action];
    }
    [self presentAlertControllerWithTitle:title
                                  message:currentValue
                           preferredStyle:WKAlertControllerStyleActionSheet
                                  actions:actions];
}

- (void)applyToggleValue:(BOOL)on forKey:(NSString *)key {
    WWNWatchSettingsBridge *bridge = [self bridge];
    if ([key isEqualToString:@"autoScale"]) {
        bridge.autoScale = on;
    } else if ([key isEqualToString:@"forceSSD"]) {
        bridge.forceSSD = on;
    } else if ([key isEqualToString:@"colorOperations"]) {
        bridge.colorOperations = on;
    } else if ([key isEqualToString:@"defaultWaypipeEnabled"]) {
        bridge.defaultWaypipeEnabled = on;
    } else if ([key isEqualToString:@"renderMacOSPointer"]) {
        bridge.renderMacOSPointer = on;
    } else if ([key isEqualToString:@"resizeDisplayForVirtualKeyboard"]) {
        bridge.resizeDisplayForVirtualKeyboard = on;
    } else if ([key isEqualToString:@"swapCmdWithAlt"]) {
        bridge.swapCmdWithAlt = on;
    } else if ([key isEqualToString:@"universalClipboard"]) {
        bridge.universalClipboard = on;
    } else if ([key isEqualToString:@"nestedCompositorsSupport"]) {
        bridge.nestedCompositorsSupport = on;
    } else if ([key isEqualToString:@"multipleClients"]) {
        bridge.multipleClients = on;
    } else if ([key isEqualToString:@"xwaylandSupport"]) {
        bridge.xwaylandSupport = on;
    } else if ([key isEqualToString:@"waypipeDebug"]) {
        bridge.waypipeDebug = on;
    } else if ([key isEqualToString:@"waypipeNoGpu"]) {
        bridge.waypipeNoGpu = on;
    } else if ([key isEqualToString:@"shakeToCloseEnabled"]) {
        bridge.shakeToCloseEnabled = on;
    } else if ([key isEqualToString:@"swipeBackToCloseEnabled"]) {
        bridge.swipeBackToCloseEnabled = on;
    }
    [bridge synchronize];
}

- (void)applyTextValue:(NSString *)value forKey:(NSString *)key {
    WWNWatchSettingsBridge *bridge = [self bridge];
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([key isEqualToString:@"renderer"]) {
        bridge.renderer = trimmed.length > 0 ? trimmed : @"metal";
    } else if ([key isEqualToString:@"waylandDisplay"]) {
        bridge.waylandDisplay = trimmed.length > 0 ? trimmed : @"wayland-0";
    } else if ([key isEqualToString:@"defaultInputProfile"]) {
        bridge.defaultInputProfile = trimmed.length > 0 ? trimmed : @"Multi-Touch";
    } else if ([key isEqualToString:@"defaultBundledAppID"]) {
        bridge.defaultBundledAppID = trimmed.length > 0 ? trimmed : @"weston-terminal";
    } else if ([key isEqualToString:@"nestedCompositorCursor"]) {
        bridge.nestedCompositorCursor = [trimmed isEqualToString:@"host"] ? @"host" : @"virtual";
    } else if ([key isEqualToString:@"compositorBackend"]) {
        bridge.compositorBackend = trimmed.length > 0 ? trimmed : @"auto";
    } else if ([key isEqualToString:@"waypipeCompress"]) {
        bridge.waypipeCompress = trimmed.length > 0 ? trimmed : @"lz4";
    } else if ([key isEqualToString:@"waypipeVideo"]) {
        bridge.waypipeVideo = trimmed.length > 0 ? trimmed : @"none";
    } else if ([key isEqualToString:@"waypipeRemoteCommand"]) {
        bridge.waypipeRemoteCommand = trimmed;
    } else if ([key isEqualToString:@"sshHost"]) {
        bridge.sshHost = trimmed;
    } else if ([key isEqualToString:@"sshUser"]) {
        bridge.sshUser = trimmed;
    } else if ([key isEqualToString:@"sshPort"]) {
        bridge.sshPort = trimmed.integerValue > 0 ? trimmed.integerValue : 22;
    } else if ([key isEqualToString:@"sshPassword"]) {
        bridge.sshPassword = value ?: @"";
    } else if ([key isEqualToString:@"sshAuthMethod"]) {
        bridge.sshAuthMethod = [trimmed isEqualToString:@"Public Key"] ? 1 : 0;
    } else if ([key isEqualToString:@"sshKeyType"]) {
        bridge.sshKeyType = trimmed.length > 0 ? trimmed : @"ed25519";
    } else if ([key isEqualToString:@"sshKeyPath"]) {
        bridge.sshKeyPath = trimmed;
    } else if ([key isEqualToString:@"sshKeyPassphrase"]) {
        bridge.sshKeyPassphrase = value ?: @"";
    } else if ([key isEqualToString:@"logLevel"]) {
        bridge.logLevel = trimmed.length > 0 ? trimmed : @"info";
    }
    [bridge synchronize];
}

@end

// MARK: - Row controllers

@implementation WWNWatchSettingsActionRowController
@end
