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
#   WAWONA_LINK_LIBGHOSTTY=1|0    optional Zig archive link (default 0).
#                                 Product paint is TerminalMetalPresent.
#                                 1 stages libghostty-macos when archive missing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/require-tip-wawona-app.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/refuse-visionos-target.sh"
wawona_refuse_visionos_target || exit 3

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
  if [[ -f "$APP/Contents/MacOS/Wawona" && ! -x "$APP/Contents/MacOS/Wawona" ]]; then
    chmod +x "$APP/Contents/MacOS/Wawona"
  fi
  if [[ ! -x "$APP/Contents/MacOS/Wawona" ]]; then
    echo "ensure-tip-wawona-macos: WAWONA_TIP_SKIP_BUILD=1 requested but binary missing at $APP; building" >&2
    need_build=1
  else
    echo "ensure-tip-wawona-macos: SKIP_BUILD=1; clean launch only" >&2
  fi
else
if [[ "${WAWONA_TEST_REBUILD:-0}" == "1" ]]; then
  need_build=1
fi
if [[ ! -x "$APP/Contents/MacOS/Wawona" ]]; then
  need_build=1
fi
# Rebuild when product tree drifts vs tip stamp (committed or dirty).
# Scripts/docs-only tip commits reuse the stamped binary. Clean launch
# still runs every time. Shared helper: require-tip-wawona-app.sh.
if [[ "$need_build" -eq 0 ]]; then
  if ! wawona_tip_stamp_is_fresh "$TIP_ROOT" "$ROOT"; then
    need_build=1
  else
    stamped="$(cat "$STAMP" 2>/dev/null || true)"
    if [[ -n "$stamped" && "$stamped" != "$HEAD" ]]; then
      echo "ensure-tip-wawona-macos: HEAD moved (non-product); reuse tip binary" >&2
      wawona_tip_write_stamp "$TIP_ROOT" "$ROOT"
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
  # Tip dogfood: TerminalMetalPresent (product). Optional Zig archive only if
  # WAWONA_LINK_LIBGHOSTTY=1. Write SRCROOT/.build/wwn-libghostty-link.xcconfig
  # BEFORE xcodebuild so wwn-version.xcconfig #include? sees OTHER_LDFLAGS.
  mkdir -p "$ROOT/.build"
  _lg_build_xc="$ROOT/.build/wwn-libghostty-link.xcconfig"
  _lg_a="$ROOT/.nix-deps/libghostty-macos/lib/libghostty-internal.a"
  _lg_inc="$ROOT/.nix-deps/libghostty-macos/include"
  # Default off: Metal Present. Explicit 1 still force_loads Zig archive.
  export WAWONA_LINK_LIBGHOSTTY="${WAWONA_LINK_LIBGHOSTTY:-0}"
  if [[ "${WAWONA_LINK_LIBGHOSTTY}" = "1" ]]; then
    if [[ ! -f "$_lg_a" ]]; then
      echo "ensure-tip-wawona-macos: staging libghostty-macos (WAWONA_LINK_LIBGHOSTTY=1)" >&2
      WAWONA_GHOSTTY_SRC="${WAWONA_GHOSTTY_SRC:-$ROOT/../Ghostty}" \
        "$ROOT/scripts/stage-libghostty-macos.sh" >&2
    fi
    if [[ -f "$_lg_a" ]]; then
      {
        echo "// Optional Zig archive link (WAWONA_LINK_LIBGHOSTTY=1). Paint is Metal."
        echo "HEADER_SEARCH_PATHS = \$(inherited) ${_lg_inc} \$(DERIVED_FILE_DIR)"
        echo "OTHER_CFLAGS = \$(inherited) -I${_lg_inc} -I\$(DERIVED_FILE_DIR)"
        echo "OTHER_LDFLAGS = \$(inherited) -force_load ${_lg_a} -lc++ -lz -lbz2 -framework Metal -framework MetalKit -framework QuartzCore -framework CoreText -framework CoreGraphics -framework CoreVideo -framework CoreImage -framework IOKit -framework Security -framework UniformTypeIdentifiers -framework Carbon -framework GameController -framework IOSurface -framework SystemConfiguration -framework Network"
      } >"$_lg_build_xc"
      echo "ensure-tip-wawona-macos: Zig archive link-on; wrote $_lg_build_xc" >&2
    else
      echo "// Zig GhosttyLib missing archive." >"$_lg_build_xc"
      echo "FAIL: WAWONA_LINK_LIBGHOSTTY=1 but $_lg_a missing" >&2
      exit 2
    fi
  else
    echo "// Zig GhosttyLib tip link off (default). TerminalMetalPresent." >"$_lg_build_xc"
    echo "ensure-tip-wawona-macos: TerminalMetalPresent tip (WAWONA_LINK_LIBGHOSTTY=0)" >&2
  fi
  # Always refresh xcodegen before tip xcodebuild (macOS dogfood contract).
  # Sibling Terminal (Metal Present) overrides flake pin so pbxproj lists
  # TerminalMetalPresent.swift. Flake pin alone can lag local Terminal tip.
  _xg_nix_args=(run "$ROOT#xcodegen-macos")
  if [[ -d "$ROOT/../Terminal/apple/Terminal" ]]; then
    _xg_nix_args+=(--override-input terminal "path:$ROOT/../Terminal")
    echo "ensure-tip-wawona-macos: xcodegen-macos + sibling Terminal override" >&2
  else
    echo "ensure-tip-wawona-macos: nix run .#xcodegen-macos" >&2
  fi
  if command -v nix >/dev/null 2>&1; then
    if ! nix "${_xg_nix_args[@]}" -- >&2; then
      echo "FAIL: nix run .#xcodegen-macos" >&2
      exit 2
    fi
  fi
  if [[ ! -f "$ROOT/.nix-deps/terminal/Terminal/TerminalMetalPresent.swift" ]]; then
    echo "FAIL: tip .nix-deps missing TerminalMetalPresent.swift after xcodegen" >&2
    exit 2
  fi
  # Target OTHER_LDFLAGS overrides xcconfig includes for list merge in practice;
  # pass force_load on the xcodebuild CLI when Zig archive link is requested.
  _xg_extra=()
  if [[ "${WAWONA_LINK_LIBGHOSTTY}" = "1" && -f "$_lg_a" ]]; then
    _xg_extra+=(
      "OTHER_LDFLAGS=\$(inherited) -force_load ${_lg_a} -lc++ -lz -lbz2 -framework Metal -framework MetalKit -framework QuartzCore -framework CoreText -framework CoreGraphics -framework CoreVideo -framework CoreImage -framework IOKit -framework Security -framework UniformTypeIdentifiers -framework Carbon -framework GameController -framework IOSurface -framework SystemConfiguration -framework Network"
    )
  fi
  xcodebuild \
    -project "$ROOT/Wawona.xcodeproj" \
    -scheme Wawona-macOS \
    -configuration Debug \
    -derivedDataPath "$DD" \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY=- \
    "${_xg_extra[@]}" \
    build >&2
  wawona_tip_write_stamp "$TIP_ROOT" "$ROOT"
  ln -sfn "$APP" "$LINK"
fi
fi # WAWONA_TIP_SKIP_BUILD

wawona_refuse_stale_app_path "$APP"
wawona_require_tip_fresh_for_proof "$TIP_ROOT" "$ROOT" || exit 2
export WAWONA_APP_PATH="$APP"
export WAWONA_RUNTIME="$RUNTIME"
export XDG_RUNTIME_DIR="$RUNTIME"
mkdir -p "$RUNTIME"

if [[ "${WAWONA_TIP_SKIP_LAUNCH:-0}" != "1" ]]; then
  # Clean launch: never attach to a leftover /Applications or old DD process.
  osascript -e 'tell application id "com.aspauldingcode.Wawona" to quit' \
    >/dev/null 2>&1 || true
  pkill -f 'Wawona.app/Contents/MacOS/Wawona' 2>/dev/null || true
  # Stale install waypipe children keep holding Colima SSH; kill them too.
  pkill -f '/Applications/Wawona.app/Contents/Resources/bin/waypipe' \
    2>/dev/null || true
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
