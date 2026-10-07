#!/usr/bin/env bash
# Soft supersede for WIP CI. Exit 0 always.
# Writes GITHUB_OUTPUT: is_tip=true|false, reason=...
#
# Tip (is_tip=true): this commit is the branch tip. Run the real checks.
# Superseded (is_tip=false): a newer commit exists. Skip work; stay green.
#
# Force tip (always run):
#   - workflow_dispatch / schedule / release
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
human=""

if [[ "${WAWONA_CI_FORCE_TIP:-}" == "1" || "$force" -eq 1 ]]; then
  reason="force"
  human="Forced run (manual or operator). Checking this commit."
elif [[ "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" \
    || "${GITHUB_EVENT_NAME:-}" == "schedule" \
    || "${GITHUB_EVENT_NAME:-}" == "release" ]]; then
  reason="event:${GITHUB_EVENT_NAME}"
  human="Manual or scheduled run. Checking this commit."
elif [[ "${GITHUB_EVENT_NAME:-}" == "workflow_call" \
    && -n "${WAWONA_CI_INTENDED_REF:-}" ]]; then
  reason="workflow_call:${WAWONA_CI_INTENDED_REF}"
  human="Called for a specific ref. Checking that commit."
elif [[ -z "${GITHUB_SHA:-}" || -z "${GITHUB_REF_NAME:-}" ]]; then
  reason="missing-sha-or-ref"
  is_tip=true
  human="Could not read commit/branch. Running checks to be safe."
else
  branch="${GITHUB_REF_NAME}"
  if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
    reason="pull_request"
    is_tip=true
    human="Pull request. Running checks on this PR commit."
  else
    git fetch --no-tags --depth=1 origin "$branch" 2>/dev/null || true
    tip="$(git rev-parse "origin/${branch}" 2>/dev/null || true)"
    if [[ -z "$tip" ]]; then
      reason="tip-unresolved"
      is_tip=true
      human="Could not see the latest branch tip. Running checks to be safe."
    elif [[ "$tip" == "$GITHUB_SHA" ]]; then
      reason="branch-tip"
      is_tip=true
      human="This is the latest commit on ${branch}. Run the real checks."
    else
      reason="superseded:tip=${tip:0:7}:sha=${GITHUB_SHA:0:7}"
      is_tip=false
      human="Not the latest commit anymore (newer: ${tip:0:7}). Skipping. This is OK, not a failure."
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
    echo "# Latest commit?"
    echo ""
    if [[ "$is_tip" == "true" ]]; then
      echo "**YES. Run the checks.**"
    else
      echo "**NO. Skipped (not a failure).**"
    fi
    echo ""
    echo "${human}"
    echo ""
    echo "- Branch: \`${GITHUB_REF_NAME:-}\`"
    echo "- This commit: \`${GITHUB_SHA:-}\`"
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [[ "$is_tip" == "true" ]]; then
  echo "Latest commit: YES. ${human}"
else
  echo "Latest commit: NO (skipped). ${human}"
fi

exit 0
