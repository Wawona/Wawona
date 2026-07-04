#!/usr/bin/env bash
# Regenerate docs/protocol-status.md from the live advertised Wayland registry.
# The manifest is produced by a single integration test so it can never drift
# from what the compositor actually exposes (p12 protocol roadmap).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Regenerating docs/protocol-status.md from live registry..."
WWN_WRITE_PROTOCOL_STATUS=1 \
  nix develop --command cargo test --lib \
    tests::protocol_matrix::test_generate_protocol_status_manifest \
    -- --nocapture --exact

echo "Done. Review docs/protocol-status.md and commit if changed."
