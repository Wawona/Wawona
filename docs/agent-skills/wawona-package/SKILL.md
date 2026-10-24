---
name: wawona-package
description: >-
  Package a Wawona dependency or program for wasm, deb, the graphics bundle,
  or a host UI compile. Write LIBC, TEXT, and GPU before any compiler. Android
  is Bionic. cairo, harfbuzz, and pango are not substitutes. Use for unfamiliar
  platforms, Wayland, Swift, Compose, GTK, and repo.wawona.io.
---

# Package for Wawona

Open this before compiling a dependency, bundling graphics, or writing host UI.
Lane law stays in `wawona-wasm-cli-ports`. Catalog law stays in
`repo-wawona-io-catalogs`. This skill is the check those rules do not spell:
do not guess Linux libraries on another platform.

`nix build` exiting 0 is not green. A clean log is not green. Model confidence
is not green.

## Stop. Write three lines first

Do this before meson, `nix build`, or a linker flag. If a line says `system`,
`host`, `usual`, or `standard Linux`, stop.

```text
LIBC    bionic | glibc | libSystem | wasi | wasix
TEXT    which of pixman, freetype, fontconfig, harfbuzz, cairo, pango
        each built for that LIBC, or "none"
GPU     one hop, or "none, wl_shm"
```

Libc is not a text library. Text libraries are not the GPU.

### LIBC

| Target | LIBC | Never |
|--------|------|--------|
| Termux Android | **Bionic** | glibc, musl, host `pkg-config` |
| Linux deb | **glibc** | Termux static libs, Bionic |
| Apple | **libSystem** | glibc |
| `wasi-p1` / `wasi-p2` | **wasi** | glibc symbols, WASIX syscalls |
| `wasix` | **wasix** | a `/wasm/v1` P1 label |

Android compiler is NDK clang in `repo.wawona.io/lib/androidNdk.nix`. The
nixpkgs `aarch64-unknown-linux-android` GCC bootstrap is the wrong toolchain.
A glibc `.so` inside a Termux deb is red.

For Android static libraries built on Darwin, disable the host `strip` fixup
with `dontStrip = true`. Darwin's cctools rewrites a GNU Android archive index
as BSD and leaves GNU `/` and `//` members as ordinary objects, which Android
`ld.lld` rejects. Validate the linked consumer, not only the archive build.

### TEXT

Separate L0 packages. None replaces another. Build order:

1. **pixman** draws pixels.
2. **freetype** reads fonts. **fontconfig** finds fonts.
3. **harfbuzz** shapes text. It is not cairo.
4. **cairo** paints. It needs pixman and the font libs it was configured with. It is not harfbuzz. It is not GLES.
5. **pango** lays out text on cairo and harfbuzz.

On Android and on wasm there is no system cairo. Each name in `TEXT` is built
for that `LIBC`, or the card names the recipe that already did. Skipping
harfbuzz because cairo is present is red. Skipping cairo because harfbuzz is
present is red.

### GPU

L1 `iLand`. Linking cairo does not provide GLES or Vulkan.

One hop. Do not stack Zink on Vulkan to reach Metal.

- Apple GLES: ANGLE to Metal. Vulkan: MoltenVK to Metal. KosmicKrisp is macOS only.
- Android GLES: ANGLE or system GLES. Vulkan: system or SwiftShader.
- watchOS: no public Metal or GLES. `GPU` is `none, wl_shm`. Present is SpriteKit.
- tvOS: Metal and OpenGL ES when `WWN_TVOS_GPU=1`. Do not copy an old note that says tvOS is shm only.

Never open `/dev/dri` or `/dev/kgsl`. No kernel DRM. No direct Turnip/KGSL.

Graphics recipes: `iLand`. Substrate (cairo, pango, pixman, freetype,
fontconfig, harfbuzz): `wwn-toolchain`. Do not swap those owners.
`wawona-repo-dag`, `wawona-platform-targets`.

Mode A bundle is static `libiland_userland.a`. Mode B `libwayland-mac.dylib`
ships only in `wawona-macos-desktop-host`.

## Card

One card for a library or a program.

