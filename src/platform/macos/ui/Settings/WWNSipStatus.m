#import "WWNSipStatus.h"
#import <stdio.h>

@implementation WWNSipStatus

+ (WWNSipStatusType)current {
  // Port of plugin-playground Configurator checkSipStatus() (feat/sip-detection).
  // Shell out to csrutil and classify the human-readable status string.
  //
  //   "System Integrity Protection status: disabled."  -> Disabled
  //   "Debugging Restrictions: disabled"               -> Partially disabled
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

  if ([result rangeOfString:@"System Integrity Protection status: disabled."]
          .location != NSNotFound) {
    return WWNSipStatusDisabled;
  }
  if ([result rangeOfString:@"Debugging Restrictions: disabled"].location !=
      NSNotFound) {
    return WWNSipStatusPartiallyDisabled;
  }
  if ([result rangeOfString:@"System Integrity Protection status: enabled."]
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
    return @"Disabled";
  case WWNSipStatusPartiallyDisabled:
    return @"Partially Disabled (Debugging Restrictions Off)";
  case WWNSipStatusUnknown:
  default:
    return @"Unknown";
  }
}

+ (BOOL)allowsDesktopReplacement:(WWNSipStatusType)status {
  return status == WWNSipStatusDisabled ||
         status == WWNSipStatusPartiallyDisabled;
}

+ (NSString *)desktopReplacementHowToMessage {
  return
      @"wwn-iland macOS Desktop Replacement (Mode B) replaces "
      @"SkyLight/WindowServer by injecting into system processes. That "
      @"requires System Integrity Protection (SIP) to permit debugging and "
      @"library injection — not a normal App Store configuration.\n\n"
      @"Why SIP must change:\n"
      @"• Partially disabled SIP lifts debugging restrictions so Wawona can "
      @"reach initproc and set hardware breakpoints in other processes.\n"
      @"• The wwn-iland shim also relies on DYLD_INSERT_LIBRARIES and runtime "
      @"code patching (Dobby). Without debugging restrictions disabled, "
      @"injection and patching are blocked and the shim will not load.\n\n"
      @"Recommended (minimal) setup:\n"
      @"1. Restart into Recovery (hold Power at boot, or Recovery partition).\n"
      @"2. Open Terminal from Utilities.\n"
      @"3. Run: csrutil enable --without debug\n"
      @"   This keeps most filesystem and kext protections; only debugging "
      @"restrictions are lifted — you do not need SIP fully off.\n"
      @"4. Reboot normally.\n"
      @"5. Verify: csrutil status should report "
      @"\"Debugging Restrictions: disabled\".\n\n"
      @"Android note: Wawona Desktop Replacement on Android does not change "
      @"SIP or system security. It uses the Android Launcher (HOME app) role "
      @"instead — no Recovery-mode steps are required on Android.";
}

@end
