#!/usr/bin/env bash
# Scale agent-device .ad coordinate taps from the 1080x2424 reference frame
# used in Wawona Android recordings to the current emulator/device size.
android_scale_ad_file() {
  local src="$1" dest="$2"
  local serial="${ANDROID_SERIAL:-${WAWONA_ANDROID_SERIAL:-}}"
  local adb=(adb)
  [[ -n "$serial" ]] && adb=(adb -s "$serial")

  local dims
  dims="$("${adb[@]}" shell wm size | tr -d '\r' | awk -F': ' '/Physical size/{print $2; exit}')"
  if [[ -z "$dims" || "$dims" != *x* ]]; then
    cp "$src" "$dest"
    return 0
  fi
  local aw="${dims%x*}" ah="${dims#*x}"
  local rw=1080 rh=2424
  if [[ "$aw" == "$rw" && "$ah" == "$rh" ]]; then
    cp "$src" "$dest"
    return 0
  fi
  echo "== Android: scale .ad taps ${rw}x${rh} -> ${aw}x${ah} =="
  awk -v aw="$aw" -v ah="$ah" -v rw="$rw" -v rh="$rh" '
    $1 == "click" && NF >= 3 {
      x = int($2 * aw / rw + 0.5)
      y = int($3 * ah / rh + 0.5)
      print "click", x, y
      next
    }
    { print }
  ' "$src" >"$dest"
}

android_scale_xy() {
  local x="$1" y="$2"
  local serial="${ANDROID_SERIAL:-${WAWONA_ANDROID_SERIAL:-}}"
  local adb=(adb)
  [[ -n "$serial" ]] && adb=(adb -s "$serial")
  local dims
  dims="$("${adb[@]}" shell wm size | tr -d '\r' | awk -F': ' '/Physical size/{print $2; exit}')"
  if [[ -z "$dims" || "$dims" != *x* ]]; then
    echo "$x $y"
    return 0
  fi
  local aw="${dims%x*}" ah="${dims#*x}"
  local rw=1080 rh=2424
  echo "$(awk -v x="$x" -v y="$y" -v aw="$aw" -v ah="$ah" -v rw="$rw" -v rh="$rh" \
    'BEGIN { printf "%d %d", int(x*aw/rw+0.5), int(y*ah/rh+0.5) }')"
}

# Tap at 1080x2424 reference coords (scaled to current display).
android_tap_ref() {
  local x="$1" y="$2"
  local serial="${ANDROID_SERIAL:-${WAWONA_ANDROID_SERIAL:-}}"
  local adb=(adb)
  [[ -n "$serial" ]] && adb=(adb -s "$serial")
  local xy
  xy="$(android_scale_xy "$x" "$y")"
  # intentional word-split: "x y"
  # shellcheck disable=SC2086
  "${adb[@]}" shell input tap $xy
}

# Compose often hides text from agent-device a11y filters; uiautomator TextView
# bounds remain reliable for Continue / Start on the welcome + machines screens.
android_uia_tap_node() {
  # $1 = grep -E pattern matched against one flattened node line
  local pattern="$1"
  local label="${2:-node}"
  local serial="${ANDROID_SERIAL:-${WAWONA_ANDROID_SERIAL:-}}"
  local adb=(adb)
  [[ -n "$serial" ]] && adb=(adb -s "$serial")
  local xml line x1 y1 x2 y2 cx cy
  xml="$(android_uia_dump)" || return 1
  line="$(printf '%s' "$xml" | tr '>' '\n' | grep -E "$pattern" | head -1)"
  [[ -n "$line" ]] || return 1
  read -r x1 y1 x2 y2 <<<"$(printf '%s' "$line" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')"
  [[ -n "${x1:-}" && -n "${y1:-}" && -n "${x2:-}" && -n "${y2:-}" ]] || return 1
  cx=$(( (x1 + x2) / 2 ))
  cy=$(( (y1 + y2) / 2 ))
  # Reject zero-size / offscreen nodes.
  if (( cx <= 0 || cy <= 0 || x2 <= x1 || y2 <= y1 )); then
    return 1
  fi
  echo "== Android: uia tap ${label} at ${cx},${cy} bounds=[${x1},${y1}][${x2},${y2}] =="
  "${adb[@]}" shell input tap "$cx" "$cy"
}

