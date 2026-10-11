# Apple-mobile Mode A backends (least maintenance)

Authority for **iOS family** App Store Mode A shell/SSH/`system()` (not macOS).
iOS / iPadOS / tvOS / watchOS / visionOS. Floor **13.0**, latest SDK.

## Freeze stack (do not reinvent)

| Need | Backend | Owner repo |
|------|---------|------------|
| coreutils | Rust uutils → `wawona_coreutils_main` | **wwn-coreutils** (pin, patch, `safe-subset.txt`) |
| SSH / scp / keygen | libssh2 CLI (`ssh_main`…) | **wwn-ssh** |
| zsh | In-process `wawona_zsh_main` | **wwn-zsh** |
| store-safe `system()` | `wawona_dispatch_inprocess` | **wwn-toolchain** `wawona-pty` |

Wawona (L4) **links** these archives and hosts SwiftUI. It does not re-pin
uutils or implement a second SSH/zsh stack.

## Patch budget

1. Pin upstream hard; bump rarely.
2. Prefer configure / env / `#ifdef` over new patch files.
3. Every Apple-mobile patch needs an anchor verifier in that `wwn-*` repo.
4. No per-OS product forks (no ios13 vs ios26 trees). 18→26 is marketing.
5. Canonical notes: `wwn-coreutils/docs/PATCH-BUDGET.md`.

## Hard rejects

- Swift backends for SSH, zsh, coreutils, or dispatch (NIOSSH, ios_system,
  Swift `Process` as the product shell path)
- OpenSSH / fork-exec of `ssh` on Apple-mobile store builds
- Real POSIX `system()` / `execve` of unsigned Mach-O
- Mega `libwawona-appstore` SDK that owns every tool
- Re-pinning uutils with `fetchFromGitHub` inside Wawona `flake.nix`
- Raising deployment target above 13.0 for Wasmer / GhosttyKit / convenience

## Verify

`python3 .github/scripts/verify-ios-shell-tools.py` checks libssh2 wiring,
`wwn-coreutils` safe-subset vs `Cargo.toml`, and forbids NIOSSH / ios_system
imports under Apple Swift sources.

See also: `wawona-ios-min-os`, `wawona-rust-first`, ios-local-shell
`APP-STORE-COMPLIANCE.md`.
