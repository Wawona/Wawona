#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --mode-a|--mode-a-simulator Wawona.app | --mode-b|--iteration Wawona-YY.M.D-iOS-arm64.tipa | --sileo Wawona.app" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
mode="$1"
artifact="$2"
[[ -e "$artifact" ]] || {
  echo "artifact not found: $artifact" >&2
  exit 1
}

fail() {
  echo "iOS Mode B artifact check failed: $*" >&2
  exit 1
}

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1"
}

check_forbidden_entitlements() {
  local entitlements="$1"
  ! /usr/bin/grep -Eq 'iowatchdog|ElleKit|ellekit' "$entitlements" ||
    fail "forbidden jailbreak or watchdog entitlement found"
}

macho_ios_minimum() {
  /usr/bin/otool -l "$1" | /usr/bin/awk '
    /cmd LC_BUILD_VERSION/ { build = 1; next }
    /cmd LC_VERSION_MIN_IPHONEOS/ { legacy = 1; next }
    build && $1 == "minos" && result == "" { result = $2; build = 0 }
    legacy && $1 == "version" && result == "" { result = $2; legacy = 0 }
    END { if (result != "") print result }
  '
}

require_ios_minimum() {
  local executable="$1"
  local expected="$2"
  local actual
  actual="$(macho_ios_minimum "$executable")"
  [[ "$actual" == "$expected" ]] ||
    fail "expected iOS minimum $expected, got ${actual:-missing}"
}

# Info.plist can advertise 13.0 while an embedded Mach-O requires a newer OS.
# Check every iOS slice; watchOS companion slices retain their own floor.
require_ios_dependency_minima() {
  local app="$1" expected_platform="$2" maximum="$3" binary platform minimum
  # A failed Swift runtime copy can leave a zero-byte dylib. otool emits no
  # load commands for that file, so the deployment-floor loop alone misses it.
  while IFS= read -r binary; do
    [[ -s "$binary" ]] || fail "empty embedded dylib: $binary"
    /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O' ||
      fail "embedded dylib is not Mach-O: $binary"
  done < <(/usr/bin/find "$app" -type f -name '*.dylib' -print)
  while IFS= read -r binary; do
    while read -r platform minimum; do
      [[ -n "$minimum" ]] || continue
      [[ "$platform" == "$expected_platform" ]] ||
        fail "wrong embedded iOS platform $platform (expected $expected_platform): $binary"
      /usr/bin/awk -v actual="$minimum" -v maximum="$maximum" 'BEGIN {
        split(actual, version, ".")
        split(maximum, limit, ".")
        exit !(version[1] < limit[1] || (version[1] == limit[1] && version[2] <= limit[2]))
      }' || fail "dependency requires iOS $minimum (maximum $maximum): $binary"
    done < <(/usr/bin/otool -l "$binary" 2>/dev/null | /usr/bin/awk '
      /cmd LC_BUILD_VERSION/ { build = 1; platform = 0; next }
      /cmd LC_VERSION_MIN_IPHONEOS/ { legacy = 1; next }
      build && $1 == "platform" { platform = $2; next }
      build && $1 == "minos" {
        if (platform == 2 || platform == 7) print platform, $2
        build = 0
      }
      legacy && $1 == "version" { print 2, $2; legacy = 0 }
    ')
  done < <(/usr/bin/find "$app" -type f \( -perm -111 -o -name '*.dylib' -o -path '*/Frameworks/*' \) \
    ! -path '*/share/*' ! -name '*.sh' ! -name '*.py' -print)
}

if [[ "$mode" == "--mode-a" || "$mode" == "--mode-a-simulator" ]]; then
  app="$artifact"
  [[ -d "$app" ]] || fail "Mode A input is not an app bundle"
  executable="$app/Wawona"
  [[ -x "$executable" ]] || fail "Mode A executable is missing"
  [[ "$(plist_value "$app/Info.plist" CFBundleIdentifier)" == "com.aspauldingcode.Wawona" ]] ||
    fail "Mode A bundle identifier changed"
  ! /usr/bin/nm -gU "$executable" 2>/dev/null | /usr/bin/grep '_wwn_iomfb_' >/dev/null ||
    fail "Mode A links the private IOMFB sink"
  ! /usr/bin/nm -gU "$executable" 2>/dev/null | /usr/bin/grep '_wwn_igetty_ios_' >/dev/null ||
    fail "Mode A links the TrollStore session switcher"
  ! /usr/bin/strings "$executable" | /usr/bin/grep -E 'IOMobileFramebuffer|WWN_MODE_B' >/dev/null ||
    fail "Mode A contains Mode B private symbols or strings"
  if /usr/bin/find "$app" \( \
      -name 'wwn-qemu-run' -o \
      -iname 'qemu-system-*' -o \
      -iname 'libqemu*' -o \
      -iname 'qemu-*.framework' -o \
      -path '*/share/qemu/*' -o \
      -path '*/Frameworks/qemu*' \
    \) | /usr/bin/grep -q .; then
    fail "QEMU artifacts are forbidden in Mode A"
  fi
  if /usr/bin/codesign -d "$app" >/dev/null 2>&1; then
    entitlements="$(mktemp)"
    trap 'rm -f "$entitlements"' EXIT
    /usr/bin/codesign -d --entitlements :- "$app" >"$entitlements" 2>/dev/null
    ! /usr/bin/grep -Eq 'IOMobileFramebuffer|platform-application|no-sandbox|get-task-allow' "$entitlements" ||
      fail "Mode A contains Mode B entitlements"
  fi
  expected_platform=2
  expected_minimum=13.0
  if [[ "$mode" == "--mode-a-simulator" ]]; then
    # SDK 26.5's arm64 Simulator linker stamps 14.0 even for a 13.0
    # deployment target. A minimal clang link reproduces this platform floor.
    expected_platform=7
    expected_minimum=14.0
    [[ "$(/usr/bin/lipo -archs "$executable")" == "arm64" ]] ||
      fail "Simulator floor check requires the native arm64 artifact"
  fi
  actual_platform="$(/usr/bin/otool -l "$executable" | /usr/bin/awk '
    /cmd LC_BUILD_VERSION/ { build = 1; next }
    build && $1 == "platform" { print $2; build = 0 }
    /cmd LC_VERSION_MIN_IPHONEOS/ { print 2 }
  ')"
  [[ "$actual_platform" == "$expected_platform" ]] ||
    fail "wrong main platform ${actual_platform:-missing} (expected $expected_platform)"
  require_ios_minimum "$executable" "$expected_minimum"
  require_ios_dependency_minima "$app" "$expected_platform" "$expected_minimum"
  echo "Mode A firewall and platform $expected_platform dependency floors $expected_minimum OK: $app"
  exit 0
