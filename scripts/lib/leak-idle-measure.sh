# Footprint / meminfo sampling for leak-idle CI gates.
#
# Apple: phys_footprint via `xcrun simctl spawn … vmmap --summary` or host `vmmap`.
# Android: TOTAL PSS from `dumpsys meminfo`.
#
# Pass rule (Start→hold): samples must stay on a plateau — (max−min) ≤ WAWONA_LEAK_PLATEAU_MB
# and no strictly monotonic climb of ≥ WAWONA_LEAK_MONO_MB across consecutive samples.
#
# Usage:
#   source scripts/lib/leak-idle-measure.sh
#   leak_sample_apple_mb <pid> [sim_udid]
#   leak_sample_android_pss_mb <serial> <package>
#   leak_analyze_plateau <samples_mb_csv> <out_json>

: "${WAWONA_LEAK_PLATEAU_MB:=20}"
: "${WAWONA_LEAK_MONO_MB:=8}"
: "${WAWONA_LEAK_HOLD_SEC:=60}"
: "${WAWONA_LEAK_SAMPLE_SEC:=15}"
export WAWONA_LEAK_PLATEAU_MB WAWONA_LEAK_MONO_MB WAWONA_LEAK_HOLD_SEC WAWONA_LEAK_SAMPLE_SEC

leak_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Parse phys_footprint from vmmap --summary output (KB or MB). Echo MB as float.
leak_parse_phys_footprint_mb() {
  local text="$1"
  local line val unit
  line="$(printf '%s\n' "$text" | grep -i 'PhysFootprint\|Physical footprint' | head -1 || true)"
  if [[ -z "$line" ]]; then
    line="$(printf '%s\n' "$text" | grep -i 'phys_footprint' | head -1 || true)"
  fi
  [[ -n "$line" ]] || return 1
  # e.g. "Physical footprint:  71.8M" or "PhysFootprint: 73400K"
  val="$(printf '%s\n' "$line" | sed -E 's/.*[: ]([0-9]+([.][0-9]+)?)[ ]*([KkMmGg]).*/\1/' )"
  unit="$(printf '%s\n' "$line" | sed -E 's/.*[: ]([0-9]+([.][0-9]+)?)[ ]*([KkMmGg]).*/\3/' )"
  [[ -n "$val" && -n "$unit" ]] || return 1
  case "$unit" in
    K|k) awk -v v="$val" 'BEGIN { printf "%.3f", v/1024 }' ;;
    M|m) awk -v v="$val" 'BEGIN { printf "%.3f", v }' ;;
    G|g) awk -v v="$val" 'BEGIN { printf "%.3f", v*1024 }' ;;
    *) return 1 ;;
  esac
}

# Sample Apple process footprint in MB. Optional sim UDID uses simctl spawn.
leak_sample_apple_mb() {
  local pid="$1"
  local udid="${2:-}"
  local out
  if [[ -n "$udid" ]]; then
    out="$(xcrun simctl spawn "$udid" vmmap --summary "$pid" 2>/dev/null || true)"
  else
    out="$(vmmap --summary "$pid" 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]]; then
    # Fallback: memorystatus / footprint via simctl (iOS) — try host vmmap anyway
    out="$(vmmap --summary "$pid" 2>/dev/null || true)"
  fi
  leak_parse_phys_footprint_mb "$out"
}

# Android TOTAL PSS in MB for a package.
leak_sample_android_pss_mb() {
  local serial="$1"
  local pkg="$2"
  local out kb
  out="$(adb -s "$serial" shell dumpsys meminfo "$pkg" 2>/dev/null || true)"
  # App Summary line looks like:
  #   TOTAL PSS:    90464            TOTAL RSS:   191800       TOTAL SWAP PSS:      174
  # Do NOT take the last integer on the line (that is SWAP PSS).
  kb="$(printf '%s\n' "$out" | awk '
    /TOTAL PSS:/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "PSS:" && (i+1) <= NF && $(i+1) ~ /^[0-9]+$/) { print $(i+1); exit }
      }
    }
  ' || true)"
  if [[ -z "$kb" || ! "$kb" =~ ^[0-9]+$ ]]; then
    # Fallback: table TOTAL row "TOTAL    <pss> ..."
    kb="$(printf '%s\n' "$out" | awk '/^[[:space:]]*TOTAL[[:space:]]+[0-9]+/{print $2; exit}' || true)"
  fi
  [[ -n "$kb" && "$kb" =~ ^[0-9]+$ ]] || return 1
  awk -v v="$kb" 'BEGIN { printf "%.3f", v/1024 }'
}

