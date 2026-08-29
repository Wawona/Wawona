# Wawona. Universal Client Support & Bundling Strategy

Goal: run "any" Wayland client without shipping a multi-gigabyte app or taking
years to build every client for every platform. Strategy is **lazy, cached,
tiered**.

## Tiers

1. **Core bundled (always present).** Minimal Weston toytoolkit clients used for
   smoke tests: `weston-simple-shm`, `weston-flower`, `weston-terminal` (mobile
   stub), `weston-smoke`, `weston-clickdot`. Statically linked; tiny.
   Planned toolkit companion: SDL2_gfx `testgfx` (software/`wl_shm`, full Apple
   matrix including tvOS/watchOS). [#107](https://github.com/Wawona/Wawona/issues/107).
   Larger native ports that ship in the binary (foot, neovim, …) stay **bundled
   or weak-linked `*_main`**, not StoreKit ODR.
2. **Wasm packages (Wawona Runtime).** Long-tail CLI and Wayland clients compiled
   to WASI P1/P2 (Component Model). Users drop `.wasm` via Files.app / SCP, or
   install via the bundled Wasm package client (OCI artifacts preferred). The
   reviewed interpreter is `wwn-wasm`; packages are **data**, not Mach-O.
   See [`wasm-wasi.md`](./wasm-wasi.md). **Not** a container machine and **not**
   `wwn-apt` / StoreKit modules (removed).
3. **Remote (waypipe).** Anything installable on a remote Linux host or NixOS VM
   runs there and streams in. Zero client bundling cost; widest coverage.
4. **Container / VM machines (separate).** OCI Linux images and full VMs are
   Machines kinds (`container` / `virtual_machine`) via `wwn-containers` /
   `wwn-vms`. Not the Wasm package path. See [`vms-containers.md`](./vms-containers.md).

## Per-client caching

- **Build cache:** each `wwn-*` port is its own flake; owner CI pushes to
  **FlakeHub Cache** so a client rebuilds only when *its* source changes. Not on
  every Wawona build. Shared cache: [`flakehub-cache.md`](./flakehub-cache.md)
  and [`2026-build-ci-optimization.md`](./2026-build-ci-optimization.md).
- **Runtime Wasm store:** installed components live under the app sandbox
  (Documents / Application Support); Files.app sideload and the package client
  share the same Runtime.
- **Lazy link:** ANGLE/Vulkan dylibs and GL client archives are only linked into
  targets that allow GPU; watchOS stays on the CPU present path.

## Decision tree

```text
Need it always / tiny smoke?                   -> core bundled native
Need Linux rootfs / Docker Hub image?          -> Machines kind container (wwn-containers)
Need full guest OS?                            -> Machines kind virtual_machine (wwn-vms)
Need long-tail tool/GUI without native port?   -> WASI .wasm → Wawona Runtime
Need software already on a remote Linux box?   -> waypipe / SSH
```
