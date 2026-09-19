# Agent / Cursor rules (tracked mirrors)

Wawona’s live Cursor rules live under `.cursor/rules/` and the multi-repo
workspace under `~/Wawona/.cursor/rules/`. The IDE directory is generally
gitignored; organization-wide rules may be force-tracked so they travel with
clones. This folder still holds **tracked mirrors** so CI and agents without
local IDE state see the same non-negotiable gates.

| Rule | Topic |
|------|--------|
| [wawona-iland-mode-b-desktop.md](./wawona-iland-mode-b-desktop.md) | Mode A vs Mode B, SIP Desktop Replacement, dylib shipping |
| [wawona-swiftui-backports.md](./wawona-swiftui-backports.md) | Organization-wide Swift/SwiftUI availability shims and older-OS fallbacks |
| Canonical prose | [`../iland-mode-a-b-desktop.md`](../iland-mode-a-b-desktop.md) |
| Entry AGENTS | [`../../AGENTS.md`](../../AGENTS.md) |

When editing policy, update **all** of: workspace `.cursor/rules/`,
`Wawona/.cursor/rules/` (local), this mirror, and `AGENTS.md`.
