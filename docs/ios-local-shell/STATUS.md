# iOS Local Shell — Engineering Status (2026-07)

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
       → ssh_main / ssh_keygen_main / scp_main (libwwn-ssh-cli.a, libssh2)
```

Keyboard: `WWNCompositorView_ios` → `wwn_ios_terminal_inject` → zsh stdin.

## Component matrix

| Component | Build output | Linked into app | Runnable from zsh | App Store posture |
|-----------|--------------|-----------------|-------------------|-------------------|
| zsh | `libwawona-zsh.a` | force_load | (shell itself) | in-process pthread, no fork |
| uutils coreutils | `libwawona.a` (coreutils feature) | via Rust | yes (~39 utils) | catch_unwind, no exit() |
| fastfetch | `libfastfetch.a` | force_load | yes | in-process (iOS/iPadOS/tvOS/watchOS/visionOS); IOKit/SMC stubbed; exit()/signal/atexit-safe; per-platform frameworks; idempotent per-run lifecycle (re-entry safe after a prior crash); seeds `$HOME/.config/fastfetch/config.jsonc` |
| neovim | `libwawona-neovim.a` | force_load | yes (`nvim`/`vi`/`vim`) | PUC Lua, spawn stubs |
| waypipe + SSH | `libwawona.a` (waypipe-ssh) | via Rust | yes | **libssh2** in-process transport (never OpenSSH) |
| `ssh` / `ssh-keygen` / `scp` CLI | `libwwn-ssh-cli.a` (wwn-ssh) | force_load | yes | libssh2 + OpenSSL keygen; OpenSSH-format keys; never `libssh-inprocess.a` |
| apt | `apt()` zsh function (rootfs template) | — | yes | in-process module front-end; no exec; App Store compliant |
| weston-terminal | `libweston-terminal.a` | force_load | via UI launch | in-process client thread |
| rootfs templates | `wawona-rootfs-ios` | embed phase | dotfiles + fastfetch config in Application Support | templates only, no Mach-O |
| neovim runtime | `neovim-rootfs-ios` | embed phase | `VIMRUNTIME` env | share tree only |

**SSH on Apple mobile:** App Store path is **libssh2 only** — terminal CLI via
`libwwn-ssh-cli.a`, waypipe via streamlocal. Settings **Generate Key** /
**Import GPG SSH Key** write OpenSSH-format keys under Documents/ssh and sync
`SSHKeyPath` ↔ `WaypipeSSHKeyPath`.
`mobile-platform-deps.nix` must not ship `openssh` / `libssh-inprocess.a`.
macOS keeps real OpenSSH binaries.

**Not on iOS (by design):** fork/exec of bundled Mach-O, downloaded dylibs, JIT,
`apt` fetching binaries into the sandbox (modules ship via the App Store),
OpenSSH in-process archives.

## Flake outputs (Wawona)

| Output | Purpose |
|--------|---------|
| `.#zsh-ios` / `.#zsh-ios-sim` | Static zsh archive |
| `.#ssh-cli-ios` (via wwn-ssh registry) | libssh2 CLI archive |
| `.#fastfetch-ios` / device variants | fastfetch archive |
| `.#neovim-ios` / rootfs | neovim + runtime |
| `.#wawona-pty-ios` | PTY + dispatch |
| `.#wawona-rootfs-ios` | shell templates |

## Anti-bitrot

- `.github/scripts/verify-ios-shell-tools.py` — requires `ssh-cli` / `libwwn-ssh-cli.a`;
  forbids `openssh-ios` / `libssh-inprocess.a` / stub `ssh_*` in `*Stubs*.c`.
- Headless CLI matrix lives in `wwn-ssh/tests/cli-matrix.json` (Nix CI).
- Sparse agent-device: `.agent-device/wawona-ios-shell-cli.ad` (`ssh -V`, keygen).
