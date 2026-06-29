# Architecture: Local ZSH + Weston Terminal on Apple Mobile

## Executive summary

Wawona runs a **single iOS process** that hosts:

1. The Wawona Wayland compositor (Rust / Smithay)
2. Optional nested Weston compositor (in-process `weston_compositor_main`)
3. Weston demo clients (keyboard, desktop-shell, **terminal**)
4. A **PTY master** owned by `libwwn-pty`
5. A **bundled static `zsh`** child attached to the PTY slave

Terminal **UI** (VT parsing, scrollback, cairo rendering, keyboard input) comes from upstream Weston `clients/terminal.c`. Terminal **shell I/O** goes through `wwn_pty_*`, not through Weston compositor `fork()` stubs.

```
┌─────────────────────────────────────────────────────────────────┐
│ Wawona.app (one process, App Store sandbox)                     │
│                                                                 │
│  ┌──────────────┐    Wayland     ┌─────────────────────────┐   │
│  │ WWNCompositor│◄──────────────►│ weston_compositor_main  │   │
│  │  (Smithay)   │                │ (nested, optional)      │   │
│  └──────┬───────┘                └───────────┬─────────────┘   │
│         │ wl_surface                         │ launcher         │
│         ▼                                    ▼                  │
│  ┌──────────────┐                ┌─────────────────────────┐   │
│  │ weston_      │  master fd     │ in-process zsh (static) │   │
│  │ terminal_main│◄──────────────►│ pthread wawona_zsh_main │   │
│  │ (terminal.c) │   wwn_pty      └─────────────────────────┘   │
│  └──────────────┘                                               │
│         ▲                                                       │
│         │ touch / keyboard (WWNCompositorView_ios)              │
└─────────┴───────────────────────────────────────────────────────┘
```

---

## Separation of concerns

| Layer | Owner | Must NOT do |
|-------|-------|-------------|
| Wayland compositor | `src/core/*`, Smithay | Spawn shells; `fork()` is stubbed on mobile Weston |
| Weston nested compositor | `compositor-apple-mobile.nix` | Launch shell children (`#define fork() -1`) |
| Terminal UI | `clients/terminal.c` + toytoolkit | Download binaries; exec paths outside rootfs |
| PTY + spawn | `dependencies/libs/wawona-pty/` | Compositor logic; network I/O |
| Shell library | `dependencies/libs/zsh/ios.nix` | JIT; `dlopen`/dynamic module load (all modules static via `--disable-dynamic`) |
| Rootfs install | `WWNRootfsManager`, `xcodegen.nix` | Write outside app container |
| Launch / env | `WWNWaypipeRunner.m` | Pass through user-supplied `PATH` to spawn |

**Critical invariant:** On iOS/iPadOS (and the rest of the sandboxed Apple family: tvOS, watchOS, visionOS) the shell runs **in-process**: `terminal.c` → `wwn_pty_spawn_shell_paced` → `ios_spawn_zsh_inprocess`, which starts a **pthread** that calls the statically-linked `wawona_zsh_main()`. **No `fork`/`exec`/`posix_spawn`/`system` is reached** on this path (the `posix_spawn` branch in `spawn_on_slave` is skipped by an early iOS return), and **no `dlopen`** occurs (zsh modules are statically linked). The compositor's disabled `fork()` is a second, independent layer.

External commands are **also** in-process (see next section): zsh's exec path is patched so safe-subset utilities dispatch to bundled Rust uutils before any fork. Android is the only family member that forks — it is not sandboxed the same way, so it `posix_spawn`s a real on-disk `zsh` and execs the uutils multicall binary normally.

---

## In-process external command dispatch (uutils/coreutils)

