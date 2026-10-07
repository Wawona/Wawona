#!/usr/bin/env bash
# Build Wawona Mode B demo for TrollStore (.tipa) and Sileo (.deb).
# One app for all Mode B proofs:
#   - IOMFB full-frame graphics via JIT paint_frame (plasma + soft orbs)
#   - Host glyphs: "Hello, Wawona World!" + LIVE HUD
#   - JIT showcase: W^X emit ARM64 fib + probe (MAP_JIT or vm_allocate+RX)
#   - Self-enable PT_TRACE_ME / attach / magnifier (same process)
# Signs with ldid. Never for App Store / TestFlight. Not UTM.
# Does NOT touch IOWatchdog (forbidden; see wawona-mode-b-watchdog-safety).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/.agent-device/test-artifacts/dmabuf/vphone-jb}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BUNDLE_ID="com.aspauldingcode.wawona.modeb.demo"
APP_NAME="WawonaModeBDemo"
VERSION="${VERSION:-26.9.2}"
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
  if command -v ldid >/dev/null 2>&1; then LDID="$(command -v ldid)"
  elif [[ -x "$HOME/.vphone/src/vphone-cli/.tools/bin/ldid" ]]; then
    LDID="$HOME/.vphone/src/vphone-cli/.tools/bin/ldid"
  else
    echo "ERROR: ldid not found (need ldid-procursus)" >&2
    exit 1
  fi
fi

mkdir -p "$OUT" "$STAGE/src" "$STAGE/include/IOMobileFramebuffer" "$STAGE/Payload/${APP_NAME}.app"
echo "Building tipa marketing VERSION=$VERSION build CFBundleVersion=$BUILD"

DEMO_DIR="$ROOT/scripts/modeb-demo"
SWIFT="$(xcrun --sdk iphoneos --find swiftc)"

"$CLANG" -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 -O2 \
  -I"$DEMO_DIR" \
  -c "$DEMO_DIR/modeb_demo_support.c" -o "$STAGE/modeb_demo_support.o"

SWIFT_COMMON=(-sdk "$SDK" -target arm64-apple-ios15.0 -parse-as-library -O \
  -import-objc-header "$DEMO_DIR/modeb-demo-Bridging-Header.h" -I"$DEMO_DIR")
"$SWIFT" "${SWIFT_COMMON[@]}" -emit-object -wmo \
  "$DEMO_DIR/ModeBDemoApp.swift" "$DEMO_DIR/ModeBDemoHost.swift" \
  -o "$STAGE/ModeBDemo.o"

"$SWIFT" -sdk "$SDK" -target arm64-apple-ios15.0 \
  "$STAGE/modeb_demo_support.o" "$STAGE/ModeBDemo.o" \
  -framework UIKit -framework Foundation -framework CoreGraphics \
  -framework QuartzCore -framework IOSurface -framework IOKit \
  -o "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}"

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
  <key>CFBundleSupportedPlatforms</key>
  <array><string>iPhoneOS</string></array>
  <key>UIDeviceFamily</key>
  <array><integer>1</integer><integer>2</integer></array>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
  <key>MinimumOSVersion</key><string>15.0</string>
  <key>LSApplicationQueriesSchemes</key>
  <array><string>apple-magnifier</string></array>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.aspauldingcode.wawona.modeb.demo</string>
      <key>CFBundleURLSchemes</key>
      <array><string>wawona-modeb-demo</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Tipa ents: JIT + IOMFB. Never IOWatchdog (Mode B watchdog safety).
cat >"$STAGE/modeb.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>get-task-allow</key><true/>
  <key>platform-application</key><true/>
  <key>com.apple.private.security.no-sandbox</key><true/>
  <key>com.apple.private.security.storage.AppDataContainers</key><true/>
  <key>com.apple.developer.kernel.increased-memory-limit</key><true/>
  <key>com.apple.developer.kernel.extended-virtual-addressing</key><true/>
  <key>com.apple.private.mapped-memory-buffer</key><true/>
  <key>com.apple.private.IOMobileFramebuffer</key><true/>
  <key>com.apple.private.allow-explicit-graphics-priority</key><true/>
  <key>com.apple.IOSurface.IOSurface</key><true/>
  <key>com.apple.security.exception.iokit-user-client-class</key>
  <array>
    <string>IOMobileFramebufferUserClient</string>
    <string>IOSurfaceRootUserClient</string>
  </array>
  <key>com.apple.security.iokit-user-client-class</key>
  <array>
    <string>IOMobileFramebufferUserClient</string>
    <string>IOSurfaceRootUserClient</string>
  </array>
  <key>com.apple.private.security.storage.AppBundles</key><true/>
