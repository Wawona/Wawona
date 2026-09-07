---
name: wawona-priors
description: Index of Wawona agent knowledge already captured in Cursor rules and skills. Use at task start to pick the right rule/skill instead of rediscovering incidents. Pointers only. Do not duplicate rule bodies.
---

# Priors index (pointer only)

Open the named rule/skill. Do not copy the body here. After adding a rule or
skill, add one row. Capture flow: `wawona-learn`.

## Skills (this set)

| Skill | When |
|-------|------|
| `wawona-rag` | Any fact, repo, gate, patch, protocol |
| `wawona-write` | Editing Wawona / wwn-* software |
| `wawona-learn` | Durable finding this session |
| `wawona-caveman` | Token voice |

## Rules (hard gates)

| Rule | When |
|------|------|
| `wawona-mission` | Ambiguous product call |
| `wawona-context` | Stack priors + MCP tool map |
| `wawona-agent-learn` | This learn loop |
| `wawona-rust-first` | New Wawona-owned logic |
| `wawona-repo-dag` | Flake input / registry key |
| `wawona-product-map` | Which product you are touching |
| `wawona-mode-a-b` / `wawona-ios-mode-b-channels` | Store vs TrollStore vs Sileo |
| `wawona-macos-mode-a` / `wawona-macos-no-appstore` | macOS in-window vs SIP |
| `wawona-iland-mode-b-desktop` | Desktop dylib / Take Over |
| `wawona-mode-b-watchdog-safety` | `watchdogd` / IOWatchdog |
| `wawona-compositor-backend` | Aqua nested vs Classic DRM |
| `wawona-nested-compositor-cursor` | Host cursor on niri/weston |
| `wawona-inprocess-cairo` | Nested weston teardown |
| `wawona-native-compositors` / `wawona-port-fidelity` | Weston/Niri; waypipe equivalence |
| `wawona-platform-targets` | Four-state gates |
| `wawona-swinging-bridge` | Not Desktop, not LockScreen |
| `wawona-test-control` / `wawona-agent-device` | UI / vphone |
| `wawona-agent-device-multitouch` | Wayland client taps |
| `wawona-local-before-ci` | Link/eval before push |
| `wawona-branch-workflow` | `development` vs `master` |
| `wawona-asc-swift-support` | ITMS-90426 |
| `wawona-release-assets` | Ship filenames |
| `wawona-no-em-dash` | Copy |
| `wawona-github-funding` / `wawona-discord-github-webhook` | New org repos |
| `wawona-vphone-*` / `wawona-trollstore-*` | Mode B lab / tipa |
| `repo-wawona-io-*` | Dual wasm/deb catalog host (`repo.wawona.io`) |

## Hard-won (do not re-learn)

- `watchdogd` SIGTRAP + armed IOWatchdog = XNU panic. Path B ACK first.
- In-process weston: no `cairo_debug_reset_static_data`.
- Nested compositor draws its own cursor. Hide host overlay.
- Global `DYLD_INSERT_LIBRARIES` kills Apple `arm64e` `/bin/*`. Prefix insert
  on the compositor exec only.
- `launchctl disable` WindowServer is sticky. Missed restore panics login.
- Wayland client taps need Multi-Touch. Touchpad "success" is often a no-op.
- Tipa: bump `CFBundleVersion`. Never install under `/var/jb/Applications` (179).
- Watch-bearing IPA needs `SwiftSupport/`. Watchless tvOS/visionOS must not.
- Prove `ld` locally. Do not burn Gate: products to discover duplicates.
- Port = substitute platform, not client. Waypipe Linux build is the reference.
- Graphics keys live in L1 `wwn-iland`. Never L0 toolchain. Never invert DAG.
- No real `/dev/dri` / kernel DRM. iland userspace only.
- `repo.wawona.io` is two catalogs. Wasm is App Store / Play only. Debs split:
  Sileo iOS jailbreak (rootless/rootful) vs Termux Android sideload (not
  jailbreak, not Play). APT is repo root. `where_to_edit` must not treat the
  hostname as the `wawona.io` website.

Canonical prose: `Wawona/docs/` and `wwn-mcp/knowledge/wawona/`.
