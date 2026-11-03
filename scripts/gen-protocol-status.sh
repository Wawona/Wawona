#!/usr/bin/env bash
# Regenerate docs/protocol-status.md from PROTOCOL_CATALOG plus the live
# advertised Wayland registry. Tables sort Functional → Partial → Stub →
# Missing. The manifest is produced by a single integration test so it can
# never drift from what the compositor actually exposes (p12 protocol roadmap).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Regenerating docs/protocol-status.md from catalog + live registry..."
WWN_WRITE_PROTOCOL_STATUS=1 \
  nix develop --command cargo test --lib \
    tests::protocol_matrix::test_generate_protocol_status_manifest \
    -- --nocapture --exact

echo "Done. Review docs/protocol-status.md and commit if changed."

SITE_SYNC="$(cd "$(dirname "$0")/../.." && pwd)/wawona.io/scripts/sync-protocol-status.sh"
if [[ -x "$SITE_SYNC" ]]; then
  echo "Syncing wawona.io contributor protocols page..."
  WAWONA_REPO="$(pwd)" "$SITE_SYNC"
else
  echo "Site copy: in Wawona/wawona.io run scripts/sync-protocol-status.sh (master channel)."
fi
echo "Milestones: docs/protocol-milestones.md (create/update with scripts/sync-protocol-milestones.sh)."
