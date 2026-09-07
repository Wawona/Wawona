#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --mode-a Wawona.app | --mode-b|--iteration Wawona-YY.M.D-iOS-arm64.tipa" >&2
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

if [[ "$mode" == "--mode-a" ]]; then
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
  if /usr/bin/find "$app" -iname '*qemu*' | /usr/bin/grep -q .; then
    fail "QEMU artifacts are forbidden in Mode A"
  fi
  if /usr/bin/codesign -d "$app" >/dev/null 2>&1; then
    entitlements="$(mktemp)"
    trap 'rm -f "$entitlements"' EXIT
    /usr/bin/codesign -d --entitlements :- "$app" >"$entitlements" 2>/dev/null
    ! /usr/bin/grep -Eq 'IOMobileFramebuffer|platform-application|no-sandbox|get-task-allow' "$entitlements" ||
      fail "Mode A contains Mode B entitlements"
  fi
  echo "Mode A firewall OK: $app"
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
if /usr/bin/grep -E 'qemu-|wwn-qemu-run|share/qemu' "$entries" >/dev/null; then
  fail "QEMU/UTM artifacts are forbidden in Mode B tipa"
fi
if [[ "$mode" == "--mode-b" ]]; then
  for guest in wawona-mobile-guest wawona-container-guest; do
    /usr/bin/grep -Fxq "Payload/Wawona.app/$guest/Image" "$entries" ||
      fail "Mode B guest kernel is missing: $guest/Image"
    /usr/bin/grep -Fxq "Payload/Wawona.app/$guest/rootfs.img" "$entries" ||
      fail "Mode B guest rootfs is missing: $guest/rootfs.img"
  done
else
  echo "iteration tipa: skipping guest Image/rootfs.img requirement"
fi
[[ "$(plist_value "$app/Info.plist" CFBundleIdentifier)" == "com.aspauldingcode.Wawona.ModeB" ]] ||
  fail "Mode B bundle identifier is wrong"
[[ -n "$(plist_value "$app/Info.plist" CFBundleVersion)" ]] ||
  fail "Mode B build number is missing"
/usr/bin/nm -gU "$executable" 2>/dev/null | /usr/bin/grep '_wwn_iomfb_open' >/dev/null ||
  fail "Mode B IOMFB sink is not linked"
/usr/bin/nm -gU "$executable" 2>/dev/null | /usr/bin/grep '_wwn_igetty_ios_initialize' >/dev/null ||
  fail "Mode B logical session switcher is not linked"
/usr/bin/nm -gU "$executable" 2>/dev/null | /usr/bin/grep '_wwn_vm_product_accel' >/dev/null ||
  fail "Mode B JIT VM acceleration contract is not linked"
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
