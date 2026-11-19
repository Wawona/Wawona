# Wawona UI five layers

Authority for how Exact chrome, platform hosts, Bend laws, and UI grading
relate. Skill: `wawona-ui-five-layers`. Rubric: `docs/ui-quality/rubric.json`.

## Layers (never collapse)

| Layer | Owns | Does not own |
|-------|------|--------------|
| Exact contract | What the user can do: routes, state, actions, accessible names | Shared layout that forces a tab bar or sidebar look |
| Platform adapter | How the user does it: AppKit, UIKit, Material, Fluent, GTK | Product policy (Rust domain) |
| Native UX guidelines | How it should feel: HIG, Material, Fluent, wear/TV rules | Bend equalities |
| Bend laws | What must never break: nav, phase, decoration force | Pixel parity |
| Computer-use critic | How quality is verified on a running app | Fabricated screenshots or unrun targets marked pass |

Agents may ship interfaces that look nothing like each other on macOS, iOS,
Android, and Windows. Semantic meaning of each action must match. Each
screen is graded against its own platform guidelines.

## Hard rules

1. Contract states catalog, inspector, Settings cover, session open. It does
   not require identical chrome across hosts.
2. No Machines|Settings root tablist. Settings is `openSettings` (gear cover).
3. Wayland surface lives on the session route, not in the inspector.
4. LAW-UX-001 through LAW-UX-010 (native convention supremacy, semantic
   equivalence, visual independence) live in the skill. Bend does not encode
   toolbars or Materials.
5. UI-001 through UI-012 (native first, one primary action, state-driven
   controls, no unexplained empty surfaces, evidence-based completion) are
   engineering invariants. Release gate is 90/100 with no hard-gate failures.
6. An unrun target is a coverage gap. Never report it as passed.
7. Do not add `prove bend` to `verify-all`. Do not emit Bend C.

## Related

`wawona-exact-contract`, `wawona-all-targets`, `wawona-platform-targets`,
`wawona-platform-native-interaction`, `wawona-formal-verification`,
`docs/ui-quality/`. Shared functionality; native interaction paradigms per host.
