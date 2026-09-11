#!/usr/bin/env bash
# Regenerate SettingsDependencies.json snapshots from settings-deps.nix.
# Do not hand-edit the JSON files. Run from Wawona repo root:
#   ./scripts/regen-settings-deps.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NIX_FILE="$ROOT/dependencies/wawona/settings-deps.nix"

if [[ ! -f "$NIX_FILE" ]]; then
  echo "error: missing $NIX_FILE" >&2
  exit 1
fi

ILAND_VERSION_FILE="$(cd "$ROOT/.." && pwd)/wwn-iland/VERSION"
if [[ -f "$ILAND_VERSION_FILE" ]]; then
  echo "iland VERSION (sibling): $(tr -d '[:space:]' <"$ILAND_VERSION_FILE")"
else
  echo "warning: sibling wwn-iland/VERSION not found; using settings-deps fallback" >&2
fi

write_json() {
  local target="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  nix-instantiate --eval --strict --json \
    -E "let d = import $NIX_FILE; in d.inventories.${target} d.versions" \
    | python3 -c 'import json,sys; print(json.dumps({"packages": json.load(sys.stdin)}, indent=2)); print()' \
    >"$out"
  echo "wrote $out"
}

write_json ios "$ROOT/src/resources/settings-deps/ios/SettingsDependencies.json"
write_json ipados "$ROOT/src/resources/settings-deps/ipados/SettingsDependencies.json"
write_json macos "$ROOT/src/resources/settings-deps/macos/SettingsDependencies.json"
write_json tvos "$ROOT/src/resources/settings-deps/tvos/SettingsDependencies.json"
write_json watchos "$ROOT/src/resources/settings-deps/watchos/SettingsDependencies.json"
write_json visionos "$ROOT/src/resources/settings-deps/visionos/SettingsDependencies.json"
write_json android "$ROOT/android/app/src/main/assets/SettingsDependencies.json"
write_json linux "$ROOT/src/linux/ui/settings_dependencies.json"

echo "regen-settings-deps: ok"
