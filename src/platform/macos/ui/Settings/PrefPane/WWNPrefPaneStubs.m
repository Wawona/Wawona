// Stubs for classes the System Settings pane must not link (compositor,
// Mode B engage, waypipe process). Actions hand off to Wawona.app.
#import "WWNPrefPaneHandoff.h"
#import "../../WWNCompositorBridge.h"
#import "../../WWNRootfsProvider.h"
#import "../../WWNRootfsICloudSync.h"
#import "../Helpers/WWNSSHKeygen.h"
#import "../Machines/WWNDesktopReplacementController.h"
#import "../Machines/WWNMachineProfileStore.h"
#import "../Machines/WWNMachinesCoordinator.h"
#import "WWNPreferencesManager.h"
#import "WWNWaypipeRunner.h"

#include <stdlib.h>
#include <string.h>

void (*wwn_startup_log_sink)(const char *module, const char *msg) = NULL;
int wwn_log_quiet = 0;

void wwn_log_ring_append(const char *module, const char *msg) {
  (void)module;
  (void)msg;
}
void wwn_log_ring_set_machine(const char *machine_id) { (void)machine_id; }
char *wwn_log_ring_dump(const char *machine_id_or_null) {
  (void)machine_id_or_null;
  return strdup("");
}
char *wwn_github_bug_report_url(const char *platform,
                                const char *install_channel,
                                const char *wawona_version,
                                const char *host_os, const char *logs) {
  (void)platform;
  (void)install_channel;
  (void)wawona_version;
  (void)host_os;
  (void)logs;
  return strdup("https://github.com/Wawona/Wawona/issues/new");
}
void WWNStringFree(char *s) { free(s); }

NSString *WWNWawonaAppBundleRoot(void) {
  return @"/Applications/Wawona.app";
}
NSString *WWNWawonaAppBundleRootForUI(void) {
  return WWNWawonaAppBundleRoot();
}
NSString *WWNWawonaExecutableDirectory(void) {
  return @"/Applications/Wawona.app/Contents/MacOS";
}
NSString *WWNWawonaFindBundledExecutable(NSString *name) {
  if (name.length == 0) {
    return nil;
  }
  NSString *path = [NSString
      stringWithFormat:@"/Applications/Wawona.app/Contents/Resources/bin/%@",
                       name];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }
  path = [NSString
      stringWithFormat:@"/Applications/Wawona.app/Contents/MacOS/%@", name];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    return path;
  }
  return nil;
}

NSNotificationName const WWNNativeClientWillLaunchNotification =
    @"WWNNativeClientWillLaunchNotification";
NSNotificationName const WWNClientMinimizeRequestedNotification =
    @"WWNClientMinimizeRequestedNotification";
NSNotificationName const WWNClientFocusRequestedNotification =
    @"WWNClientFocusRequestedNotification";
NSNotificationName const WWNHostWindowsDidChangeNotification =
    @"WWNHostWindowsDidChangeNotification";

BOOL WWNWestonDemoPrefersFixedSquare(NSString *clientId, NSString *title) {
  (void)clientId;
  (void)title;
  return NO;
}

@implementation WWNCompositorBridge
+ (instancetype)sharedBridge {
  static WWNCompositorBridge *s;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    s = [[self alloc] init];
  });
  return s;
}
- (void)setForceSSD:(BOOL)enabled {
  (void)enabled;
}
- (void)setForceSSDForClientLaunch:(BOOL)enabled {
  (void)enabled;
}
@end

BOOL WWNHostSessionUsesOwnDisplayDRM(void) { return NO; }

static NSString *sCLIBackend = nil;

NSString *WWNResolveCompositorBackend(NSString *overrideValue) {
  if (overrideValue.length > 0 &&
      ![overrideValue isEqualToString:@"auto"]) {
    return overrideValue;
  }
  if (sCLIBackend.length > 0) {
    return sCLIBackend;
  }
  return @"wayland";
}

void WWNSetCompositorBackendCLIOverride(NSString *backend) {
  sCLIBackend = [backend copy];
}

