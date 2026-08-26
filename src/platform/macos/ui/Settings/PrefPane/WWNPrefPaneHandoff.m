#import "WWNPrefPaneHandoff.h"
#import <AppKit/AppKit.h>

void WWNHandoffToWawonaApp(NSString *sectionTitle) {
  NSURL *appURL = [NSURL fileURLWithPath:@"/Applications/Wawona.app"];
  NSWorkspaceOpenConfiguration *cfg =
      [NSWorkspaceOpenConfiguration configuration];
  NSMutableArray<NSString *> *args =
      [NSMutableArray arrayWithObject:@"--show-settings"];
  if (sectionTitle.length > 0) {
    [args addObject:[NSString stringWithFormat:@"--settings-section=%@",
                                               sectionTitle]];
  }
  cfg.arguments = args;
  cfg.activates = YES;
  [[NSWorkspace sharedWorkspace] openApplicationAtURL:appURL
                                        configuration:cfg
                                    completionHandler:nil];
}
