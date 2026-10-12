# Wawona package check

Skill: `wawona-package`. Open it before a dependency compile, a wasm or deb
package, a graphics bundle, or host UI (Swift, SwiftUI, Kotlin, Compose, C,
GTK).

Write these three lines before meson, `nix build`, or a linker flag. `system`,
`host`, `usual`, and `standard Linux` fail the check.

```text
LIBC    bionic | glibc | libSystem | wasi | wasix
TEXT    pixman, freetype, fontconfig, harfbuzz, cairo, pango
        each built for that LIBC, or none
GPU     one hop, or none, wl_shm
```

## Hard rejects

- Android Termux is **Bionic**. Not glibc. Not musl. Not host `pkg-config`. NDK clang in `repo.wawona.io/lib/androidNdk.nix`. Not the nixpkgs Android GCC bootstrap.
- cairo, harfbuzz, pango, pixman, freetype, and fontconfig are separate L0 libraries. None replaces another. There is no system cairo on Android or wasm.
- Linking cairo does not provide GLES or Vulkan. GPU is L1 `wwn-iland`.
- `nix build` exiting 0 is not green. Verdict is `nix run .#package-doctor` in `repo.wawona.io`.
- New deb program: one directory `catalog/deb/<kind>/<name>/` copied from `TEMPLATE.nix`. `builtins.readDir` is the index. Android libraries come from `pkgs/wayland/ndkLibs.nix`. Do not import `androidNdk.nix` from the package.

Lane choice stays `wawona-wasm-cli-ports`. Deb shape stays
`wawona-optional-software`. Catalog split stays `repo-wawona-io-catalogs`.
Do not paste those rules here.
