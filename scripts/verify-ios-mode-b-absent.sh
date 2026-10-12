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

PATTERNS='IOMobileFramebuffer|WWN_MODE_B|WWNIomfb|ellekit|TrollStore|repo\.wawona\.io/jailbreak|dynamic-codesigning|MAP_JIT'

if [[ "$ARCHIVE" == *.tipa ]]; then
  if ! grep -R -E -q "$PATTERNS" "$ROOT" 2>/dev/null; then
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
echo "OK: no Mode B markers in $ARCHIVE"
