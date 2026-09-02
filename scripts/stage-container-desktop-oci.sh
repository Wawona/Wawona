#!/usr/bin/env bash
# Optional: stage a local wawona-container-desktop OCI layout into an app
# bundle (or a staging dir) so Start can use --image-archive without
# ~/.local/share/wwn-oci.
#
# Usage:
#   scripts/stage-container-desktop-oci.sh [/path/to/Wawona.app]
#   scripts/stage-container-desktop-oci.sh --out /tmp/oci-stage
#
# Source layout is resolved from:
#   1) WAWONA_CONTAINER_DESKTOP_OCI (env)
#   2) ~/.local/share/wwn-oci catalog entry for wawona-container-desktop
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT=""
APP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT="${2:?}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      APP="$1"
      shift
      ;;
  esac
done

resolve_layout() {
  if [[ -n "${WAWONA_CONTAINER_DESKTOP_OCI:-}" ]]; then
    echo "$WAWONA_CONTAINER_DESKTOP_OCI"
    return
  fi
  local root="${WWN_OCI_ROOT:-$HOME/.local/share/wwn-oci}"
  local images="$root/images"
  local f ref digest hex layout
  shopt -s nullglob
  for f in "$images"/*.json; do
    ref="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("reference") or d.get("canonical") or "")' "$f" 2>/dev/null || true)"
    if [[ "$ref" != *wawona-container-desktop* ]]; then
      continue
    fi
    digest="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("manifest_digest",""))' "$f")"
    [[ "$digest" == sha256:* ]] || continue
    hex="${digest#sha256:}"
    layout="$root/oci-layout/$hex"
    if [[ -f "$layout/index.json" ]]; then
      echo "$layout"
      return
    fi
  done
  return 1
}

SRC="$(resolve_layout)" || {
  echo "FAIL: no wawona-container-desktop OCI layout found." >&2
  echo "Build/import first:" >&2
  echo "  nix build path:$ROOT/../wwn-containers#packages.aarch64-linux.wawona-container-desktop" >&2
  echo "  container import ./result --reference wawona-container-desktop:latest" >&2
  exit 1
}

if [[ -n "$OUT" ]]; then
  DEST="$OUT/wawona-container-desktop"
elif [[ -n "$APP" ]]; then
  DEST="$APP/Contents/Resources/oci/wawona-container-desktop"
else
  DEST="$ROOT/.agent-device/test-artifacts/oci/wawona-container-desktop"
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -a "$SRC" "$DEST"
echo "OK: staged $SRC → $DEST"
echo "Recipes pick this up via Resources/oci/wawona-container-desktop (bundled) or imageArchivePath."
