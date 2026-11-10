#!/usr/bin/env bash
# Fail closed unless WAWONA_APP_PATH is a tip test build (not stale install).
# Sourced or exec'd by Appium / agent-device / smoke harnesses.
#
# Escape (lab only, never Appium catalog / UI proof): WAWONA_ALLOW_STALE_TEST_APP=1
#
# Product paths that invalidate a tip stamp (same set as ensure-tip-macos):
# Sources/, src/, Darwin/, Cargo.*, Package.swift, dependencies/, xcodegen,
# flake, VERSION.
#
# Freshness: tip_root/git-HEAD + tip_root/product-FP. Binary mtime is not enough.
# A morning tip after afternoon Sources edits is stale even if the .app exists.

# Do not force set -e on callers that source this library.
if [[ "${BASH_SOURCE[0]-}" == "${0:-}" ]]; then
  set -euo pipefail
fi

WAWONA_TIP_PRODUCT_PATHS=(
  Sources/ src/ Darwin/ Cargo.toml Cargo.lock Package.swift
  dependencies/ xcodegen.nix flake.nix flake.lock VERSION
)

wawona_refuse_stale_app_path() {
  local app="${1:-${WAWONA_APP_PATH:-}}"
  if [[ -z "$app" ]]; then
    echo "FAIL: WAWONA_APP_PATH empty" >&2
    return 2
  fi
  # String gate before existence (install may be absent and still forbidden).
  case "$app" in
    /Applications/*|*/Applications/Wawona.app|~/Applications/*|"$HOME"/Applications/*)
      echo "FAIL: refusing stale install path: $app" >&2
      echo "Build tip and set WAWONA_APP_PATH (ensure-tip-wawona-macos.sh or ensure-tip-wawona-apple-sim.sh)." >&2
      return 2
      ;;
  esac
  if [[ ! -d "$app" ]]; then
    echo "FAIL: WAWONA_APP_PATH not a directory: $app" >&2
    return 2
  fi
  local resolved
  resolved="$(cd "$app" && pwd -P)"
  case "$resolved" in
    /Applications/*|*/Applications/Wawona.app)
      echo "FAIL: refusing stale install path: $resolved" >&2
      return 2
      ;;
  esac
  # Old dogfood trees (not tip stamp dir).
  case "$resolved" in
    */build/DerivedData-macos/*|*/build/DerivedData-macos-new/*|*/Library/Developer/Xcode/DerivedData/*)
      if [[ "$resolved" != /tmp/wawona-macos-tip/* \
         && "$resolved" != /tmp/wawona-macos-a11y/* \
         && "$resolved" != /tmp/wawona-tvos-tip/* \
         && "$resolved" != /tmp/wawona-visionos-tip/* \
         && "$resolved" != /tmp/wawona-ios-tip/* \
         && "$resolved" != /tmp/wawona-watchos-tip/* ]]; then
        echo "FAIL: refusing stale DerivedData: $resolved" >&2
        return 2
      fi
      ;;
  esac
  if [[ "${WAWONA_ALLOW_STALE_TEST_APP:-0}" == "1" ]]; then
    echo "WARN: WAWONA_ALLOW_STALE_TEST_APP=1 (forbidden for Appium catalog / UI proof)" >&2
  fi
  return 0
}

# Fingerprint of product paths at HEAD + worktree (committed + dirty + staged).
# Docs-only commits change HEAD but not this fingerprint when product trees match.
wawona_tip_product_fingerprint() {
  local root="${1:-.}"
  (
    cd "$root" || exit 1
    # Index + worktree content for product paths (stable across docs-only HEAD moves).
    git ls-files -s -- "${WAWONA_TIP_PRODUCT_PATHS[@]}" 2>/dev/null || true
    echo '--'
    git diff -- "${WAWONA_TIP_PRODUCT_PATHS[@]}" 2>/dev/null || true
    echo '--'
    git diff --cached -- "${WAWONA_TIP_PRODUCT_PATHS[@]}" 2>/dev/null || true
  ) | shasum -a 256 | awk '{print $1}'
}

wawona_tip_write_stamp() {
  local tip_root="${1:?tip root}"
  local repo_root="${2:-.}"
  local head
  mkdir -p "$tip_root"
  head="$(git -C "$repo_root" rev-parse HEAD)"
  printf '%s\n' "$head" >"${tip_root}/git-HEAD"
  wawona_tip_product_fingerprint "$repo_root" >"${tip_root}/product-FP"
}

# True when tip stamps match current product tree (HEAD move docs-only OK).
wawona_tip_stamp_is_fresh() {
  local tip_root="${1:?tip root}"
  local repo_root="${2:-.}"
  local stamp="${tip_root}/git-HEAD"
  local fp_stamp="${tip_root}/product-FP"
  local head stamped fp_now fp_have product_dirty

  head="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$head" ]] || return 1
  stamped="$(cat "$stamp" 2>/dev/null || true)"
  [[ -n "$stamped" ]] || return 1
  fp_have="$(cat "$fp_stamp" 2>/dev/null || true)"
  fp_now="$(wawona_tip_product_fingerprint "$repo_root")"
  [[ -n "$fp_have" ]] || return 1
  [[ "$fp_have" == "$fp_now" ]] || return 1

  # Extra: if HEAD moved with product commits vs stamp, fingerprint already
  # differs (ls-files -s). Keep HEAD compare for clear failure modes / old tips
  # that only had git-HEAD.
  product_dirty=0
  if [[ "$stamped" != "$head" ]]; then
    if ! git -C "$repo_root" diff --quiet "$stamped" "$head" -- "${WAWONA_TIP_PRODUCT_PATHS[@]}" 2>/dev/null; then
      product_dirty=1
    fi
  fi
  [[ "$product_dirty" -eq 0 ]]
}

# Fail closed before screenshot / AX / "fixed" claims. Binary mtime is not enough.
wawona_require_tip_fresh_for_proof() {
  local tip_root="${1:?tip root}"
  local repo_root="${2:-.}"
  if [[ "${WAWONA_ALLOW_STALE_TEST_APP:-0}" == "1" ]]; then
    echo "WARN: WAWONA_ALLOW_STALE_TEST_APP=1 skips tip freshness (forbidden for UI proof)" >&2
    return 0
  fi
  if ! wawona_tip_stamp_is_fresh "$tip_root" "$repo_root"; then
    echo "FAIL: tip at $tip_root is stale vs product Sources (or missing git-HEAD / product-FP stamp)" >&2
    echo "Run ensure-tip for this platform before agent-device / simctl screenshot." >&2
    echo "Never install a morning /tmp/wawona-*-tip binary after afternoon Source edits." >&2
    return 2
  fi
  return 0
}

wawona_tip_app_macos() {
  echo "${WAWONA_TIP_APP:-/tmp/wawona-macos-tip/DerivedData/Build/Products/Debug/Wawona.app}"
}
