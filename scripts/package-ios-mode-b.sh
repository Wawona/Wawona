#!/usr/bin/env bash
# Package a Mode B iOS .app into TrollStore .tipa and/or Sileo .deb wrappers.
# Never used by Ship: beta / TestFlight. See docs/agent-rules/wawona-release-assets.md
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --app PATH.app --version CALVER --out DIR [--tipa] [--rootless-deb] [--rootful-deb] [--ldid PATH]
EOF
  exit 1
}

APP=""
VERSION=""
OUT="dist"
DO_TIPA=0
DO_ROOTLESS=0
DO_ROOTFUL=0
LDID="${LDID:-ldid}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --tipa) DO_TIPA=1; shift ;;
    --rootless-deb) DO_ROOTLESS=1; shift ;;
    --rootful-deb) DO_ROOTFUL=1; shift ;;
    --ldid) LDID="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$APP" && -n "$VERSION" && -d "$APP" ]] || usage
mkdir -p "$OUT"

ENTITLEMENTS="$(mktemp)"
cat >"$ENTITLEMENTS" <<'PLIST'
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
</dict>
</plist>
PLIST

BIN="$(/usr/bin/find "$APP" -maxdepth 2 -type f -perm +111 | head -1)"
if [[ -z "$BIN" ]]; then
  BIN="$APP/Wawona"
fi

if [[ "$DO_TIPA" -eq 1 ]]; then
  if command -v "$LDID" >/dev/null 2>&1; then
    "$LDID" -S"$ENTITLEMENTS" "$BIN" || true
  else
    echo "warning: ldid not found; packaging unsigned .tipa" >&2
  fi
  STAGE="$(mktemp -d)"
  mkdir -p "$STAGE/Payload"
  cp -R "$APP" "$STAGE/Payload/"
  TIPA="$OUT/Wawona-${VERSION}-iOS-arm64.tipa"
  (cd "$STAGE" && zip -qry "$OLDPWD/$TIPA" Payload)
  rm -rf "$STAGE"
  echo "wrote $TIPA"
fi

pack_deb() {
  local scheme="$1" arch="$2" prefix="$3"
  local stage control_dir data_root deb
  stage="$(mktemp -d)"
  control_dir="$stage/DEBIAN"
  mkdir -p "$control_dir"
  if [[ "$scheme" == "rootless" ]]; then
    data_root="$stage${prefix}/Applications"
  else
    data_root="$stage/Applications"
  fi
  mkdir -p "$data_root"
  cp -R "$APP" "$data_root/"
  cat >"$control_dir/control" <<EOF
Package: com.aspauldingcode.wawona
Version: ${VERSION}
Architecture: ${arch}
Maintainer: Wawona Team <team@wawona.io>
Description: Wawona Mode B (${scheme}) for jailbroken iOS
Section: Applications
Priority: optional
Homepage: https://repo.wawona.io
EOF
  deb="$OUT/Wawona-${VERSION}-iOS-arm64-${scheme}.deb"
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -Zxz -b "$stage" "$deb"
  else
    # Fallback: tar.gz named .deb for CI artifact wiring when dpkg-deb absent.
    # Real Release ships must use dpkg-deb.
    echo "warning: dpkg-deb missing; writing tar staging as ${deb}.tar.gz" >&2
    tar -C "$stage" -czf "${deb}.tar.gz" .
    echo "staged ${deb}.tar.gz (install dpkg-deb for real .deb)"
    rm -rf "$stage"
    return
  fi
  rm -rf "$stage"
  echo "wrote $deb"
}

if [[ "$DO_ROOTLESS" -eq 1 ]]; then
  pack_deb rootless iphoneos-arm64 /var/jb
fi
if [[ "$DO_ROOTFUL" -eq 1 ]]; then
  pack_deb rootful iphoneos-arm /
fi

rm -f "$ENTITLEMENTS"
