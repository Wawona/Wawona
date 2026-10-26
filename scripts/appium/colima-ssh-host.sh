#!/usr/bin/env bash
# Resolve the SSH alias Colima generated for the selected profile.
set -euo pipefail

config="${1:?usage: colima-ssh-host.sh SSH_CONFIG}"
if [[ -n "${COLIMA_SSH_HOST:-}" ]]; then
  printf '%s\n' "$COLIMA_SSH_HOST"
  exit 0
fi
if [[ ! -s "$config" ]]; then
  echo "FAIL: Colima SSH config missing or empty: $config" >&2
  exit 1
fi

host="$(awk 'tolower($1) == "host" {
  for (i = 2; i <= NF; i++) {
    if ($i !~ /[*?!]/) { print $i; exit }
  }
}' "$config")"
if [[ -z "$host" ]]; then
  echo "FAIL: no concrete Host alias in Colima SSH config: $config" >&2
  exit 1
fi
printf '%s\n' "$host"
