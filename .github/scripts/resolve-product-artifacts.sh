#!/usr/bin/env bash
# Resolve GHA artifacts produced by product-build.yml for a git SHA.
#
# Usage:
#   resolve-product-artifacts.sh <sha> <artifact-name> <dest-dir> [wait-seconds]
#
# Finds a successful Product build run for the commit that uploaded the named
# artifact (device-gate may fan out one product-build call per product), waits
# if still in progress (up to wait-seconds, default 5400), then downloads into
# dest-dir.
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

run_has_artifact() {
  local id="$1"
  gh api "repos/$REPO/actions/runs/$id/artifacts" --jq \
    --arg name "$ARTIFACT" \
    '[.artifacts[] | select(.name == $name and .expired == false)] | length > 0' 2>/dev/null \
    | grep -q true
}

# Prefer a completed successful run that actually uploaded $ARTIFACT.
find_run_with_artifact() {
  local ids
  ids="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --commit "$SHA" --limit 30 \
    --json databaseId,status,conclusion \
    --jq '[.[] | select(.status=="completed" and .conclusion=="success")] | .[].databaseId' 2>/dev/null || true)"
  local id
  for id in $ids; do
    if run_has_artifact "$id"; then
      echo "$id"
      return 0
    fi
  done
  return 1
}

find_in_progress() {
  gh run list --repo "$REPO" --workflow "$WORKFLOW" --commit "$SHA" --limit 20 \
    --json databaseId,status \
    --jq '[.[] | select(.status=="in_progress" or .status=="queued")] | .[0].databaseId // empty'
}

run_id=""
while (( SECONDS < deadline )); do
  run_id="$(find_run_with_artifact || true)"
  if [[ -n "$run_id" ]]; then
    break
  fi
  pending="$(find_in_progress || true)"
  if [[ -n "$pending" ]]; then
    echo "== product-build run $pending still running for $SHA; waiting for artifact $ARTIFACT =="
    sleep 30
    continue
  fi
  echo "== no product-build run with $ARTIFACT for $SHA yet; waiting =="
  sleep 20
done

if [[ -z "$run_id" ]]; then
  echo "error: no successful product-build run with artifact=$ARTIFACT for sha=$SHA within ${WAIT_SECS}s" >&2
  exit 1
fi

echo "== downloading $ARTIFACT from product-build run $run_id into $DEST =="
gh run download "$run_id" --repo "$REPO" --name "$ARTIFACT" --dir "$DEST"
ls -la "$DEST"
