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

**Wasm:** store optional GUI. Card under `catalog/wasm/<kind>/<name>/`.
`abi = wasi-p1` or `abi = wasix`. WASIX is not Pulley.
GTK4 is `catalog/wasm/lib/gtk4`. A GTK demo is `catalog/wasm/gui`.
Implementation stays in `catalog/wasm/src/wasinix`. Do not recreate
`Wawona/wasinix` or `Wawona/wasm-packages`.
## Deb recipe shape

```text
repo.wawona.io/catalog/deb/gui/<name>/default.nix
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

## Stale xcodegen trap (2026-10-12)

After unbundle, tip Nix/`xcodegen.nix` must drop `-force_load`
`libfoot.a` / `libfuzzel.a` (and similar move-set archives). A **checked-in
or leftover** `Wawona.xcodeproj` can still force_load them.

Symptoms on local `xcodebuild -scheme Wawona-iOS`:

```text
ld: library '…/DerivedSources/libfoot.a' not found
# or after a host stub:
ld: building for iOS-simulator, but linking … built for macOS
Undefined symbols: _foot_main, _fuzzel_main (from libwwn-pty dispatch)
```

`scripts/xcode-prebuild.sh` privatizes zsh/fastfetch. It does **not** build
foot/fuzzel. Lab escape: ios-sim `ar` stubs that export `foot_main` /
`fuzzel_main`, or regenerate the project from tip Nix. Product fix: unlink
in xcodegen in the same change as the unbundle.

## Never

- Grow App Store patch surface past zsh, uutils, fastfetch
- Ship ElleKit or APT in store IPA
- Revive nixpkgs2wasi stubs
- Default launcher `weston-terminal`
- Leave stale `Wawona.xcodeproj` force_loading move-set archives after unlink
