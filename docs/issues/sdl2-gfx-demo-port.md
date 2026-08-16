# SDL2_gfx demo port across the board

## Status

- Open — tracking issue [#107](https://github.com/Wawona/Wawona/issues/107)
- Class: toolkit-smoke companion (Tier 6 on [#77](https://github.com/Wawona/Wawona/issues/77))
- Repos (to scaffold): `wwn-sdl2`, `wwn-sdl2-gfx`

Keep this file synchronized with the GitHub issue body when phases or
delivery decisions change.

## Summary

Port the **SDL2_gfx** demo (`testgfx` / drawing-primitives smoke) as a
first-class Wawona Wayland client across the full platform matrix —
complementary to [`wwn-kmscube`](https://github.com/Wawona/wwn-kmscube)
(GBM/EGL/ANGLE cube). Prefer the **software / `wl_shm` renderer** so
**tvOS and watchOS** stay in scope without bundling
Vulkan/OpenGL/ANGLE (platform rule).

**Upstream pins (starting point):**

- SDL2 — latest stable with Wayland video (pin in Phase 0)
- SDL2_gfx **1.0.4** (nixpkgs `SDL2_gfx`)

**Env contract:** `SDL_VIDEODRIVER=wayland` (see
[`2026-toolkit-de-compat.md`](../2026-toolkit-de-compat.md)).

## Why

| Need | Why SDL2_gfx demo |
|------|-------------------|
| Toolkit smoke beyond Weston toys | Exercises SDL → Wayland path used by many games/tools |
| Non-GL path on constrained Apple targets | Software renderer works where ANGLE/Vulkan are forbidden (tvOS/watchOS) |
| Complements kmscube | kmscube = GLES/iland; this = 2D primitives / SHM (and optional GLES later) |
| Dispatch/integration rehearsal | Same in-process `*_main` model as kmscube / fastfetch / weston clients |

## Delivery model

| Platform | Artifact | Launch | Renderer |
|----------|----------|--------|----------|
| **macOS** | `bin/testgfx` + `libtestgfx.a` | fork/exec from Resources **or** in-process | software (default); GLES optional later |
| **iOS / iPadOS / visionOS** | `libtestgfx.a` + `testgfx_main` | in-process via `wawona-dispatch` / Machines | software SHM required first |
| **tvOS / watchOS** | `libtestgfx.a` + `testgfx_main` | in-process / remote as allowed | **software only** — never link ANGLE/MoltenVK/IOKit GL stack |
| **Android** | `libtestgfx_bin.so` PIE and/or archive | exec from `nativeLibraryDir` or in-process | software first; GLES optional |
| **Linux** | nixpkgs / host reference binary | baseline | nixpkgs SDL2 + SDL2_gfx |

**Hard rules (from platform targets):**

- Entire Apple family stays first-class — do not drop schemes to unblock another target.
- watchOS/tvOS: native + remote only; **no** VM/container; **no** bundled Vulkan/OpenGL/ANGLE/ICD.
- visionOS = macOS product parity for nested/bundled clients (including this demo once green).
- Gate in `mobile-platform-deps.nix` / `xcodegen.nix` / Machines profile kinds — not ad-hoc `#ifdef` sprawl.

## Architecture

```
zsh / Machines launcher
  → wawona_dispatch_inprocess("testgfx")   # Apple mobile
  → testgfx_main(argc, argv)
       → SDL2 (Wayland video, software renderer)
       → SDL2_gfx primitives
       → wl_shm buffers → Wawona compositor
```

**Registry keys (proposed):**

- `sdl2` — library recipes (`wwn-sdl2.registryFragment`)
- `sdl2-gfx` — lib + demo recipes (`wwn-sdl2-gfx.registryFragment`)
- Entry symbol: `testgfx_main` (header `testgfx.h`)

## Phases

### Phase 0 — Research & pins

- [ ] Confirm upstream demo entry (`test/testgfx.c` or equivalent in SDL2_gfx 1.0.4)
- [ ] Pin SDL2 + SDL2_gfx versions; document Wayland video + software renderer configure flags
- [ ] Map App Store constraints via wwn-mcp compliance knowledge
- [ ] Decide catalog class: **core bundled smoke** vs Wasm package (default proposal: core bundled if size allows)
- [ ] Keep [#107](https://github.com/Wawona/Wawona/issues/107) and this file in sync

### Phase 1 — Scaffold `wwn-sdl2`

- [ ] New repo: `flake.nix`, `registryFragment.sdl2`, per-platform stubs
- [ ] Build SDL2 **Wayland-only** video; disable UIKit/AppKit present paths for nested Wawona
- [ ] Apple mobile: static archive
- [ ] Patch-anchor CI when patches land
- [ ] Smoke: Wayland window create/destroy on macOS + one mobile target

### Phase 2 — Scaffold `wwn-sdl2-gfx`

- [ ] New repo depending on `wwn-sdl2` (+ `wwn-toolchain`)
- [ ] Build SDL2_gfx 1.0.4; demo as `libtestgfx.a` with `-Dmain=testgfx_main`
- [ ] macOS standalone `testgfx` binary + `include/testgfx.h`
- [ ] README port plan + zlib license notes

### Phase 3 — Per-platform recipes

- [ ] macOS / iOS / iPadOS / visionOS / tvOS / watchOS / Android / Linux
- [ ] tvOS/watchOS: assert no ANGLE/MoltenVK/IOKit GL on the link line
- [ ] Flake outputs: `testgfx-ios`, `testgfx-macos`, `testgfx-android`, …

### Phase 4 — Wawona integration

- [ ] Flake inputs + `registryFragment` merge
- [ ] `wawona-dispatch.c`: `testgfx` → `testgfx_main`
- [ ] RootFS / Machines launcher; `SDL_VIDEODRIVER=wayland`
- [ ] `xcodegen.nix` / `mobile-platform-deps.nix` / Android gradlegen

### Phase 5 — Smoke & capability lane

- [ ] Full Apple family + Android software-path smoke
- [ ] agent-device replay once UI entry exists
- [ ] Rows in [`testing/everywhere-matrix.md`](../testing/everywhere-matrix.md)

### Phase 6 — CI, docs, lock

- [ ] Per-repo verify scripts + sample builds
- [ ] Update porting convention / toolkit / universal-client docs
- [ ] Bump `flake.lock`; wwn-mcp reindex

## Key risks

| Risk | Mitigation |
|------|------------|
| SDL2 pulls UIKit/AppKit video by default on Apple | Configure/patch Wayland-only |
| Archive size | Measure; demote to Wasm Runtime package if needed |
| `exit()` kills host on mobile | In-process exit shim (kmscube/fastfetch pattern) |
| Accidental ANGLE on tvOS/watchOS | CI link-flag assert + deps gating |
| Audio/joystick subsystems | Disable until needed (#46 is separate) |

## Done when

- [ ] `wwn-sdl2` + `wwn-sdl2-gfx` are source of truth
- [ ] `testgfx` / `testgfx_main` runs on macOS, iOS, iPadOS, tvOS, watchOS, visionOS, Android (software path)
- [ ] tvOS/watchOS builds do not link ANGLE/MoltenVK/Vulkan ICDs
- [ ] Dispatch + Machines/zsh launch documented and smoke-tested
- [ ] Docs + CI green for sample outputs

## Related

- GitHub: [#107](https://github.com/Wawona/Wawona/issues/107)
- Sequencing: [#77](https://github.com/Wawona/Wawona/issues/77)
- kmscube: [#58](https://github.com/Wawona/Wawona/issues/58)
- Game Controller (adjacent): [#46](https://github.com/Wawona/Wawona/issues/46)
- [`2026-wwn-porting-convention.md`](../2026-wwn-porting-convention.md)
- [`2026-toolkit-de-compat.md`](../2026-toolkit-de-compat.md)
- [`2026-universal-client-strategy.md`](../2026-universal-client-strategy.md)
