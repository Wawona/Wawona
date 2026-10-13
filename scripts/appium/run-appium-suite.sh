#!/usr/bin/env bash
# Run Wawona Appium pytest suite. Requires Appium server unless WAWONA_APPIUM_DRY=1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/Tests/appium"
export PYTHONPATH="${ROOT}/Tests/appium${PYTHONPATH:+:$PYTHONPATH}"
export WAWONA_APPIUM_ARTIFACTS="${WAWONA_APPIUM_ARTIFACTS:-$ROOT/.agent-device/test-artifacts/appium}"
mkdir -p "$WAWONA_APPIUM_ARTIFACTS"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install -q -r requirements.txt
else
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

python3 "$ROOT/scripts/appium/verify-a11y-sync.py"
python3 "$ROOT/scripts/appium/verify-matrix.py"

MARKERS="${WAWONA_APPIUM_MARKERS:-}"
EXTRA=()
if [[ -n "$MARKERS" ]]; then
  EXTRA+=(-m "$MARKERS")
fi

if [[ "${WAWONA_APPIUM_DRY:-0}" == "1" ]]; then
  exec pytest tests/test_gates_unit.py -q "${EXTRA[@]}" "$@"
fi

exec pytest tests -q --junitxml="$WAWONA_APPIUM_ARTIFACTS/junit.xml" "${EXTRA[@]}" "$@"