NSString *WWNCompositorBackendCLIOverride(void) { return sCLIBackend; }

@implementation WWNWaypipeRunner
+ (instancetype)sharedRunner {
  static WWNWaypipeRunner *s;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    s = [[self alloc] init];
  });
  return s;
}
- (BOOL)isRunning {
  return NO;
}
- (BOOL)isWestonSimpleSHMRunning {
  return NO;
}
- (BOOL)westonRunning {
  return NO;
}
- (BOOL)westonTerminalRunning {
  return NO;
}
- (BOOL)footRunning {
  return NO;
}
- (NSString *)findWaypipeBinary {
  return nil;
}
- (NSArray<NSString *> *)buildWaypipeArguments:(WWNPreferencesManager *)prefs {
  (void)prefs;
  return @[];
}
- (NSString *)generateWaypipePreviewString:(WWNPreferencesManager *)prefs {
  (void)prefs;
  return @"Open Wawona to preview and run Waypipe.";
}
- (NSString *)validatePreflightForPrefs:(WWNPreferencesManager *)prefs {
  (void)prefs;
  return nil;
}
- (void)launchWaypipe:(WWNPreferencesManager *)prefs {
  (void)prefs;
  WWNHandoffToWawonaApp(@"Waypipe");
}
- (void)stopWaypipe {
}
- (void)launchWestonSimpleSHM {
}
- (void)stopWestonSimpleSHM {
}
- (void)launchWeston {
}
- (void)launchWestonDrm {
}
- (void)stopWeston {
}
- (void)launchWestonTerminal {
}
- (void)stopWestonTerminal {
}
- (void)launchFoot {
}
- (void)stopFoot {
}
- (void)launchBundledClientWithId:(NSString *)clientId {
  (void)clientId;
}
- (void)launchBundledClientWithId:(NSString *)clientId
                        machineId:(NSString *)machineId {
  (void)clientId;
  (void)machineId;
}
- (void)launchWasmModuleAtPath:(NSString *)wasmModulePath
                     machineId:(NSString *)machineId {
  (void)wasmModulePath;
  (void)machineId;
}
- (void)stopBundledClientForMachineId:(NSString *)machineId {
  (void)machineId;
}
- (BOOL)isBundledClientRunningForMachineId:(NSString *)machineId {
  (void)machineId;
  return NO;
}
- (NSUInteger)runningInstanceCountForClientId:(NSString *)clientId {
  (void)clientId;
  return 0;
}
- (void)stopAllNativeClients {
}
- (BOOL)isAnyNativeClientRunning {
  return NO;
}
- (BOOL)baremetalCompositorLaunchSpecForProfile:(WWNMachineProfile *)profile
                                     executable:(NSString **)outPath
                                      arguments:(NSArray<NSString *> **)outArgs
                                    environment:
                                        (NSDictionary<NSString *, NSString *> **)
                                            outEnv
                                          error:(NSError **)error {
  (void)profile;
  if (outPath)
    *outPath = nil;
  if (outArgs)
    *outArgs = nil;
  if (outEnv)
    *outEnv = nil;
  if (error)
    *error = nil;
  return NO;
}
@end

NSString *const kWWNMachineTypeSSHWaypipe = @"ssh_waypipe";
NSString *const kWWNMachineTypeSSHTerminal = @"ssh_terminal";
NSString *const kWWNMachineTypeNative = @"native";
NSString *const kWWNMachineTypeVirtualMachine = @"virtual_machine";
NSString *const kWWNMachineTypeContainer = @"container";

@implementation WWNMachineProfile
+ (instancetype)defaultProfile {
  return [[self alloc] initDefaultProfile];
}
- (instancetype)initDefaultProfile {
  self = [super init];
  if (self) {
    _machineId = [[NSUUID UUID] UUIDString];
    _name = @"Machine";
    _type = kWWNMachineTypeNative;
    _settingsOverrides = @{};
    _runtimeOverrides = @{};
  }
  return self;
}
- (NSDictionary *)serialize {
  return @{};
}
@end

