# iOS system-UI helpers for agent-device sessions.
#
# Allow Paste (SpringBoard / CoreSimulatorBridge) cannot be exercised under
# XCUITest. Dismiss it with host Simulator CGEvent + screenshot locate.
#
# Keyboard input and the swipe-typing tutorial Continue use normal agent-device
# commands (`type` / `fill` / `press label="Continue"`). Do not host-tap the
# keyboard.
#
# Usage:
#   source "$ROOT/scripts/lib/agent-device-ios-system-ui.sh"
#   ios_prepare_system_ui
#   ios_dismiss_system_ui "${ad_common[@]}"   # Allow Paste + optional Continue
#   agent-device type "hello" "${ad_common[@]}"
#
# Env:
#   WAWONA_IOS_UDID   optional sim UDID (else resolve from --device / booted)
#   WAWONA_IOS_SIM    simulator name (default: iPhone 17 Pro)

ios_resolve_udid() {
  if [[ -n "${WAWONA_IOS_UDID:-}" ]]; then
    printf '%s\n' "$WAWONA_IOS_UDID"
    return 0
  fi
  local name="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
  local udid
  udid="$(xcrun simctl list devices booted 2>/dev/null \
    | grep -F "$name" | head -1 \
    | sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)).*/\1/p')"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl list devices available 2>/dev/null \
      | grep -F "$name" | head -1 \
      | sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)).*/\1/p')"
  fi
  printf '%s\n' "$udid"
}

ios_sim_window_bounds() {
  /usr/bin/osascript <<'EOF' 2>/dev/null
tell application "Simulator" to activate
delay 0.12
tell application "System Events"
  tell process "Simulator"
    set frontmost to true
    set {wx, wy} to position of window 1
    set {ww, wh} to size of window 1
    return (wx as text) & "," & (wy as text) & "," & (ww as text) & "," & (wh as text)
  end tell
end tell
EOF
}

# Host CGEvent clicks at absolute screen coordinates (may need Accessibility).
ios_host_click_screen() {
  local sx="${1:?}" sy="${2:?}"
  /usr/bin/swift -e "
import Foundation
import CoreGraphics
let sx: Double = $sx
let sy: Double = $sy
let src = CGEventSource(stateID: .hidSystemState)
let pt = CGPoint(x: sx, y: sy)
for _ in 0..<2 {
  CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.04)
  CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.06)
  CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.15)
}
print(\"host_click \\(sx),\\(sy)\")
" 2>/dev/null
}

# Call before open/relaunch. Safe to re-run.
ios_prepare_system_ui() {
  local udid
  udid="$(ios_resolve_udid)"

  # Stop Mac clipboard → sim sync (source of Allow Paste from CoreSimulatorBridge).
  defaults write com.apple.iphonesimulator PasteboardAutomaticSync -bool false 2>/dev/null || true

  if [[ -n "$udid" ]]; then
    printf '' | xcrun simctl pbcopy "$udid" 2>/dev/null || true
    # Prefs reduce first-run swipe-typing tutorial; if it still appears, press Continue
    # via agent-device (not host taps).
    xcrun simctl spawn "$udid" defaults write com.apple.keyboard kbUserDidPath -bool YES 2>/dev/null || true
    xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences \
      DidShowContinuousPathIntroduction -bool YES 2>/dev/null || true
    xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences \
      DidShowGestureKeyboardIntroduction -bool YES 2>/dev/null || true
    xcrun simctl spawn "$udid" defaults write com.apple.KeyboardServices \
      DidShowContinuousPathIntroduction -bool YES 2>/dev/null || true
  fi
}

# Screenshot → locate Allow Paste (under blue Don't Allow) → host click.
# No-op (return 0) when the alert is not visible.
ios_host_dismiss_allow_paste() {
  local udid bounds shot
  udid="$(ios_resolve_udid)"
  [[ -n "$udid" ]] || return 1
  bounds="$(ios_sim_window_bounds)"
  [[ -n "$bounds" ]] || return 1

  shot="$(mktemp -t wawona_allow_paste_XXXXXX).png"
  xcrun simctl io "$udid" screenshot "$shot" >/dev/null 2>&1 || {
    rm -f "$shot"
    return 1
  }

  # Locator lives in a .swift file. macOS /bin/bash 3.2 still tokenizes
  # apostrophes inside $(... <<'HEREDOC'), which broke sourcing this helper.
  local helper_dir locator screen_xy rc=0
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  elif [[ -n "${ROOT:-}" && -d "$ROOT/scripts/lib" ]]; then
    helper_dir="$ROOT/scripts/lib"
  else
    helper_dir="$(cd "$(dirname "$0")" && pwd)"
  fi
  locator="$helper_dir/locate-allow-paste.swift"
  screen_xy="$(/usr/bin/swift "$locator" "$shot" "$bounds")" || rc=$?
  rm -f "$shot"
  if [[ $rc -ne 0 ]]; then
    return "$rc"
  fi
  # Empty stdout = no alert present.
  [[ -n "$screen_xy" ]] || return 0

  local sx sy
  sx="$(echo "$screen_xy" | awk '{print $1}')"
  sy="$(echo "$screen_xy" | awk '{print $2}')"
  [[ -n "$sx" && -n "$sy" ]] || return 0
  ios_host_click_screen "$sx" "$sy"
}

# Dismiss Allow Paste (host) + keyboard tutorial Continue (agent-device).
# Typing afterward: agent-device type / fill as usual.
ios_dismiss_system_ui() {
  local -a ad=("$@")

  ios_host_dismiss_allow_paste || true
  sleep 0.35

  if ((${#ad[@]})); then
    agent-device press 'label="Continue"' "${ad[@]}" >/dev/null 2>&1 || true
    agent-device press 'text="Continue"' "${ad[@]}" >/dev/null 2>&1 || true
    agent-device find Continue press --first "${ad[@]}" >/dev/null 2>&1 || true
  fi
}
