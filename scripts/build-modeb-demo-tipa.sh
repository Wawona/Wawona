#!/usr/bin/env bash
# Build a minimal TrollStore .tipa demo that requests JIT + IOMobileFramebuffer.
# Signs with ldid (prefer ldid-procursus). Never for App Store / TestFlight.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/.agent-device/test-artifacts/dmabuf/vphone-jb}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BUNDLE_ID="com.aspauldingcode.wawona.modeb-demo"
APP_NAME="WawonaModeBDemo"
# Marketing version (CalVer). NOT the install identity iOS uses for replace.
VERSION="${VERSION:-26.9.2}"
# Build number (CFBundleVersion). Bump this to force TrollStore/iOS reinstall.
# Default: max(existing tipa build, state file) + 1.
STATE_FILE="${STATE_FILE:-$OUT/.modeb-demo-build}"
BUILD="${BUILD:-}"
if [[ -z "$BUILD" ]]; then
  prev=0
  if [[ -f "$STATE_FILE" ]]; then
    prev="$(tr -d '[:space:]' <"$STATE_FILE" || true)"
  fi
  if [[ -f "$OUT/WawonaModeBDemo-${VERSION}-iOS-arm64.tipa" ]]; then
    tipa_build="$(unzip -p "$OUT/WawonaModeBDemo-${VERSION}-iOS-arm64.tipa" "Payload/${APP_NAME}.app/Info.plist" 2>/dev/null \
      | plutil -extract CFBundleVersion raw - 2>/dev/null || true)"
    if [[ "$tipa_build" =~ ^[0-9]+$ ]] && (( tipa_build > prev )); then
      prev="$tipa_build"
    fi
  fi
  BUILD=$((prev + 1))
fi
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
LDID="${LDID:-}"
if [[ -z "$LDID" ]]; then
  if command -v ldid >/dev/null 2>&1; then
    LDID="$(command -v ldid)"
  elif [[ -x "$HOME/.vphone/src/vphone-cli/.tools/bin/ldid" ]]; then
    LDID="$HOME/.vphone/src/vphone-cli/.tools/bin/ldid"
  else
    echo "ERROR: ldid not found (need ldid-procursus for TrollStore)" >&2
    exit 1
  fi
fi

mkdir -p "$OUT" "$STAGE/src" "$STAGE/Payload/${APP_NAME}.app"
echo "Building tipa marketing VERSION=$VERSION build CFBundleVersion=$BUILD (these are different)"


cat >"$STAGE/src/main.m" <<'OBJC'
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <sys/errno.h>
#import <dlfcn.h>
#import <pthread.h>
#import <libkern/OSCacheControl.h>
#import <os/log.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UILabel *label;
@end

@implementation AppDelegate

