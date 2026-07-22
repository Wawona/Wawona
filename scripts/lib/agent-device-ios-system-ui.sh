# iOS system-UI helpers for agent-device sessions.
#
# Allow Paste (SpringBoard / CoreSimulatorBridge) cannot be exercised under
# XCUITest — dismiss it with host Simulator CGEvent + screenshot locate.
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

  local screen_xy rc=0
  screen_xy="$(/usr/bin/swift - "$shot" "$bounds" <<'SWIFT'
import Foundation
import AppKit
let shotPath = CommandLine.arguments[1]
let boundsArg = CommandLine.arguments[2]
guard let img = NSImage(contentsOfFile: shotPath),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else { exit(1) }
let w = rep.pixelsWide, h = rep.pixelsHigh
struct P { var x: Int; var y: Int }
var blues: [P] = [], grays: [P] = []
// Centered alert only — exclude Machines Start/FAB (right/lower chrome).
let y0 = h * 38 / 100, y1 = h * 62 / 100
let x0 = w * 22 / 100, x1 = w * 78 / 100
for y in stride(from: y0, through: y1, by: 3) {
  for x in stride(from: x0, through: x1, by: 3) {
    guard let c = rep.colorAt(x: x, y: y) else { continue }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    if b > 0.70 && r < 0.40 && g > 0.35 && g < 0.70 && b > g {
      blues.append(P(x: x, y: y))
    }
    let maxc = max(r, g, b), minc = min(r, g, b)
    if maxc > 0.75 && minc > 0.65 && (maxc - minc) < 0.12 {
      grays.append(P(x: x, y: y))
    }
  }
}
func center(_ ps: [P]) -> (Int, Int)? {
  guard !ps.isEmpty else { return nil }
  return (ps.map(\.x).reduce(0, +) / ps.count, ps.map(\.y).reduce(0, +) / ps.count)
}
// No blue Don't Allow in the alert band → nothing to dismiss.
guard let blue = center(blues) else { exit(0) }
let below = grays.filter {
  $0.y > blue.1 + 40 &&
    $0.y < blue.1 + h * 12 / 100 &&
    abs($0.x - blue.0) < w / 6
}
// Empirically ~11% of framebuffer height below Don't Allow center
// (Allow Paste row under the blue button on iPhone 17 Pro @3x).
let allow = center(below) ?? (blue.0, blue.1 + Int(Double(h) * 0.11))
let parts = boundsArg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
guard parts.count == 4 else { exit(3) }
let wx = parts[0], wy = parts[1], ww = parts[2], wh = parts[3]
let sx = wx + Double(allow.0) * ww / Double(w)
let sy = wy + Double(allow.1) * wh / Double(h)
print("\(sx) \(sy)")
SWIFT
)" || rc=$?
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
