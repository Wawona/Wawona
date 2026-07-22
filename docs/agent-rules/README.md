# Agent / Cursor rules (tracked mirrors)

Wawona’s live Cursor rules live under `.cursor/rules/` (gitignored IDE dir) and
the multi-repo workspace under `~/Wawona/.cursor/rules/`. This folder holds
**tracked mirrors** so clones, CI, and agents without local IDE state still see
the same non-negotiable gates.

| Rule | Topic |
|------|--------|
| [wawona-iland-mode-b-desktop.md](./wawona-iland-mode-b-desktop.md) | Mode A vs Mode B, SIP Desktop Replacement, dylib shipping |
| Canonical prose | [`../iland-mode-a-b-desktop.md`](../iland-mode-a-b-desktop.md) |
| Entry AGENTS | [`../../AGENTS.md`](../../AGENTS.md) |

When editing policy, update **all** of: workspace `.cursor/rules/`,
`Wawona/.cursor/rules/` (local), this mirror, and `AGENTS.md`.
