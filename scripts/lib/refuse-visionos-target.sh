#!/usr/bin/env bash
# Fail closed when a visionOS / xros destination is selected for non-visionOS
# work (Terminal, macOS tip, iOS smoke). agent-device lists "Apple Vision Pro"
# as the first `ios simulator`, so an unpinned --platform ios picks it.
#
# Usage: source this file, then call `wawona_refuse_visionos_target [extra...]`.
# Extra args are checked too (device names, -destination strings).
# Escape: WAWONA_TARGET_VISIONOS=1 (only when the task is visionOS).

wawona_refuse_visionos_target() {
  [[ "${WAWONA_TARGET_VISIONOS:-0}" == "1" ]] && return 0
  local root="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  local candidates=(
    "${AGENT_DEVICE_PLATFORM:-}"
    "${AGENT_DEVICE_DEVICE:-}"
    "${WAWONA_IOS_SIM:-}"
    "${WAWONA_IOS_DEVICE:-}"
    "${WAWONA_XCODE_DESTINATION:-}"
    "${DESTINATION:-}"
    "$@"
  )
  local f
  for f in "$root/agent-device.json" "$root/.xcodebuildmcp/config.yaml"; do
    [[ -f "$f" ]] && candidates+=("$(cat "$f")")
  done
  local c
  for c in "${candidates[@]}"; do
    [[ -z "$c" ]] && continue
    if printf '%s' "$c" | grep -Eqi 'vision ?pro|visionos|xros|xrsimulator'; then
      echo "FAIL: visionOS target selected ($c). Terminal and macOS work never" >&2
      echo "      target Vision Pro. Set WAWONA_TARGET_VISIONOS=1 only for visionOS tasks." >&2
      return 3
    fi
  done
  return 0
}