# Resolve PID of bundle on simulator (com.aspauldingcode.Wawona).
leak_ios_pid() {
  local udid="$1"
  local bundle="${2:-com.aspauldingcode.Wawona}"
  local pid
  # iOS app launchd labels are "UIKitApplication:<bundle>[0x..][rb-legacy]", not
  # a bare "<bundle>" — an exact `$3==bundle` never matches, so match the bundle
  # id as a substring of the label column. (This step was previously unreached:
  # iOS failed earlier at machines_home_not_reached before pid resolution.)
  pid="$(xcrun simctl spawn "$udid" launchctl list 2>/dev/null \
    | awk -v b="$bundle" 'index($3, b) > 0 { print $1; exit }')"
  if [[ -n "$pid" && "$pid" != "-" && "$pid" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$pid"
    return 0
  fi
  # Fallback: host process for this sim's app binary (the simulator runs the app
  # as a host process; its path contains the sim UDID + Wawona.app/Wawona but not
  # the bundle id, so match on the executable path, then a looser Wawona.app).
  pid="$(pgrep -f "Devices/$udid/data/Containers/Bundle/.*/Wawona\.app/Wawona" 2>/dev/null | head -1 || true)"
  [[ -z "$pid" ]] && pid="$(pgrep -f "Wawona\.app/Wawona" 2>/dev/null | head -1 || true)"
  [[ -z "$pid" ]] && pid="$(pgrep -f "$bundle" 2>/dev/null | head -1 || true)"
  [[ -n "$pid" ]] && printf '%s\n' "$pid"
}

leak_macos_pid() {
  local bundle_id="${1:-com.aspauldingcode.Wawona}"
  # Prefer exact bundle via osascript / pgrep app name
  local pid
  pid="$(pgrep -x Wawona 2>/dev/null | head -1 || true)"
  if [[ -z "$pid" ]]; then
    pid="$(pgrep -f "$bundle_id" 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$pid" ]] && printf '%s\n' "$pid"
}

# Analyze comma-separated MB samples. Writes JSON to $2; exit 0=pass 1=fail.
leak_analyze_plateau() {
  local csv="$1"
  local out_json="$2"
  local plateau_mb="${WAWONA_LEAK_PLATEAU_MB}"
  local mono_mb="${WAWONA_LEAK_MONO_MB}"

  python3 - "$csv" "$out_json" "$plateau_mb" "$mono_mb" <<'PY'
import json, sys
csv, out_path, plateau_s, mono_s = sys.argv[1:5]
plateau = float(plateau_s)
mono = float(mono_s)
parts = [p.strip() for p in csv.split(",") if p.strip()]
try:
    samples = [float(p) for p in parts]
except ValueError:
    samples = []
status = "fail"
reason = "no_samples"
spread = None
mono_climb = None
if samples:
    mn, mx = min(samples), max(samples)
    spread = mx - mn
    mono_climb = 0.0
    for a, b in zip(samples, samples[1:]):
        if b > a:
            mono_climb = max(mono_climb, b - a)
        else:
            # reset consecutive climb tracker for strict mono across whole series
            pass
    # Strict monotonic climb from first to last with each step increasing
    strict = all(samples[i] < samples[i + 1] for i in range(len(samples) - 1))
    total_climb = samples[-1] - samples[0] if len(samples) >= 2 else 0.0
    if spread > plateau:
        status, reason = "fail", f"plateau_spread_mb={spread:.2f}>{plateau}"
    elif strict and total_climb >= mono:
        status, reason = "fail", f"monotonic_climb_mb={total_climb:.2f}>={mono}"
    else:
        status, reason = "pass", f"plateau_spread_mb={spread:.2f}<={plateau}"
payload = {
    "status": status,
    "reason": reason,
    "samples_mb": samples,
    "spread_mb": spread,
    "plateau_limit_mb": plateau,
    "mono_limit_mb": mono,
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
sys.exit(0 if status == "pass" else 1)
PY
}

# Sample loop: call sample_fn → append MB; write timeline TSV.
# Args: out_dir label sample_cmd... (command that prints one MB float)
leak_hold_sample_loop() {
  local out_dir="$1"
  local label="$2"
  shift 2
  local hold="${WAWONA_LEAK_HOLD_SEC}"
  local every="${WAWONA_LEAK_SAMPLE_SEC}"
  local timeline="$out_dir/${label}-timeline.txt"
  local csv=""
  local t=0
  local mb
  mkdir -p "$out_dir"
  {
    echo "# target=$label hold_sec=$hold sample_sec=$every plateau_mb=$WAWONA_LEAK_PLATEAU_MB"
    echo "# t_sec mb iso"
  } >"$timeline"
  while (( t <= hold )); do
    if ! mb="$("$@" 2>/dev/null)"; then
      echo "FAIL: sample command failed at t=${t}s ($label)" >&2
      return 1
    fi
    if [[ -z "$mb" ]]; then
      echo "FAIL: empty sample at t=${t}s ($label)" >&2
      return 1
    fi
    echo "$t $mb $(leak_now_iso)" >>"$timeline"
    if [[ -z "$csv" ]]; then
      csv="$mb"
    else
      csv="$csv,$mb"
    fi
    if (( t >= hold )); then
      break
    fi
    sleep "$every"
    t=$((t + every))
  done
  printf '%s\n' "$csv" >"$out_dir/${label}-samples.csv"
  leak_analyze_plateau "$csv" "$out_dir/${label}-plateau.json"
}
