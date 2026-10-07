#!/usr/bin/env bash
# Soft supersede for WIP CI. Exit 0 always.
# Writes GITHUB_OUTPUT: is_tip=true|false, reason=...
#
# Tip (is_tip=true): caller runs the full job matrix.
# Superseded (is_tip=false): caller skips expensive work; workflow stays green.
#
# Force tip (no supersede):
#   - workflow_dispatch / schedule / release events
#   - WAWONA_CI_FORCE_TIP=1
#   - --force
set -euo pipefail

force=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
  esac
done

reason=""
is_tip=true

if [[ "${WAWONA_CI_FORCE_TIP:-}" == "1" || "$force" -eq 1 ]]; then
  reason="force"
elif [[ "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" \
    || "${GITHUB_EVENT_NAME:-}" == "schedule" \
    || "${GITHUB_EVENT_NAME:-}" == "release" ]]; then
  reason="event:${GITHUB_EVENT_NAME}"
elif [[ "${GITHUB_EVENT_NAME:-}" == "workflow_call" \
    && -n "${WAWONA_CI_INTENDED_REF:-}" ]]; then
  # Caller asked for an explicit ref (nightly / operator). Do not supersede.
  reason="workflow_call:${WAWONA_CI_INTENDED_REF}"
elif [[ -z "${GITHUB_SHA:-}" || -z "${GITHUB_REF_NAME:-}" ]]; then
  reason="missing-sha-or-ref"
  is_tip=true
else
  branch="${GITHUB_REF_NAME}"
  # pull_request: compare against the PR head SHA already checked out; tip of
  # the base branch is not the right signal. Always run.
  if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
    reason="pull_request"
    is_tip=true
  else
    git fetch --no-tags --depth=1 origin "$branch" 2>/dev/null || true
    tip="$(git rev-parse "origin/${branch}" 2>/dev/null || true)"
    if [[ -z "$tip" ]]; then
      reason="tip-unresolved"
      is_tip=true
    elif [[ "$tip" == "$GITHUB_SHA" ]]; then
      reason="branch-tip"
      is_tip=true
    else
      reason="superseded:tip=${tip:0:7}:sha=${GITHUB_SHA:0:7}"
      is_tip=false
    fi
  fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "is_tip=${is_tip}"
    echo "reason=${reason}"
  } >>"$GITHUB_OUTPUT"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### CI tip gate"
    echo "- is_tip: \`${is_tip}\`"
    echo "- reason: \`${reason}\`"
    echo "- sha: \`${GITHUB_SHA:-}\`"
    echo "- ref: \`${GITHUB_REF_NAME:-}\`"
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [[ "$is_tip" == "true" ]]; then
  echo "ci-require-branch-tip: continue (reason=${reason})"
else
  echo "ci-require-branch-tip: superseded (reason=${reason})"
fi

exit 0
