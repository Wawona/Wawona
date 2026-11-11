#!/usr/bin/env bash
# Fail closed when repo CalVer is not today's date (YY.M.D, no zero-pad).
# Agents must bump VERSION + Cargo.toml before product builds.
#
# Escape (release rebuild of a past tip / tagged ship only):
#   WAWONA_ALLOW_STALE_CALVER=1
set -euo pipefail

ROOT="${WAWONA_CALVER_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT"

if [[ "${WAWONA_ALLOW_STALE_CALVER:-}" == "1" ]]; then
  echo "verify-calver-today: skipped (WAWONA_ALLOW_STALE_CALVER=1)"
  exit 0
fi

# The project's day boundary is America/Los_Angeles.
TODAY="$(TZ=America/Los_Angeles date '+%y.%-m.%-d')"

VERSION_FILE="$(tr -d '[:space:]' <VERSION 2>/dev/null || true)"
CARGO_VER="$(
  awk -F'"' '
    $0 ~ /^\[package\]/ { in_pkg = 1; next }
    in_pkg && $0 ~ /^\[/ { in_pkg = 0 }
    in_pkg && $1 ~ /^version[[:space:]]*=/ { print $2; exit }
  ' Cargo.toml
)"

fail() {
  echo "error: CalVer mismatch (fail closed)." >&2
  echo "  today (America/Los_Angeles): $TODAY" >&2
  echo "  VERSION file:                ${VERSION_FILE:-<missing>}" >&2
  echo "  Cargo.toml package.version:  ${CARGO_VER:-<missing>}" >&2
  echo "Bump VERSION and Cargo.toml to $TODAY, sync Cargo.lock, then rebuild." >&2
  echo "Escape hatch for intentional stale rebuilds: WAWONA_ALLOW_STALE_CALVER=1" >&2
  exit 1
}

[[ -n "$VERSION_FILE" && -n "$CARGO_VER" ]] || fail
[[ "$VERSION_FILE" == "$TODAY" ]] || fail
[[ "$CARGO_VER" == "$TODAY" ]] || fail

echo "verify-calver-today: OK ($TODAY)"
