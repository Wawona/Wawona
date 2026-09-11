# Relay Wasm on every Wawona target

Wawona Relay Runtime (WASI / `wwn-wasm`, later `wwn-relay`) must compile, link,
and ship on **every** product target: **macOS**, **iOS**, **iPadOS**, **tvOS**,
**watchOS**, **visionOS**, **Android**, **Linux**. Same class as Weston/Niri:
mandatory native bundle. VM/container machine kinds may stay **forbidden** on
tvOS / watchOS / visionOS. **Wasm must not.**

## Execute engines (do not conflate with packages)

Packages stay bytecode (`/wasm/v1`, `.wasm` documents). The engine that
**runs** them is Relay:

| Target | Mode A execute | Forbidden in that artifact |
|---|---|---|
| Apple mobile (iOS / iPadOS / tvOS / watchOS / visionOS) | Pulley / static | Cranelift native, `MAP_JIT` |
| Android Play / unrooted sideload | Pulley or store-safe Cranelift | Mode B JIT, AVF as a wasm path |
| macOS / Linux | Wasmtime Cranelift | None of the mobile store JIT bans |
| Mode B tipa / Sileo / desktop-host / root Android | Same packages; JIT execute allowed | A second wasm product, ElleKit-in-tipa |

There is **no** Mode B flavor of the Runtime catalog. Mode B may JIT-execute
the same bytecode. Store IPA/AAB must not.

## hello-wasi-gui must run on every target

`examples/hello-wasi-gui` (bundled `hello-wasi-gui.wasm`) is the required
Wayland WASI smoke. Machines **Start** on **watchOS** (and every other
product target) must launch it via Relay. Transfer-only WatchConnectivity
is not enough.

Present path for that smoke is **`wl_shm` + `xdg_wm_base`** into the host
Wawona compositor (SpriteKit blit on watchOS). That is the portable GUI
path.

GPU Wayland wasm clients (GLES / Vulkan / Metal via ANGLE / MoltenVK /
KosmicKrisp) follow the platform GPU gate:

| Target | hello-wasi-gui (`wl_shm`) | GPU wasm (GL / VK / Metal) |
|---|---|---|
| macOS, iOS, iPadOS, visionOS, Android, Linux | required | required when GPU stack is available |
| tvOS | required | Metal / GLES when bundled |
| watchOS | **required** | **blocked** (no Metal / GLES / `CAMetalLayer`). SHM + SpriteKit only |

## Hard rejects

- Empty `runCommand` / weak no-op stubs that leave watchOS (or any target)
  without `libwawona_wasm.a`
- Shipping a header-only Android `wawona-wasm` (`include/` only, empty `lib/`)
  as if Start can run hello-wasi-gui. Link `-lwawona_wasm` only when
  `libwawona_wasm.a` exists. Fix the Relay Android recipe. Do not toast
  ProcessBuilder "not bundled" as a substitute
- Dropping wasm from a scheme, `mobile-platform-deps`, or `wasmLdflags` to
  make CI or size look green
- Treating tvOS / watchOS / visionOS wasm as optional or "transfer only"
- Hiding `wawona-wasm` from Watch Machines so Start cannot run hello-wasi-gui
- Cranelift native / `MAP_JIT` in App Store Apple-mobile
- Calling wasm a VM or a container
- Claiming Metal / GLES / Vulkan wasm on watchOS (SDK has no public GPU)

Canonical: [`../wasm-wasi.md`](../wasm-wasi.md), `wawona-native-compositors`,
`wawona-linux-vms-relay-runtime`. Cursor: `.cursor/rules/wawona-relay-wasm.mdc`.