fi

if [[ "$mode" == "--sileo" ]]; then
  app="$artifact"
  [[ -d "$app" ]] || fail "Sileo input is not an app bundle"
  executable="$app/Wawona"
  [[ -x "$executable" ]] || fail "Sileo executable is missing"
  [[ "$(plist_value "$app/Info.plist" CFBundleIdentifier)" == "com.aspauldingcode.Wawona.ModeB" ]] ||
    fail "Sileo bundle identifier is wrong"
  require_ios_minimum "$executable" "13.0"
  echo "Sileo iOS 13+ artifact gate OK: $app"
  exit 0
fi

[[ "$mode" == "--mode-b" || "$mode" == "--iteration" ]] || usage
[[ "$(basename "$artifact")" =~ ^Wawona-[0-9]{2}\.[0-9]{1,2}\.[0-9]{1,2}-iOS-arm64\.tipa$ ]] ||
  fail "Mode B filename does not follow release naming"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
entries="$tmp/entries.txt"
unzip -Z1 "$artifact" >"$entries"
if zipinfo -l "$artifact" |
  /usr/bin/awk '$1 ~ /^l/ { found=1 } END { exit(found ? 0 : 1) }'; then
  fail "tipa must not contain symbolic links"
fi
unzip -q "$artifact" -d "$tmp" \
  "Payload/Wawona.app/Wawona" \
  "Payload/Wawona.app/Info.plist"
app="$tmp/Payload/Wawona.app"
executable="$app/Wawona"
[[ -x "$executable" ]] || fail "Mode B executable is missing"
! /usr/bin/grep -q '^Payload/Wawona\.app/_CodeSignature/' "$entries" ||
  fail "tipa must not contain _CodeSignature"
for framework in libEGL libGLESv2; do
  /usr/bin/grep -Fxq \
    "Payload/Wawona.app/Frameworks/$framework.framework/$framework" "$entries" ||
    fail "Mode B runtime dependency is missing: $framework.framework"
done
# Relay owns the CPU. Real engine files only. Do not match zsh
# completion `_qemu` or "No QEMU" copy in path names.
if /usr/bin/grep -E \
  'wwn-qemu-run|qemu-system-|libqemu|qemu-[^/]*\.framework|/share/qemu/|Frameworks/qemu' \
  "$entries" >/dev/null; then
  fail "QEMU artifacts are forbidden in Mode B (Relay fail closed)"
fi
# Guest Image/rootfs are Relay NixOS prebuilts, not a QEMU ship path.
# Embed them only after Relay boots a guest and presents Wayland into
# iland. Until then both official and iteration tipas stay slim.
echo "Mode B tipa: skipping leftover guest Image/rootfs (Relay frames planned)"
[[ "$(plist_value "$app/Info.plist" CFBundleIdentifier)" == "com.aspauldingcode.Wawona.ModeB" ]] ||
  fail "Mode B bundle identifier is wrong"
[[ -n "$(plist_value "$app/Info.plist" CFBundleVersion)" ]] ||
  fail "Mode B build number is missing"
require_ios_minimum "$executable" "14.0"
/usr/bin/nm -gU "$executable" 2>/dev/null | /usr/bin/grep '_wwn_iomfb_open' >/dev/null ||
  fail "Mode B IOMFB sink is not linked"
/usr/bin/nm -gU "$executable" 2>/dev/null | /usr/bin/grep '_wwn_igetty_ios_initialize' >/dev/null ||
  fail "Mode B logical session switcher is not linked"
# VM start fail-closes in WWNMobileVmEngine. Do not require the leftover
# QEMU wwn_vm_product_accel contract symbol.
/usr/bin/strings "$executable" | /usr/bin/grep 'IOMobileFramebuffer' >/dev/null ||
  fail "Mode B IOMFB SPI is absent"

entitlements="$tmp/modeb-entitlements.plist"
ldid -e "$executable" >"$entitlements"
for required in \
  get-task-allow \
  platform-application \
  com.apple.private.security.no-sandbox \
  com.apple.private.IOMobileFramebuffer \
  com.apple.security.iokit-user-client-class; do
  /usr/bin/grep -q "$required" "$entitlements" ||
    fail "missing entitlement: $required"
done
check_forbidden_entitlements "$entitlements"
if [[ "$mode" == "--iteration" ]]; then
  echo "Mode B iteration tipa firewall OK: $artifact"
else
  echo "Mode B tipa firewall OK: $artifact"
fi
