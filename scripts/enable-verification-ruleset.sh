#!/usr/bin/env bash
# Enable a development branch ruleset that requires "Verification report".
# Usage: scripts/enable-verification-ruleset.sh [owner/repo]
set -euo pipefail
REPO="${1:-Wawona/Wawona}"
tmp="$(mktemp)"
jq -n '{
  name: "Verification report required",
  target: "branch",
  enforcement: "active",
  conditions: { ref_name: { include: ["refs/heads/development"], exclude: [] } },
  rules: [
    {
      type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: false,
        do_not_enforce_on_create: true,
        required_status_checks: [
          { context: "Verification report" }
        ]
      }
    }
  ],
  bypass_actors: [
    { actor_id: 1, actor_type: "OrganizationAdmin", bypass_mode: "always" }
  ]
}' >"$tmp"
if id=$(gh api "repos/$REPO/rulesets" --jq '.[] | select(.name=="Verification report required") | .id' | head -1); then
  if [[ -n "$id" ]]; then
    gh api "repos/$REPO/rulesets/$id" --method PUT --input "$tmp"
    echo "updated ruleset $id on $REPO"
    exit 0
  fi
fi
gh api "repos/$REPO/rulesets" --method POST --input "$tmp"
echo "created ruleset on $REPO"