android_uia_tap_text() {
  local want="$1"
  android_uia_tap_node "text=\"${want}\"" "text=${want}"
}

android_uia_tap_id() {
  local want="$1"
  android_uia_tap_node "resource-id=\"[^\"]*${want}\"" "id=${want}"
}

android_uia_dump() {
  local serial="${ANDROID_SERIAL:-${WAWONA_ANDROID_SERIAL:-}}"
  local adb=(adb)
  [[ -n "$serial" ]] && adb=(adb -s "$serial")
  local out path
  # Prefer exec-out dump (avoids /sdcard permission issues on some API 34 images).
  out="$("${adb[@]}" exec-out uiautomator dump /dev/tty 2>/dev/null | tr -d '\r')" || true
  if printf '%s' "$out" | grep -q '<hierarchy'; then
    printf '%s' "$out"
    return 0
  fi
  "${adb[@]}" shell uiautomator dump /sdcard/wawona-ui.xml >/dev/null 2>&1 \
    || "${adb[@]}" shell uiautomator dump >/dev/null 2>&1 \
    || return 1
  for path in /sdcard/wawona-ui.xml /sdcard/window_dump.xml; do
    out="$("${adb[@]}" exec-out cat "$path" 2>/dev/null | tr -d '\r')" || true
    if printf '%s' "$out" | grep -q '<hierarchy'; then
      printf '%s' "$out"
      return 0
    fi
  done
  return 1
}

android_uia_has_text() {
  local want="$1"
  local xml
  xml="$(android_uia_dump)" || return 1
  printf '%s' "$xml" | grep -Fq "text=\"$want\""
}

# Compose testTagsAsResourceId → resource-id containing the wwn.* tag.
android_uia_has_id() {
  local want="$1"
  local xml
  xml="$(android_uia_dump)" || return 1
  printf '%s' "$xml" | grep -Eiq "resource-id=\"[^\"]*${want}\""
}

# Poll UiAutomator until text or resource-id appears (agent-device waits can miss Compose).
android_uia_wait() {
  local kind="$1" # text | id
  local want="$2"
  local timeout_ms="${3:-20000}"
  local elapsed=0
  local step=1000
  while (( elapsed < timeout_ms )); do
    if [[ "$kind" == "id" ]]; then
      android_uia_has_id "$want" && return 0
    else
      android_uia_has_text "$want" && return 0
    fi
    sleep "$(awk -v s="$step" 'BEGIN { printf "%.3f", s/1000 }')"
    elapsed=$((elapsed + step))
  done
  return 1
}

# Alt+D for nested niri Mod+D. keycombination exists on API 34+ images only.
android_inject_alt_d() {
  local serial="${ANDROID_SERIAL:-${WAWONA_ANDROID_SERIAL:-}}"
  local adb=(adb)
  [[ -n "$serial" ]] && adb=(adb -s "$serial")
  if "${adb[@]}" shell input keycombination 57 32 >/dev/null 2>&1; then
    return 0
  fi
  echo "WARN: input keycombination unavailable; trying sendevent Alt+D fallback" >&2
  # Generic virtual keyboard path used by many x86_64 Google APIs images.
  local dev
  dev="$("${adb[@]}" shell 'getevent -pl 2>/dev/null | awk "/add device/ {d=\$NF} /name:.*Virtual/ {print d; exit}"' | tr -d '\r')"
  if [[ -z "$dev" ]]; then
    echo "WARN: no virtual input device for sendevent; Alt+D inject skipped" >&2
    return 1
  fi
  # KEY_LEFTALT=56, KEY_D=32 (linux input codes; differ from Android keycodes).
  "${adb[@]}" shell "sendevent $dev 1 56 1; sendevent $dev 1 32 1; sendevent $dev 0 0 0; sendevent $dev 1 32 0; sendevent $dev 1 56 0; sendevent $dev 0 0 0"
}
