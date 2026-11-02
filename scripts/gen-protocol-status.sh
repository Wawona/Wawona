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
echo "Site copy: in Wawona/wawona.io run scripts/sync-protocol-status.sh (master channel)."
