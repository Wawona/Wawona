# watchOS / tvOS Scope — Constrained In-Process Shell

**Decision (v2):** The in-process zsh stack (zsh + `wawona-pty` + `wawona-rootfs` +
real `weston-terminal`) now ships across the **entire Apple family**, including
tvOS, watchOS, and visionOS, using the exact same App-Store-compliant model as
iOS/iPadOS (no `fork`/`exec`; zsh runs on a pthread over a fake PTY). watchOS and
tvOS apply a **constrained UX** rather than being excluded outright.

This supersedes the v1 "watchOS excludes the local shell" decision.

---

## What ships per platform

| Platform | zsh / PTY / terminal | coreutils (uutils) | UX |
|----------|----------------------|--------------------|----|
| iOS / iPadOS | Full | Full safe subset | Full terminal |
| visionOS | Full | Full safe subset | Full terminal |
| tvOS | Full | Full safe subset | Constrained (no soft keyboard; focus-engine input) |
| watchOS | Full (size-gated) | **Excluded** (binary-size budget) | Minimal: short sessions, redirect-to-iPhone affordance |

### watchOS coreutils gate

`coreutils` is **not** in the watchOS Rust feature set
(`dependencies/wawona/rust-backend-c2n.nix`): the uutils umbrella pulls too many
crates for the tier-3 size budget. On watchOS the shell therefore exposes zsh
builtins only; the `command_not_found_handler` in
`dependencies/wawona/ios-rootfs.nix` prints the "bundled but unavailable in this
build" message for safe-subset names so the UX stays honest.

---

## Rationale for the constrained (not excluded) approach

| Constraint | Mitigation |
|------------|-----------|
| Screen size (~41–49 mm) | Constrained UX; short interactive sessions; redirect-to-iPhone affordance retained |
| Memory budget | watchOS size-gates coreutils off; zsh + compositor only |
| Input | Soft keyboard where available; tvOS uses focus-engine; redirect string still offered |

---

## Build chain

The whole Apple family reuses the platform-agnostic iOS recipes (they resolve the
SDK/min-version from `iosToolchain` via `apple-mobile-platform.nix`):

- `wwn-toolchain/dependencies/toolchains/common/registry.nix` → `zsh`, `zsh-framework`,
  `wawona-pty`, `wawona-rootfs` point at the iOS recipes for tv/watch/vision.
- `dependencies/wawona/mobile-platform-deps.nix` → the `mobile`/`tv`/`watch`/
  `vision` variants all build the zsh stack.
- `wwn-weston/dependencies/clients/weston/ios.nix` → real `clients/terminal.c` for the whole
  family (no C stub).
- `dependencies/wawona/rust-backend-c2n.nix` → `coreutils` feature on
  iOS/tvOS/visionOS; **off** on watchOS.

---

## App Review

The shell is bundled, runs in-process, executes only first-party MIT-licensed
Rust utilities + zsh builtins, downloads no code, and never forks/execs on the
sandbox (exit-safe via `catch_unwind`). For watchOS, describe the shell as a
constrained companion experience; do not over-claim a full desktop terminal.

Any spawn policy must re-use [SECURITY-SPAWN-POLICY.md](SECURITY-SPAWN-POLICY.md) —
no exceptions.
