#!/usr/bin/env bash
# Create .secrets/ and .release-secrets.env if missing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p .secrets

if [[ ! -f .secrets/README.md ]]; then
  cat > .secrets/README.md <<'EOF'
# Local release secrets (gitignored contents)

Drop key files here. See ../.release-secrets.env.template for how to obtain each value.
EOF
fi

touch .secrets/.gitkeep

if [[ ! -f .release-secrets.env ]]; then
  cp .release-secrets.env.template .release-secrets.env
  # Point paths at .secrets/ when template uses bare examples
  sed -i '' \
    -e 's|^ASC_P8_PATH=.*|ASC_P8_PATH=.secrets/AuthKey.p8|' \
    -e 's|^ANDROID_KEYSTORE_PATH=.*|ANDROID_KEYSTORE_PATH=.secrets/wawona-upload.keystore|' \
    -e 's|^PLAY_JSON_PATH=.*|PLAY_JSON_PATH=.secrets/play-store.json|' \
    .release-secrets.env 2>/dev/null || sed -i \
    -e 's|^ASC_P8_PATH=.*|ASC_P8_PATH=.secrets/AuthKey.p8|' \
    -e 's|^ANDROID_KEYSTORE_PATH=.*|ANDROID_KEYSTORE_PATH=.secrets/wawona-upload.keystore|' \
    -e 's|^PLAY_JSON_PATH=.*|PLAY_JSON_PATH=.secrets/play-store.json|' \
    .release-secrets.env
  echo "Created .release-secrets.env — fill in values, then run ./scripts/sync-github-secrets.sh"
else
  echo ".release-secrets.env already exists"
fi

echo "Ready: .secrets/ (drop AuthKey.p8, wawona-upload.keystore, play-store.json here)"
