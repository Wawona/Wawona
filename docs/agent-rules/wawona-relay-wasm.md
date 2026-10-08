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
| iOS / iPadOS through OS 26, plus tvOS / watchOS / visionOS | Pulley / static | Cranelift native, `MAP_JIT`, Wasmer, WKWebView JSPI |
| iOS / iPadOS 27+ | Wasmer WASIX Swift SDK: hidden WKWebView, WebKit JIT, JSPI. Same `/wasm/v1` bytecode. Only when the build defines `WWN_WASMER_IOS27` and links WasmerSDK. Otherwise Pulley. | Cranelift native, `MAP_JIT`, a second wasm catalog, raising the deployment target above 13.0 |
| Android Play / unrooted sideload | Pulley or store-safe Cranelift | Mode B JIT, AVF as a wasm path |
| macOS / Linux | Wasmtime Cranelift | A second Wasmer engine beside Cranelift |
| Mode B tipa / Sileo / desktop-host / root Android | Same packages. Mode B iOS stays Pulley until `MAP_JIT`. Wasmer WebKit is the Mode A iOS 27 path, not the tipa path. | A second wasm product, ElleKit-in-tipa |

There is **no** Mode B flavor of the Runtime catalog. Mode B may JIT-execute
the same bytecode where that artifact already allows it. Store IPA/AAB must
not contain Cranelift or `MAP_JIT`. iOS 27+ Mode A may use WebKit's JIT
through WasmerSDK.

## Later WASIX registry (planned)

Catalog ABI and publish path:
[`repo.wawona.io/docs/wasm-abi.md`](https://github.com/Wawona/repo.wawona.io/blob/development/docs/wasm-abi.md).
WebC / wasinix / WASIX packages are **not shipping**. The execute table above
stays in force.

Before any WASIX package is treated as runnable everywhere, the **same
commit** must update this rule and product docs for:

1. Store iOS / iPadOS through OS 26: Pulley only. A WASIX package does **not**
   run on store Pulley.
2. macOS / Linux: today Wasmtime Cranelift only (no second Wasmer engine).
   WASIX-as-Wasmer-only **changes** that row. Do not link Wasmer into those
   products in a docs-only or registry tip.
3. `wpm install` stays Wasm package data. Never `docker pull`. Containers stay
   Machines kind `container`.

Hard reject until that gate: claim WASIX runs on Pulley or on store iOS /
iPadOS ≤ 26 Mode A.

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
  make CI or size look green. GitHub #156 (watchOS size gate) closed wontfix
- Treating tvOS / watchOS / visionOS wasm as optional or "transfer only"
- Hiding `wawona-wasm` from Watch Machines so Start cannot run hello-wasi-gui
- Cranelift native / `MAP_JIT` in App Store Apple-mobile
- Wasmer, WKWebView, or JSPI Wasm execute on iOS 13-26
- Linking WasmerSDK by raising the iOS deployment target above 13.0
- Calling wasm a VM or a container
- A wasm fuel burst that cannot cover one Wayland SHM frame. `chess-wawona`
  trapped `all fuel consumed` after `toplevel configure 0x0` on a 25_000_000
  budget. Keep the burst at 2_000_000_000, refill it after a `socket_recv`
  that returns bytes, and do not turn fuel off (a pure wasm spin must still trap)
- Claiming Metal / GLES / Vulkan wasm on watchOS (SDK has no public GPU)
- Claiming WASIX / WebC / wasinix packages are runnable on store Pulley or on
  iOS / iPadOS ≤ 26 Mode A before the Later WASIX registry same-commit gate

Canonical: [`../wasm-wasi.md`](../wasm-wasi.md), `wawona-native-compositors`,
`wawona-linux-vms-relay-runtime`. Cursor: `.cursor/rules/wawona-relay-wasm.mdc`.
Registry ABI: `repo.wawona.io/docs/wasm-abi.md`.
