#!/usr/bin/env bash
# Fail store-shaped IPA/AAB archives that contain Mode B / jailbreak markers.
# Mode B .tipa jobs use the inverse check (must contain JIT/FB markers).
set -euo pipefail

ARCHIVE="${1:?usage: $0 path/to/Wawona.ipa|.aab|.app}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

case "$ARCHIVE" in
  *.ipa|*.tipa)
    unzip -q "$ARCHIVE" -d "$TMP"
    ROOT="$TMP/Payload"
    ;;
  *.app)
    ROOT="$ARCHIVE"
    ;;
  *.aab|*.apk)
    unzip -q "$ARCHIVE" -d "$TMP"
    ROOT="$TMP"
    ;;
  *)
    echo "unsupported archive: $ARCHIVE" >&2
    exit 2
    ;;
esac

# Mode B / jailbreak markers. Bare MAP_JIT is handled separately: Darwin
# mmap flag name tables embed adjacent MAP_NOCACHEMAP_JIT bytes.
PATTERNS='IOMobileFramebuffer|WWN_MODE_B|WWNIomfb|ellekit|TrollStore|repo\.wawona\.io/jailbreak|dynamic-codesigning'

if [[ "$ARCHIVE" == *.tipa ]]; then
  if ! grep -R -E -q "$PATTERNS|MAP_JIT" "$ROOT" 2>/dev/null; then
    echo "FAIL: Mode B .tipa missing expected Mode B markers" >&2
    exit 1
  fi
  echo "OK: Mode B markers present in $ARCHIVE"
  exit 0
fi

if grep -R -E -q "$PATTERNS" "$ROOT" 2>/dev/null; then
  echo "FAIL: store archive contains Mode B / jailbreak markers:" >&2
  grep -R -E -n "$PATTERNS" "$ROOT" 2>/dev/null | head -40 >&2
  exit 1
fi

# Reject MAP_JIT only when an occurrence is *not* inside the Darwin flag table
# run (...MAP_NOCACHE MAP_JIT PROT_...).
map_jit_non_table_hit() {
  local f="$1"
  local pos start chunk
  while IFS=: read -r pos _; do
    [[ -n "${pos:-}" ]] || continue
    start=$((pos > 12 ? pos - 12 : 0))
    chunk=$(LC_ALL=C dd if="$f" bs=1 skip="$start" count=24 2>/dev/null || true)
    if ! printf '%s' "$chunk" | grep -q 'MAP_NOCACHEMAP_JIT'; then
      echo "$f:$pos"
      return 0
    fi
  done < <(LC_ALL=C grep -aobF 'MAP_JIT' "$f" 2>/dev/null || true)
  return 1
}

bad=0
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if hit=$(map_jit_non_table_hit "$f"); then
    echo "FAIL: MAP_JIT marker (not Darwin mmap flag table): $hit" >&2
    bad=1
  fi
done < <(grep -R -a -l -F 'MAP_JIT' "$ROOT" 2>/dev/null || true)

if [[ "$bad" -ne 0 ]]; then
  exit 1
fi
echo "OK: no Mode B markers in $ARCHIVE"
