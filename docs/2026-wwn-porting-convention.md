# Wawona. `wwn-*` Porting Convention

Any third-party software patched to run on Apple platforms and/or Android under
Wawona lives in a dedicated `wwn-<name>` repository in the Wawona GitHub org and
integrates through `wwn-toolchain`. This keeps upstream forks isolated, license-
clean, and independently CI-able.

## When to make a `wwn-*` repo

Make one when you must **patch** upstream source to be App Store compliant or to
cross-compile for Apple/Android (no JIT, no `fork+exec` of external binaries, no
`dlopen` of arbitrary code, sandbox-safe paths). Do **not** make one for
pure-Nix packaging of already-portable software.

Prefer **WASI / Wasm packages** for long-tail tools that do not need a native
port: compile to `wasm32-wasip1` / `wasm32-wasip2`, ship as documents or registry
artifacts for **Wawona Runtime** (`wwn-wasm`). See [`wasm-wasi.md`](./wasm-wasi.md).

## Existing repos (examples)

- `wwn-toolchain`. Shared cross toolchains (Apple + Android NDK), the hub.
- `wwn-weston`. Umbrella for Weston compositor + Weston clients on Apple/Android.
- `wwn-waypipe`. Waypipe with libssh2 (Apple mobile) / OpenSSH portable (Android) transports.
- `wwn-fastfetch`, `wwn-neofetch`, `wwn-zsh`. App Store-compliant CLI ports.
- `wwn-wasm`. Wawona Runtime (WASI P1/P2). Optional software distribution path.
- `wwn-containers` / `wwn-vms`. OCI containers and VMs (Machines kinds), distinct
  from Wasm packages.

**Removed:** `wwn-apt` (StoreKit / ODR “apt” module catalog). Do not revive it.

## Naming (authoritative)

- Repo: `wwn-<upstream-name>`, lowercase, hyphenated (`wwn-hyprland`, not
  `wwn-Hyprland`).
- Resolved exception: there is **no `wwn-utm` repo**. The UTM engine unit
  (QEMU-TCTI patches + build scripts + reference backends) is vendored inside
  `wwn-vms` at `dependencies/vms/utm/` (the old `Wawona/UTM` fork was never
  published; folding it into `wwn-vms` removed the phantom dependency).
- Bundle/attr names in Nix follow the same stem (`wwn-niri`, attr `niri` inside).

## Repo skeleton

Each `wwn-*` repo provides:

1. `flake.nix`. Exposes the port as packages keyed by target
   (`<name>-ios`, `-ios-sim`, `-android`, `-macos`), consuming `wwn-toolchain`.
2. `registryFragment`. A Nix attrset Wawona merges into its client registry so
   the app can discover/launch the port (see `dependencies/`).
3. `patches/`. Upstream patches, one anchored file per concern, verifiable by a
   `verify-*-patches.py` anchor script (pattern used by `wwn-weston`).
4. `README.md`. Port plan: upstream version, compliance deltas, delivery mode
   (native/nested/waypipe/wasm), current status.

## Planned ports

`wwn-niri`, `wwn-sway`, `wwn-hyprland`, `wwn-xfce`, `wwn-kde`, `wwn-gnome`,
`wwn-cosmic` (VM/UTM engine: vendored in `wwn-vms`, not a separate repo).
Full ports are downstream; repos start as
flake + `registryFragment` skeleton + port-plan README
(tracked by `p29-wwn-ports-scaffold`). Delivery is **native bundle** and/or
**Wasm package**. Never StoreKit ODR via `apt`.

### Toolkit smoke (companion)

- `wwn-sdl2` + `wwn-sdl2-gfx`. SDL2 Wayland + SDL2_gfx `testgfx` demo across
  the board (software/`wl_shm` first so tvOS/watchOS stay in scope without
  ANGLE). Tracking: [#107](https://github.com/Wawona/Wawona/issues/107),
  plan mirror [`issues/sdl2-gfx-demo-port.md`](./issues/sdl2-gfx-demo-port.md).
  Complements `wwn-kmscube` (GLES/iland path).
- `wwn-gtk`. GTK4 Wayland + `gtk4_demo` / `gtk4_demo_main` across the board
  (Cairo/`wl_shm` first on tvOS/watchOS; GL only where `allowGpu`). Prefer
  **core-bundled or Wasm** when size/compliance allow. Not ODR. Tracking:
  [#109](https://github.com/Wawona/Wawona/issues/109), plan mirror
  [`issues/gtk4-demo-port.md`](./issues/gtk4-demo-port.md). Shared foundation
  for `wwn-gtkgreet` / `wwn-gtklock` / `wwn-gnome`.
- `wwn-qt6` + `wwn-qmlscene`. Qt6 Wayland QPA + `qmlscene` demo across the
  board (software RHI / `wl_shm` first so tvOS/watchOS stay in scope without
  ANGLE). Tracking: [#108](https://github.com/Wawona/Wawona/issues/108),
  plan mirror [`issues/qmlscene-port.md`](./issues/qmlscene-port.md).
  Complements `wwn-kmscube` and `#107`; shared Qt foundation for `#74` `wwn-kde`.
