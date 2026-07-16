#!/usr/bin/env bash
# Run a command with Wawona release secrets via SecretSpec.
#
# Profiles:
#   local (default) - pass store (tier 0); derives Fastlane/CI env names
#   sync            - pass store (for sync-github-secrets.sh)
#   ci              - process environment (GitHub Actions; already CI-shaped)
#
# Usage:
#   ./scripts/release-env.sh fastlane ios beta
#   SECRETSPEC_PROFILE=ci ./scripts/release-env.sh fastlane android beta
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROFILE="${SECRETSPEC_PROFILE:-local}"
export SECRETSPEC_FILE="${SECRETSPEC_FILE:-$ROOT/secretspec.toml}"
export PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 2
fi

if ! command -v secretspec >/dev/null 2>&1; then
  echo "error: secretspec not on PATH (use: nix develop .#release)" >&2
  exit 1
fi

case "$PROFILE" in
  ci)
    export SECRETSPEC_PROVIDER="${SECRETSPEC_PROVIDER:-env}"
    exec secretspec run -P ci -- "$@"
    ;;
  sync)
    exec secretspec run -P sync -- "$@"
    ;;
  local|development)
    # Inject pass secrets, then map ASC_* -> APP_STORE_CONNECT_* for Fastlane.
    exec secretspec run -P local -- bash -c '
      set -euo pipefail
      if [[ -n "${ASC_KEY_ID:-}" ]]; then
        export APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-$ASC_KEY_ID}"
      fi
      if [[ -n "${ASC_ISSUER_ID:-}" ]]; then
        export APP_STORE_CONNECT_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-$ASC_ISSUER_ID}"
      fi
      if [[ -n "${ASC_P8:-}" && -z "${APP_STORE_CONNECT_API_KEY:-}" ]]; then
        export APP_STORE_CONNECT_API_KEY="$(printf "%s" "$ASC_P8" | base64 | tr -d "\n")"
      fi
      if [[ -n "${APPLE_SIGNING_PAT:-}" && -z "${MATCH_GIT_BASIC_AUTHORIZATION:-}" ]]; then
        export MATCH_GIT_BASIC_AUTHORIZATION="$(
          printf "x-access-token:%s" "$APPLE_SIGNING_PAT" | base64 | tr -d "\n"
        )"
      fi
      export MATCH_GIT_URL="${MATCH_GIT_URL:-git@github.com:aspauldingcode/apple-signing.git}"
      exec "$@"
    ' bash "$@"
    ;;
  *)
    echo "error: unknown SECRETSPEC_PROFILE=$PROFILE (local|sync|ci)" >&2
    exit 1
    ;;
esac
