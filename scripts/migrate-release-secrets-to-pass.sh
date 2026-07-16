#!/usr/bin/env bash
# One-shot: import .release-secrets.env + .secrets/* into the private pass store.
# Tier 0 only. Requires gpg-agent unlocked and PASSWORD_STORE_DIR set.
#
# Usage:
#   ./scripts/migrate-release-secrets-to-pass.sh [.release-secrets.env]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${1:-.release-secrets.env}"
STORE="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
GPG_ID_FILE="$STORE/.gpg-id"
APPLE="secretspec/wawona/release-apple"
ANDROID="secretspec/wawona/release-android"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi
if [[ ! -f "$GPG_ID_FILE" ]]; then
  echo "Missing $GPG_ID_FILE - init pass / clone aspauldingcode/.password-store first" >&2
  exit 1
fi
if ! command -v pass >/dev/null 2>&1; then
  echo "pass required" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

FP="$(head -n1 "$GPG_ID_FILE")"
mkdir -p "$STORE/$APPLE" "$STORE/$ANDROID"
# Tier-0 ACL: same recipients as store root (extend later for tier-1 helpers).
printf '%s\n' "$FP" > "$STORE/$APPLE/.gpg-id"
printf '%s\n' "$FP" > "$STORE/$ANDROID/.gpg-id"
printf '%s\n' "$FP" > "$STORE/secretspec/wawona/.gpg-id"

pass_insert() {
  local path="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "skip empty: $path" >&2
    return 0
  fi
  printf '%s' "$value" | pass insert -m -f "$path" >/dev/null
  echo "stored $path"
}

pass_insert_file() {
  local path="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    echo "missing file for $path: $file" >&2
    exit 1
  fi
  pass insert -m -f "$path" < "$file" >/dev/null
  echo "stored $path (from $file)"
}

: "${APPLE_ID:?}"
: "${TEAM_ID:?}"
: "${MATCH_PASSWORD:?}"
: "${APPLE_SIGNING_PAT:?}"
: "${ASC_KEY_ID:?}"
: "${ASC_ISSUER_ID:?}"
: "${ASC_P8_PATH:?}"

pass_insert "$APPLE/APPLE_ID" "$APPLE_ID"
pass_insert "$APPLE/TEAM_ID" "$TEAM_ID"
pass_insert "$APPLE/MATCH_PASSWORD" "$MATCH_PASSWORD"
pass_insert "$APPLE/APPLE_SIGNING_PAT" "$APPLE_SIGNING_PAT"
pass_insert "$APPLE/ASC_KEY_ID" "$ASC_KEY_ID"
pass_insert "$APPLE/ASC_ISSUER_ID" "$ASC_ISSUER_ID"
pass_insert_file "$APPLE/ASC_P8" "$ASC_P8_PATH"

if [[ -n "${ANDROID_KEYSTORE_PATH:-}" && -f "${ANDROID_KEYSTORE_PATH}" ]]; then
  : "${ANDROID_KEYSTORE_PASSWORD:?}"
  : "${ANDROID_KEY_ALIAS:?}"
  : "${ANDROID_KEY_PASSWORD:?}"
  : "${PLAY_JSON_PATH:?}"
  B64="$(base64 -i "$ANDROID_KEYSTORE_PATH" | tr -d '\n')"
  pass_insert "$ANDROID/ANDROID_KEYSTORE_BASE64" "$B64"
  pass_insert "$ANDROID/ANDROID_KEYSTORE_PASSWORD" "$ANDROID_KEYSTORE_PASSWORD"
  pass_insert "$ANDROID/ANDROID_KEY_ALIAS" "$ANDROID_KEY_ALIAS"
  pass_insert "$ANDROID/ANDROID_KEY_PASSWORD" "$ANDROID_KEY_PASSWORD"
  pass_insert_file "$ANDROID/PLAY_STORE_JSON_KEY" "$PLAY_JSON_PATH"
else
  echo "Skipped Android/Play (ANDROID_KEYSTORE_PATH unset or missing)"
fi

# Commit ACL markers if the store is a git repo (pass git).
if [[ -d "$STORE/.git" ]]; then
  (
    cd "$STORE"
    git add secretspec/wawona 2>/dev/null || true
    if ! git diff --cached --quiet 2>/dev/null; then
      git commit -m "Add Wawona release-apple/release-android SecretSpec paths"
    fi
  )
fi

echo "Done. Verify: secretspec check -P local -f $ROOT/secretspec.toml"
echo "Push store: (cd \"\$PASSWORD_STORE_DIR\" && pass git push)"
