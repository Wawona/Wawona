#import "WWNSipStatus.h"
#import <stdio.h>

@interface WWNSipStatus (WWNSipStatusClassify)
+ (WWNSipStatusType)classifyStatusText:(NSString *)result;
@end

@implementation WWNSipStatus

+ (WWNSipStatusType)current {
  // Shell out to csrutil and classify the human-readable status string.
  // Do not use CSR_* syscalls. First line is the overall state:
  //
  //   "System Integrity Protection status: disabled."  -> Fully disabled
  //   "... status: unknown (Custom Configuration)."      -> Partial
  //     (Debugging Restrictions: disabled is not enough for Mode B)
  //   "System Integrity Protection status: enabled."   -> Enabled
  //   (anything else / no csrutil)                     -> Unknown
  FILE *pipe = popen("/usr/bin/csrutil status 2>/dev/null", "r");
  if (!pipe) {
    return WWNSipStatusUnknown;
  }

  NSMutableString *result = [NSMutableString string];
  char buffer[256];
  while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
    [result appendString:[NSString stringWithUTF8String:buffer]];
  }
  pclose(pipe);
  return [self classifyStatusText:result];
}

+ (WWNSipStatusType)classifyStatusText:(NSString *)result {
  NSString *trimmed = [result
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  NSString *firstLine = [[trimmed
      componentsSeparatedByCharactersInSet:[NSCharacterSet
                                               newlineCharacterSet]]
      firstObject];
  firstLine = [firstLine
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  NSString *head = firstLine.length > 0 ? firstLine : trimmed;

  BOOL custom = [head rangeOfString:@"Custom Configuration"
                            options:NSCaseInsensitiveSearch]
                    .location != NSNotFound ||
                [head rangeOfString:@"unknown" options:NSCaseInsensitiveSearch]
                        .location != NSNotFound;
  if (!custom &&
      [head rangeOfString:@"status: disabled"
                  options:NSCaseInsensitiveSearch]
              .location != NSNotFound) {
    return WWNSipStatusDisabled;
  }
  if (custom ||
      [result rangeOfString:@"Debugging Restrictions: disabled"].location !=
          NSNotFound) {
    return WWNSipStatusPartiallyDisabled;
  }
  if ([head rangeOfString:@"status: enabled"
                  options:NSCaseInsensitiveSearch]
          .location != NSNotFound) {
    return WWNSipStatusEnabled;
  }
  return WWNSipStatusUnknown;
}

+ (NSString *)describe:(WWNSipStatusType)status {
  switch (status) {
  case WWNSipStatusEnabled:
    return @"Enabled";
  case WWNSipStatusDisabled:
    return @"Fully Disabled";
  case WWNSipStatusPartiallyDisabled:
    return @"Partially Disabled (Mode B needs Fully Disabled)";
  case WWNSipStatusUnknown:
  default:
    return @"Unknown";
  }
}

+ (BOOL)allowsDesktopReplacement:(WWNSipStatusType)status {
  return status == WWNSipStatusDisabled;
}

+ (NSString *)desktopReplacementHowToMessage {
  return
      @"wwn-iland macOS Desktop Replacement (Mode B) replaces "
      @"SkyLight/WindowServer by injecting libwayland-mac.dylib into a root "
      @"compositor. That requires System Integrity Protection (SIP) fully "
      @"disabled. Not a normal App Store configuration.\n\n"
      @"Why SIP must be fully off:\n"
      @"Take Over disables kernel IOWatchdog, then unloads Apple's "
      @"watchdogd and WindowServer so framebufferd can own SkyLight. "
      @"DYLD_INSERT_LIBRARIES and Dobby also need SIP off. With SIP only "
      @"partially disabled (csrutil enable --without debug), launchctl "
      @"bootout of WindowServer returns 150. Debugging Restrictions off "
      @"is not enough.\n\n"
      @"Unloading watchdogd without IOWatchdog disable panics immediately "
      @"on this macOS (2026-08-19).\n\n"
      @"Required setup:\n"
      @"1. Restart into Recovery (hold Power at boot, or Recovery partition).\n"
      @"2. Open Terminal from Utilities.\n"
      @"3. Run: csrutil disable\n"
      @"4. Reboot normally.\n"
      @"5. Verify: csrutil status should report "
      @"\"System Integrity Protection status: disabled.\" "
      @"Wawona Settings → Desktop must show Fully Disabled.\n\n"
      @"Do not use csrutil enable --without debug for Desktop Replacement.\n\n"
      @"Android note: Wawona Desktop Replacement on Android does not change "
      @"SIP or system security. It uses the Android Launcher (HOME app) role "
      @"instead. No Recovery-mode steps are required on Android.";
}

@end
