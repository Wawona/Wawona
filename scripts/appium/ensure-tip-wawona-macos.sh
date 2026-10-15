#!/usr/bin/env bash
# Tip macOS Wawona for Appium / local tests: rebuild when git HEAD drifts,
# refuse stale installs, clean-launch the tip binary every time.
#
# Usage:
#   eval "$(scripts/appium/ensure-tip-wawona-macos.sh)"
#   # exports WAWONA_APP_PATH, WAWONA_RUNTIME, XDG_RUNTIME_DIR
#
# Env:
#   WAWONA_TEST_REBUILD=1     force xcodebuild even if HEAD stamp matches
#   WAWONA_TIP_SKIP_BUILD=1   reuse existing tip binary (still clean launch +
#                             refuse stale). Lab only when nix/xcode contended;
#                             never Gate UI. Catalog may use when tip.bin exists.
#   WAWONA_TIP_SKIP_LAUNCH=1  build/resolve only (no quit/relaunch)
#   WAWONA_ALLOW_STALE_TEST_APP=1  lab escape (never for catalog)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/require-tip-wawona-app.sh"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/nix/var/nix/profiles/default/bin:${HOME}/.nix-profile/bin:${PATH:-}"

TIP_ROOT="${WAWONA_TIP_ROOT:-/tmp/wawona-macos-tip}"
DD="${TIP_ROOT}/DerivedData"
APP="$(wawona_tip_app_macos)"
STAMP="${TIP_ROOT}/git-HEAD"
LINK="${TIP_ROOT}/Wawona.app"
RUNTIME="${WAWONA_RUNTIME:-${XDG_RUNTIME_DIR:-/tmp/wawona-$(id -u)}}"

cd "$ROOT"
HEAD="$(git rev-parse HEAD)"
need_build=0
if [[ "${WAWONA_TIP_SKIP_BUILD:-0}" == "1" ]]; then
  if [[ ! -x "$APP/Contents/MacOS/Wawona" ]]; then
    echo "FAIL: WAWONA_TIP_SKIP_BUILD=1 but tip binary missing: $APP" >&2
    exit 2
  fi
  echo "ensure-tip-wawona-macos: SKIP_BUILD=1; clean launch only" >&2
else
if [[ "${WAWONA_TEST_REBUILD:-0}" == "1" ]]; then
  need_build=1
fi
if [[ ! -x "$APP/Contents/MacOS/Wawona" ]]; then
  need_build=1
fi
# Rebuild when product tree drifts vs tip stamp (committed or dirty).
# Scripts/docs-only tip commits reuse the stamped binary. Clean launch
# still runs every time. Product paths: Sources/, src/, Darwin/, Cargo.*,
# flake, VERSION, xcodegen.
PRODUCT_PATHS=(
  Sources/ src/ Darwin/ Cargo.toml Cargo.lock Package.swift
  dependencies/ xcodegen.nix flake.nix flake.lock VERSION
)
if [[ "$need_build" -eq 0 ]]; then
  stamped="$(cat "$STAMP" 2>/dev/null || true)"
  if [[ -z "$stamped" ]]; then
    need_build=1
  else
    product_dirty=0
    if [[ "$stamped" != "$HEAD" ]]; then
      if ! git diff --quiet "$stamped" "$HEAD" -- "${PRODUCT_PATHS[@]}" 2>/dev/null; then
        product_dirty=1
      fi
    fi
    # Uncommitted product edits vs working tree also force rebuild.
    if ! git diff --quiet -- "${PRODUCT_PATHS[@]}" 2>/dev/null; then
      product_dirty=1
    fi
    if ! git diff --quiet --cached -- "${PRODUCT_PATHS[@]}" 2>/dev/null; then
      product_dirty=1
    fi
    if [[ "$product_dirty" -eq 1 ]]; then
      need_build=1
    elif [[ "$stamped" != "$HEAD" ]]; then
      echo "ensure-tip-wawona-macos: HEAD moved (non-product); reuse tip binary" >&2
      echo "$HEAD" >"$STAMP"
    fi
  fi
fi

