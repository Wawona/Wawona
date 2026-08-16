#!/usr/bin/env bash
# Sync Wawona release secrets from SecretSpec/pass -> GitHub Environment secrets.
# Tier 0 only. Values come from the private pass store (sops-nix unlocks GPG).
#
# Usage:
#   ./scripts/sync-github-secrets.sh [--apple-only]
#   SECRETSPEC_PROFILE=sync ./scripts/sync-github-secrets.sh
#
# See docs/maintainers/secrets.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APPLE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --apple-only) APPLE_ONLY=1 ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) echo "Unexpected argument: $arg (dotenv path no longer supported)" >&2; exit 1 ;;
  esac
done

GITHUB_REPO="${GITHUB_REPO:-Wawona/Wawona}"
GITHUB_ENV="${GITHUB_ENV:-release-beta}"
export SECRETSPEC_FILE="${SECRETSPEC_FILE:-$ROOT/secretspec.toml}"
export SECRETSPEC_PROFILE="${SECRETSPEC_PROFILE:-sync}"
export PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required" >&2
  exit 1
fi
if ! command -v secretspec >/dev/null 2>&1; then
  echo "secretspec required (nix develop .#release)" >&2
  exit 1
fi

gh auth status >/dev/null

ss_get() {
  secretspec get -P "$SECRETSPEC_PROFILE" "$1"
}

echo "Checking SecretSpec profile=${SECRETSPEC_PROFILE}..."
if [[ "$APPLE_ONLY" -eq 1 ]]; then
  for k in APPLE_ID TEAM_ID MATCH_PASSWORD APPLE_SIGNING_PAT ASC_KEY_ID ASC_ISSUER_ID ASC_P8 \
    DEVELOPER_ID_APPLICATION_P12_BASE64 DEVELOPER_ID_INSTALLER_P12_BASE64; do
    if [[ -z "$(ss_get "$k" 2>/dev/null || true)" ]]; then
      echo "Missing $k in pass (profile $SECRETSPEC_PROFILE)" >&2
      echo "See docs/maintainers/secrets.md" >&2
      exit 1
    fi
  done
else
  secretspec check -P "$SECRETSPEC_PROFILE" || {
    echo "secretspec check failed. See docs/maintainers/secrets.md" >&2
    exit 1
  }
fi

APPLE_ID="$(ss_get APPLE_ID)"
TEAM_ID="$(ss_get TEAM_ID)"
MATCH_PASSWORD="$(ss_get MATCH_PASSWORD)"
APPLE_SIGNING_PAT="$(ss_get APPLE_SIGNING_PAT)"
ASC_KEY_ID="$(ss_get ASC_KEY_ID)"
ASC_ISSUER_ID="$(ss_get ASC_ISSUER_ID)"
ASC_P8="$(ss_get ASC_P8)"
DEVELOPER_ID_APPLICATION_P12_BASE64="$(ss_get DEVELOPER_ID_APPLICATION_P12_BASE64)"
DEVELOPER_ID_INSTALLER_P12_BASE64="$(ss_get DEVELOPER_ID_INSTALLER_P12_BASE64)"

echo "Creating GitHub Environment $GITHUB_ENV on $GITHUB_REPO..."
gh api --method PUT "repos/$GITHUB_REPO/environments/$GITHUB_ENV" >/dev/null

set_secret() {
  local name="$1"
  local value="$2"
  printf '%s' "$value" | gh secret set "$name" --env "$GITHUB_ENV" --repo "$GITHUB_REPO"
  echo "Set $name"
}

MATCH_GIT_BASIC_AUTHORIZATION="$(printf 'x-access-token:%s' "$APPLE_SIGNING_PAT" | base64 | tr -d '\n')"
APP_STORE_CONNECT_API_KEY="$(printf '%s' "$ASC_P8" | base64 | tr -d '\n')"

set_secret MATCH_PASSWORD "$MATCH_PASSWORD"
set_secret MATCH_GIT_BASIC_AUTHORIZATION "$MATCH_GIT_BASIC_AUTHORIZATION"
set_secret APP_STORE_CONNECT_API_KEY "$APP_STORE_CONNECT_API_KEY"
set_secret APP_STORE_CONNECT_KEY_ID "$ASC_KEY_ID"
set_secret APP_STORE_CONNECT_ISSUER_ID "$ASC_ISSUER_ID"
set_secret APPLE_ID "$APPLE_ID"
set_secret TEAM_ID "$TEAM_ID"
set_secret DEVELOPER_ID_APPLICATION_P12_BASE64 "$DEVELOPER_ID_APPLICATION_P12_BASE64"
set_secret DEVELOPER_ID_INSTALLER_P12_BASE64 "$DEVELOPER_ID_INSTALLER_P12_BASE64"

if [[ "$APPLE_ONLY" -eq 0 ]]; then
  ANDROID_KEYSTORE_BASE64="$(ss_get ANDROID_KEYSTORE_BASE64)"
  ANDROID_KEYSTORE_PASSWORD="$(ss_get ANDROID_KEYSTORE_PASSWORD)"
  ANDROID_KEY_ALIAS="$(ss_get ANDROID_KEY_ALIAS)"
  ANDROID_KEY_PASSWORD="$(ss_get ANDROID_KEY_PASSWORD)"
  PLAY_STORE_JSON_KEY="$(ss_get PLAY_STORE_JSON_KEY)"
  set_secret ANDROID_KEYSTORE_BASE64 "$ANDROID_KEYSTORE_BASE64"
  set_secret ANDROID_KEYSTORE_PASSWORD "$ANDROID_KEYSTORE_PASSWORD"
  set_secret ANDROID_KEY_ALIAS "$ANDROID_KEY_ALIAS"
  set_secret ANDROID_KEY_PASSWORD "$ANDROID_KEY_PASSWORD"
  set_secret PLAY_STORE_JSON_KEY "$PLAY_STORE_JSON_KEY"
else
  echo "Skipped Android/Play secrets (--apple-only)"
fi

echo "Done. Verify: gh secret list --env $GITHUB_ENV --repo $GITHUB_REPO"
