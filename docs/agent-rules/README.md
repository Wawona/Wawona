# Agent / Cursor rules (tracked mirrors)

Wawona’s live Cursor rules live under `.cursor/rules/` (gitignored IDE dir) and
the multi-repo workspace under `~/Wawona/.cursor/rules/`. This folder holds
**tracked mirrors** so clones, CI, and agents without local IDE state still see
the same non-negotiable gates.

| Rule | Topic |
|------|--------|
| [wawona-android-jbr.md](./wawona-android-jbr.md) | Android Gradle / Studio use JBR 21, not nixpkgs OpenJDK |
| [wawona-agent-learn.md](./wawona-agent-learn.md) | RAG + skills + capture loop. Software must improve on prior knowledge. Caveman-lite |
| [wawona-guest-wayland-iland.md](./wawona-guest-wayland-iland.md) | Linux guests are Wayland into Wawona (iland), never UTM Spice/ANGLE/virgl |
| [wawona-linux-vms-relay-runtime.md](./wawona-linux-vms-relay-runtime.md) | NixOS-only VMs; Mode A = Wawona store runtime; Mode B adds Mode B runtime |
| [wawona-relay-wasm.md](./wawona-relay-wasm.md) | Relay Wasm on every product target including watchOS |
| [wawona-ios-min-os.md](./wawona-ios-min-os.md) | iOS 11.0 min OS vs latest iPhoneOS SDK; one ANGLE, one MoltenVK |
| [wawona-gh.md](./wawona-gh.md) | `gh` via Shell. No GitHub MCP. Authorship ban is not a `gh` ban |
| [wawona-macos-mode-a.md](./wawona-macos-mode-a.md) | macOS Mode A always works with SIP on (in-window iland DRM) |
| [wawona-compositor-backend.md](./wawona-compositor-backend.md) | macOS weston/niri nest in Aqua; iland DRM after Classic (WindowServer down) |
| [wawona-nested-compositor-cursor.md](./wawona-nested-compositor-cursor.md) | Nested/iland compositors hide+grab host cursor; they draw their own. iOS Touchpad overlay stays off |
| [wawona-inprocess-cairo.md](./wawona-inprocess-cairo.md) | Apple mobile + Android weston must not cairo_debug_reset_static_data on nested teardown |
| [wawona-mode-b-watchdog-safety.md](./wawona-mode-b-watchdog-safety.md) | Never Take Over / LLDB-attach `watchdogd` (macOS 26 SIGTRAP panic) |
| [wawona-vphone-control.md](./wawona-vphone-control.md) | Jailbroken vphone lab bring-up + agent-device session control |
| [wawona-trollstore-tipa-iteration.md](./wawona-trollstore-tipa-iteration.md) | Tipa build vs marketing version; install/open-jit test loop |
| [wawona-vphone-mode-b-packages.md](./wawona-vphone-mode-b-packages.md) | packages tipa/apt/debug channels (never conflate Mode A) |
| [wawona-vphone-lldb.md](./wawona-vphone-lldb.md) | packages debug attach → user-lldb; deny-list watchdogd |
| [wawona-swinging-bridge.md](./wawona-swinging-bridge.md) | Wawona Swinging Bridge Mode A/B (not Desktop) |
| [wawona-product-map.md](./wawona-product-map.md) | Swinging Bridge / Desktop / VMs / containers / Runtime packages |
| [wawona-rust-first.md](./wawona-rust-first.md) | Wawona-owned code is Rust; C only as FFI/JNI/UI glue |
| [wawona-settings-dependencies.md](./wawona-settings-dependencies.md) | Settings Dependencies list only this product's linked packages |
| [wawona-github-funding.md](./wawona-github-funding.md) | GitHub Sponsors FUNDING.yml on every `github.com/Wawona` repo |
| Canonical prose | [`../iland-mode-a-b-desktop.md`](../iland-mode-a-b-desktop.md) |
| Entry AGENTS | [`../../AGENTS.md`](../../AGENTS.md) |

When editing policy, update **all** of: workspace `.cursor/rules/`,
`Wawona/.cursor/rules/` (local), this mirror, and `AGENTS.md`.

Skills (workflows, not hard gates): [`../agent-skills/`](../agent-skills/).
Learn loop: `wawona-agent-learn`. Always query wwn-mcp first.

- `wawona-trollstore-tipa-dev.md` — TrollStore tipa vs Sileo deb; JIT/ldid/IOMFB; nix+agent-device+vphone loop
