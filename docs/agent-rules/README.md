# Agent / Cursor rules (tracked mirrors)

Wawona’s live Cursor rules live under `.cursor/rules/` (gitignored IDE dir) and
the multi-repo workspace under `~/Wawona/.cursor/rules/`. This folder holds
**tracked mirrors** so clones, CI, and agents without local IDE state still see
the same non-negotiable gates.

| Rule | Topic |
|------|--------|
| [wawona-iland-mode-b-desktop.md](./wawona-iland-mode-b-desktop.md) | Mode A vs Mode B, SIP Desktop/LockScreen, dylib shipping |
| [wawona-mode-b-watchdog-safety.md](./wawona-mode-b-watchdog-safety.md) | Never Take Over / LLDB-attach `watchdogd` (macOS 26 SIGTRAP panic) |
| [wawona-swinging-bridge.md](./wawona-swinging-bridge.md) | Wawona Swinging Bridge Mode A/B (not Desktop) |
| [wawona-product-map.md](./wawona-product-map.md) | Swinging Bridge / Desktop / VMs / containers / Runtime packages |
| [wawona-product-integration.md](./wawona-product-integration.md) | L4 gates + store firewall |
| [wawona-release-assets.md](./wawona-release-assets.md) | GitHub + store binary filenames (CalVer / platform / arch) |
| Canonical prose | [`../iland-mode-a-b-desktop.md`](../iland-mode-a-b-desktop.md) |
| Entry AGENTS | [`../../AGENTS.md`](../../AGENTS.md) |

When editing policy, update **all** of: workspace `.cursor/rules/`,
`Wawona/.cursor/rules/` (local), this mirror, and `AGENTS.md`.
