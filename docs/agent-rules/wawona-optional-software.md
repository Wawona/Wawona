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
| Relay wasm runtime (`wpm`, Pulley) | Relay | Runtime. No bundled demo `.wasm` |
| zsh | wwn-zsh | App Store keep |
| uutils safe subset | wwn-coreutils | App Store keep. No wasm twin |
| fastfetch | `repo.wawona.io` `catalog/deb/cli/fastfetch/in-app` | App Store keep. Not the deb card. |
| waypipe + ssh (libssh2 on Apple mobile) | wwn-waypipe / wwn-ssh | Product remote path |

## Move-set

| Package | Destination | App Store patches |
|---------|-------------|-------------------|
| weston, niri | Deb (WASIX nested later, research) | Delete |
| foot, weston-terminal | Deb | Delete |
| weston-simple-shm and weston toys | Deb | Delete |
| kmscube, gbm-es2-demo, opengl-cube, vkcube, weston-simple-egl | Deb | Delete |
| hello-wasi-gui, chess-wawona | Wasm P1 | Already wasm |
| gtk4-hello, wayland-bridge-smoke | `catalog/wasm/gui`, `abi = wasix` | Link gtk4 lib. Wasmer hosts only. |
| GTK and similar | `catalog/wasm/lib` (gtk4) plus a deb when one exists | Do not add in-app |

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
