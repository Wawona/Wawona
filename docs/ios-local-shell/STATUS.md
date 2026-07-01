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
```

Keyboard: `WWNCompositorView_ios` → `wwn_ios_terminal_inject` → zsh stdin.

## Component matrix

| Component | Build output | Linked into app | Runnable from zsh | App Store posture |
|-----------|--------------|-----------------|-------------------|-------------------|
| zsh | `libwawona-zsh.a` | force_load | (shell itself) | in-process pthread, no fork |
| uutils coreutils | `libwawona.a` (coreutils feature) | via Rust | yes (~39 utils) | catch_unwind, no exit() |
| fastfetch | `libfastfetch.a` | force_load | yes | in-process (iOS/iPadOS/tvOS/watchOS/visionOS); IOKit/SMC stubbed; exit()/signal/atexit-safe; per-platform frameworks |
| neovim | `libwawona-neovim.a` | force_load | yes (`nvim`/`vi`/`vim`) | PUC Lua, spawn stubs |
| waypipe + SSH | `libwawona.a` (waypipe-ssh) | via Rust | yes | libssh2 in-process, no openssh |
| weston-terminal | `libweston-terminal.a` | force_load | via UI launch | in-process client thread |
| rootfs templates | `wawona-rootfs-ios` | embed phase | dotfiles in Application Support | templates only, no Mach-O |
| neovim runtime | `neovim-rootfs-ios` | embed phase | `VIMRUNTIME` env | share tree only |

**Not on iOS (by design):** openssh binary, sshpass, fork/exec of bundled Mach-O,
downloaded dylibs, JIT.

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
4. `WAWONA_INPROC_CLIENTS` (fastfetch, nvim, waypipe) in same template
5. `rust-backend-c2n.nix` iOS features: `waypipe-ssh`, `coreutils`
6. `xcodegen.nix` force_load flags for zsh, fastfetch, neovim, weston-terminal, pty

## Manual smoke (weston-terminal)

1. Launch compositor (app start).
2. Settings → Clients → **weston-terminal** (or Machines profile with native client).
3. Expect login banner + prompt; run `ls`, `fastfetch`, `nvim --version`.
4. For waypipe SSH: set `WAYPIPE_SSH_PASSWORD` if needed, then
   `waypipe ssh user@host -- weston-simple-shm` (remote must have waypipe server).

## Remaining gaps

| Gap | Severity | Notes |
|-----|----------|-------|
| Physical device PTY validation | Medium | Nix green; fill [ios-local-shell-spike.md](../ios-local-shell-spike.md) |
| `grep` / `find` (uutils) | Low | Not in safe subset v1 |
| visionOS local terminal | N/A | Stub runner; no weston-terminal |
| openssh CLI from shell | N/A | libssh2 only; App Store compliant |
| Docs README “SHM stub” rows | Low | Historical; terminal.c is real — see STATUS |

## Repo ownership

| Piece | Repo |
|-------|------|
| zsh patch, rootfs recipe | wwn-zsh |
| PTY, dispatch | wwn-toolchain |
| uutils | wwn-coreutils (via Wawona Rust) |
| weston-terminal patch | wwn-weston |
| fastfetch / neovim | wwn-fastfetch / wwn-neovim |
| Integration, xcodegen, app | Wawona |
