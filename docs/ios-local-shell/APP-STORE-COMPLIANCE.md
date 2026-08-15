# App Store Compliance Model: Bundled Native ZSH

This document explains **why** Wawona's local shell is App Store–compliant, **how** it differs from rejected or risky patterns, and **which Apple guidelines** apply. It is written for engineers, product, and App Review.

**Claim we are making:** Wawona ships a **fixed set of native ARM64 code** (in-process `wawona_zsh_main`, uutils, clients) inside the signed app. Apple mobile never `fork`/`exec`s user Mach-O. User-provided **WebAssembly** is a document interpreted by a **Pulley** engine linked at review time — not JIT, not unsigned native code. See [wasm-wasi.md](../wasm-wasi.md).

---

## Guideline mapping (Apple App Store Review Guidelines)

Interpretations below are Wawona's **engineering compliance posture**, not legal advice. Final authority is Apple Review.

| Guideline area | Relevant concern | Wawona stance | Evidence |
|----------------|------------------|---------------|----------|
| **2.5.2** Software requirements | Private APIs, unstable behavior | Public POSIX: `posix_openpt`, `posix_spawn`, `openpty` ([documented for iPhoneOS](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_openpt.3.html)) | Phase 0 spike + code in `wawona-pty` |
| **2.5.2** | Downloading executable code | **No** post-review native download | Spawn path rejects non-rootfs binaries; waypipe guards unchanged |
| **2.5.2** | JIT / dynamic codegen | **No** native JIT / `MAP_JIT` | Pulley interpreter for `.wasm` documents; no iSH-style CPU emulator |
| **4.2 Minimum functionality** | Must be more than a shell | Wayland compositor + nested Weston + dev workflows | Core app purpose documented in Review notes |
| **5.1 Data collection** | Terminal input / files | Local-only in app container; disclose in Privacy Nutrition Label | [APP-REVIEW-NOTES.md](APP-REVIEW-NOTES.md) |
| **5.2 Intellectual property** | GPL/LGPL components | zsh (Zlib-like), Weston (MIT); see [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md) | License section in app |

---

## Exposure class (Wawona internal)

Aligned with [policy-traceability.md](../compliance/policy-traceability.md):

| Capability | Class | Store-safe? |
|------------|-------|-------------|
| Local bundled zsh via PTY | `store-safe-conditional` | Yes, with path lock + disclosure |
| Remote SSH shell (waypipe) | `store-safe-remote` | Yes (existing) |
| Post-review binary download + exec | **forbidden** | Never |
| x86 usermode / Alpine guest (iSH model) | **out of scope** | Not pursuing |
| ios_system dylib command table | **different model** | We ship full zsh binary instead |
| Compositor virtual keyboard/pointer abuse | `desktop-only` | Disabled in store-safe profile |

Rust profile: `profile-store-safe` on iOS release builds. Local shell feature flag must not enable `desktop-only` protocols.

---

## Competitive landscape (App Store terminals)

