# Wawona — Universal Client Support & Bundling Strategy

Goal: run "any" Wayland client without shipping a multi-gigabyte app or taking
years to build every client for every platform. Strategy is **lazy, cached,
tiered**.

## Tiers

1. **Core bundled (always present).** Minimal Weston toytoolkit clients used for
   smoke tests: `weston-simple-shm`, `weston-flower`, `weston-terminal` (mobile
   stub), `weston-smoke`, `weston-clickdot`. Statically linked; tiny.
   Planned toolkit companion: SDL2_gfx `testgfx` (software/`wl_shm`, full Apple
   matrix including tvOS/watchOS) — [#107](https://github.com/Wawona/Wawona/issues/107).
2. **On-demand modules (`wwn-apt`).** Larger apps/DEs (foot, neovim, sway, niri,
   hyprland, xfce, kde, cosmic) are StoreKit products / ODR tags fetched only
   when the user installs them. Not in the base download. See
   [`2026-wwn-porting-convention.md`](./2026-wwn-porting-convention.md).
3. **Remote (waypipe).** Anything installable on a remote Linux host or NixOS VM
   runs there and streams in. Zero client bundling cost; widest coverage.

## Per-client caching

- **Build cache:** each `wwn-*` port is its own flake; owner CI pushes to
  **FlakeHub Cache** so a client rebuilds only when *its* source changes — not on
  every Wawona build. Shared cache: [`flakehub-cache.md`](./flakehub-cache.md)
  and [`2026-build-ci-optimization.md`](./2026-build-ci-optimization.md).
- **Runtime cache:** ODR/StoreKit assets land in a managed cache dir tracked by
  `WWNModuleManager`'s `installed.json`; eviction is LRU by Apple's ODR policy on
  device, explicit `apt remove` otherwise.
- **Lazy link:** ANGLE/Vulkan dylibs and GL client archives are only linked into
  a session when the client actually needs GPU transport (else SHM path, no load).

## Why this scales

- Base app stays small (core clients only) → fast review, fast install.
- CI builds the base + core clients on every PR; heavy ports build in their own
  repos' CI and publish to the shared cache (nightly full-matrix pulls them).
- Coverage grows by adding `wwn-*` repos + `wwn-apt` catalog rows, not by growing
  the monolith.

## Delivery decision tree

```
client small + store-safe + frequently used?  -> core bundled
client large but store-portable?               -> wwn-apt module (ODR/StoreKit)
client not portable / needs full Linux?        -> waypipe (remote or VM)
```