`ls`, `cat`, `cp`, … are **not** child processes on the Apple sandbox. The bundled
Rust [uutils/coreutils](https://github.com/uutils/coreutils) umbrella crate is
compiled to a static library and linked into the signed binary; a single C entry
point `wawona_coreutils_main(argc, argv)` dispatches by `argv[0]` basename through
the umbrella `util_map`.

```
zsh execcmd_exec (Src/exec.c, patched by patch-zsh-exec.py)
  │  argv[0] basename in safe subset?  (wawona_dispatch_can_handle)
  ├── no  → normal not-found / sandbox-denied path (no external binaries shipped)
  └── yes → wawona_dispatch_inprocess()           [libwwn-pty.a / wawona-dispatch.c]
             → wawona_coreutils_main()             [libcoreutils.a, Rust]
                 → uucore::util_map()[name]        (in std::panic::catch_unwind)
                 → returns i32 exit code  (NEVER process::exit)
```

The patch runs **at zsh's fork-decision point**, so a handled command neither forks
nor takes the fake-exec path; it behaves like a builtin (`lastval` set, fds restored
via `fixfds`, `goto done`). A panic is caught so the host app survives. The safe
subset is fixed in three places kept in sync: `Cargo.toml` `coreutils` feature,
`wwn_safe_subset[]` in `wawona-dispatch.c`, and `WAWONA_INPROC_TOOLS` in the
`.zshrc` template. `watchOS` size-gates the coreutils feature off (builtins only).

On **macOS/Android** the identical utilities ship as an ordinary uutils **multicall
binary** on `PATH` (`coreutils` + per-util symlinks); there zsh exec()s it normally
and neither the exec patch nor the dispatch shim is used.

### In-process clients (static archives)

These ship as separate `-force_load` archives (not uutils). Same dispatch path;
listed in `WAWONA_INPROC_CLIENTS` in the `.zshrc` template:

| Command | Archive | Entry point | Notes |
|---------|---------|-------------|-------|
| `fastfetch` | `libfastfetch.a` | `fastfetch_main` | No fork; patched for Apple mobile |
| `nvim` / `vi` / `vim` | `libwawona-neovim.a` | `wawona_nvim_main` | PUC Lua only; `:terminal` stubbed |
| `waypipe` | `libwawona.a` (`waypipe-ssh`) | `waypipe_main` | libssh2 SSH in-process; no openssh binary |

SSH from a shell: `export WAYPIPE_SSH_PASSWORD=…` then `waypipe ssh user@host -- …`.
The Settings UI uses the same entry point with captured stdout/stderr.

---

## Data flows

### Keyboard → shell

```
UITouch / UIKeyCommand
  → WWNCompositorView_ios
  → WWNCompositorBridge injectKey*
  → Smithay wl_keyboard
  → weston-terminal (toytoolkit seat)
  → terminal.c input handler
  → write(master_fd, bytes)
  → zsh stdin (slave fd)
```

### Shell → screen

```
zsh stdout/stderr (slave fd)
  → read(master_fd)
  → terminal.c VT parser
  → cairo draw + wl_surface commit
  → Wawona compositor buffer
  → CGImage / IOSurface present (WWNCompositorBridge)
```

### Terminal resize

```
WWNCore output resize / xdg configure
  → terminal.c SIGWINCH or equivalent hook
  → wwn_pty_set_winsize(master_fd, ws)
  → kernel TIOCSWINSZ on slave
  → zsh line editor reflow
```

### OSC 7 / title (reuse macOS patch intent)

macOS `weston/macos.nix` already patches `terminal.c` for OSC 7 cwd-as-title. The same patch family applies to iOS so window titles and shell integration stay consistent across platforms.

---

## In-process client launch (already implemented)

Mobile Weston clients do not `exec()` separate binaries. They run inside the app via:

| Component | Role |
|-----------|------|
| `mobile-weston-client-launch.c` | Maps `"weston-terminal"` → `weston_terminal_main` |
| `wwn-mobile-clients.h` | Declares client entry symbols |
| `wwn_mobile_consume_wayland_socket_fd()` | Clients connect via inherited FD, not `WAYLAND_DISPLAY` |
| `WWNWaypipeRunner.m` | Sets env, calls `weston_terminal_main` on compositor thread |

After Phase 1, `weston_terminal_main` comes from real `terminal.c`, not `mobile-weston-terminal.c`.

---

## Rootfs layout (target)

```
Wawona.app/
  Resources/
    wawona-rootfs/           # read-only template (Nix `$out/rootfs`)
      usr/bin/zsh            # placeholder marker only (zsh is in the app binary)
      usr/share/zsh/...      # autoloadable functions (completion, prompts) for fpath
      etc/zsh/zshenv.template
      etc/zsh/zshrc.template
      etc/zsh/zlogin.template
  Application Support/       # first-launch copy (writable)
    wawona-rootfs/
      home/                  # effective HOME / ZDOTDIR for zsh
        .zshenv              # fpath setup (points at bundled functions)
        .zshrc               # interactive config + prompt + completion
        .zlogin              # login banner
        .zsh_history
```

zsh itself is **not** an on-disk binary — it is statically linked into the app (`libwawona-zsh.a`); `usr/bin/zsh` is a non-executable placeholder kept only for path conventions. `WWNRootfsManager` copies the `etc/zsh/*.template` dotfiles into the writable `home/` on first launch (install marker `.installed-v8`) so the user can edit `.zshenv`/`.zshrc`/`.zlogin` without mutating the signed bundle.

---

## Environment variables (spawn time)

Set in `WWNWaypipeRunner.m` (or a dedicated `WWNLocalShellEnvironment`) **before** `weston_terminal_main`:

| Variable | Value | Purpose |
|----------|-------|---------|
| `HOME` | `…/Application Support/wawona-rootfs/home` | Writable user dir |
| `ZDOTDIR` | same as `HOME` or explicit | zsh dotfile location |
| `WAWONA_ROOTFS` | absolute rootfs path | Spawn layer validation |
| `PATH` | `/usr/bin:/bin` | No host PATH leakage; on the Apple sandbox contains no real executables — `ls`/`cat`/… are dispatched in-process by the zsh exec hook, not found on `PATH`. (macOS/Android prepend the uutils multicall dir.) |
| `TERM` | `xterm-256color` | Matches terminal.c expectations |
| `WAWONA_SHELL` | `$WAWONA_ROOTFS/usr/bin/zsh` | Explicit shell for spawn hook |
| `XDG_RUNTIME_DIR` | existing Wawona tmp | Wayland socket dir |
| `WESTON_CONFIG_FILE` | generated `weston.ini` | Nested Weston only |

Never inherit `DYLD_*`, `LD_*`, or host `PATH` from SpringBoard.

---

## Platform matrix

| Platform | Terminal UI | Local zsh | Coreutils | Build attr |
|----------|---------------|-----------|-----------|------------|
| **iOS** | Full `terminal.c` | **Yes — in-process** | in-process uutils (safe subset) | `.#weston-ios`, `.#zsh-ios` |
| **iPadOS** | Same (`ipados.nix` → `ios.nix`) | **Yes — in-process** | in-process uutils | same |
| **tvOS** | Full `terminal.c` (constrained UX) | **Yes — in-process** | in-process uutils | reuses iOS recipes |
| **visionOS** | Full `terminal.c` | **Yes — in-process** | in-process uutils | reuses iOS recipes |
| **watchOS** | Full `terminal.c` (constrained UX) | **Yes — in-process** | **size-gated off** (builtins only) | see [WATCHOS-SCOPE.md](WATCHOS-SCOPE.md) |
| **Android** | Full `terminal.c` | **Yes — forked** (`posix_spawn` real `zsh`) | uutils multicall on `PATH` | `.#zsh-android`, APK `libzsh_bin.so` |
| **macOS** | Meson path | Host `/bin/zsh` via `forkpty` | uutils multicall on `PATH` | `weston/macos.nix` unchanged |

---

## Remote shell (parallel, already supported)

Machine profiles using waypipe + SSH run **remote** zsh on Linux/macOS hosts. That path is `store-safe-remote` and does not use `wwn_pty`. Local and remote shells coexist as separate machine presets.

---

## Failure modes

| Symptom | Likely cause | Mitigation |
|---------|--------------|------------|
| Terminal window, no prompt | PTY spike failed; spawn stub | Phase 0 report; show in-UI error |
| Prompt but no echo | master/slave fd not wired | Fix `wwn_pty_open` |
| Jetsam under memory pressure | zsh + nested Weston + compositor | Single shell; reap on `stopActiveIOSBundledClient` |
| App Review rejection | Unclear disclosure | [APP-REVIEW-NOTES.md](APP-REVIEW-NOTES.md) |

---

## Code anchors

| Topic | Path |
|-------|------|
| SHM stub (to delete) | `dependencies/clients/weston/mobile-weston-terminal.c` |
| iOS client build | `dependencies/clients/weston/ios.nix` ~484–491 |
| macOS terminal patches | `dependencies/clients/weston/macos.nix` |
| Compositor fork stub | `dependencies/clients/weston/compositor-apple-mobile.nix` |
| Client lookup | `dependencies/clients/weston/mobile-weston-client-launch.c` |
| Launch / teardown | `src/platform/macos/ui/Settings/WWNWaypipeRunner.m` |
| Store-safe profile | `src/core/wayland/mod.rs` |
