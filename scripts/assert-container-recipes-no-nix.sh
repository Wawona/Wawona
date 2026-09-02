#!/usr/bin/env bash
# Assert CLI container recipes never shell nix / cargo at Start.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECIPES="$ROOT/src/platform/macos/ui/Machines/WWNCLIMachineRecipes.m"

if [[ ! -f "$RECIPES" ]]; then
  echo "FAIL: missing $RECIPES" >&2
  exit 1
fi

# Match real Start-path invocations, not prose that says "no nix shell".
if rg -n \
  -e 'WWNCLINixShellPrefix' \
  -e 'nix --extra-experimental-features' \
  -e 'nix shell -f' \
  -e 'nix shell nixpkgs' \
  -e 'nixos/nix' \
  -e 'nix build ' \
  -e 'cargo (build|run|install) ' \
  "$RECIPES"; then
  echo "FAIL: container recipes still invoke nix/cargo at Start" >&2
  exit 1
fi

if ! rg -q 'wawona-container-desktop' "$RECIPES"; then
  echo "FAIL: expected wawona-container-desktop image ref" >&2
  exit 1
fi

# Required default desktop recipes must exist and not be nix-based.
for recipe in flower sway weston-container labwc hyprland; do
  if ! rg -q "recipe isEqualToString:@\"$recipe\"" "$RECIPES"; then
    echo "FAIL: missing container recipe '$recipe'" >&2
    exit 1
  fi
done

if ! rg -q 'Hyprland' "$RECIPES"; then
  echo "FAIL: hyprland recipe must exec Hyprland (prebaked)" >&2
  exit 1
fi

echo "OK: container recipes use prebaked image (no nix shell)"
echo "OK: flower/sway/weston-container/labwc/hyprland present"
