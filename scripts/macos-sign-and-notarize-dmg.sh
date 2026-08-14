#!/usr/bin/env bash
# Deep-sign Wawona.app (Developer ID Application), productsign WawonaAgent.pkg
# (Developer ID Installer), build a UDZO DMG, submit to notarytool, staple.
#
# Intended for Ship: GitHub assets (release.yml). Secrets from GitHub Environment
# release-beta / SecretSpec (see docs/maintainers/secrets.md).
#
# P12 files must be macOS-importable (openssl pkcs12 -export / Keychain export).
# cryptography.io PBES2 bags often fail `security import` with MAC verification.
#
# Usage:
#   DEVELOPER_ID_APPLICATION_P12_BASE64=… \
#   DEVELOPER_ID_INSTALLER_P12_BASE64=… \
#   MATCH_PASSWORD=… \
#   APP_STORE_CONNECT_API_KEY=… \   # base64 of ASC .p8 PEM
#   APP_STORE_CONNECT_KEY_ID=… \
#   APP_STORE_CONNECT_ISSUER_ID=… \
#   ./scripts/macos-sign-and-notarize-dmg.sh \
#     --app dmg-staging/Wawona.app \
#     --pkg dmg-staging/WawonaAgent.pkg \
#     --dmg Wawona-26.8.9-macOS-arm64.dmg \
#     --staging dmg-staging
#
# Env:
#   WAWONA_DEVELOPER_ID_ENTITLEMENTS  override entitlements plist path
#   WAWONA_SKIP_NOTARIZE=1            sign + DMG only (local debug)
#   WAWONA_CODESIGN_IDENTITY          force Application identity name
#   WAWONA_PRODUCTSIGN_IDENTITY       force Installer identity name
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="${WAWONA_DEVELOPER_ID_ENTITLEMENTS:-$ROOT/src/resources/app-bundle/Wawona-macOS-DeveloperID.entitlements}"

APP=""
PKG=""
DMG=""
STAGING=""
VERSION="${WAWONA_VERSION:-}"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?}"; shift 2 ;;
    --pkg) PKG="${2:?}"; shift 2 ;;
    --dmg) DMG="${2:?}"; shift 2 ;;
    --staging) STAGING="${2:?}"; shift 2 ;;
    --version) VERSION="${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$APP" && -d "$APP" ]] || { echo "error: --app must be a Wawona.app bundle" >&2; exit 2; }
[[ -f "$ENTITLEMENTS" ]] || { echo "error: entitlements missing: $ENTITLEMENTS" >&2; exit 2; }

if [[ -z "$VERSION" ]]; then
  VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)"
fi
if [[ -z "$DMG" ]]; then
  DMG="$ROOT/Wawona-${VERSION}-macOS-arm64.dmg"
fi
if [[ -z "$STAGING" ]]; then
  STAGING="$(dirname "$APP")"
fi

: "${DEVELOPER_ID_APPLICATION_P12_BASE64:?Set DEVELOPER_ID_APPLICATION_P12_BASE64}"
: "${DEVELOPER_ID_INSTALLER_P12_BASE64:?Set DEVELOPER_ID_INSTALLER_P12_BASE64}"
: "${MATCH_PASSWORD:?Set MATCH_PASSWORD (P12 passphrase)}"

