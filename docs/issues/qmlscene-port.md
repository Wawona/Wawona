# Qt qmlscene port across the board

## Status

- Open — tracking issue [#108](https://github.com/Wawona/Wawona/issues/108)
- Class: toolkit-smoke companion (Tier 6 on [#77](https://github.com/Wawona/Wawona/issues/77))
- Repos (to scaffold): `wwn-qt6`, `wwn-qmlscene`

Keep this file synchronized with the GitHub issue body when phases or
delivery decisions change.

## Summary

Port **qmlscene** (Qt Quick viewer) as a first-class Wawona Wayland client
across the full platform matrix — complementary to
[`wwn-kmscube`](https://github.com/Wawona/wwn-kmscube) (GLES/iland) and
[#107](https://github.com/Wawona/Wawona/issues/107) (`testgfx` / SDL2 software
SHM). Prefer **Qt Quick software RHI** so **tvOS and watchOS** stay in scope
without bundling Vulkan/OpenGL/ANGLE (platform rule).

**Repos (to scaffold):**

- [`wwn-qt6`](https://github.com/Wawona/wwn-qt6) — Qt6 foundation: `qtbase` +
  `qtwayland` QPA + `qtdeclarative` (no JIT); shared later by
  [#74](https://github.com/Wawona/Wawona/issues/74) `wwn-kde`
- [`wwn-qmlscene`](https://github.com/Wawona/wwn-qmlscene) — `qmlscene` / demo
  entry (`qmlscene_main`), consumes `wwn-qt6`

**Catalog class:** `wwn-apt` **optional** (`status: planned` → `approved` when
green). Qt closure is too large for core-bundled weston-toy tier.

**Env contract:** `QT_QPA_PLATFORM=wayland` (see
[`2026-toolkit-de-compat.md`](../2026-toolkit-de-compat.md)).

## Why

| Need | Why qmlscene |
|------|----------------|
| Toolkit smoke for Qt/QML | Exercises Qt Wayland QPA + QML engine path used by KDE/Plasma clients |
| Non-GL path on constrained Apple targets | Software RHI works where ANGLE/Vulkan are forbidden (tvOS/watchOS) |
| Complements kmscube + SDL2_gfx | kmscube = GLES/iland; testgfx = 2D SHM; qmlscene = QML / Scene Graph |
| Unblocks #74 Qt recipes | `wwn-qt6` is the shared foundation; kde stays Plasma/KWin |
| Dispatch/integration rehearsal | Same in-process `*_main` model as kmscube / fastfetch / weston clients |

## Delivery model

| Platform | Artifact | Launch | Renderer |
|----------|----------|--------|----------|
| **macOS** | `bin/qmlscene` + archive | fork/exec from Resources **or** in-process | software (default); GPU RHI optional later |
| **iOS / iPadOS / visionOS** | `libqmlscene.a` + `qmlscene_main` | in-process via `wawona-dispatch` / Machines | software RHI required first |
| **tvOS / watchOS** | `libqmlscene.a` + `qmlscene_main` | in-process / remote as allowed | **software only** — never link ANGLE/MoltenVK/IOKit GL stack |
| **Android** | PIE and/or archive | exec from `nativeLibraryDir` or in-process | software first; GLES optional |
| **Linux** | nixpkgs / host reference binary | baseline | host Qt6 |

**Hard rules (from platform targets):**

- Entire Apple family stays first-class — do not drop schemes to unblock another target.
- watchOS/tvOS: native + remote only; **no** VM/container; **no** bundled Vulkan/OpenGL/ANGLE/ICD.
- visionOS = macOS product parity for nested/bundled clients (including this demo once green).
- Gate in `mobile-platform-deps.nix` / `xcodegen.nix` / Machines profile kinds — not ad-hoc `#ifdef` sprawl.

**Compliance (locked):**

- QML **no JIT** (interpret/AOT only)
- No `dlopen` of downloaded plugins on Apple mobile
- Static/in-process entry; exit shim so `qmlscene` cannot `exit()` the host (kmscube/fastfetch pattern)
- Sandbox-safe QML import paths as read-only bundle data

## Architecture

```
zsh / Machines launcher
  → wawona_dispatch_inprocess("qmlscene")   # Apple mobile
  → qmlscene_main(argc, argv)
       → Qt6 (qtwayland QPA, QT_QPA_PLATFORM=wayland)
       → qtdeclarative (no JIT)
       → software RHI → wl_shm → Wawona compositor
       → (allowGpu platforms only) ANGLE/Metal RHI optional later
```

**Registry keys (proposed):**

- `qt6` — library recipes (`wwn-qt6.registryFragment`)
- `qmlscene` — client recipes (`wwn-qmlscene.registryFragment`)
- Entry symbol: `qmlscene_main` (header `qmlscene.h`)

## Phases

### Phase 0 — Research & pins

- [ ] Confirm upstream qmlscene entry in `qtdeclarative` (version pin)
- [ ] Pin Qt6 set (`qtbase` + `qtwayland` + `qtdeclarative`); document software RHI flags
- [ ] Map App Store constraints (no JIT, no dlopen of downloaded plugins, static archive on Apple mobile)
- [ ] Confirm catalog class: **`wwn-apt` optional** (not core-bundled)
- [ ] Keep [#108](https://github.com/Wawona/Wawona/issues/108) and this file in sync

### Phase 1 — Scaffold `wwn-qt6`

- [ ] New repo: `flake.nix`, `registryFragment.qt6`, per-platform stubs
- [ ] Build `qtbase` + Wayland QPA + `qtdeclarative` with **JIT off**
- [ ] No Plasma / KDE Frameworks in this repo
- [ ] Apple mobile: static archives
- [ ] Patch-anchor CI when patches land
- [ ] Smoke: Qt Wayland window create/destroy on macOS + one mobile target

### Phase 2 — Scaffold `wwn-qmlscene`

- [ ] New repo depending on `wwn-qt6` (+ `wwn-toolchain`)
- [ ] Build qmlscene as `libqmlscene.a` with `-Dmain=qmlscene_main` (or equivalent)
- [ ] macOS standalone `qmlscene` binary + `include/qmlscene.h`
- [ ] Bundle a minimal sample `.qml` as read-only data
- [ ] README port plan + Qt license posture for store

### Phase 3 — Per-platform recipes

- [ ] macOS / iOS / iPadOS / visionOS / tvOS / watchOS / Android / Linux
- [ ] tvOS/watchOS: assert no ANGLE/MoltenVK/IOKit GL on the link line
- [ ] Flake outputs: `qmlscene-ios`, `qmlscene-macos`, `qmlscene-android`, …

### Phase 4 — Wawona integration

- [ ] Flake inputs + `registryFragment` merge
- [ ] `wawona-dispatch.c`: `qmlscene` → `qmlscene_main`
- [ ] RootFS / Machines launcher; `QT_QPA_PLATFORM=wayland` (+ software RHI env)
- [ ] `xcodegen.nix` / `mobile-platform-deps.nix` / Android gradlegen
- [ ] `wwn-apt` catalog row `planned` → `approved` when green

### Phase 5 — Smoke & capability lane

- [ ] Full Apple family + Android software-path smoke
- [ ] iPadOS / visionOS: one Wayland client ↔ one host window
- [ ] agent-device replay once UI entry exists
- [ ] Rows in [`testing/everywhere-matrix.md`](../testing/everywhere-matrix.md)

### Phase 6 — CI, docs, lock

- [ ] Per-repo verify scripts + sample builds
- [ ] Update porting convention / toolkit / universal-client docs
- [ ] Bump `flake.lock`; wwn-mcp reindex
- [ ] Note on [#74](https://github.com/Wawona/Wawona/issues/74): `wwn-kde` can consume `wwn-qt6`

## Key risks

| Risk | Mitigation |
|------|------------|
| Qt Quick assumes GPU Scene Graph | Software RHI first; GPU only behind `allowGpu` |
| QML JIT / MAP_JIT on Apple | Force interpret-only; CI assert |
| Massive archive size | apt ODR/optional — never core-bundled by default |
| Plugin/`dlopen` model vs store | Static modules / bundled imports only on mobile |
| Accidental ANGLE on tvOS/watchOS | CI link-flag assert + deps gating |
| Overlap with #74 | `wwn-qt6` shared; kde stays Plasma/KWin |
| `exit()` kills host on mobile | In-process exit shim (kmscube/fastfetch pattern) |

## Done when

- [ ] `wwn-qt6` + `wwn-qmlscene` are source of truth
- [ ] `qmlscene` / `qmlscene_main` runs on macOS, iOS, iPadOS, tvOS, watchOS, visionOS, Android (software RHI)
- [ ] tvOS/watchOS builds do not link ANGLE/MoltenVK/Vulkan ICDs
- [ ] Dispatch + Machines/zsh + apt launch documented and smoke-tested
- [ ] Docs + CI green for sample outputs
- [ ] `wwn-apt` entry `planned` → `approved` when green

## Related

- GitHub: [#108](https://github.com/Wawona/Wawona/issues/108)
- Sequencing: [#77](https://github.com/Wawona/Wawona/issues/77)
- SDL2_gfx: [#107](https://github.com/Wawona/Wawona/issues/107)
- kmscube: [#58](https://github.com/Wawona/Wawona/issues/58)
- KDE / Qt consumer: [#74](https://github.com/Wawona/Wawona/issues/74)
- [`2026-wwn-porting-convention.md`](../2026-wwn-porting-convention.md)
- [`2026-toolkit-de-compat.md`](../2026-toolkit-de-compat.md)
- [`2026-universal-client-strategy.md`](../2026-universal-client-strategy.md)