- `name`, upstream `version`, upstream `homepage`
- `channel`: `wasm`, `deb`, or both only when the table below says so
- `abi`: `wasi-p1`, `wasi-p2`, or `wasix` when channel is wasm
- `hosts` for deb: `macos`, `ios-rootless`, `ios-rootful`, `ios-roothide`, `linux`, `android-termux`
- `deps`: names only
- `wayland`: yes or no
- the three lines above

Forbidden on the card: `cflags`, `ldflags`, a cross file, an invented `0.1.0`.

## Where it builds

Two search channels. Never one list. Store `wpm` reads `/wasm/v1` only.

| Need | Where |
|------|--------|
| stdio and files | `catalog/wasm/cli/<name>` `abi = wasi-p1`, Wasmtime smoke |
| Component Model only | wrap that P1 module (`wasm-tools component new`), `wasi-p2`, Wasmtime |
| fork, threads, sockets, TTY, toolkit | `catalog/wasm/{cli,gui,lib}` `abi = wasix`, Wasmer smoke. Not a P1 row |
| name in `native-all-targets.txt` | stop. No wasm twin |
| deb process | `repo.wawona.io` `mkDebFromBins`. No `apple-mobile.nix`, no `*_main` |

Full lane steps: skill `wawona-wasm-cli-ports`. Deb shape: `wawona-optional-software`.

Deb hosts:

- **macOS.** Mach-O. No Darwin row in `Packages` yet. Do not publish that deb until `file` shows Mach-O for the arch.
- **iOS / iPadOS.** Jailbroken only. `iphoneos-arm64` prefix `/var/jb`, `iphoneos-arm` prefix `/`, optional RootHide. Not the store IPA.
- **Android.** Termux. `aarch64`, Bionic, prefix `/data/data/com.termux/files/usr`. Not jailbreak. Not Play.
- **Linux.** glibc, `amd64` or `arm64`, prefix `/usr`.

Wasm is one bytecode for every product target. Every module uses the Wawona
host ABI (`wasm-host-abi`, `wayland-wasm`). `wayland: yes` on Pulley is
`wl_shm` plus `xdg_wm_base` only. `ci.suites.wayland` is `unknown` until a
real suite passes. Do not claim it passed. WASIX does not run on store Pulley
through iOS 26.

A library other packages link (cairo, pixman, wayland, xkbcommon, fontconfig,
harfbuzz, libffi) is wide. Edit the shared recipe once. A leaf program does
not get its own copy of those flags.

## Add a program or toolkit

Deb process packages live in `repo.wawona.io`.

1. Copy `pkgs/wayland/TEMPLATE.nix` to `catalog/deb/gui/<name>/default.nix` (or `catalog/deb/cli` or `catalog/deb/lib`).
2. `builtins.readDir` is the index. Do not add a clients.nix line.
3. Android compiler and libraries come from `pkgs/wayland/ndkLibs.nix` (`pcPath`, `cargoEnv`). Do not import `lib/androidNdk.nix` from the package. `scripts/check-wayland-ndk-imports.py` fails that import.
4. Pack with `packProcessDeb` (`lib/packProcessDeb.nix`): pname, upstream version, homepage, files. No copied `dpkg-deb` script.
5. Termux apt unpack stays `lib/termuxSysroot.nix` (niri pango, glib, harfbuzz). Do not fold that into `ndkLibs.nix`.
6. A new toolkit library is one `pkgs/wayland/<name>-android/default.nix` (`{ nativePkgs, androidNdk }`) plus one name in `ndkLibs.nix` `libs`. Callers use `pcPath`. They do not import the recipe.
7. Wawona core does not gain that toolkit. No new `xcodegen.nix` link line and no store IPA archive. In-app stays compositor, Relay wasm, zsh, uutils, fastfetch. New programs are this deb card, or a wasm lane (`wawona-wasm-cli-ports`).

`nix run .#package-doctor -- --target android|linux|macos|ios-rootless|ios-rootful|ios-roothide|wasi-p1|wasi-p2|wasix --out PATH`.

## Languages

Rust owns compositor policy, profiles, prefs, launch, and session.

