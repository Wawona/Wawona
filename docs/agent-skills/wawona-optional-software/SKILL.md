---
name: wawona-optional-software
description: >-
  Unbundle Wayland clients from the Wawona app into repo.wawona.io wasm and
  deb packages. Keep zsh, uutils, fastfetch in-app. Debs skip App Store patches.
---

# Optional software (how to unbundle)

Hard gates: `wawona-optional-software`, `wawona-native-compositors`,
`repo-wawona-io-channels`, `wawona-wasm-cli-ports`, `wawona-native-over-wasm`.

## Keep vs move

**Keep in app (App Store patches OK):** zsh, uutils safe subset, fastfetch,
compositor + iland, Relay wasm runtime, `hello-wasi-gui` smoke.

**Move to deb (delete App Store patches):** weston, niri, foot,
weston-terminal, weston toys, GPU cubes. Deb = upstream process.

**Wasm:** store optional GUI. P1 = `wasm-packages`. WASIX = `wasinix` (not Pulley).
GTK toolkit = `wasinix` `pkgs/libraries/` (not `pkgs/programs/`). A GTK app
demo is a separate program that links `libraries.gtk4`. Deb twin on
`repo.wawona.io`. See `wasinix/docs/libraries-vs-programs.md`.
## Deb recipe shape

```text
repo.wawona.io/pkgs/wayland/<name>/default.nix
  → mkDebFromBins, target android|linux
  → upstream / process binary + platform substitution only
  → NEVER apple-mobile.nix / *_main rename / no-fork
  → NEVER pack glibc Linux ELF into Termux aarch64 deb
```

| Target | Prove |
|--------|--------|
| Linux | `nix build .#packages.aarch64-linux.linux-wayland` |
| Termux | `nix build .#weston-simple-shm-android` then `.#android-wayland` |

Prove: process connects to a live Wawona Wayland socket. Then unlink from
`xcodegen.nix` and delete that client's App Store patch set in the same change.

## Machines

Default bundled id: empty / Native Shell. Store picker: `wpm` only. Mode B /
Termux / Linux: list installed debs under the package prefix.

## Never

- Grow App Store patch surface past zsh, uutils, fastfetch
- Ship ElleKit or APT in store IPA
- Revive nixpkgs2wasi stubs
- Default launcher `weston-terminal`
