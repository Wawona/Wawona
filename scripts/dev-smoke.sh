#!/usr/bin/env bash
# One-command, minimal-resource local dev loop for Wawona on an Apple Silicon Mac.
#
# Goal (plan Phase 20): make verifying a change cheap and token-free on this M1.
# Each platform uses the fastest local path and, where possible, drives a
# recorded agent-device batch replay (no LLM/MCP, so zero Cursor tokens).
#
# Usage:
#   scripts/dev-smoke.sh <platform> [--build] [--no-replay]
#
#   <platform>  one of: core | macos | ios | android | linux | all
#   --build     force the (scoped) build step before smoking
#   --no-replay skip the agent-device replay (just build/launch)
#
# Environment:
#   WAWONA_IOS_SIM        iOS simulator name (default "iPhone 17 Pro")
#   WAWONA_ANDROID_SERIAL android serial (default: first adb device)
#   WAWONA_SKIP_NIX_PREBUILD=1  reuse the already-built libwawona.a in Xcode
#
# This script never runs the heavy full-matrix build; that lives in CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/.agent-device/test-artifacts"
IOS_SIM="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
DO_BUILD=0
DO_REPLAY=1
PLATFORM="${1:-core}"
shift || true

for arg in "$@"; do
  case "$arg" in
    --build) DO_BUILD=1 ;;
    --no-replay) DO_REPLAY=0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$ARTIFACTS"

log() { printf '\033[1;36m[dev-smoke]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[dev-smoke]\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── core: the cheapest possible signal. Rust unit + integration tests ────────
run_cargo() {
  if have cargo; then
    ( cd "$ROOT" && cargo "$@" )
  else
    # cargo lives in the flake devShell on this machine
    ( cd "$ROOT" && nix develop --command cargo "$@" )
  fi
}

smoke_core() {
  log "cargo test (Rust core; native aarch64-darwin)"
  run_cargo test --lib --no-fail-fast || {
    warn "cargo test reported failures (see output above)"
    return 1
  }
}

# ── macOS: build/launch the native app + run the Wayland client compat matrix ─
smoke_macos() {
  if [[ "$DO_BUILD" == "1" ]]; then
    log "building macOS app via Nix (.#wawona-macos)"
    ( cd "$ROOT" && nix build .#wawona-macos )
  fi
  local app
  app="$(find "$ROOT/result" "$ROOT/build" -maxdepth 4 -name 'Wawona.app' 2>/dev/null | head -1 || true)"
  if [[ -z "$app" ]]; then
    warn "Wawona.app not found; run with --build first (nix build .#wawona-macos)"
    return 1
  fi
  log "launching $app"
  open "$app"
  sleep 3
  # Point the compat matrix at the running compositor's socket if exported.
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    log "running Wayland client compat matrix against XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
    "$ROOT/scripts/test-wayland-compat-matrix.sh" || warn "compat matrix had failures"
  else
    warn "XDG_RUNTIME_DIR unset; skipping compat matrix (export it to run client smoke)"
  fi
}

# ── iOS: scoped project + simulator replay (token-free) ───────────────────────
smoke_ios() {
  if ! have agent-device; then
    warn "agent-device not on PATH; cannot run iOS replay"
    return 1
  fi
  if [[ "$DO_BUILD" == "1" ]]; then
    log "generating scoped iOS Xcode project (.#xcodegen-ios) and building"
    ( cd "$ROOT" && nix run .#xcodegen-ios )
    ( cd "$ROOT" && WAWONA_SKIP_NIX_PREBUILD="${WAWONA_SKIP_NIX_PREBUILD:-0}" \
        xcodebuild -project Wawona.xcodeproj -scheme Wawona-iOS \
          -destination "platform=iOS Simulator,name=$IOS_SIM" build )
  fi
  log "agent-device doctor + prepare (warms XCTest runner)"
  agent-device doctor --platform ios || true
  agent-device prepare ios-runner --platform ios --device "$IOS_SIM" \
    --session wawona-ios-smoke --timeout 240000 || true
  if [[ "$DO_REPLAY" == "1" ]]; then
    log "iOS batch replay"
    agent-device batch --session wawona-ios-smoke --platform ios --device "$IOS_SIM" \
      --steps-file "$ROOT/.agent-device/wawona-ios-smoke-batch.json" --json
  fi
}

# ── Android: emulator/device replay (heavy. Run sparingly) ───────────────────
smoke_android() {
  if ! have agent-device; then
    warn "agent-device not on PATH; cannot run Android replay"
    return 1
  fi
  local serial="${WAWONA_ANDROID_SERIAL:-}"
  if [[ -z "$serial" ]] && have adb; then
    serial="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')"
  fi
  if [[ -z "$serial" ]]; then
    warn "no Android device/emulator; set WAWONA_ANDROID_SERIAL or boot an emulator"
    return 1
  fi
  if [[ "$DO_BUILD" == "1" ]]; then
    log "generating Android Studio project + jniLibs (.#gradlegen)"
    ( cd "$ROOT" && nix run .#gradlegen )
  fi
  if [[ "$DO_REPLAY" == "1" ]]; then
    log "Android batch replay (serial=$serial)"
    agent-device batch --session wawona-android-smoke --platform android --serial "$serial" \
      --steps-file "$ROOT/.agent-device/wawona-android-smoke-batch.json" --json
  fi
}

# ── Linux: JIT cargo run (only meaningful on a Linux host / Phase 26 VM) ───────
smoke_linux() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    warn "Linux smoke needs a Linux host (Tier 2). On this Mac use the Phase 26 VM."
    warn "On Linux: cargo run --features linux-ui --bin wawona-linux-ui"
    return 0
  fi
  log "cargo run --features linux-ui (JIT, no Nix)"
  run_cargo run --features linux-ui --bin wawona-linux-ui
}

case "$PLATFORM" in
  core) smoke_core ;;
  macos) smoke_macos ;;
  ios) smoke_ios ;;
  android) smoke_android ;;
  linux) smoke_linux ;;
  all)
    smoke_core || true
    smoke_ios || true
    smoke_android || true
    smoke_macos || true
    ;;
  *)
    echo "usage: $0 <core|macos|ios|android|linux|all> [--build] [--no-replay]" >&2
    exit 2
    ;;
esac

log "done; artifacts in $ARTIFACTS"
