---
name: wawona-ui-five-layers
description: >-
  Permanent UI engineering directive: Exact contract, platform adapter, native
  guidelines, Bend laws, computer-use critic. Use before Exact chrome edits,
  UI grading, or autonomous UI loops.
---

# UI five layers

Rule: `wawona-ui-five-layers`. Rubric: `Wawona/docs/ui-quality/rubric.json`.
Contract skill: `wawona-exact-contract`. Exact craft gate:
`wawona-exact-ui-design` (loads `frontend-design` / `impeccable` / `better-*`;
Contract no-tells still wins).

## Share semantics, not appearance

| Layer | Question |
|-------|----------|
| Exact contract | What can the user do? |
| Platform adapter | How do they do it here? |
| Native guidelines | How should it feel here? |
| Bend laws | What must never break? |
| Computer-use critic | Did the running app prove it? |

Different-looking macOS / iOS / Android / Windows UIs are allowed when
actions keep the same meaning and each screen meets that platform's UX rules.

## LAW-UX (guidelines, not Bend)

1. Native convention supremacy.
2. Semantic equivalence, visual independence.
3. Prefer native components.
4. Platform-specific navigation (sidebar, stack, rail, NavigationView).
5. Native input modalities.
6. Native accessibility.
7. Adaptive layout per device class.
8. Contract and renderer separation.
9. Grade each platform against itself.
10. Autonomously improve native UX without forcing one visual design.

## UI invariants (UI-001..012)

Native first. One primary action. State-driven controls. Semantic labels.
No unexplained empty surfaces. Stable layout. Progressive disclosure.
Functional verification on a running app. Cross-platform semantic parity.
Accessibility by default. Regression prevention. Evidence-based completion.

Release quality: every tested screen >= 90/100 and no hard-gate failures.
Unrun targets are gaps.

## Loop

Discover → build → explore (computer use) → observe → grade → diagnose →
plan → implement → verify → compare → repeat. Contract change preferred
when many targets share the defect. Adapter change when only native chrome
differs.

## Hard rejects

- Machines|Settings root tablist
- Wayland surface in the inspector
- Claiming pass without runtime interaction
- Pixel parity as the universal bar
