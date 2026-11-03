#!/usr/bin/env bash
# Regenerate docs/protocol-expect/{profile}.json from PROTOCOL_CATALOG.expect_on.
# These files feed the WASI P1 protocol-probe guest (repo.wawona.io catalog).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Regenerating docs/protocol-expect/*.json from catalog expect_on..."
WWN_WRITE_PROTOCOL_EXPECT=1 \
  nix develop --command cargo test --lib \
    core::wayland::catalog::tests::test_generate_protocol_expect_manifests \
    -- --nocapture --exact

PROBE_EXPECT="$(cd "$(dirname "$0")/../.." && pwd)/repo.wawona.io/catalog/wasm/src/p1/packages/protocol-probe/expect"
if [[ -d "$(dirname "$PROBE_EXPECT")" ]]; then
  mkdir -p "$PROBE_EXPECT"
  cp -f docs/protocol-expect/*.json "$PROBE_EXPECT/"
  echo "Synced expect JSON into $PROBE_EXPECT"
else
  echo "Probe package not found yet; skipped sync to repo.wawona.io."
fi

echo "Done. Review docs/protocol-expect/ and commit if changed."
