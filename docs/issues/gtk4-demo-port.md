# gtk4-demo port across the board (`wwn-gtk`)

## Status

- Open — tracking issue [#109](https://github.com/Wawona/Wawona/issues/109)
- Class: toolkit-smoke companion (Tier 6 on [#77](https://github.com/Wawona/Wawona/issues/77))
- Delivery: **`wwn-apt` optional module** (`planned` → `approved`)
- Repo (to scaffold): [`wwn-gtk`](https://github.com/Wawona/wwn-gtk)

Keep this file synchronized with the GitHub issue body when phases or
delivery decisions change.

## Summary

Port **GTK4** + **`gtk4-demo`** as a first-class Wawona Wayland client across
the full platform matrix. Establishes the shared GTK4 foundation for greeters
and GNOME — complementary to the SDL2 toolkit smoke in
[#107](https://github.com/Wawona/Wawona/issues/107).

**Upstream pins (starting point):**

- GTK4 — pin from nixpkgs `gtk4` in Phase 0
- Demo entry: upstream `demos/gtk-demo` → `gtk4_demo_main`

**Env contract:** `GDK_BACKEND=wayland` (see
[`2026-toolkit-de-compat.md`](../2026-toolkit-de-compat.md)).

## Why

| Need | Why gtk4-demo |
|------|----------------|
| Toolkit smoke for GTK family | Exercises GDK Wayland path used by greeters, GNOME clients, XFCE |
| Shared foundation | #75 / #101 / #102 must not each re-vendor GTK4 |
| Matrix rehearsal | Same in-process `*_main` + apt-module pattern as foot/neovim; sibling to #107 |
| Constrained Apple targets | Cairo/`wl_shm` path keeps tvOS/watchOS in scope without ANGLE |

## Delivery model

| Platform | Artifact | Launch | Renderer |
|----------|----------|--------|----------|
| **macOS** | `bin/gtk4-demo` (+ archive optional) | NSTask from Resources **or** in-process | Wayland; GL demos OK |
| **iOS / iPadOS / visionOS** | `libgtk4_demo.a` + `gtk4_demo_main` | in-process after apt install | Cairo/SHM first; GL behind `allowGpu` |
| **tvOS / watchOS** | same archive | in-process | **Cairo/SHM only** — never ANGLE/MoltenVK/IOKit |
| **Android** | `libgtk4_demo_bin.so` / `libgtk4_demo.so` | exec or in-process | SHM first; GLES optional |
| **Linux** | nixpkgs / host `gtk4-demo` | CI / compat-matrix baseline | reference |

**Hard rules (from platform targets):**

- Entire Apple family stays first-class — do not drop schemes to unblock another target.
- watchOS/tvOS: native + remote only; **no** VM/container; **no** bundled Vulkan/OpenGL/ANGLE/ICD.
- visionOS = macOS product parity for this module once green.
- Gate in `mobile-platform-deps.nix` / `xcodegen.nix` / Machines — not ad-hoc `#ifdef` sprawl.
- Optional-module link only (do **not** permanently force-load into base IPA).

## Architecture

```
zsh / Machines (after apt install gtk4-demo)
  → wawona_dispatch_inprocess("gtk4-demo")   # Apple mobile
  → gtk4_demo_main(argc, argv)
       → GTK4 (GDK Wayland)
       → Cairo/wl_shm  (all platforms)
       → GLES/ANGLE    (allowGpu platforms only)
       → Wawona compositor
```

**Registry keys (proposed):**

- `gtk4` — library closure (`wwn-gtk.registryFragment`)
- `gtk4-demo` — demo client recipes
- Entry symbol: `gtk4_demo_main`

**Consumers later (do not re-vendor GTK4):** `wwn-gtkgreet` (#101),
`wwn-gtklock` (#102), `wwn-gnome` (#75).

## Phases

### Phase 0 — Research & pins

- [ ] Pin GTK4 version from nixpkgs; document Wayland-only configure flags
- [ ] Map demo entry (`demos/gtk-demo` → `gtk4_demo_main`)
- [ ] Inventory missing leaf libs (gdk-pixbuf, graphene, epoxy, …)
- [ ] Catalog class locked: **`wwn-apt` optional** (not core-bundled)
- [ ] Keep [#109](https://github.com/Wawona/Wawona/issues/109) and this file in sync

### Phase 1 — Scaffold `wwn-gtk`

- [ ] New repo: `flake.nix`, `registryFragment.{gtk4,gtk4-demo}`, per-platform stubs
- [ ] README port plan + license notes
- [ ] `wwn-apt/catalog/modules/gtk4-demo.yaml` with `status: planned`
- [ ] Update catalog allowlists / validate scripts

### Phase 2 — Toolchain leaf libs + GTK4 cross

- [ ] Add missing shared leaf libs to `wwn-toolchain` only as needed; keep **GTK4 in `wwn-gtk`**
- [ ] Build GTK4 **Wayland-only**; sandbox-safe GSettings/schemas/icons
- [ ] Apple mobile compliance + patch-anchor CI
- [ ] First green: macOS `gtk4-demo` binary

### Phase 3 — `gtk4_demo_main` + matrix recipes

- [ ] `libgtk4_demo.a` + header with `gtk4_demo_main`
- [ ] tvOS/watchOS: Cairo/SHM only; CI assert no ANGLE/MoltenVK/IOKit
- [ ] visionOS: macOS product parity once green
- [ ] Android NDK PIE/archive recipes
- [ ] Flake outputs: `gtk4-demo-macos`, `gtk4-demo-ios`, …

### Phase 4 — Wawona integration (optional-module path)

- [ ] Flake input `wwn-gtk` + merge `registryFragment`
- [ ] Gate in `mobile-platform-deps.nix` / `xcodegen.nix` only when module linked
- [ ] Dispatch: `"gtk4-demo" → gtk4_demo_main`; inject `GDK_BACKEND=wayland`
- [ ] Machines/Android: after `apt install` — **not** permanent core `kBundledClients`

### Phase 5 — Smoke & capability lane

- [ ] macOS / iOS / iPadOS / visionOS / tvOS / watchOS / Android smoke
- [ ] agent-device iOS smoke once UI entry exists
- [ ] Rows in `docs/testing/everywhere-matrix.md` + compat-matrix script

### Phase 6 — CI, docs, apt flip, lock

- [ ] `verify-gtk-*-patches.py` + sample `nix build` CI
- [ ] Flip `wwn-apt` `planned` → `approved`
- [ ] Update porting-convention (sibling to #107), toolkit-de-compat, universal-client-strategy, wwn-repos-catalog
- [ ] Bump `flake.lock`; wwn-mcp reindex; note on #75

## Related

- Sequencing: [#77](https://github.com/Wawona/Wawona/issues/77)
- Sibling toolkit smoke: [#107](https://github.com/Wawona/Wawona/issues/107)
- GTK consumers: [#75](https://github.com/Wawona/Wawona/issues/75) · [#101](https://github.com/Wawona/Wawona/issues/101) · [#102](https://github.com/Wawona/Wawona/issues/102)
- Lockscreen / greeter UI: [#103](https://github.com/Wawona/Wawona/issues/103) · [#104](https://github.com/Wawona/Wawona/issues/104)
- Phase 29 DE ports: [#70](https://github.com/Wawona/Wawona/issues/70) · [#72](https://github.com/Wawona/Wawona/issues/72) · [#73](https://github.com/Wawona/Wawona/issues/73) · [#74](https://github.com/Wawona/Wawona/issues/74)
- Linux GTK shell parity: [#90](https://github.com/Wawona/Wawona/issues/90)
- GL contrast: [#58](https://github.com/Wawona/Wawona/issues/58)
- Cairo teardown risk: [#96](https://github.com/Wawona/Wawona/issues/96)
- UI catalog drift: [#67](https://github.com/Wawona/Wawona/issues/67)
