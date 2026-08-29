#import "WWNPreferencePane.h"
#import "WWNPreferences.h"

@implementation WWNPreferencePane

- (NSView *)loadMainView {
  NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 520)];
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [[WWNPreferences sharedPreferences] installMacSettingsInterfaceInView:view];
  [self setMainView:view];
  [self mainViewDidLoad];
  return [self mainView];
}

- (void)mainViewDidLoad {
}

@end
