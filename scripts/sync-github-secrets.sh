#!/usr/bin/env bash
# Sync .release-secrets.env to GitHub Environment secrets on Wawona/Wawona via gh CLI.
# Usage: sync-github-secrets.sh [.release-secrets.env] [--apple-only]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APPLE_ONLY=0
ENV_FILE=".release-secrets.env"
for arg in "$@"; do
  case "$arg" in
    --apple-only) APPLE_ONLY=1 ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) ENV_FILE="$arg" ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — copy from .release-secrets.env.template" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

GITHUB_REPO="${GITHUB_REPO:-Wawona/Wawona}"
GITHUB_ENV="${GITHUB_ENV:-release-beta}"

require() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing $name in $ENV_FILE" >&2
    exit 1
  fi
}

require MATCH_PASSWORD
require APPLE_ID
require TEAM_ID
require APPLE_SIGNING_PAT
require ASC_P8_PATH
require ASC_KEY_ID
require ASC_ISSUER_ID

if [[ "$APPLE_ONLY" -eq 0 ]]; then
  require ANDROID_KEYSTORE_PATH
  require ANDROID_KEYSTORE_PASSWORD
  require ANDROID_KEY_ALIAS
  require ANDROID_KEY_PASSWORD
  require PLAY_JSON_PATH
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required" >&2
  exit 1
fi

gh auth status >/dev/null

echo "Creating GitHub Environment $GITHUB_ENV on $GITHUB_REPO..."
gh api --method PUT "repos/$GITHUB_REPO/environments/$GITHUB_ENV" >/dev/null

set_secret() {
  local name="$1"
  local value="$2"
  printf '%s' "$value" | gh secret set "$name" --env "$GITHUB_ENV" --repo "$GITHUB_REPO"
  echo "Set $name"
}

MATCH_GIT_BASIC_AUTHORIZATION="$(printf 'x-access-token:%s' "$APPLE_SIGNING_PAT" | base64 | tr -d '\n')"
APP_STORE_CONNECT_API_KEY="$(base64 -i "$ASC_P8_PATH" | tr -d '\n')"

set_secret MATCH_PASSWORD "$MATCH_PASSWORD"
set_secret MATCH_GIT_BASIC_AUTHORIZATION "$MATCH_GIT_BASIC_AUTHORIZATION"
set_secret APP_STORE_CONNECT_API_KEY "$APP_STORE_CONNECT_API_KEY"
set_secret APP_STORE_CONNECT_KEY_ID "$ASC_KEY_ID"
set_secret APP_STORE_CONNECT_ISSUER_ID "$ASC_ISSUER_ID"
set_secret APPLE_ID "$APPLE_ID"
set_secret TEAM_ID "$TEAM_ID"

if [[ "$APPLE_ONLY" -eq 0 ]]; then
  ANDROID_KEYSTORE_BASE64="$(base64 -i "$ANDROID_KEYSTORE_PATH" | tr -d '\n')"
  PLAY_STORE_JSON_KEY="$(cat "$PLAY_JSON_PATH")"
  set_secret ANDROID_KEYSTORE_BASE64 "$ANDROID_KEYSTORE_BASE64"
  set_secret ANDROID_KEYSTORE_PASSWORD "$ANDROID_KEYSTORE_PASSWORD"
  set_secret ANDROID_KEY_ALIAS "$ANDROID_KEY_ALIAS"
  set_secret ANDROID_KEY_PASSWORD "$ANDROID_KEY_PASSWORD"
  set_secret PLAY_STORE_JSON_KEY "$PLAY_STORE_JSON_KEY"
else
  echo "Skipped Android/Play secrets (--apple-only)"
fi

echo "Done. Verify: gh secret list --env $GITHUB_ENV --repo $GITHUB_REPO"
