# watchOS / tvOS Scope. Constrained In-Process Shell

**Decision (v2):** The in-process zsh stack (zsh + `wawona-pty` + `wawona-rootfs` +
real `weston-terminal`) ships across the **entire Apple family**, including
tvOS, watchOS, and visionOS, using the same App-Store-compliant model as
iOS/iPadOS (no `fork`/`exec`; zsh runs on a pthread over a fake PTY). watchOS and
tvOS apply a **constrained UX** rather than excluding the shell.

This supersedes the v1 "watchOS excludes the local shell" decision.

---

## What ships per platform

| Platform | zsh / PTY / terminal | coreutils (uutils) | Relay Wasm | UX |
|----------|----------------------|--------------------|------------|----|
| iOS / iPadOS | Full | Full safe subset | Pulley | Full terminal |
| visionOS | Full | Full safe subset | Pulley | Full terminal |
| tvOS | Full | Full safe subset | Pulley | Constrained (no soft keyboard; focus-engine input) |
| watchOS | Full | Full safe subset (arm64) | Pulley (mandatory) | Minimal: short sessions, redirect-to-iPhone affordance |

### watchOS coreutils (required)

`coreutils` is **on** for every product Apple backend, including watchOS
(`dependencies/wawona/rust-backend-c2n.nix`: `waypipe-ssh`, `smithay-protocols`,
`coreutils`). Same in-process safe subset as iOS. Link pulls
`wawona_coreutils_main` with `-Wl,-u,_wawona_coreutils_main`.

Exception: the **arm64_32** Watch slice does not link `libwawona.a` (Nix
archives are arm64 LP64). `WWNWatchStubs.c` provides a weak
`wawona_coreutils_main` only under `!__LP64__`. Do **not** add a weak
coreutils stub on arm64. That would satisfy `-u` and drop real uutils.

Older docs that said "watchOS size-gates coreutils off" are **superseded**.
Wasm on watchOS is also mandatory (`wawona-relay-wasm`); never equate the two.

---

## Rationale for the constrained (not excluded) approach

| Constraint | Mitigation |
|------------|-----------|
| Screen size (~41-49 mm) | Constrained UX; short interactive sessions; redirect-to-iPhone affordance retained |
| Memory / IPA size | Keep the safe subset; do not drop uutils or wasm to green a size gate |
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
  iOS/tvOS/visionOS/**watchOS**.

---

## App Review

The shell is bundled, runs in-process, executes only first-party MIT-licensed
Rust utilities + zsh builtins, downloads no code, and never forks/execs on the
sandbox (exit-safe via `catch_unwind`). For watchOS, describe the shell as a
constrained companion experience; do not over-claim a full desktop terminal.

Any spawn policy must re-use [SECURITY-SPAWN-POLICY.md](SECURITY-SPAWN-POLICY.md).
No exceptions.

---

## Present (SpriteKit)

Watch clients still commit **SHM** (`CGImage` in `WWNWatchCompositorBridge`).
The session surface GPU-composites those frames with SpriteKit
(`WatchSpritePresentView`, 30 fps cap, paused when the scene is not active).
That is **not** GLES/Vulkan. `gpuStackGate` stays blocked until the watchOS
SDK ships public Metal. `WWN_WATCHOS_METAL=1` is research only and never in
the store Watch IPA. `WWN_WATCH_SK_PRESENT=0` restores the CPU `Image` blit.
