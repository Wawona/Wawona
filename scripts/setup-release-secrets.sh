#!/usr/bin/env bash
# Tier-0 helper: point maintainers at SecretSpec + pass (legacy dotenv optional).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

cat <<'EOF'
Wawona release secrets are managed with SecretSpec + a private pass store.

  docs/maintainers/secrets.md

Typical flow:
  1. Ensure ~/.password-store tracks github.com/aspauldingcode/.password-store
  2. nix develop .#release
  3. secretspec check -P local
  4. ./scripts/sync-github-secrets.sh
  5. ./scripts/release-env.sh fastlane validate_env

Migrating from an old .release-secrets.env:
  ./scripts/migrate-release-secrets-to-pass.sh
  (cd "$PASSWORD_STORE_DIR" && pass git push)
EOF

if [[ ! -d .secrets ]]; then
  mkdir -p .secrets
  echo "Created .secrets/ (gitignored; migration staging only)"
fi

if [[ -f .release-secrets.env ]]; then
  echo ""
  echo "Note: .release-secrets.env still present - prefer pass; migrate when ready."
fi