| App | App Store | Local shell? | Mechanism | zsh? |
|-----|-----------|--------------|-----------|------|
| [a-Shell](https://github.com/holzschu/a-Shell) | Yes | Partial | [ios_system](https://github.com/holzschu/ios_system): commands as **signed dylibs**, `ios_execv` in-process | **No** — author lists shells as hard |
| [Blink Shell](https://github.com/blinksh/blink) | Yes | Utilities only | Local tools + **remote** Mosh/SSH TTY | Remote only |
| [iSH](https://github.com/ish-app/ish) | Yes (historical friction) | Linux userland | x86 emulation + Alpine; full zsh **inside guest** | Yes, inside emulated Linux |
| Prompt / Termius / Geistty | Yes | No | SSH passthrough | Remote only |
| **Wawona (target)** | Target | **Yes** | Native ARM64 static zsh + PTY + Weston terminal UI | **Yes, native** |

**Wawona's differentiation:** Full interactive **zsh** (not a curated command list), native ARM64 (not x86 guest), integrated with a **real Wayland terminal emulator** (Weston `terminal.c`), built reproducibly with **Nix** and path-locked spawn policy.

---

## Compliance patterns we adopt

### From a-Shell (approved)

- All executable code present at review time in the signed bundle
- No arbitrary download-and-exec of native binaries
- Sandboxed file access limited to app container + user-granted imports

### From iSH (approved, heavy)

- Bundled userland concept (we use rootfs, not full Linux)
- **We explicitly reject** x86 JIT / interpreter attack surface

### From Blink (approved)

- Clear product positioning: developer tool
- Remote shell as optional parallel path (`store-safe-remote`)

---

## Compliance patterns we reject

| Pattern | Reason |
|---------|--------|
| Downloading `curl \| sh` scripts that fetch Mach-O | Post-review native code |
| `dlopen` of user-provided dylibs | Unsigned code execution |
| Cranelift / `MAP_JIT` on Apple mobile | Native codegen of downloaded code |
| Interpreting user `.wasm` with Pulley (signed-in-bundle engine) | **Allowed** — same class as JS in JavaScriptCore; see [wasm-wasi.md](../wasm-wasi.md) |
| Spawning `/bin/sh` from host filesystem | Outside sandbox; not in bundle |
| Spawning from `/tmp` or cache after extract | Effectively post-review if content is mutable |
| Enabling compositor `fork()` for clients | Breaks mobile stub model; use client-side spawn only |

---

## ios_system author on shells

From [ios_system README](https://github.com/holzschu/ios_system):

> Shells are hard to compile… take a lot of memory.

We accept that cost deliberately. Cross-compiling zsh via Nix with stripped features is Phase 2 work; if size exceeds budget, document `--disable-*` and optional `dash` fallback **without** changing the compliance model (still bundled binary).

---

## Privacy and user disclosure

| Data | Stored where | Leaves device? |
|------|--------------|----------------|
| Terminal keystrokes | App memory → PTY → zsh | Only if user runs network commands |
| `.zsh_history` | `Application Support/wawona-rootfs/home/` | No by default |
| Files created by shell | App container | Only via explicit share sheet / iCloud if user opts in |

App Privacy label: **User Content** (terminal input) processed on-device. No analytics on command text.

Optional Settings toggle: **Enable local shell** (default on for internal builds; product decision for release).

---

## Enforcement architecture

Compliance is not policy PDFs alone — it is **code enforcement**:

1. **`wwn_pty_spawn_shell()`** — rejects `shell_path` not under `WAWONA_ROOTFS` prefix (see [SECURITY-SPAWN-POLICY.md](SECURITY-SPAWN-POLICY.md))
2. **Nix rootfs** — only known binaries installed into `wawona-rootfs`
3. **No `exec*` from ObjC download handlers** — existing waypipe policy unchanged
4. **Cargo feature gates** — `profile-store-safe` excludes desktop-only Wayland globals
5. **CI** — `.#zsh-ios`, `.#weston-ios` build on merge

---

## Review narrative (short)

> Wawona is a developer tool that runs a Wayland compositor on iOS. The terminal window uses the open-source Weston terminal emulator. The shell is **zsh**, statically linked and run **in-process** (`wawona_zsh_main` on a pthread) — there is no `fork`/`exec` of a zsh Mach-O. Optional user `.wasm` files are **documents** interpreted by a Pulley engine linked into the reviewed binary (no JIT, no unsigned native code). Remote administration via SSH is optional and uses the same approach as other App Store terminal apps.

Full reviewer copy: [APP-REVIEW-NOTES.md](APP-REVIEW-NOTES.md).

---

## Open validation items

In-process zsh + PTY is the shipping model (see [ARCHITECTURE.md](ARCHITECTURE.md)). Remaining checks:

- [ ] `help` / `ls $WAWONA_ROOTFS/usr/bin` / `ls` / `phoon` on device
- [ ] User `.wasm` via Files / File Sharing → `wasm ./tool.wasm hello` (Pulley)
- [ ] Background / jetsam behavior when the shell thread runs
- [ ] Confirm no `MAP_JIT` / Cranelift native in the iphoneos slice (`verify-wasm-ios-patches.py`)

See [../wasm-wasi.md](../wasm-wasi.md).
