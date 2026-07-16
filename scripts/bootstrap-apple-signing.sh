#!/usr/bin/env bash
# Create aspauldingcode/apple-signing (if missing) and populate via fastlane match.
# Tier 0: secrets from SecretSpec/pass (see docs/maintainers/secrets.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export SECRETSPEC_FILE="${SECRETSPEC_FILE:-$ROOT/secretspec.toml}"
export PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

load_from_pass() {
  command -v secretspec >/dev/null 2>&1 || return 1
  secretspec get -P local APPLE_ID >/dev/null 2>&1 || return 1
  APPLE_ID="$(secretspec get -P local APPLE_ID)"
  TEAM_ID="$(secretspec get -P local TEAM_ID)"
  MATCH_PASSWORD="$(secretspec get -P local MATCH_PASSWORD)"
  ASC_KEY_ID="$(secretspec get -P local ASC_KEY_ID)"
  ASC_ISSUER_ID="$(secretspec get -P local ASC_ISSUER_ID)"
  ASC_P8="$(secretspec get -P local ASC_P8)"
  ASC_P8_PATH="$(mktemp)"
  printf '%s\n' "$ASC_P8" > "$ASC_P8_PATH"
  chmod 600 "$ASC_P8_PATH"
  export APPLE_ID TEAM_ID MATCH_PASSWORD ASC_KEY_ID ASC_ISSUER_ID ASC_P8_PATH
  trap 'rm -f "$ASC_P8_PATH"' EXIT
  return 0
}

if ! load_from_pass; then
  if [[ -f .release-secrets.env ]]; then
    echo "WARN: falling back to .release-secrets.env - migrate with ./scripts/migrate-release-secrets-to-pass.sh" >&2
    # shellcheck source=/dev/null
    source .release-secrets.env
  else
    echo "Missing pass secrets and .release-secrets.env - see docs/maintainers/secrets.md" >&2
    exit 1
  fi
fi

: "${MATCH_PASSWORD:?Set MATCH_PASSWORD (pass or .release-secrets.env)}"
: "${APPLE_ID:?Set APPLE_ID}"
: "${TEAM_ID:?Set TEAM_ID}"
: "${ASC_P8_PATH:?Set ASC_P8 (pass) or ASC_P8_PATH}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"

export MATCH_PASSWORD APPLE_ID TEAM_ID
export MATCH_GIT_URL="${MATCH_GIT_URL:-git@github.com:aspauldingcode/apple-signing.git}"
export SPACESHIP_CONNECT_API_KEY_ID="$ASC_KEY_ID"
export SPACESHIP_CONNECT_API_KEY_ISSUER_ID="$ASC_ISSUER_ID"
export SPACESHIP_CONNECT_API_KEY_FILEPATH="$ASC_P8_PATH"
export FASTLANE_IS_INTERACTIVE=false

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required" >&2
  exit 1
fi

gh auth status >/dev/null

if ! gh repo view aspauldingcode/apple-signing >/dev/null 2>&1; then
  echo "Creating aspauldingcode/apple-signing..."
  gh repo create aspauldingcode/apple-signing \
    --private \
    --description "Encrypted Apple certs/profiles for Wawona (fastlane match)"
fi

# Seed README when the signing repo has no commits yet (match will populate certs/ later).
if ! gh api repos/aspauldingcode/apple-signing/contents/README.md >/dev/null 2>&1; then
  TMP_README="$(mktemp)"
  cat > "$TMP_README" <<'EOF'
# apple-signing

Encrypted Apple certificates and provisioning profiles for Wawona.

Managed by [fastlane match](https://docs.fastlane.tools/actions/match/). Do not edit manually.

Populate via `./scripts/bootstrap-apple-signing.sh` from the Wawona repo.
EOF
  gh api repos/aspauldingcode/apple-signing/contents/README.md \
    --method PUT \
    -f message="Initialize apple-signing for fastlane match" \
    -f content="$(base64 < "$TMP_README" | tr -d '\n')" >/dev/null || true
  rm -f "$TMP_README"
fi

if [[ ! -f fastlane/Matchfile ]]; then
  echo "fastlane/Matchfile missing - run from Wawona tree after fastlane scaffold" >&2
  exit 1
fi

MAIN_APP_ID="com.aspauldingcode.Wawona"
WATCH_APP_ID="com.aspauldingcode.Wawona.watch"
INCLUDE_WATCH="${MATCH_INCLUDE_WATCH:-1}"

API_KEY_JSON="$(mktemp)"
trap 'rm -f "$API_KEY_JSON" "${ASC_P8_PATH:-}"' EXIT
jq -n \
  --arg key_id "$ASC_KEY_ID" \
  --arg issuer_id "$ASC_ISSUER_ID" \
  --arg key "$(cat "$ASC_P8_PATH")" \
  '{key_id:$key_id, issuer_id:$issuer_id, key:$key, in_house:false}' \
  > "$API_KEY_JSON"

run_match() {
  local type="$1"
  local platform="$2"
  local app_id="$3"
  local force_flag="${4:-}"
  echo "Running fastlane match $type ($platform) for $app_id ${force_flag}..."
  nix develop .#release --command bash -lc \
    "export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 FASTLANE_IS_INTERACTIVE=false MATCH_PASSWORD='${MATCH_PASSWORD}' TEAM_ID='${TEAM_ID}' MATCH_GIT_URL='${MATCH_GIT_URL}'; fastlane match ${type} --platform ${platform} --app_identifier '${app_id}' --readonly false ${force_flag} --api_key_path '${API_KEY_JSON}'"
}

# Prefer Fastfile lane: enables iCloud on App ID + force-regenerates App Store profiles.
if [[ "${MATCH_USE_FASTFILE:-1}" == "1" ]]; then
  echo "Running fastlane regenerate_signing (iCloud + force match)..."
  nix develop .#release --command bash -lc \
    "export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 FASTLANE_IS_INTERACTIVE=false MATCH_PASSWORD='${MATCH_PASSWORD}' TEAM_ID='${TEAM_ID}' MATCH_GIT_URL='${MATCH_GIT_URL}' MATCH_FORCE=1 MATCH_READONLY=0 APP_STORE_CONNECT_KEY_ID='${ASC_KEY_ID}' APP_STORE_CONNECT_ISSUER_ID='${ASC_ISSUER_ID}' APP_STORE_CONNECT_API_KEY=\"\$(base64 < '${ASC_P8_PATH}' | tr -d '\n')\"; fastlane regenerate_signing"
else
  FORCE_FLAG=""
  if [[ "${MATCH_FORCE:-1}" == "1" ]]; then
    FORCE_FLAG="--force"
  fi
  run_match appstore ios "$MAIN_APP_ID" "$FORCE_FLAG"
  run_match appstore tvos "$MAIN_APP_ID" "$FORCE_FLAG"
  if [[ "$INCLUDE_WATCH" == "1" ]]; then
    run_match appstore ios "$WATCH_APP_ID" "$FORCE_FLAG"
  fi
fi

run_match development ios "$MAIN_APP_ID"
if [[ "$INCLUDE_WATCH" == "1" ]]; then
  run_match development ios "$WATCH_APP_ID"
fi

if [[ "$INCLUDE_WATCH" != "1" ]]; then
  echo ""
  echo "Note: skipped $WATCH_APP_ID (MATCH_INCLUDE_WATCH=0)."
fi

echo "apple-signing repo populated. Verify with: gh repo view aspauldingcode/apple-signing"
