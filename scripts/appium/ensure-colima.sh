#!/usr/bin/env bash
# Fail closed unless Colima is installed and the default VM is running.
# Catalog Wayland guests on Darwin must use Colima + waypipe (not local-bundle).
#
# Usage:
#   scripts/appium/ensure-colima.sh
#   WAWONA_COLIMA_START=1 scripts/appium/ensure-colima.sh   # start if stopped
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${HOME}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:${PATH:-}"

# Host brew often missing in agent shells; resolve colima from nix if needed.
if ! command -v colima >/dev/null 2>&1; then
  if command -v nix >/dev/null 2>&1; then
    _colima_out="$(nix build --no-link --print-out-paths 'nixpkgs#colima' 2>/dev/null | head -1 || true)"
    _lima_out="$(nix build --no-link --print-out-paths 'nixpkgs#lima' 2>/dev/null | head -1 || true)"
    if [[ -n "${_colima_out}" && -x "${_colima_out}/bin/colima" ]]; then
      export PATH="${_colima_out}/bin:${_lima_out:+${_lima_out}/bin:}${PATH}"
    fi
  fi
fi

if ! command -v colima >/dev/null 2>&1; then
  echo "FAIL: colima not on PATH. Install via brew (colima lima) or nix profile, then colima start." >&2
  exit 6
fi

status_out="$(colima status 2>&1 || true)"
if echo "$status_out" | grep -Eiq 'is running|Running'; then
  echo "colima already running"
else
  if [[ "${WAWONA_COLIMA_START:-0}" == "1" ]]; then
    echo "colima not running; starting (WAWONA_COLIMA_START=1)"
    colima start
  else
    echo "FAIL: colima not running. Start with: colima start" >&2
    echo "$status_out" >&2
    exit 6
  fi
fi

SSH_CONFIG="${COLIMA_SSH_CONFIG:-$HOME/.colima/ssh_config}"
KEY="${COLIMA_SSH_KEY:-$HOME/.colima/_lima/_config/user}"
HOST="${COLIMA_SSH_HOST:-127.0.0.1}"
USER_NAME="${COLIMA_SSH_USER:-lima}"
PORT="${COLIMA_SSH_PORT:-}"
if [[ -z "$PORT" && -f "$SSH_CONFIG" ]]; then
  PORT="$(awk '$1=="Port" { print $2; exit }' "$SSH_CONFIG" || true)"
fi
PORT="${PORT:-49419}"

if [[ ! -f "$KEY" ]]; then
  echo "FAIL: Colima SSH key missing at $KEY" >&2
  exit 6
fi

if ! ssh -o BatchMode=yes -o ConnectTimeout=8 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i "$KEY" -p "$PORT" "${USER_NAME}@${HOST}" 'true' >/dev/null 2>&1; then
  echo "FAIL: cannot ssh ${USER_NAME}@${HOST}:$PORT (Colima guest)" >&2
  exit 6
fi

echo "colima ok ssh=${USER_NAME}@${HOST}:$PORT"