@implementation WWNMachineProfileStore
+ (NSArray<WWNMachineProfile *> *)loadProfiles {
  return @[];
}
+ (NSArray<WWNMachineProfile *> *)upsertProfile:(WWNMachineProfile *)profile {
  (void)profile;
  return @[];
}
+ (NSArray<WWNMachineProfile *> *)deleteProfileById:(NSString *)machineId {
  (void)machineId;
  return @[];
}
+ (NSArray<WWNMachineProfile *> *)deleteAllProfiles {
  return @[];
}
+ (NSString *)activeMachineId {
  return nil;
}
+ (void)setActiveMachineId:(NSString *)machineId {
  (void)machineId;
}
+ (WWNMachineProfile *)profileById:(NSString *)machineId {
  (void)machineId;
  return nil;
}
+ (void)applyMachineToRuntimePrefs:(WWNMachineProfile *)profile {
  (void)profile;
}
+ (void)applyActiveMachineToRuntimePrefs {
}
+ (void)persistActiveMachineSettings {
}
+ (NSDictionary<NSString *, id> *)resolvedRuntimeSettingsForProfile:
    (WWNMachineProfile *)profile {
  (void)profile;
  return @{};
}
+ (BOOL)isMachineThumbnailEnabledForProfile:(WWNMachineProfile *)profile {
  (void)profile;
  return YES;
}
+ (BOOL)resolvedShakeToCloseForProfile:(WWNMachineProfile *)profile {
  (void)profile;
  return YES;
}
+ (BOOL)resolvedSwipeBackToCloseForProfile:(WWNMachineProfile *)profile {
  (void)profile;
  return YES;
}
+ (BOOL)resolvedRenderMacOSPointerForProfile:(WWNMachineProfile *)profile {
  (void)profile;
  return NO;
}
+ (BOOL)resolvedRenderMacOSPointerActive {
  return NO;
}
+ (NSString *)resolvedNestedCompositorCursorForProfile:
    (WWNMachineProfile *)profile {
  (void)profile;
  return @"virtual";
}
+ (NSString *)resolvedNestedCompositorCursorActive {
  return @"virtual";
}
+ (BOOL)resolvedShowHostCursorActive {
  return NO;
}
+ (BOOL)resolvedShowVirtualPointerActive {
  return NO;
}
+ (BOOL)resolvedAlwaysOnTopForProfile:(WWNMachineProfile *)profile {
  (void)profile;
  return NO;
}
+ (BOOL)profileIndicatesNestedWithNativeClientId:(NSString *)clientId
                                   customCommand:(NSString *)customCommand {
  (void)customCommand;
  return [clientId isEqualToString:@"weston"] ||
         [clientId isEqualToString:@"niri"];
}
+ (BOOL)profileIndicatesNestedCompositor:(WWNMachineProfile *)profile {
  (void)profile;
  return NO;
}
+ (BOOL)nativeClientIdIndicatesModeBOwnDisplay:(NSString *)clientId
                                 customCommand:(NSString *)customCommand {
  (void)customCommand;
  return [self profileIndicatesNestedWithNativeClientId:clientId
                                          customCommand:customCommand];
}
+ (BOOL)profileIndicatesModeBOwnDisplay:(WWNMachineProfile *)profile {
  (void)profile;
  return NO;
}
+ (BOOL)profileEligibleForAppBridge:(WWNMachineProfile *)profile {
  (void)profile;
  return NO;
}
+ (void)migrateTvosGpuOpenGLDriverSnapshotsIfNeeded {
}
@end

@implementation WWNMachinesCoordinator
+ (instancetype)sharedCoordinator {
  static WWNMachinesCoordinator *s;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    s = [[self alloc] init];
  });
  return s;
}
- (void)showMachinesWindowAndActivate:(BOOL)activate {
  (void)activate;
  WWNHandoffToWawonaApp(@"Machines");
}
- (void)showMachinesWindowFromMenu:(id)sender {
  (void)sender;
  [self showMachinesWindowAndActivate:YES];
}
@end

