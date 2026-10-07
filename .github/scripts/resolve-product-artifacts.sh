#!/usr/bin/env bash
# Resolve GHA artifacts produced by product-build.yml for a git SHA.
#
# Usage:
#   resolve-product-artifacts.sh <sha> <artifact-name> <dest-dir> [wait-seconds]
#
# Finds a successful product run for the commit that uploaded the named
# artifact. Gate: products and Ship call thin product-*.yml workflows (artifacts
# land on the parent run). Waits if still in progress (default 5400s).
#
# Fail-fast: if no in-progress/queued producer exists after an initial grace
# window (~120s), exit 1 immediately instead of spinning until deadline.
# Prefer owning the product workflow via workflow_call (see release.yml).
set -euo pipefail

SHA="${1:?usage: $0 <sha> <artifact-name> <dest-dir> [wait-seconds]}"
ARTIFACT="${2:?}"
DEST="${3:?}"
WAIT_SECS="${4:-5400}"
REPO="${GITHUB_REPOSITORY:-Wawona/Wawona}"
# Parent runs that upload product-* artifacts (thin slices + legacy dispatcher).
WORKFLOWS=(
  "device-gate.yml"
  "release.yml"
  "product-build.yml"
  "product-ios-sim.yml"
  "product-android-apk.yml"
  "product-macos-app.yml"
  "product-appimage.yml"
  "product-apple-family.yml"
  "product-ios-modeb.yml"
)
# Allow a short window for a sibling workflow_call to appear in the API.
GRACE_SECS="${RESOLVE_PRODUCT_GRACE_SECS:-120}"

if ! command -v gh >/dev/null; then
  echo "error: gh CLI required" >&2
  exit 1
fi

mkdir -p "$DEST"
deadline=$((SECONDS + WAIT_SECS))
started=$SECONDS

run_has_artifact() {
  local id="$1"
  gh api "repos/$REPO/actions/runs/$id/artifacts" --jq \
    --arg name "$ARTIFACT" \
    '[.artifacts[] | select(.name == $name and .expired == false)] | length > 0' 2>/dev/null \
    | grep -q true
}

# Prefer a completed successful run that actually uploaded $ARTIFACT.
find_run_with_artifact() {
  local wf ids id
  for wf in "${WORKFLOWS[@]}"; do
    ids="$(gh run list --repo "$REPO" --workflow "$wf" --commit "$SHA" --limit 30 \
      --json databaseId,status,conclusion \
      --jq '[.[] | select(.status=="completed" and .conclusion=="success")] | .[].databaseId' 2>/dev/null || true)"
    for id in $ids; do
      if run_has_artifact "$id"; then
        echo "$id"
        return 0
      fi
    done
  done
  return 1
}

find_in_progress() {
  local wf id
  for wf in "${WORKFLOWS[@]}"; do
    id="$(gh run list --repo "$REPO" --workflow "$wf" --commit "$SHA" --limit 20 \
      --json databaseId,status \
      --jq '[.[] | select(.status=="in_progress" or .status=="queued")] | .[0].databaseId // empty' 2>/dev/null || true)"
    if [[ -n "$id" ]]; then
      echo "$id"
      return 0
    fi
  done
  return 1
}

run_id=""
while (( SECONDS < deadline )); do
  run_id="$(find_run_with_artifact || true)"
  if [[ -n "$run_id" ]]; then
    break
  fi
  pending="$(find_in_progress || true)"
  if [[ -n "$pending" ]]; then
    echo "== product run $pending still running for $SHA; waiting for artifact $ARTIFACT =="
    sleep 30
    continue
  fi

  elapsed=$((SECONDS - started))
  if (( elapsed >= GRACE_SECS )); then
    echo "error: no in-progress product producer for sha=$SHA after ${GRACE_SECS}s grace; " \
      "refusing to wait ${WAIT_SECS}s (artifact=$ARTIFACT). " \
      "Call a product-*.yml (or device-gate.yml) from the consumer workflow instead." >&2
    exit 1
  fi

  echo "== no product run with $ARTIFACT for $SHA yet; grace ${elapsed}s/${GRACE_SECS}s =="
  sleep 15
done

if [[ -z "$run_id" ]]; then
  echo "error: no successful product run with artifact=$ARTIFACT for sha=$SHA within ${WAIT_SECS}s" >&2
  exit 1
fi

echo "== downloading $ARTIFACT from run $run_id into $DEST =="
gh run download "$run_id" --repo "$REPO" --name "$ARTIFACT" --dir "$DEST"
ls -la "$DEST"
