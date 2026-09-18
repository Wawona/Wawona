#import "WWNLegacyMachinesViewController.h"
#import "../macos/ui/Machines/WWNMachineProfileStore.h"
#import "../macos/ui/Machines/WWNMachineSessionBridge.h"

@interface WWNLegacyMachinesViewController ()
@property(nonatomic, copy, nullable) dispatch_block_t onConnect;
@property(nonatomic, copy) NSArray<WWNMachineProfile *> *profiles;
@end

@implementation WWNLegacyMachinesViewController

- (instancetype)initWithOnConnect:(dispatch_block_t)onConnect {
  self = [super initWithStyle:UITableViewStylePlain];
  if (self) {
    _onConnect = [onConnect copy];
    _profiles = @[];
    self.title = @"Machines";
    self.clearsSelectionOnViewWillAppear = YES;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.whiteColor;
  self.tableView.accessibilityIdentifier = @"wwn.machines.legacy";
  self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(reloadProfiles)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];
  [self reloadProfiles];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadProfiles {
  self.profiles = [WWNMachineProfileStore loadProfiles] ?: @[];
  [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return self.profiles.count == 0 ? 1 : self.profiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  static NSString *const reuseID = @"Machine";
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                  reuseIdentifier:reuseID];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  }
  if (self.profiles.count == 0) {
    cell.textLabel.text = @"No machines configured";
    cell.detailTextLabel.text = @"Add a profile on an iOS 13+ device, then it is available here.";
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
  }
  WWNMachineProfile *profile = self.profiles[(NSUInteger)indexPath.row];
  cell.textLabel.text = profile.name.length ? profile.name : @"Unnamed Machine";
  cell.detailTextLabel.text = profile.type.length ? profile.type : @"Machine";
  cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  cell.accessibilityIdentifier = [@"wwn.machines.legacy." stringByAppendingString:profile.machineId ?: @"machine"];
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)tableView;
  if (self.profiles.count == 0) {
    return;
  }
  WWNMachineProfile *profile = self.profiles[(NSUInteger)indexPath.row];
  NSError *error = nil;
  if (![WWNMachineSessionBridge connectProfile:profile error:&error]) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Unable to start machine"
                                                                   message:error.localizedDescription ?: @"The machine could not be started."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return;
  }
  if (self.onConnect) {
    self.onConnect();
  }
}

@end