static BOOL tryMapJit(NSString **detail) {
  size_t len = 16384;
  void *p = mmap(NULL, len, PROT_READ | PROT_WRITE | PROT_EXEC,
                 MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
  if (p == MAP_FAILED) {
    // Fallback probe without MAP_JIT (shows entitlement path still signed).
    p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (p == MAP_FAILED) {
      *detail = [NSString stringWithFormat:@"mmap failed errno=%d", errno];
      return NO;
    }
    munmap(p, len);
    *detail = [NSString stringWithFormat:@"MAP_JIT unavailable errno=%d (entitlements still stamped)", errno];
    return NO;
  }
  typedef void (*JitWP)(int);
  JitWP wp = (JitWP)dlsym(RTLD_DEFAULT, "pthread_jit_write_protect_np");
  if (wp) wp(0);
  uint32_t *code = (uint32_t *)p;
  code[0] = 0xd65f03c0; // ret
  if (wp) wp(1);
  sys_icache_invalidate(p, 4);
  typedef void (*Thunk)(void);
  @try {
    ((Thunk)p)();
  } @catch (NSException *ex) {
    munmap(p, len);
    *detail = [NSString stringWithFormat:@"JIT thunk threw %@", ex];
    return NO;
  }
  munmap(p, len);
  *detail = @"MAP_JIT write+exec OK";
  return YES;
}

static NSString *probeIOMFB(void) {
  // Soft-link: presence of the private framework / symbol is enough for the demo
  // entitlement claim. Real own-display work lives in Mode B Wawona, not this stub.
  void *h = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer",
                   RTLD_LAZY);
  if (!h) {
    return [NSString stringWithFormat:@"IOMFB dlopen failed: %s", dlerror()];
  }
  void *sym = dlsym(h, "IOMobileFramebufferGetMainDisplay");
  if (!sym) sym = dlsym(h, "IOMobileFramebufferOpen");
  return [NSString stringWithFormat:@"IOMFB loaded sym=%p", sym];
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  UIViewController *vc = [UIViewController new];
  vc.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.12 blue:0.18 alpha:1];
  self.label = [[UILabel alloc] initWithFrame:CGRectInset(vc.view.bounds, 24, 80)];
  self.label.numberOfLines = 0;
  self.label.textColor = UIColor.whiteColor;
  self.label.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
  self.label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  NSString *jitDetail = nil;
  BOOL jitOk = tryMapJit(&jitDetail);
  NSString *iomfb = probeIOMFB();
  self.label.text = [NSString stringWithFormat:
      @"Wawona Mode B tipa demo\n"
      @"bundle: com.aspauldingcode.wawona.modeb-demo\n\n"
      @"JIT (MAP_JIT): %@\n%@\n\n"
      @"Framebuffer:\n%@\n\n"
      @"Entitlements via ldid (TrollStore):\n"
      @"  dynamic-codesigning\n"
      @"  get-task-allow\n"
      @"  no-sandbox\n"
      @"  IOMobileFramebuffer*\n",
      jitOk ? @"OK" : @"FAIL", jitDetail, iomfb];

  [vc.view addSubview:self.label];
  self.window.rootViewController = vc;
  [self.window makeKeyAndVisible];
  return YES;
}
@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
OBJC

# Need pthread_jit_write_protect_np declaration
# Compile for device arm64
"$CLANG" -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=15.0 \
  -fobjc-arc -framework UIKit -framework Foundation -framework CoreGraphics \
  -o "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}" \
  "$STAGE/src/main.m"

cat >"$STAGE/Payload/${APP_NAME}.app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>Wawona Mode B Demo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>UILaunchStoryboardName</key><string></string>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
  </array>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST

ENT="$STAGE/modeb.entitlements"
cat >"$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>get-task-allow</key><true/>
  <key>platform-application</key><true/>
  <key>com.apple.private.security.no-sandbox</key><true/>
  <key>com.apple.private.security.container-required</key><false/>
  <key>dynamic-codesigning</key><true/>
  <key>com.apple.developer.kernel.increased-memory-limit</key><true/>
  <key>com.apple.developer.kernel.extended-virtual-addressing</key><true/>
  <key>com.apple.private.mapped-memory-buffer</key><true/>
  <!-- IOMobileFramebuffer / own-display (TrollStore Mode B Desktop path) -->
  <key>com.apple.private.IOMobileFramebuffer</key><true/>
  <key>com.apple.IOSurface.IOSurface</key><true/>
  <key>com.apple.private.security.storage.AppBundles</key><true/>
</dict>
</plist>
PLIST

echo "signing with $LDID"
"$LDID" -S"$ENT" "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}"
# Also stamp the bundle if ldid supports -Cadhoc
"$LDID" -S"$ENT" "$STAGE/Payload/${APP_NAME}.app" 2>/dev/null || true

TIPA="$OUT/WawonaModeBDemo-${VERSION}-iOS-arm64.tipa"
rm -f "$TIPA"
(cd "$STAGE" && zip -qry "$TIPA" Payload)
printf '%s\n' "$BUILD" >"$STATE_FILE"
echo "wrote $TIPA"
echo "CFBundleShortVersionString (marketing)=$VERSION"
echo "CFBundleVersion (build)=$BUILD  ← bump this to force iOS/TrollStore reinstall"
# Show entitlements
"$LDID" -e "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}" 2>/dev/null | head -40 || true
ls -la "$TIPA"