if [[ "$need_build" -eq 1 ]]; then
  # Status on stderr only: stdout is eval'd by capture-catalog-gallery.
  echo "ensure-tip-wawona-macos: building tip Wawona-macOS for $HEAD" >&2
  mkdir -p "$TIP_ROOT" "$DD"
  # Tip xcodegen from flake when available. Never leave stale root-owned tmp.
  rm -f "$ROOT/.xcodegen-project.tmp.json" 2>/dev/null || true
  if [[ ! -d "$ROOT/Wawona.xcodeproj" ]] && command -v nix >/dev/null 2>&1; then
    XG="$(nix build --no-link --print-out-paths "$ROOT#xcodegen-macos" 2>/dev/null | head -1 || true)"
    if [[ -n "$XG" && -x "$XG/bin/xcodegen" ]]; then
      if ! "$XG/bin/xcodegen" >&2; then
        echo "FAIL: xcodegen failed (check $ROOT/.xcodegen-project.tmp.json perms)" >&2
        exit 2
      fi
    fi
  fi
  if [[ ! -d "$ROOT/Wawona.xcodeproj" ]]; then
    echo "FAIL: Wawona.xcodeproj missing; generate via nix/xcodegen first" >&2
    exit 2
  fi
  xcodebuild \
    -project "$ROOT/Wawona.xcodeproj" \
    -scheme Wawona-macOS \
    -configuration Debug \
    -derivedDataPath "$DD" \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY=- \
    build >&2
  echo "$HEAD" >"$STAMP"
  ln -sfn "$APP" "$LINK"
fi
fi # WAWONA_TIP_SKIP_BUILD

wawona_refuse_stale_app_path "$APP"
export WAWONA_APP_PATH="$APP"
export WAWONA_RUNTIME="$RUNTIME"
export XDG_RUNTIME_DIR="$RUNTIME"
mkdir -p "$RUNTIME"

if [[ "${WAWONA_TIP_SKIP_LAUNCH:-0}" != "1" ]]; then
  # Clean launch: never attach to a leftover /Applications or old DD process.
  osascript -e 'tell application id "com.aspauldingcode.Wawona" to quit' \
    >/dev/null 2>&1 || true
  pkill -f 'Wawona.app/Contents/MacOS/Wawona' 2>/dev/null || true
  sleep 1
  rm -f "$RUNTIME/wayland-0"
  nohup env WAWONA_RUNTIME="$RUNTIME" XDG_RUNTIME_DIR="$RUNTIME" \
    "$APP/Contents/MacOS/Wawona" \
    >"${TIP_ROOT}/launch.log" 2>&1 &
  disown 2>/dev/null || true
  for _ in $(seq 1 60); do
    if python3 -c "import socket;s=socket.socket(socket.AF_UNIX);s.settimeout(1);s.connect('$RUNTIME/wayland-0')" \
      2>/dev/null; then
      break
    fi
    sleep 0.4
  done
  if ! python3 -c "import socket;s=socket.socket(socket.AF_UNIX);s.settimeout(1);s.connect('$RUNTIME/wayland-0')" \
    2>/dev/null; then
    echo "FAIL: tip Wawona did not bind $RUNTIME/wayland-0" >&2
    tail -40 "${TIP_ROOT}/launch.log" >&2 || true
    exit 2
  fi
  # Prove the live process is the tip binary, not /Applications.
  live="$(pgrep -lf 'MacOS/Wawona' 2>/dev/null | head -1 || true)"
  if echo "$live" | grep -E '/Applications/|DerivedData-macos' >/dev/null 2>&1; then
    echo "FAIL: live Wawona is stale: $live" >&2
    exit 2
  fi
  if ! echo "$live" | grep -F "$APP/Contents/MacOS/Wawona" >/dev/null 2>&1; then
    # Accept symlink tip path.
    if ! echo "$live" | grep -E 'wawona-macos-tip|result-macos|/result/Applications' >/dev/null 2>&1; then
      echo "FAIL: live Wawona is not tip app: $live" >&2
      echo "expected: $APP/Contents/MacOS/Wawona" >&2
      exit 2
    fi
  fi
fi

# Print exports for eval "$(…)"
printf 'export WAWONA_APP_PATH=%q\n' "$WAWONA_APP_PATH"
printf 'export WAWONA_RUNTIME=%q\n' "$WAWONA_RUNTIME"
printf 'export XDG_RUNTIME_DIR=%q\n' "$XDG_RUNTIME_DIR"
echo "ensure-tip-wawona-macos: ok app=$WAWONA_APP_PATH head=$HEAD" >&2
