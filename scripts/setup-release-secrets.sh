#!/usr/bin/env bash
# Tier-0 helper: SecretSpec + private pass (sops-nix unlocks GPG on the host).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

cat <<'EOF'
Wawona release secrets: SecretSpec + private pass store.

  docs/maintainers/secrets.md

Host: dendritic / sops-nix unlocks GPG for pass (do not put MATCH/Play
ciphertext into public Wawona sops files).

Typical flow:
  1. ~/.password-store → git@github.com:aspauldingcode/.password-store.git
  2. pass show secretspec/wawona/release-apple/TEAM_ID
  3. nix develop .#release
  4. secretspec check -P local
  5. ./scripts/sync-github-secrets.sh
  6. ./scripts/release-env.sh fastlane validate_env

Insert / rotate a value:
  pass insert -m secretspec/wawona/release-apple/<KEY>
  (cd "$PASSWORD_STORE_DIR" && pass git push)
  ./scripts/sync-github-secrets.sh
EOF

if [[ ! -d "${PASSWORD_STORE_DIR:-$HOME/.password-store}/secretspec/wawona" ]]; then
  echo ""
  echo "warn: secretspec/wawona missing under PASSWORD_STORE_DIR — clone the private store first." >&2
  exit 1
fi

if command -v secretspec >/dev/null 2>&1; then
  export SECRETSPEC_FILE="${SECRETSPEC_FILE:-$ROOT/secretspec.toml}"
  secretspec check -P local || {
    echo "secretspec check failed — see docs/maintainers/secrets.md" >&2
    exit 1
  }
  echo ""
  echo "secretspec check -P local: OK"
else
  echo ""
  echo "Note: secretspec not on PATH — run inside: nix develop .#release"
fi