if [[ "${WAWONA_SKIP_NOTARIZE:-0}" != "1" ]]; then
  # Accept either CI-shaped APP_STORE_CONNECT_* or SecretSpec ASC_* (+ base64 key).
  if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${ASC_KEY_ID:-}" ]]; then
    APP_STORE_CONNECT_KEY_ID="$ASC_KEY_ID"
  fi
  if [[ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    APP_STORE_CONNECT_ISSUER_ID="$ASC_ISSUER_ID"
  fi
  if [[ -z "${APP_STORE_CONNECT_API_KEY:-}" && -n "${ASC_P8:-}" ]]; then
    APP_STORE_CONNECT_API_KEY="$(printf '%s' "$ASC_P8" | base64 | tr -d '\n')"
  fi
  : "${APP_STORE_CONNECT_API_KEY:?Set APP_STORE_CONNECT_API_KEY (base64 .p8) or ASC_P8}"
  : "${APP_STORE_CONNECT_KEY_ID:?Set APP_STORE_CONNECT_KEY_ID or ASC_KEY_ID}"
  : "${APP_STORE_CONNECT_ISSUER_ID:?Set APP_STORE_CONNECT_ISSUER_ID or ASC_ISSUER_ID}"
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/wawona-devid-XXXXXX")"
KEYCHAIN="$WORKDIR/wawona-devid.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
APP_P12="$WORKDIR/developer_id_application.p12"
INST_P12="$WORKDIR/developer_id_installer.p12"
ASC_P8="$WORKDIR/AuthKey.p8"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

printf '%s' "$DEVELOPER_ID_APPLICATION_P12_BASE64" | base64 -d >"$APP_P12"
printf '%s' "$DEVELOPER_ID_INSTALLER_P12_BASE64" | base64 -d >"$INST_P12"
[[ -s "$APP_P12" && -s "$INST_P12" ]] || { echo "error: P12 decode produced empty file" >&2; exit 1; }

echo "Creating temporary signing keychain..."
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
# Prefer our keychain first so codesign/productsign find the imported identities.
EXISTING_KC="$(security list-keychains -d user | sed 's/"//g' | tr '\n' ' ')"
security list-keychains -d user -s "$KEYCHAIN" $EXISTING_KC

security import "$APP_P12" -k "$KEYCHAIN" -P "$MATCH_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productsign >/dev/null
security import "$INST_P12" -k "$KEYCHAIN" -P "$MATCH_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productsign >/dev/null
# Developer ID G2 intermediate — needed for a complete signing chain in a
# fresh keychain (system roots alone are not always enough for codesign).
DEVID_G2="$WORKDIR/DeveloperIDG2CA.cer"
if curl -fsSL -o "$DEVID_G2" \
  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer; then
  security import "$DEVID_G2" -k "$KEYCHAIN" -T /usr/bin/codesign \
    -T /usr/bin/security -T /usr/bin/productsign >/dev/null 2>&1 \
    || security add-certificates -k "$KEYCHAIN" "$DEVID_G2" >/dev/null 2>&1 \
    || true
fi
security set-key-partition-list -S apple-tool:,apple:,codesign:,productsign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

APP_IDENTITY="${WAWONA_CODESIGN_IDENTITY:-}"
INST_IDENTITY="${WAWONA_PRODUCTSIGN_IDENTITY:-}"
if [[ -z "$APP_IDENTITY" ]]; then
  APP_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$INST_IDENTITY" ]]; then
  # productsign looks at signing identities; list via find-identity without -p codesigning
  INST_IDENTITY="$(security find-identity -v "$KEYCHAIN" \
    | awk -F'"' '/Developer ID Installer/ { print $2; exit }')"
fi
[[ -n "$APP_IDENTITY" ]] || { echo "error: no Developer ID Application identity in keychain" >&2; security find-identity -v "$KEYCHAIN" >&2; exit 1; }
[[ -n "$INST_IDENTITY" ]] || { echo "error: no Developer ID Installer identity in keychain" >&2; security find-identity -v "$KEYCHAIN" >&2; exit 1; }
echo "Application identity: $APP_IDENTITY"
echo "Installer identity:   $INST_IDENTITY"

# Make the bundle writable (nix / artifact zips are often immutable-ish).
chmod -R u+w "$APP"
find "$APP/Contents/MacOS" -type f -exec chmod +x {} + 2>/dev/null || true
find "$APP/Contents/Resources/bin" -type f -exec chmod +x {} + 2>/dev/null || true
find "$APP" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true

# Nix packaging historically drops FHS lib/ + share/ next to Contents/. codesign
# then fails with "unsealed contents present in the bundle root". Runtime already
# probes Contents/Resources/{lib,share} (see WWNPlatformCallbacks.m).
relocate_fhs_into_contents() {
  local app="$1"
  local res="$app/Contents/Resources"
  local d entry base
  mkdir -p "$res"
  for d in lib share; do
    if [[ -d "$app/$d" ]]; then
      echo "Relocating .app/$d → Contents/Resources/$d (codesign seal)"
      mkdir -p "$res/$d"
      cp -a "$app/$d/." "$res/$d/"
      rm -rf "$app/$d"
    fi
  done
  shopt -s nullglob
  for entry in "$app"/*; do
    base="$(basename "$entry")"
    [[ "$base" == Contents ]] && continue
    echo "error: unexpected .app root entry (breaks codesign): $entry" >&2
    exit 1
  done
  shopt -u nullglob
}
relocate_fhs_into_contents "$APP"

sign_macho() {
  local target="$1"
  local with_entitlements="${2:-0}"
  if [[ "$with_entitlements" == "1" ]]; then
    /usr/bin/codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" \
      --sign "$APP_IDENTITY" "$target"
  else
    /usr/bin/codesign --force --options runtime --timestamp \
      --sign "$APP_IDENTITY" "$target"
  fi
}

# GHA upload-artifact / zip materializes framework symlinks as real files/dirs
# (top-level Foo + Resources + Versions/Current copy). codesign then errors with
# "bundle format is ambiguous (could be app or framework)". Restore the macOS
# layout before signing.
repair_framework_symlinks() {
  local fw="$1"
  local name
  name="$(basename "$fw" .framework)"
  [[ -d "$fw/Versions/A" ]] || return 0

  if [[ -e "$fw/Versions/Current" && ! -L "$fw/Versions/Current" ]]; then
    rm -rf "$fw/Versions/Current"
    ln -s A "$fw/Versions/Current"
  elif [[ ! -e "$fw/Versions/Current" ]]; then
    ln -s A "$fw/Versions/Current"
  fi

  if [[ -e "$fw/$name" && ! -L "$fw/$name" ]]; then
    rm -rf "$fw/$name"
    ln -s "Versions/Current/$name" "$fw/$name"
  elif [[ ! -e "$fw/$name" ]]; then
    ln -s "Versions/Current/$name" "$fw/$name"
  fi

  if [[ -e "$fw/Resources" && ! -L "$fw/Resources" ]]; then
    rm -rf "$fw/Resources"
    ln -s "Versions/Current/Resources" "$fw/Resources"
  elif [[ ! -e "$fw/Resources" && -d "$fw/Versions/A/Resources" ]]; then
    ln -s "Versions/Current/Resources" "$fw/Resources"
  fi
}

sign_framework() {
  local fw="$1"
  local name bin
  name="$(basename "$fw" .framework)"
  repair_framework_symlinks "$fw"
  bin="$fw/Versions/A/$name"
  if [[ ! -f "$bin" ]]; then
    bin="$fw/$name"
  fi
  if [[ -f "$bin" ]]; then
    # Resolve symlinks so we sign the real Mach-O once.
    bin="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$bin")"
    sign_macho "$bin"
  fi
  sign_macho "$fw"
}

echo "Deep-signing nested Mach-O (inside-out)..."
while IFS= read -r -d '' fw; do
  echo "  framework: $fw"
  sign_framework "$fw"
done < <(find "$APP/Contents" -name '*.framework' -print0 2>/dev/null | sort -z)

# Loose dylibs / bundles (skip anything inside a .framework — already sealed)
while IFS= read -r -d '' lib; do
  case "$lib" in
    *.framework/*) continue ;;
  esac
  sign_macho "$lib"
done < <(find "$APP/Contents" \( -name '*.dylib' -o -name '*.so' \) -type f -print0 2>/dev/null | sort -z)

# Helper executables (Resources/bin, MacOS helpers except the main app binary last)
MAIN_BIN="$APP/Contents/MacOS/Wawona"
while IFS= read -r -d '' bin; do
  [[ "$bin" == "$MAIN_BIN" ]] && continue
  case "$bin" in
    *.framework/*) continue ;;
  esac
  # Skip non-Mach-O (scripts) and symlinks into frameworks we already signed
  [[ -L "$bin" ]] && continue
  file -b "$bin" 2>/dev/null | grep -q 'Mach-O' || continue
  sign_macho "$bin"
done < <(find "$APP/Contents" -type f -perm +111 -print0 2>/dev/null | sort -z)

# Main executable + bundle seal (entitlements on both)
sign_macho "$MAIN_BIN" 1
sign_macho "$APP" 1

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP" 2>&1 || {
  echo "note: spctl assess may fail pre-notarization; continuing" >&2
}

if [[ -n "$PKG" ]]; then
  # Rebuild from the sealed app so the installer payload matches (staging may
  # have packaged pre-relocate lib/share at the .app root).
  echo "Rebuilding agent pkg from sealed app → $PKG"
  chmod +x "$ROOT/scripts/macos-launch-agent-pkg.sh"
  WAWONA_VERSION="$VERSION" WAWONA_APP_SRC="$APP" \
    "$ROOT/scripts/macos-launch-agent-pkg.sh" "$PKG"
  echo "productsign $PKG ..."
  SIGNED_PKG="$WORKDIR/WawonaAgent-signed.pkg"
  productsign --sign "$INST_IDENTITY" --timestamp "$PKG" "$SIGNED_PKG"
  mv -f "$SIGNED_PKG" "$PKG"
  pkgutil --check-signature "$PKG" || true
fi

# Ensure staging has Applications symlink + README if we own the folder.
if [[ -d "$STAGING" ]]; then
  [[ -e "$STAGING/Applications" ]] || ln -s /Applications "$STAGING/Applications"
  if [[ ! -f "$STAGING/README.txt" ]]; then
    {
      echo 'Wawona macOS install'
      echo '===================='
      echo 'Option A (app only): drag Wawona.app into Applications.'
      echo 'Option B (recommended): double-click WawonaAgent.pkg to install'
      echo '  Wawona.app plus the compositor + menubar LaunchAgents.'
    } >"$STAGING/README.txt"
  fi
  [[ -d "$STAGING/Wawona.app" ]] || { echo "error: $STAGING/Wawona.app missing" >&2; exit 1; }
  echo "Building DMG from $STAGING → $DMG"
  rm -f "$DMG"
  hdiutil create -volname "Wawona" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG"
else
  [[ -f "$DMG" ]] || { echo "error: DMG missing and no --staging to build from" >&2; exit 1; }
fi

if [[ "${WAWONA_SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "WAWONA_SKIP_NOTARIZE=1 — skipping notarytool/staple"
  ls -lah "$DMG"
  exit 0
fi

printf '%s' "$APP_STORE_CONNECT_API_KEY" | base64 -d >"$ASC_P8"
[[ -s "$ASC_P8" ]] || { echo "error: APP_STORE_CONNECT_API_KEY did not decode to a .p8" >&2; exit 1; }
# Accept PEM that lost its trailing newline.
if ! grep -q 'BEGIN PRIVATE KEY' "$ASC_P8"; then
  echo "error: decoded API key does not look like a PEM private key" >&2
  exit 1
fi

echo "Submitting $DMG to notarytool (wait)..."
xcrun notarytool submit "$DMG" \
  --key "$ASC_P8" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling ticket..."
xcrun stapler staple "$DMG"
# Staple the app too when present (helps Gatekeeper after drag-install from DMG).
xcrun stapler staple "$APP" 2>/dev/null || true
if [[ -n "$PKG" && -f "$PKG" ]]; then
  xcrun stapler staple "$PKG" 2>/dev/null || true
fi

echo "Final Gatekeeper assessment..."
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" 2>&1 || true
codesign --verify --deep --strict --verbose=2 "$APP"
echo "OK: notarized DMG at $DMG"
ls -lah "$DMG"