- **Apple.** Swift and SwiftUI in `Sources/WawonaUI`, `Sources/WawonaApple`, `Sources/WawonaWatch`, `Darwin/`. Load `wawona-apple-swift`, then `swiftui-pro` and `swiftui-expert-skill`. iOS 13 floor. No new Objective-C product class. C is the `WWNCore*` trampoline only.
- **Android.** Kotlin and Compose. Load `wawona-android-compose`, then `compose-agent` and `modern-jetpack-compose`. In-app `SettingsDialog` only. JNI is a trampoline. Gradle JVM is JBR 21.
- **Linux.** GTK / libadwaita for host UI. Rust core.
- **C.** Upstream ports stay C. New Wawona product logic is not C.
- **GTK programs.** Deb plus WASIX. Not an in-app store static port. Not Pulley if they need fork or threads.

## Wayland on a platform you have not shipped

Rules: `wawona-wayland-protocol-compat`, `wawona-port-fidelity`,
`wawona-compositor-backend`, `wawona-guest-wayland-iland`,
`wawona-host-keymap-bridge`.

Invariants: newest practical stable interface, older clients bind down, no
second copy of the same interface. A port substitutes the platform under the
client. The waypipe Linux build is the reference. No assumed host compositor.
Nested weston and niri on Aqua use Wayland. Classic (WindowServer down) uses
iland DRM. Seat keymap comes from the host bridge. No layout picker.

Checklist before a new backend. Answer from the SDK, not from memory:

1. List public GPU frameworks. No public Metal, GLES, or Vulkan means blocked. Do not use a private API.
2. Mark available, planned, blocked, or forbidden. VM and container kinds are forbidden on tvOS, watchOS, and visionOS. Wasm is not.
3. Name `GPU` with one hop, or `none, wl_shm`.
4. Name `LIBC` and `TEXT` for that libc.
5. Name the UI language from the table above.
6. Say in-app, deb, or wasm. Store Apple-mobile and Play do not get a deb.
7. Name the Wayland globals and match them to the waypipe reference.

If the platform is new, record the checklist with `wawona-learn` in the same
change.

## Green

Run the doctor. Do not treat `nix build` exit 0 as the verdict.

```text
nix run .#package-doctor -- --target android --out result
```

`--wayland` stays red until a socket trace exists. Instantiate is not that trace.

The doctor prints `UNIT`, `VERDICT`, `REASON`, `EVIDENCE`, `SCOPE`. It checks the packed `.deb` under `$out/deb/`, ELF machine, glibc `ld-linux` / `GLIBC_` on Android, Termux or `/usr` or `/var/jb` prefix, Mach-O, and wasm magic. P1 and P2 need `wasmtime` on `PATH`. WASIX needs `wasmer`. The module is not executed.

On red, return `UNIT`, `VERDICT`, `REASON`, `EVIDENCE`, `SCOPE`. Fix that unit
only. Cap three tries. Then stop. A missing text library is a new card for
that library, not a flag pasted into the program.

## Hard rejects

- Guess glibc, musl, or host pkg-config for Android.
- Treat cairo, harfbuzz, pango, pixman, freetype, or fontconfig as one library.
- Treat cairo as the GPU stack.
- Invent `0.1.0` or a stub under an upstream name.
- Revive `nixpkgs2wasi`.
- Label WASIX as `wasi-p1`.
- Put `cflags` on the card or paste `CC_aarch64_linux_android` into a package file.
- Import `lib/androidNdk.nix` from a package. Use `ndkLibs.nix`.
- Pack a glibc ELF into a Termux deb.
- Put App Store `*_main` or `apple-mobile.nix` into a deb recipe.
- Open real `/dev/dri`.

## Cross-system product cache

When a Darwin product references a Linux artifact, prebuild the exact pinned Linux output on a native Linux runner and let the shared CI cache publish it before the Darwin job starts. Add a job dependency so the Darwin product cannot race the cache push. Nix on macOS can consume cached Linux store paths, but it cannot build a missing `aarch64-linux` dependency. Keep the product artifact when fixing this gate; do not silently drop the Linux guest feature to avoid the platform mismatch.