@implementation WWNModeBReadyReport
@end
@implementation WWNModeBCoverageReport
@end
@implementation WWNModeBMenuBarStatus
@end

@implementation WWNDesktopReplacementController
+ (instancetype)sharedController {
  static WWNDesktopReplacementController *s;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    s = [[self alloc] init];
  });
  return s;
}
- (BOOL)shouldEngageModeB {
  return NO;
}
- (BOOL)isDesktopMachine:(WWNMachineProfile *)profile {
  (void)profile;
  return NO;
}
- (NSString *)bundledDylibPath {
  return nil;
}
- (BOOL)iowatchdogStickyAckPresent {
  return NO;
}
- (NSString *)iowatchdogStickyAckStatusSummary {
  return @"Open Wawona";
}
- (NSError *)injectionPreflightError {
  return nil;
}
- (BOOL)ensureDesktopMachineSelected:(NSError **)error {
  if (error)
    *error = nil;
  return NO;
}
- (BOOL)engageForProfile:(WWNMachineProfile *)profile error:(NSError **)error {
  (void)profile;
  if (error)
    *error = nil;
  WWNHandoffToWawonaApp(@"Desktop");
  return NO;
}
- (BOOL)engageSelectedDesktopMachine:(NSError **)error {
  if (error)
    *error = nil;
  WWNHandoffToWawonaApp(@"Desktop");
  return NO;
}
- (BOOL)disengage {
  WWNHandoffToWawonaApp(@"Desktop");
  return NO;
}
- (void)resumeAfterAquaLogin {
}
- (void)presentPendingSessionFailureAlert {
}
- (BOOL)reconcilePrefsWithCurrentSip {
  return NO;
}
- (int)cliStatus {
  return 0;
}
- (int)cliReady {
  return 3;
}
- (WWNModeBReadyReport *)evaluateClassicReadiness {
  WWNModeBReadyReport *r = [[WWNModeBReadyReport alloc] init];
  r.verdict = WWNModeBVerdictBlocked;
  r.token = @"blocked";
  r.reason = @"Open Wawona to manage Desktop Replacement.";
  r.nextStep = r.reason;
  r.userSummary = r.reason;
  r.needsSipHowTo = NO;
  r.canPrepareRequirements = NO;
  return r;
}
- (BOOL)isModeBCompositorLive {
  return NO;
}
- (BOOL)isClassicTakeoverLive {
  return NO;
}
- (WWNModeBMenuBarStatus *)menuBarDesktopStatusRefreshingGate:(BOOL)refreshGate {
  (void)refreshGate;
  WWNModeBMenuBarStatus *s = [[WWNModeBMenuBarStatus alloc] init];
  s.state = @"blocked";
  s.tooltip = @"Open Wawona";
  return s;
}
- (BOOL)requestNativeMacOSRestart:(NSError **)error {
  if (error)
    *error = nil;
  return NO;
}
- (BOOL)installDesktopReplacementRequirements:(NSError **)error {
  if (error)
    *error = nil;
  WWNHandoffToWawonaApp(@"Desktop");
  return NO;
}
- (BOOL)ensureWatchdogSafetyReady:(NSError **)error {
  if (error)
    *error = nil;
  return NO;
}
- (void)presentRestartAfterPrepareWithMessage:(NSString *)message {
  (void)message;
}
- (void)presentDesktopReplacementPrepareFlow {
  WWNHandoffToWawonaApp(@"Desktop");
}
- (void)presentReplaceNowFlow {
  WWNHandoffToWawonaApp(@"Desktop");
}
- (void)presentReadyTakeOverOffer {
  WWNHandoffToWawonaApp(@"Desktop");
}
- (BOOL)endClassicSession {
  return NO;
}
- (WWNModeBCoverageReport *)evaluateWatchdogCoverage {
  return [[WWNModeBCoverageReport alloc] init];
}
- (WWNModeBCoverageReport *)runWatchdogDoctor:(NSError **)error {
  if (error)
    *error = nil;
  return [[WWNModeBCoverageReport alloc] init];
}
- (BOOL)healWatchdogCoverage:(NSError **)error {
  if (error)
    *error = nil;
  return NO;
}
- (void)presentWatchdogCoverageCheck {
}
- (void)presentWatchdogHealFlow {
}
- (int)cliPrepare {
  return 3;
}
- (int)cliEngageKeepWindowServer:(BOOL)keepWindowServer {
  (void)keepWindowServer;
  return 3;
}
- (int)cliDisengage {
  return 0;
}
- (int)cliStage {
  return 0;
}
- (int)cliSelectDesktopMachine:(NSString *)idOrName {
  (void)idOrName;
  return 1;
}
@end

