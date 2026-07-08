# iOS Local Shell — Engineering Status (2026-06)

Authoritative snapshot of the App Store–compliant local shell stack. For
architecture see [ARCHITECTURE.md](ARCHITECTURE.md); for compliance see
[APP-STORE-COMPLIANCE.md](APP-STORE-COMPLIANCE.md).

## End-to-end path (implemented)

```
Settings / Machines → weston-terminal
  → WWNRootfsManager.applyShellEnvironment
  → wwn_launch_host_client → weston_terminal_main (real terminal.c)
  → wwn_pty_spawn_shell_paced → wawona_zsh_main (libwawona-zsh.a)
  → zsh exec hook → wawona_dispatch_inprocess
       → uutils (wawona_coreutils_main)
       → fastfetch_main / wawona_nvim_main / waypipe_main (weak)
       → ssh_main / ssh_keygen_main (weak; libssh-inprocess.a)
```

Keyboard: `WWNCompositorView_ios` → `wwn_ios_terminal_inject` → zsh stdin.

## Component matrix

| Component | Build output | Linked into app | Runnable from zsh | App Store posture |
|-----------|--------------|-----------------|-------------------|-------------------|
| zsh | `libwawona-zsh.a` | force_load | (shell itself) | in-process pthread, no fork |
| uutils coreutils | `libwawona.a` (coreutils feature) | via Rust | yes (~39 utils) | catch_unwind, no exit() |
| fastfetch | `libfastfetch.a` | force_load | yes | in-process (iOS/iPadOS/tvOS/watchOS/visionOS); IOKit/SMC stubbed; exit()/signal/atexit-safe; per-platform frameworks; idempotent per-run lifecycle (re-entry safe after a prior crash); seeds `$HOME/.config/fastfetch/config.jsonc` |
| neovim | `libwawona-neovim.a` | force_load | yes (`nvim`/`vi`/`vim`) | PUC Lua, spawn stubs |
| waypipe + SSH | `libwawona.a` (waypipe-ssh) | via Rust | yes | libssh2 in-process transport |
| openssh (`ssh`/`ssh-keygen`) | `libssh-inprocess.a` | force_load | yes | in-process `ssh_main` weak symbol; requires `openssh` built in `mobile-platform-deps.nix` |
| apt | `apt()` zsh function (rootfs template) | — | yes | in-process module front-end; no exec; App Store compliant |
| weston-terminal | `libweston-terminal.a` | force_load | via UI launch | in-process client thread |
| rootfs templates | `wawona-rootfs-ios` | embed phase | dotfiles + fastfetch config in Application Support | templates only, no Mach-O |
| neovim runtime | `neovim-rootfs-ios` | embed phase | `VIMRUNTIME` env | share tree only |

**In-process `ssh`:** the OpenSSH client is linked as `libssh-inprocess.a` and
dispatched in-process (`ssh_main`), not fork/exec'd. It is gated by building
`openssh` in `mobile-platform-deps.nix`; without it `opensshInprocessLdflags` is
empty and `ssh` reports `NOT_HANDLED`.

**Not on iOS (by design):** fork/exec of bundled Mach-O, downloaded dylibs, JIT,
`apt` fetching binaries into the sandbox (modules ship via the App Store).

## Flake outputs (Wawona)

| Output | Purpose |
|--------|---------|
| `.#zsh-ios` / `.#zsh-ios-sim` | Static zsh archive |
| `.#wawona-pty-ios` / `-sim` | PTY + dispatch shim |
| `.#wawona-rootfs-ios` / `-sim` | Shell templates + zsh share |
| `.#fastfetch-ios` / `.#fastfetch-ios-device` | fastfetch archive |
| `.#neovim-ios` / `.#neovim-ios-device` | neovim archive |
| `.#neovim-rootfs-ios` / `-sim` | VIM runtime templates |
| `.#weston-ios` | Includes `libweston-terminal.a` |
| `.#waypipe-ios` / `-sim` | Standalone archive (also in libwawona.a) |
| `.#wawona-ios-app-sim` / device IPA | Full app |

## Sync points (keep aligned on change)

1. `Cargo.toml` `coreutils` feature list
2. `wwn_safe_subset[]` in `wwn-toolchain/.../wawona-dispatch.c`
3. `WAWONA_INPROC_TOOLS` in `dependencies/wawona/ios-rootfs.nix`
4. `WAWONA_INPROC_CLIENTS` (fastfetch, nvim, waypipe, ssh, ssh-keygen, scp) + `apt()` function in same template
5. `rust-backend-c2n.nix` iOS features: `waypipe-ssh`, `coreutils`
6. `xcodegen.nix` force_load flags for zsh, fastfetch, neovim, weston-terminal, pty, `opensshInprocessLdflags`
7. fastfetch default config: `fastfetchConfigTemplate` in `ios-rootfs.nix` ↔ seeded by `WWNRootfsManager.installFastfetchConfigFromBundle` under the general `XDG_CONFIG_HOME` (`$HOME/.config`)
8. `openssh` built in `mobile-platform-deps.nix` (mobile/tv) so `libssh-inprocess.a` links `ssh_main`

## Manual smoke (weston-terminal)

1. Launch compositor (app start).
2. Settings → Clients → **weston-terminal** (or Machines profile with native client).
3. Expect login banner + prompt; run `ls`, `echo`, `whoami`, `fastfetch`, `nvim --version`.
4. `ssh` (no args) should print OpenSSH usage, not `command not found` / `NOT_HANDLED`.
5. `apt help` and `apt list` should print the in-process module front-end output.
6. For waypipe SSH: set `WAYPIPE_SSH_PASSWORD` if needed, then
   `waypipe ssh user@host -- weston-simple-shm` (remote must have waypipe server).

Automated: `agent-device replay .agent-device/wawona-ios-shell-cli.ad` drives
this flow and captures per-command screenshots.

## Remaining gaps

| Gap | Severity | Notes |
|-----|----------|-------|
| Physical device PTY validation | Medium | Nix green; fill [ios-local-shell-spike.md](../ios-local-shell-spike.md) |
| `whoami` on device | Medium | uutils reads identity via `getpwuid`; verify it does not panic in the sandbox (`USER=mobile` is set in `applyShellEnvironment`); patch uutils identity path if needed |
| `neovim` interactive on device | Medium | Confirm `VIMRUNTIME` embed + TUI render/resize under weston-terminal; smoke `nvim --version` then interactive |
| `waypipe` in-process runtime | Medium | Confirm `waypipe --version` and SSH subcommand env (network entitlement, `WAYPIPE_SSH_PASSWORD`) from the shell |
| `grep` / `find` (uutils) | Low | Not in safe subset v1 |
| visionOS local terminal | N/A | Stub runner; no weston-terminal |
| `apt` module purchase flow | Deferred | W1 ships in-process front-end (help/list); StoreKit/ODR + `WWNModuleManager` are W2–W4 |
| Docs README “SHM stub” rows | Low | Historical; terminal.c is real — see STATUS |
| weston-terminal launch latency | Low | Launch runs on a background queue (no UI stall); the visible delay is the paced zsh bootstrap on `ios_zsh_thread`. `wwn_launch_host_client` joins intentionally to keep session state coherent |

## Repo ownership

| Piece | Repo |
|-------|------|
| zsh patch, rootfs recipe | wwn-zsh |
| PTY, dispatch | wwn-toolchain |
| uutils | wwn-coreutils (via Wawona Rust) |
| weston-terminal patch | wwn-weston |
| fastfetch / neovim | wwn-fastfetch / wwn-neovim |
| Integration, xcodegen, app | Wawona |
