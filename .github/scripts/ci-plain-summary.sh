#!/usr/bin/env bash
# Tiny helpers for dumb-simple GitHub Actions summaries.
# Usage:
#   source .github/scripts/ci-plain-summary.sh
#   ci_summary_title "Products"
#   ci_summary_line "PASS" "iOS built"
#   ci_summary_verdict "PASS" "Safe to promote this tip."
set -euo pipefail

ci_summary_title() {
  local title="$1"
  {
    echo "# ${title}"
    echo ""
  } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# status: PASS | FAIL | SKIP | WAIT
ci_summary_line() {
  local status="$1"
  local text="$2"
  local mark
  case "$status" in
    PASS) mark="PASS" ;;
    FAIL) mark="FAIL" ;;
    SKIP) mark="SKIP" ;;
    *) mark="$status" ;;
  esac
  echo "- **${mark}** — ${text}" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

ci_summary_verdict() {
  local status="$1"
  local text="$2"
  {
    echo ""
    echo "## Verdict"
    echo ""
    echo "**${status}:** ${text}"
    echo ""
  } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# Map GitHub job result → PASS/FAIL/SKIP
ci_result_word() {
  case "${1:-}" in
    success) echo PASS ;;
    failure) echo FAIL ;;
    cancelled) echo FAIL ;;
    skipped) echo SKIP ;;
    *) echo "${1:-UNKNOWN}" ;;
  esac
}
