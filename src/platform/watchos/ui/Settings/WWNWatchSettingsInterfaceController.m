#import "WWNWatchSettingsInterfaceController.h"
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
        @"Graphics",
        @"Connection",
        @"SSH Defaults",
        @"Advanced",
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
        @"Graphics",
        @"Connection",
        @"SSH Defaults",
        @"Advanced",
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
    self.sectionTitle = [(NSDictionary *)context objectForKey:kWWNWatchSettingsSectionKey] ?: @"Settings";
    [self setTitle:self.sectionTitle];
    self.rows = [self buildRowsForSection:self.sectionTitle];
    [self reloadTable];
}

- (NSArray<WWNWatchSettingsRowModel *> *)buildRowsForSection:(NSString *)section {
    WWNWatchSettingsBridge *bridge = [self bridge];
    if ([section isEqualToString:@"Display"]) {
        return @[
            [self toggleRow:@"Auto Scale" key:@"autoScale" value:bridge.autoScale],
            [self toggleRow:@"Force SSD" key:@"forceSSD" value:bridge.forceSSD],
            [self toggleRow:@"Color Operations (HDR)" key:@"colorOperations" value:bridge.colorOperations],
        ];
    }
    if ([section isEqualToString:@"Graphics"]) {
        return @[
            [self actionRow:@"Renderer" key:@"renderer" value:bridge.renderer],
        ];
    }
    if ([section isEqualToString:@"Connection"]) {
        return @[
            [self actionRow:@"Wayland Display" key:@"waylandDisplay" value:bridge.waylandDisplay],
            [self actionRow:@"Input Profile" key:@"defaultInputProfile" value:bridge.defaultInputProfile],
            [self actionRow:@"Bundled App ID" key:@"defaultBundledAppID" value:bridge.defaultBundledAppID],
            [self toggleRow:@"Waypipe by Default" key:@"defaultWaypipeEnabled" value:bridge.defaultWaypipeEnabled],
        ];
    }
    if ([section isEqualToString:@"SSH Defaults"]) {
        return @[
            [self actionRow:@"Host" key:@"sshHost" value:bridge.sshHost],
            [self actionRow:@"User" key:@"sshUser" value:bridge.sshUser],
            [self actionRow:@"Port" key:@"sshPort" value:[NSString stringWithFormat:@"%ld", (long)bridge.sshPort]],
            [self actionRow:@"Password" key:@"sshPassword" value:bridge.sshPassword.length > 0 ? @"••••••" : @""],
        ];
    }
    if ([section isEqualToString:@"Advanced"]) {
        return @[
            [self actionRow:@"Log Level" key:@"logLevel" value:bridge.logLevel],
            [self toggleRow:@"XWayland Support" key:@"xwaylandSupport" value:bridge.xwaylandSupport],
            [self toggleRow:@"Shake to Close" key:@"shakeToCloseEnabled" value:bridge.shakeToCloseEnabled],
            [self toggleRow:@"Swipe Back to Close" key:@"swipeBackToCloseEnabled" value:bridge.swipeBackToCloseEnabled],
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
    } else if ([key isEqualToString:@"xwaylandSupport"]) {
        bridge.xwaylandSupport = on;
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
        bridge.defaultInputProfile = trimmed.length > 0 ? trimmed : @"direct";
    } else if ([key isEqualToString:@"defaultBundledAppID"]) {
        bridge.defaultBundledAppID = trimmed.length > 0 ? trimmed : @"weston-simple-shm";
    } else if ([key isEqualToString:@"sshHost"]) {
        bridge.sshHost = trimmed;
    } else if ([key isEqualToString:@"sshUser"]) {
        bridge.sshUser = trimmed;
    } else if ([key isEqualToString:@"sshPort"]) {
        bridge.sshPort = trimmed.integerValue > 0 ? trimmed.integerValue : 22;
    } else if ([key isEqualToString:@"sshPassword"]) {
        bridge.sshPassword = value ?: @"";
    } else if ([key isEqualToString:@"logLevel"]) {
        bridge.logLevel = trimmed.length > 0 ? trimmed : @"info";
    }
    [bridge synchronize];
}

@end

// MARK: - Row controllers

@implementation WWNWatchSettingsActionRowController
@end
