#!/usr/bin/env bash
# Verify Mode B libwayland-mac.dylib packaging rules:
#   - wawona-macos and wawona-macos-desktop-host (3rd-party macOS): dylib MUST
#     be present. macOS is not App Store constrained.
#   - iOS / Android app roots: dylib MUST be absent (store-safe Mode A)
#
# Usage:
#   verify-iland-mode-b-bundle.sh --mode absent  /path/to/Wawona.app
#   verify-iland-mode-b-bundle.sh --mode present /path/to/Wawona.app
#   verify-iland-mode-b-bundle.sh --mode absent  /path/to/Payload/*.app   # iOS
#   verify-iland-mode-b-bundle.sh --mode absent  /path/to/apk-unpacked    # Android
set -euo pipefail

mode=""
root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) mode="${2:-}"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) root="$1"; shift ;;
  esac
done

if [[ "$mode" != "present" && "$mode" != "absent" ]]; then
  echo "usage: $0 --mode present|absent <app-or-artifact-root>" >&2
  exit 2
fi
if [[ -z "$root" || ! -e "$root" ]]; then
  echo "missing or invalid root: ${root:-"(empty)"}" >&2
  exit 2
fi

dylib_rel="Contents/Library/Wawona/iland/libwayland-mac.dylib"
found="$(find "$root" \( -name 'libwayland-mac.dylib' -o -name 'libwwn-iland.dylib' \) 2>/dev/null || true)"

if [[ "$mode" == "present" ]]; then
  if [[ ! -f "$root/$dylib_rel" ]]; then
    echo "FAIL: expected Mode B dylib at $root/$dylib_rel" >&2
    exit 1
  fi
  if ! file "$root/$dylib_rel" | grep -q 'Mach-O'; then
    echo "FAIL: $root/$dylib_rel is not a Mach-O dylib" >&2
    exit 1
  fi
  echo "OK: Mode B dylib present ($root/$dylib_rel)"
else
  if [[ -n "$found" ]]; then
    echo "FAIL: Mode B dylib must be absent from store-safe / non-macOS artifact:" >&2
    echo "$found" >&2
    exit 1
  fi
  echo "OK: Mode B dylib absent under $root"
fi
