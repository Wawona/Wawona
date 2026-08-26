#!/usr/bin/env bash
# macOS container machine smoke: agent-device drives Machines UI to create a
# nixos/nix container profile with desktop session, then starts it.
#
# macOS AX snapshots expose human labels (not wwn.* ids). This script uses
# snapshot refs (@eN) and stable labels from WWNMachineEditorView.
#
# Usage:
#   scripts/agent-device-container-smoke-macos.sh
#
# Env:
#   WAWONA_CONTAINER_IMAGE    OCI ref (default: nixos/nix)
#   WAWONA_CONTAINER_COMMAND  guest command (default: nix weston-flower)
#   WAWONA_CONTAINER_MACHINE_NAME  profile name
#   WAWONA_CONTAINER_SESSION  agent-device session name
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/.agent-device/test-artifacts"
IMAGE="${WAWONA_CONTAINER_IMAGE:-nixos/nix}"
COMMAND="${WAWONA_CONTAINER_COMMAND:-nix --extra-experimental-features nix-command run nixpkgs#weston -- weston-flower}"
MACHINE_NAME="${WAWONA_CONTAINER_MACHINE_NAME:-Nix Weston Container}"
SESS="${WAWONA_CONTAINER_SESSION:-wawona-macos-container}"

mkdir -p "$ARTIFACTS"

log() { echo "[container-smoke-macos] $*"; }

command -v agent-device >/dev/null || { echo "agent-device not on PATH" >&2; exit 1; }

ad=(--platform macos --session "$SESS")

pkill -f "agent-device/dist/src/internal/daemon.js" 2>/dev/null || true
sleep 1

log "open Wawona"
agent-device open Wawona "${ad[@]}"

log "Add Machine"
agent-device snapshot -i "${ad[@]}" | tee "$ARTIFACTS/macos-container-machines.txt"
ADD_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'button.*Add Machine' | tail -1 | awk '{print $1}')"
[[ -n "$ADD_REF" ]] || { log "FAIL: Add Machine button not found"; exit 1; }
agent-device press "$ADD_REF" "${ad[@]}"

sleep 2
agent-device snapshot -i "${ad[@]}" | tee "$ARTIFACTS/macos-container-editor-open.txt"

NAME_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'text-field.*Display Name' | awk '{print $1}' | head -1)"
TYPE_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'Machine Type' | awk '{print $1}' | head -1)"
agent-device fill "$NAME_REF" "$MACHINE_NAME" "${ad[@]}"

agent-device press "$TYPE_REF" "${ad[@]}"
sleep 0.5
CONTAINER_MENU="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'menu-item' | tail -1 | awk '{print $1}')"
agent-device press "$CONTAINER_MENU" "${ad[@]}"

for _ in 1 2 3 4 5; do agent-device scroll down "${ad[@]}"; done
agent-device snapshot -i "${ad[@]}" | tee "$ARTIFACTS/macos-container-editor-scrolled.txt"

IMG_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'text-field.*Container Image' | awk '{print $1}' | head -1)"
CMD_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'text-field.*Container Command' | awk '{print $1}' | head -1)"
DESK_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'checkbox.*Desktop session' | awk '{print $1}' | head -1)"
agent-device fill "$IMG_REF" "$IMAGE" "${ad[@]}"
agent-device fill "$CMD_REF" "$COMMAND" "${ad[@]}"
agent-device press "$DESK_REF" "${ad[@]}" || true

for _ in 1 2 3 4 5; do agent-device scroll up "${ad[@]}"; done
SAVE_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'button.*Save' | awk '{print $1}' | head -1)"
agent-device press "$SAVE_REF" "${ad[@]}"

sleep 2
for _ in 1 2 3 4 5; do agent-device scroll down "${ad[@]}"; done
START_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg "button.*Start $MACHINE_NAME" | awk '{print $1}' | head -1)"
[[ -n "$START_REF" ]] || START_REF="$(agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg 'button.*Start Nix Weston' | awk '{print $1}' | head -1)"
agent-device press "$START_REF" "${ad[@]}"

sleep 10
agent-device screenshot --out "$ARTIFACTS/macos-container-after-start.png" "${ad[@]}" || true
agent-device snapshot -i "${ad[@]}" | tee "$ARTIFACTS/macos-container-after-start.txt"

if agent-device snapshot -i "${ad[@]}" 2>/dev/null | rg -q 'Error'; then
  log "FAIL: machine card shows Error (see wwn-containerd / container logs)"
  exit 1
fi

log "PASS: container machine profile created and Start was pressed"
log "Artifacts: $ARTIFACTS"
