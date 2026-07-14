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
