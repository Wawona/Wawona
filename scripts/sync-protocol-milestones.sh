#!/usr/bin/env bash
# Create or update GitHub milestones for the Wayland protocol roadmap.
# Titles must match docs/protocol-milestones.md.
#
# Requires a valid gh token (pass / gh auth). Does not close milestones.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-Wawona/Wawona}"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh not installed" >&2
  exit 1
fi

if ! gh api "repos/$REPO" --jq .full_name >/dev/null 2>&1; then
  echo "error: gh cannot read repos/$REPO (check GH_TOKEN / gh auth login)" >&2
  exit 1
fi

milestones=(
  "Wayland protocols: Explorer catalog honesty|Catalog tracks all Explorer families; Missing rows; portable advertise gates; protocol-status + wawona.io sync."
  "Wayland protocols: close Partials|commit-timing, fifo, gestures, idle-notify, foreign-toplevel list, wlr foreign/virtual-pointer, toplevel icon/tag."
  "Wayland protocols: high-traffic Stubs|session-lock, workspace, data-control, color, screencopy, wlr-output/gamma/power, security-context, tablet, xwayland."
  "Wayland protocols: KDE / Plasma remainder|plasma shell, window management, virtual desktop, screencast, output management/device/order, appmenu, fake-input."
  "Wayland protocols: COSMIC + River|Implement COSMIC and River protocol families to Functional."
  "Wayland protocols: Hyprland + Treeland + Weston|Implement Hyprland, Treeland, and Weston/IVI families to Functional."
  "Wayland protocols: external vendor shells|GTK shell, Aura, AGL, Mir, XApp, NVIDIA EGLStream as demand requires."
  "Wayland protocols: Kani erroneous-check proofs|Every Functional protocol error path has a named helper + fail-closed Kani harness in Verification report."
)

existing="$(gh api "repos/$REPO/milestones?state=all&per_page=100" --jq '.[].title' || true)"

for entry in "${milestones[@]}"; do
  title="${entry%%|*}"
  desc="${entry#*|}"
  if printf '%s\n' "$existing" | grep -Fxq "$title"; then
    number="$(gh api "repos/$REPO/milestones?state=all&per_page=100" \
      --jq ".[] | select(.title==\"$title\") | .number")"
    gh api --method PATCH "repos/$REPO/milestones/$number" \
      -f description="$desc" -f state=open >/dev/null
    echo "updated #$number $title"
  else
    gh api --method POST "repos/$REPO/milestones" \
      -f title="$title" -f description="$desc" -f state=open >/dev/null
    echo "created $title"
  fi
done

echo "Done. See docs/protocol-milestones.md"
