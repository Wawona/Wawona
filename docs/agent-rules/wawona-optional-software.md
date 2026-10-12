# Optional software (wasm and deb)

Authority for what stays inside the Wawona app versus what installs later from
`repo.wawona.io`. Cursor rule: `wawona-optional-software`. Native compositor
rule: `wawona-native-compositors`.

## Goal

Ship the compositor. Keep a small App Store-safe shell (zsh, uutils, fastfetch).
Move Wayland clients and nested compositors to installable packages so App Store
no-fork patch burden shrinks instead of growing.

## Keep-set (in every artifact)

| Component | Owner | Patches |
|-----------|-------|---------|
| Smithay compositor + iland present | Wawona / wwn-iland | Product |
| Relay wasm runtime + `hello-wasi-gui` smoke | Relay | Runtime |
| zsh | wwn-zsh | App Store keep |
| uutils safe subset | wwn-coreutils | App Store keep. No wasm twin |
| fastfetch | wwn-fastfetch | App Store keep |

## Move-set

| Package | Destination | App Store patches |
|---------|-------------|-------------------|
| weston, niri | Deb (WASIX nested later, research) | Delete |
| foot, weston-terminal | Deb | Delete |
| weston-simple-shm and weston toys | Deb | Delete |
| kmscube, gbm-es2-demo, opengl-cube, vkcube, weston-simple-egl | Deb | Delete |
| hello-wasi-gui, chess-wawona | Wasm P1 | Already wasm |
| gtk4-hello, wayland-bridge-smoke | WASIX (wasinix `pkgs/programs/`) | Link `libraries.gtk4`; Relay host `wawona_wayland_*`; Wasmer hosts only (not Pulley / store IPA keep-set) |
| GTK and similar | Deb + WASIX `pkgs/libraries/` (not `programs/`) | Do not add in-app |

Deb audiences: jailbreak iOS rootless/rootful, Termux `aarch64`, Linux amd64/arm64.
Store hosts use `wpm` / wasm only until a real wasm port exists.

## Deb rules

- Upstream process. Fork/exec/JIT allowed.
- Platform substitution only (port fidelity).
- Never `apple-mobile.nix` / renamed `*_main` / in-process cairo skips.
- After unlink: delete patch files and `verify-*-ios-patches.py` anchors for that client.

## Machines

Default session: Native Shell (zsh). Wayland picker lists installed debs and
`wpm` modules. Store UI never offers APT.