</dict>
</plist>
PLIST

echo "signing with $LDID"
"$LDID" -S"$STAGE/modeb.entitlements" "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}"
# Do NOT ldid-sign the .app directory (creates _CodeSignature/CodeResources that
# TrollStore Lite rejects / installforce no-ops). Binary-only ldid is enough.
rm -rf "$STAGE/Payload/${APP_NAME}.app/_CodeSignature"

TIPA="$OUT/WawonaModeBDemo-${VERSION}-iOS-arm64.tipa"
rm -f "$TIPA"
(cd "$STAGE" && zip -qry "$TIPA" Payload)
printf '%s\n' "$BUILD" >"$STATE_FILE"
echo "wrote $TIPA"
echo "CFBundleShortVersionString (marketing)=$VERSION"
echo "CFBundleVersion (build)=$BUILD"
"$LDID" -e "$STAGE/Payload/${APP_NAME}.app/${APP_NAME}" 2>/dev/null | head -50 || true
unzip -l "$TIPA"
ls -la "$TIPA"

# Sileo debs. Same signed binary as the tipa. Rootless and rootful are
# different trees (prefix + Architecture), not a renamed archive.
DPKG_DEB="${DPKG_DEB:-}"
if [[ -z "$DPKG_DEB" ]]; then
  if command -v dpkg-deb >/dev/null 2>&1; then DPKG_DEB="$(command -v dpkg-deb)"
  else
    echo "ERROR: dpkg-deb not found (need it to pack the Sileo debs)" >&2
    exit 1
  fi
fi
DEB_VERSION="${VERSION}-${BUILD}"
MAINTAINER="Alex Spaulding <aspauldingcode@gmail.com>"
pack_modeb_deb() {
  local scheme="$1" arch="$2" app_prefix="$3"
  local deb_root="$STAGE/deb-${scheme}"
  local app_dir="$deb_root/${app_prefix}/${APP_NAME}.app"
  rm -rf "$deb_root"
  mkdir -p "$app_dir" "$deb_root/DEBIAN"
  cp -R "$STAGE/Payload/${APP_NAME}.app/." "$app_dir/"
  rm -rf "$app_dir/_CodeSignature"
  cat >"$deb_root/DEBIAN/control" <<EOF
Package: ${BUNDLE_ID}
Name: Wawona Mode B Demo
Version: ${DEB_VERSION}
Architecture: ${arch}
Maintainer: ${MAINTAINER}
Author: ${MAINTAINER}
Description: Mode B framebuffer and JIT demo (${scheme}). IOMFB plasma, Hello text, fib HUD. Not App Store.
Section: Utilities
Priority: optional
Depends: firmware (>= 15.0)
Homepage: https://wawona.io
Tag: role::developer
EOF
  # Do not ship #!/bin/sh maintainer scripts. iOS 26 vphone /bin has no
  # sh; Irisin-install then fails postinst with errno 2 and leaves the
  # package half-configured, which blocks later Irisin installs.
  # uicache is optional; SpringBoard still sees /var/jb/Applications.

  local deb="$OUT/wawona-modeb-demo_${DEB_VERSION}_${arch}.deb"
  rm -f "$deb"
  "$DPKG_DEB" -Zxz --root-owner-group -b "$deb_root" "$deb"
  echo "wrote $deb"
}
pack_modeb_deb rootless iphoneos-arm64 var/jb/Applications
pack_modeb_deb rootful iphoneos-arm Applications

REPO_DEBS="${REPO_DEBS:-$ROOT/../repo.wawona.io/debs}"
if [[ -d "$REPO_DEBS" ]]; then
  cp -f "$OUT"/wawona-modeb-demo_"${DEB_VERSION}"_iphoneos-arm*.deb "$REPO_DEBS/"
  echo "copied Sileo debs to $REPO_DEBS"
fi