@implementation WWNRootfsProvider
+ (WWNRootfsCapabilities)capabilities {
  return WWNRootfsCapabilitySettings;
}
+ (NSDictionary<NSString *, NSString *> *)snapshot {
  return @{
    @"mode" : @"host",
    @"home" : NSHomeDirectory() ?: @"",
    @"filesHint" : @"Open Wawona to manage the local shell.",
    @"platformLabel" : @"macOS",
  };
}
+ (void)prepareUserAccess {
}
+ (BOOL)refreshShellDotfiles:(NSError **)error {
  if (error)
    *error = nil;
  WWNHandoffToWawonaApp(@"Local Shell");
  return NO;
}
+ (BOOL)reinstallSystemTree:(NSError **)error {
  if (error)
    *error = nil;
  WWNHandoffToWawonaApp(@"Local Shell");
  return NO;
}
+ (void)applyShellEnvironment {
}
+ (BOOL)openUserFilesLocation {
  WWNHandoffToWawonaApp(@"Local Shell");
  return NO;
}
+ (BOOL)isICloudSyncSupported {
  return YES;
}
+ (BOOL)isICloudSyncEnabled {
  return [WWNSharedUserDefaults()
      boolForKey:WWNRootfsICloudSyncPreferenceKey];
}
+ (BOOL)setICloudSyncEnabled:(BOOL)enabled error:(NSError **)error {
  if (error)
    *error = nil;
  [WWNSharedUserDefaults() setBool:enabled
                            forKey:WWNRootfsICloudSyncPreferenceKey];
  return YES;
}
@end

NSString *const WWNRootfsICloudSyncPreferenceKey =
    @"wawona.pref.localShellICloudSyncEnabled";

@implementation WWNRootfsICloudSync
+ (BOOL)isSupported {
  return YES;
}
+ (BOOL)isEnabled {
  return [WWNSharedUserDefaults() boolForKey:WWNRootfsICloudSyncPreferenceKey];
}
+ (BOOL)isContainerAvailable {
  return NO;
}
+ (NSString *)icloudHomePath {
  return nil;
}
+ (NSString *)statusSummary {
  return @"Open Wawona for iCloud Drive status.";
}
+ (void)prepareICloudLayout {
}
+ (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
  if (error)
    *error = nil;
  [WWNSharedUserDefaults() setBool:enabled
                            forKey:WWNRootfsICloudSyncPreferenceKey];
  return YES;
}
@end

@implementation WWNSSHKeygen
+ (NSString *)generateKeyType:(NSString *)type
                   passphrase:(NSString *)passphrase
                        error:(NSError **)error {
  (void)type;
  (void)passphrase;
  if (error)
    *error = nil;
  WWNHandoffToWawonaApp(@"SSH");
  return nil;
}
+ (NSString *)installOpenSSHPrivateKeyAtURL:(NSURL *)url error:(NSError **)error {
  (void)url;
  if (error)
    *error = nil;
  WWNHandoffToWawonaApp(@"SSH");
  return nil;
}
+ (NSString *)installOpenSSHPrivateKeyData:(NSData *)data
                             preferredName:(NSString *)name
                                     error:(NSError **)error {
  (void)data;
  (void)name;
  if (error)
    *error = nil;
  WWNHandoffToWawonaApp(@"SSH");
  return nil;
}
+ (void)syncKeyPrefsWithPath:(NSString *)keyPath
                 passphrase:(NSString *)passphrase {
  (void)keyPath;
  (void)passphrase;
}
@end
