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
| Smithay compositor + iland present | Wawona / iLand | Product |
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

## Unlink: audit what rode along on the link line

Dropping a client's ldflags helper from `xcodegen.nix` also drops every
keep-set archive that helper happened to carry. The weston helpers were the
only provider of three keep-set inputs, and removing them left the Apple
targets with undefined symbols that look unrelated to weston:

| Lost with the weston helpers | Owns | Symptom |
|---|---|---|
| `-force_load libwwn-pty.a` (`westonToytoolkitLdflags`) | in-process shell ABI + store-safe dispatch | `_wawona_dispatch_*`, `_wwn_pty_ios_*`, `_wwn_zsh_soft_exit` |
| `-lwayland-server` (`westonCompositorLdflags`) | watchOS mini server, and the `xdg-shell-protocol.o` merged into that archive | `_wl_display_*`, `_wl_global_create`, `_wl_resource_*`, `_xdg_*_interface` |
| `-liconv` | zsh `zreaddir` / `getkeystring` | `_iconv`, `_iconv_open`, `_iconv_close` |

Two more classes show up only after the keep-set link is restored:

- **Weak optional-software refs become hard errors.** Darwin does not treat a
  weak *declaration* in a `-force_load`ed object as allow-missing the way ELF
  does. `wawona-dispatch.o` references every client entry point it can start,
  so unlinking phoon / foot / fuzzel / weston / niri needs stub definitions in
  `src/platform/ios/WWNAppleMobileOptionalStubs.c` and
  `src/platform/watchos/WWNWatchStubs.c`, including the
  `wwn_weston_compositor_is_running` / `wwn_niri_main_*` probes. Swift
  `@_silgen_name` references (`kmscube_main`, `gbm_es2_demo_main`) are strong,
  not weak, and need the same stubs.
- **Do not `-force_load libiland_userland.a` on a target with no ANGLE.** That
  archive carries iland's EGL shim built with `ILAND_ANGLE_STATIC`, so
  force-loading imports 24 `angle_egl*` symbols. Store Apple-mobile presents
  through Metal and bundles no ANGLE. Use a lazy `-liland_userland` with
  `-Wl,-u` roots on the Mode A present ABI (`iland_drm_*`); nothing else in the
  archive references EGL, so `egl.c.o` drops out and the userspace DRM/KMS/GBM
  path still links.

Before pushing an unlink, link the affected app target locally
(`wawona-local-before-ci`). The watchOS and iOS failures above were four Gate
cycles apart because each one only surfaced after the previous was fixed.

## Machines

Default session: Native Shell (zsh). Wayland picker lists installed debs and
`wpm` modules. Store UI never offers APT.
