#!/usr/bin/env bash
# Fail if a Watch app bundle exceeds the App Store thin-binary gate (ITMS-90389).
# Relay wasm / wpm stay required; size must fit with wasm linked (no unlink wasm).
set -euo pipefail

LIMIT_BYTES="${WAWONA_WATCHOS_SIZE_LIMIT_BYTES:-$((75 * 1024 * 1024))}"
APP=""

usage() {
  echo "usage: $0 [--limit-mb N] <WawonaWatch.app|Wawona.app>" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit-mb)
      LIMIT_BYTES=$(( ${2:?} * 1024 * 1024 ))
      shift 2
      ;;
    -h|--help) usage ;;
    *)
      APP="$1"
      shift
      ;;
  esac
done

[[ -n "$APP" && -d "$APP" ]] || usage

# Prefer the companion Watch app when embedded in an iOS host.
WATCH_APP="$APP"
if [[ -d "$APP/Watch" ]]; then
  cand="$(find "$APP/Watch" -maxdepth 1 -type d -name '*.app' -print -quit || true)"
  [[ -n "$cand" ]] && WATCH_APP="$cand"
fi

EXE=""
for cand in "$WATCH_APP/WawonaWatch" "$WATCH_APP/Wawona" "$WATCH_APP/$(basename "$WATCH_APP" .app)"; do
  if [[ -f "$cand" ]]; then
    EXE="$cand"
    break
  fi
done
[[ -n "$EXE" ]] || { echo "FAIL: no Watch executable under $WATCH_APP" >&2; exit 1; }

# Prove Relay wasm stayed linked (do not size-gate by dropping wasm).
if ! /usr/bin/nm -gU "$EXE" 2>/dev/null | /usr/bin/grep -q 'wawona_wasm_run'; then
  if ! /usr/bin/strings "$EXE" | /usr/bin/grep -q 'wawona_wasm'; then
    echo "FAIL: Watch executable missing wawona_wasm (Relay wasm required)" >&2
    exit 1
  fi
fi

SIZE="$(/usr/bin/stat -f%z "$EXE" 2>/dev/null || /usr/bin/stat -c%s "$EXE")"
LIMIT_MB=$(( LIMIT_BYTES / 1024 / 1024 ))
SIZE_MB=$(awk -v s="$SIZE" 'BEGIN { printf "%.2f", s/1024/1024 }')

if (( SIZE > LIMIT_BYTES )); then
  echo "FAIL: Watch executable ${SIZE_MB} MB > ${LIMIT_MB} MB limit ($EXE)" >&2
  exit 1
fi

echo "OK: Watch executable ${SIZE_MB} MB <= ${LIMIT_MB} MB (wasm present) ($EXE)"
