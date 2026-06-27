# App Store–Compliant Local Shell on Apple Mobile

**Wawona is building the world's first App Store–compliant, bundled, native ARM64 Z shell on iOS and iPadOS** — not a remote SSH passthrough, not an x86 Linux guest, not a dylib-only command table. A real `zsh` binary, cross-compiled with Nix, executed inside the app sandbox through a dedicated PTY layer, driving upstream Weston `clients/terminal.c`.

This directory is the **authoritative documentation** for that program. If you change spawn policy, rootfs layout, Nix packages, or App Review posture, update these docs in the same PR.

> **Note (repo split):** the zsh Nix recipes, `patch-zsh-exec.py`, the Wawona
> RootFS recipe, and the `verify-zsh-ios-patches.py` patch-anchor check now live
> in the **[`wwn-zsh`](https://github.com/Wawona/wwn-zsh)** repo; the patched
> Weston terminal/compositor recipes live in
> **[`wwn-weston`](https://github.com/Wawona/wwn-weston)**. Wawona consumes both
> as flake inputs. Edit the recipes/patches there, not under Wawona's
> `dependencies/`. (Some text below references the older in-tree
> `dependencies/libs/zsh` / `dependencies/clients/weston` paths and a
> `posix_spawn` model — the current design is in-process, no fork/exec; trust the
> `wwn-zsh` recipes and `.cursor/rules/wawona-context.mdc`.)

---

## Why this exists

| What exists today on iOS | What Wawona is building |
|--------------------------|-------------------------|
| Remote shells (Blink, Prompt, Termius) | **Local** interactive shell |
| Command tables as signed dylibs (a-Shell) | **Full zsh** with scripts, completion, history |
| x86 Linux usermode + Alpine (iSH) | **Native ARM64** static binary, no guest JIT |
| Fake SHM terminal window (`mobile-weston-terminal.c`) | **Real** cairo/toytoolkit `terminal.c` |
| "iOS can't fork" accepted as law | **Prove** `posix_openpt` + `posix_spawn` on device (Phase 0) |

macOS is **out of scope** for this track — it already uses Meson `weston/macos.nix` with `forkpty`. watchOS is **stub-only** in v1.

---

## Document map

| Doc | Audience | Contents |
|-----|----------|----------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Engineers | End-to-end data flow, process model, separation of concerns |
| [APP-STORE-COMPLIANCE.md](APP-STORE-COMPLIANCE.md) | Legal, PM, Review | Guideline mapping, competitive landscape, allowed vs forbidden |
| [IMPLEMENTATION-ROADMAP.md](IMPLEMENTATION-ROADMAP.md) | Engineers, PM | Phases 0–4, PR sequence, exit criteria, risks |
| [WAWONA-PTY-SPEC.md](WAWONA-PTY-SPEC.md) | C/Rust engineers | `wwn_pty_*` API contract, errno policy, spawn rules |
| [ROOTFS-AND-ZSH.md](ROOTFS-AND-ZSH.md) | Nix maintainers | `zsh-ios`, rootfs layout, flake outputs, env vars |
| [SECURITY-SPAWN-POLICY.md](SECURITY-SPAWN-POLICY.md) | Security, Review | Path lock, no post-review exec, teardown |
| [APP-REVIEW-NOTES.md](APP-REVIEW-NOTES.md) | App Review | Copy-paste reviewer explanation |
| [TESTFLIGHT-CHECKLIST.md](TESTFLIGHT-CHECKLIST.md) | QA | Device/simulator smoke before external testers |
| [WATCHOS-SCOPE.md](WATCHOS-SCOPE.md) | PM, engineers | Explicit non-goals for watch |
| [../ios-local-shell-spike.md](../ios-local-shell-spike.md) | Spike owner | Phase 0 device report template (fill after hardware test) |

---

## Related repo docs

| Path | Relationship |
|------|--------------|
| [../compliance/policy-traceability.md](../compliance/policy-traceability.md) | Capability → store-safe class mapping (includes local shell row) |
| [../testing/everywhere-matrix.md](../testing/everywhere-matrix.md) | CI targets + manual smoke for terminal/zsh |
| [../../dependencies/clients/weston/ios.nix](../../dependencies/clients/weston/ios.nix) | Current mobile Weston client build (SHM stub today) |
| [../../dependencies/clients/weston/compositor-apple-mobile.nix](../../dependencies/clients/weston/compositor-apple-mobile.nix) | Compositor `fork()` stub — **not** used for shell spawn |
| [../../src/platform/macos/ui/Settings/WWNWaypipeRunner.m](../../src/platform/macos/ui/Settings/WWNWaypipeRunner.m) | In-process client launch + env wiring |

---

## Flake outputs (planned / in progress)

| Output | Purpose |
|--------|---------|
| `.#zsh-ios` | Static `zsh` for `aarch64-apple-ios` |
| `.#zsh-ios-sim` | Simulator slice |
| `.#wawona-rootfs-ios` | Bundled `/usr/bin`, share files, `.zshrc` template |
| `.#wawona-pty-ios` | `libwwn-pty.a` PTY + spawn layer |
| `.#wawona-pty-spike-ios` | Phase 0 harness binary |
| `.#weston-ios` | Includes real `weston-terminal` (after Phase 1) |

---

## Guiding principles

1. **Bundled-only execution** — every byte of native code the shell runs was in the signed app bundle at review time.
2. **Spawn layer is the gate** — `wwn_pty_spawn_shell()` rejects paths outside the rootfs allowlist; compositor `fork()` stubs stay untouched.
3. **Phase 0 gates Phase 2** — no production shell integration until device PTY spike passes or documents an approved fallback.
4. **Document every assumption** — especially what iOS allows vs what man pages claim.
5. **macOS unchanged** — do not regress desktop `forkpty` paths while porting mobile.

---

## Status (2026-06)

| Phase | Status | Notes |
|-------|--------|-------|
| 0 — PTY + zsh spike | **Not started** | See spike template |
| 1 — Real `terminal.c` UI | **Not started** | SHM stub still in `ios.nix` |
| 2 — `wawona-pty` + rootfs | **Not started** | Spec written in this doc set |
| 3 — Compliance + TestFlight | **In progress (docs)** | This directory |
| 4 — Ecosystem polish | **Future** | foot, extra rootfs tools |

Master plan (Cursor): `.cursor/plans/ios_weston_terminal_zsh_b55c5cd8.plan.md`
