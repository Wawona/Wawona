# App Store Review Notes. Local Bundled ZSH

**Copy/adapt this text for App Store Connect → App Review Information → Notes.** Keep in sync with [APP-STORE-COMPLIANCE.md](APP-STORE-COMPLIANCE.md).

---

## App summary for reviewers

**Wawona** is a developer tool that implements a Wayland compositor on iOS/iPadOS. Developers use it to run graphical Linux-style demo clients and, optionally, a **local terminal** backed by the open-source **Weston terminal emulator** and the **Z shell (zsh)**.

The local shell is **not** a mechanism to download or run arbitrary code from the internet. It is the same compliance model as other App Store developer environments: **only pre-bundled, Apple-reviewed native binaries** inside the app sandbox may be executed.

---

## What executes on device

| Component | Origin | Execution |
|-----------|--------|-----------|
| Wawona compositor | Bundled in app | In-process |
| Weston demo clients | Bundled static libraries | In-process (`weston_terminal_main`, etc.) |
| **zsh** | Statically linked into the app binary (`libwawona-zsh.a`) | **In-process**. Runs on a pthread via `wawona_zsh_main()`; **no `fork`/`exec`/`posix_spawn`** |
| **Core utilities (`ls`, `cat`, `cp`, …)** | Bundled Rust [uutils/coreutils](https://github.com/uutils/coreutils) (MIT), statically linked into the app binary | **In-process**. Dispatched by argv[0] from zsh through `wawona_dispatch_inprocess` → `wawona_coreutils_main`; **no `fork`/`exec`** |
| Remote SSH sessions | User-configured host | Network. Optional; same as other SSH clients |
| **WASM / WASI** | User-provided `.wasm` **document** (Files / File Sharing) | Interpreted by bundled Wasmtime **Pulley** (`wawona_wasm_run`); not Mach-O, not JIT, not Apple-signed |

There is **no JIT**, **no x86 emulator**, and **no post-install download of native executables**. User `.wasm` is bytecode read by the reviewed interpreter (same class as JavaScript in JavaScriptCore).

### zsh execution model (iOS/iPadOS and the rest of the sandboxed Apple family)

- zsh is compiled to a **static archive** and linked directly into the signed app binary. Its `main` is renamed to `wawona_zsh_main`.
- The terminal starts zsh by creating a **pthread** that calls `wawona_zsh_main()`. There is no child process. `fork`, `exec*`, `posix_spawn`, and `system` are never reached on this path.
- All zsh modules (including `zle`, `complete`, `computil`, `zutil`) are **statically linked** (`configure --disable-dynamic`); there is **no `dlopen`** and no runtime module loading.
- Common commands run **in-process too**: zsh's external-command path in `Src/exec.c` is patched (`patch-zsh-exec.py`) so that, *before* any `fork`/`execve`, a command whose `argv[0]` is in a fixed **safe subset** (`ls cat cp mv rm mkdir … truncate`) is dispatched to the statically linked Rust uutils/coreutils umbrella via `wawona_dispatch_inprocess()`. No child process is created; the utility returns an exit code like a builtin.
  - The utility set is **first-party, MIT-licensed Rust code compiled into the signed binary**. Nothing is downloaded. The safe subset deliberately excludes exit-prone / sandbox-meaningless utilities.
  - Each utility runs inside `std::panic::catch_unwind`, so a misbehaving utility returns a non-zero exit code instead of aborting the app. No utility in the subset calls `process::exit`.
- Anything outside the safe subset still cannot launch: `command_not_found_handler` reports that external binaries cannot run in the sandbox, and any `execve` of a path would be denied by the OS sandbox; the app ships no loose external command binaries.
- Exactly **one** in-process shell session runs per app launch (zsh's process-global state is not re-entrant).

---

## User-visible local shell flow

1. User selects a machine profile or nested Weston demo that includes **Terminal**.
2. A terminal window opens (text rendering, keyboard input).
3. The app starts the **statically linked in-process zsh** (a pthread running `wawona_zsh_main`) attached to an in-process pseudo-terminal emulation (`socketpair` + input pipe + TTY shim). No child process is created.
4. User commands run as zsh builtins with file access limited to the **app container** (and documents the user explicitly shares via system UI). External binaries cannot be launched.

---

## What the app does NOT do

- Download Mach-O binaries, dylibs, or scripts that are then executed natively
- Expose a "run arbitrary command URL" from Safari
- Install package managers that fetch native code
- Escalate to root or modify system files
- Inject input into other apps (virtual pointer/keyboard protocols disabled in store-safe build)

---

## Privacy

- Terminal input is processed **on device**.
- Command history may be stored in the app's Application Support directory (`~/.zsh_history` equivalent).
- No terminal content is sent to Wawona analytics by default.
- Optional SSH connections are initiated by the user to their own servers.

Privacy Nutrition Label: include **User Content** if Apple questionnaire asks about freeform text input.

---

## Demo account / review steps

1. Install build on iPad or iPhone (TestFlight or Review build).
2. Open **Machines** → select **Weston** (or bundled terminal profile).
3. Launch **weston-terminal** or nested Weston → tap terminal icon in launcher.
4. Confirm shell prompt appears; type `echo hello` → output `hello`.
5. Type `pwd` → path inside app container / rootfs home.
6. Type `ls /` and `cat ~/.zshrc` → output produced by the in-process bundled uutils utilities (still no child process).
7. Type `help` → catalog of builtins, uutils, clients, and WASM.
8. Optional: drop a `.wasm` via Files / File Sharing and run `wasm ./tool.wasm hello`.

If local shell is behind a Settings toggle, enable **Enable local shell** first.

---

## Comparable apps

Reviewers may compare to **a-Shell** (bundled command binaries), **iSH** (bundled Linux userland), **Blink** (remote shell). Wawona combines a **Wayland compositor** with a **bundled native zsh**. Stricter spawn policy (rootfs path lock) than generic shell apps.

---

## Contact for review questions

[Fill in engineering contact before submission]

---

## Version history

| Version | Change |
|---------|--------|
| 2026-06 | Initial local zsh documentation. Pre-ship |
| 2026-06 | zsh moved fully in-process (static `wawona_zsh_main` on a pthread); modules statically linked (`--disable-dynamic`), no `dlopen`; no `fork`/`exec`/`posix_spawn`; builtins-only, single session per launch |
| 2026-06 | Bundled in-process uutils/coreutils (MIT Rust): `ls`/`cat`/`cp`/… dispatched from zsh's exec path before any fork, via `wawona_dispatch_inprocess` → `wawona_coreutils_main`; safe subset only; `catch_unwind` exit-safety; still no `fork`/`exec`. macOS/Android ship the same utilities as a normal multicall binary on `PATH`. |
| 2026-08 | WASI P1/P2 interpreter (`wwn-wasm`, Pulley on Apple mobile). User `.wasm` is a document; no Cranelift native / `MAP_JIT` on iOS family. Milestone [Support WASI P1 P2 WASM!](https://github.com/Wawona/Wawona/milestone/2). |
