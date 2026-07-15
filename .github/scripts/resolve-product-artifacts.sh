#!/usr/bin/env bash
# Resolve GHA artifacts produced by product-build.yml for a git SHA.
#
# Usage:
#   resolve-product-artifacts.sh <sha> <artifact-name> <dest-dir> [wait-seconds]
#
# Finds a successful Product build run for the commit, waits if still in
# progress (up to wait-seconds, default 5400), then downloads the named
# artifact into dest-dir.
set -euo pipefail

SHA="${1:?usage: $0 <sha> <artifact-name> <dest-dir> [wait-seconds]}"
ARTIFACT="${2:?}"
DEST="${3:?}"
WAIT_SECS="${4:-5400}"
REPO="${GITHUB_REPOSITORY:-Wawona/Wawona}"
WORKFLOW="product-build.yml"

if ! command -v gh >/dev/null; then
  echo "error: gh CLI required" >&2
  exit 1
fi

mkdir -p "$DEST"
deadline=$((SECONDS + WAIT_SECS))

find_run() {
  # Prefer successful completed runs for this SHA.
  gh run list --repo "$REPO" --workflow "$WORKFLOW" --commit "$SHA" --limit 20 \
    --json databaseId,status,conclusion,updatedAt \
    --jq '[.[] | select(.status=="completed" and .conclusion=="success")] | .[0].databaseId // empty'
}

find_in_progress() {
  gh run list --repo "$REPO" --workflow "$WORKFLOW" --commit "$SHA" --limit 10 \
    --json databaseId,status \
    --jq '[.[] | select(.status=="in_progress" or .status=="queued")] | .[0].databaseId // empty'
}

run_id=""
while (( SECONDS < deadline )); do
  run_id="$(find_run || true)"
  if [[ -n "$run_id" ]]; then
    break
  fi
  pending="$(find_in_progress || true)"
  if [[ -n "$pending" ]]; then
    echo "== product-build run $pending still running for $SHA; waiting =="
    sleep 30
    continue
  fi
  echo "== no product-build run for $SHA yet; waiting =="
  sleep 20
done

if [[ -z "$run_id" ]]; then
  echo "error: no successful product-build run for sha=$SHA within ${WAIT_SECS}s" >&2
  exit 1
fi

echo "== downloading $ARTIFACT from product-build run $run_id into $DEST =="
gh run download "$run_id" --repo "$REPO" --name "$ARTIFACT" --dir "$DEST"
ls -la "$DEST"
