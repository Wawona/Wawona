# OpenGL Cube + Vulkan Cube port (mirror kmscube)

## Status

- Open — tracking issue [#113](https://github.com/Wawona/Wawona/issues/113)
- `vkcube`: **done on Apple.** Full platform recipe set, `_vkcube_main` linked,
  runs on macOS against both ICDs under selection (`libMoltenVK.dylib` /
  `libvulkan_kosmickrisp.dylib`, each logged `(selected)`) and on the iOS
  simulator. Android `swiftshader` selection is a known FUCKUP — see
  `docs/iland-graphics-progress.md`.
- `opengl-cube`: **was a duplicate of `kmscube`; now its own upstream.** Apple
  recipes existed only for Android before 2026-07-25, so Start on macOS failed
  with `Could not find executable opengl-cube in app bundle`. Recipes added,
  archive linked (`_opengl_cube_main`), and it rendered 300+ presents through
  ANGLE — but as the *same* program as kmscube. Re-pointed at
  c2d7fa/opengl-cube and rebuilt; **runtime proof of the ported renderer is
  still pending** (host build succeeded, render not yet observed).
- Sources of truth for platform status stay `docs/iland-graphics-progress.md`
  (grades) and this file (packaging/launch).
- Class: GPU bundled-client smoke (depends on nested-client / iland presenter foundations)
- Repos: [`wwn-kmscube`](https://github.com/Wawona/wwn-kmscube) (primary), [`wwn-iland`](https://github.com/Wawona/wwn-iland) (ldflags only), [`Wawona`](https://github.com/Wawona/Wawona) (link + launch)

Keep this file synchronized with the GitHub issue body when phases or
delivery decisions change. Cursor plan: `port_gl_vk_cubes_f44b72b6`.

## Related issues

| Issue | Why it matters |
|-------|----------------|
| [#58](https://github.com/Wawona/Wawona/issues/58) | KMS Cube DRM/`/dev/dri/card0` — same virtual-DRM present path |
| [#110](https://github.com/Wawona/Wawona/issues/110) | Nested launch umbrella; item 4 routes `kmscube` → iland Metal — **generalize for the two new ids** |
| [#112](https://github.com/Wawona/Wawona/issues/112) | Non-Weston Starts must log as `KMSCUBE` / `VKCUBE`, never `[WESTON]` |
| [#107](https://github.com/Wawona/Wawona/issues/107) | Sibling demo-port pattern (software SHM complement; do not conflate) |
| [#77](https://github.com/Wawona/Wawona/issues/77) | ROADMAP sequencing |

## Summary

Complete stubbed Machines clients **OpenGL Cube** (`opengl-cube`) and
**Vulkan Cube** (`vkcube`) so they run on device on Apple GPU platforms +
Android by **copying the kmscube packaging path**:

`registry → lib*_main.a → iland-gl-ldflags → in-process Machines Start → WWNIlandPresenter`.

Catalog UI already lists both. Runtime today: Apple unknown id / missing
binary; Android archives optional but not product-linked; `vkcube` is an
instance-create smoke stub.

## Upstream decisions (locked)

| Catalog id | Do not use | Use |
|------------|------------|-----|
| `kmscube` | — | **[embtom/kmscube](https://github.com/embtom/kmscube)**, vendored at `wwn-kmscube/upstream/` (`kmscube.c`, `esUtil.c`, `kmscube_compat.h`) |
| `opengl-cube` | `kmscube.c` under `-Dmain=opengl_cube_main` | **[c2d7fa/opengl-cube](https://github.com/c2d7fa/opengl-cube)** @ `daba3b8` (CC0), vendored under `wwn-kmscube/upstream/opengl-cube/` and ported off GLFW/GLEW onto iland KMS |
| `vkcube` | LunarG Vulkan-Tools cube (not preferred here); current `upstream/vkcube.c` stub | **[krh/vkcube](https://github.com/krh/vkcube)** vendored under `wwn-kmscube/upstream/vkcube/` |

**Revised 2026-07-25.** This table previously sent `opengl-cube` at the *same*
mesa/kmscube sources under a renamed entry point. That shipped: both ids built,
both ran, and both drew the identical cube, because they were the identical
program. Two catalog entries for one demo is a product bug, so `opengl-cube` is
now its own upstream. The three cubes are distinct **software**, not three
labels on one renderer.

**Present path — corrected 2026-07-25 (second correction).** The three cubes must
differ by **graphics path**, not only by renderer. Getting this wrong is what
produced a duplicate client in the first place:

| Client | Path | What it proves |
|---|---|---|
| KMS Cube | iland's **userspace KMS/DRM** — opens the virtual card, GBM buffers, `drmModePageFlip` | that DRM/KMS client semantics work with **no kernel and no Linux**; that is the entire point of wwn-iland |
| OpenGL Cube | **Wawona's Wayland compositor + our EGL/OpenGL** — `wl_surface` + `wl_egl_window` + `eglSwapBuffers` | that a stock Wayland GL client works on our compositor |
| Vulkan Cube | Vulkan (KMS today, via the ICD under selection) | that Vulkan reaches the host GPU |

So OpenGL Cube must **not** open `/dev/dri/card0`. It is an ordinary Wayland
client. It still needs an **ES3** context with a **depth buffer** (upstream
depth-tests), where kmscube needs neither.

**Status of this correction — done.** The c2d7fa vendoring is correct and stays,
and `upstream/opengl-cube/opengl_cube.c` is now a real Wayland client
(`wl_display` / xdg-shell / `wl_egl_window`), no longer the iland KMS host copied
from kmscube. Launch wiring followed: `opengl-cube` was removed from
`WWNIsIlandGpuCubeClientId` and from both presenters' cube tables, so macOS
launches it out-of-process as an ordinary bundled Wayland client and iOS launches
it in-process through `WWNClientMainForId` like `weston-simple-shm`. The
"duplicated DRM scaffolding" note in Phase 1a is moot: a Wayland client has none.

**Resolved — Apple mobile can use Wayland-EGL.** The older claim that the iOS
family cannot use `wl_egl_window` / `EGL_PLATFORM_WAYLAND_KHR` was an artifact of
iland having no Wayland winsys, not a platform limit: nothing in the path needs
anything unavailable on iOS. iland now carries the winsys on
macOS/iOS/iPadOS/visionOS (IOSurface-backed `wl_buffer`s posted through
`zwp_linux_dmabuf_v1` with the IOSurface-id modifier), plus an AHardwareBuffer
variant for Android. tvOS/watchOS stay on the fallback.
`simple-egl-apple-mobile-stub.c` is therefore obsolete as a *statement of
impossibility*; it remains only until the mobile unstub lands.
- Vulkan Cube = krh/vkcube **KMS/GBM** against iland virtual DRM (`/dev/dri/card0` → fd 42) + host Vulkan ICD (MoltenVK Apple; device Vulkan / SwiftShader Android).
- tvOS / watchOS: **never** link or show these clients (`allowsGpuStack == false`).

**Prerequisite:** wwn-iland supplies OpenGL (ANGLE) + Vulkan + software-fallback for DRM/GBM bind. This issue owns **client packaging + launch wiring**, not a new iland graphics architecture.

## Delivery model

| Platform | Artifact | Launch |
|----------|----------|--------|
| **macOS** | `libopengl_cube.a` / `libvkcube.a` + `bin/opengl-cube` / `bin/vkcube` | `vkcube` = **in-process** iland presenter; `opengl-cube` = out-of-process bundled Wayland client (`bin/opengl-cube`) |
| **iOS / iPadOS / visionOS** | archives only (`*_main`) | `vkcube` in-process via Machines → WaypipeRunner → iland presenter; `opengl-cube` in-process via `WWNClientMainForId`, same as `weston-simple-shm` |
| **Android** | archives linked into `libwawona.so` | JNI → presenter path (mirror `kmscube_stub_main`) |
| **tvOS / watchOS** | not built / not linked | hidden + refuse |

Symbols:

| Client id | Archive | Entry | Header |
|-----------|---------|-------|--------|
| `kmscube` (existing) | `libkmscube.a` | `kmscube_main` | `kmscube.h` |
| `opengl-cube` | `libopengl_cube.a` | `opengl_cube_main` | `opengl_cube.h` |
| `vkcube` | `libvkcube.a` | `vkcube_main` | `vkcube.h` |

---

# AI how-to (execute in order)

Agents: follow phases sequentially. Prefer editing by **copying kmscube files**
and renaming symbols over inventing new build systems. Work on branch
`development` in each repo (`git checkout development && git pull --ff-only`).
Never force-push `master`/`development`. Do not commit unless the human asks.

### Hard don'ts

- Do **not** ship GLFW or GLEW. c2d7fa/opengl-cube *is* vendored, but ported off
  them onto Wayland + `wl_egl_window` — neither library reaches a target.
- Do **not** give two catalog ids the same renderer under different entry-point
  names. If two clients look the same at runtime, one of them is wrong.
- Do **not** route `opengl-cube` through the iland KMS presenter. That is what
  made it indistinguishable from KMS Cube (and, when both paths raced, made
  Start sometimes show kmscube). It is a Wayland client on every target that
  has a GPU stack.
- Do **not** add ANGLE/Vulkan/MoltenVK to tvOS/watchOS deps or schemes.
- Do **not** ship Mode B `libwayland-mac.dylib` for these clients.
- Do **not** leave Android calling `opengl_cube_main` / `vkcube_main` without
  the same iland presenter setup kmscube uses.
- Do **not** log Starts under `[WESTON]` (#112) — use `KMSCUBE` / `VKCUBE`.

### Mental model (copy this)

```text
wwn-kmscube/upstream  →  per-platform .nix  →  libCLIENT.a (CLIENT_main)
       ↓
registryFragment.CLIENT in wwn-kmscube/flake.nix
       ↓
Wawona mobile-platform-deps / android.nix builds CLIENT when allowGpu
       ↓
iland-gl-ldflags / iland-gl-android-ldflags pull archive into app
       ↓
Machines Start id=CLIENT
       ↓
WWNWaypipeRunner → ensureIlandPresentationView → pthread → CLIENT_main
       ↓
iland virtual DRM + present (Metal / Android overlay)
```

---

## Phase 0 — Branch + inventory (read-only)

1. Confirm branches:
   ```bash
   cd ~/Wawona/wwn-kmscube && git checkout development && git pull --ff-only
   cd ~/Wawona/wwn-iland   && git checkout development && git pull --ff-only
   cd ~/Wawona/Wawona      && git checkout development && git pull --ff-only
   ```
2. Read the kmscube template end-to-end:
   - `wwn-kmscube/dependencies/clients/kmscube/{apple-mobile,macos,android,ios}.nix`
   - `wwn-kmscube/flake.nix` (`registryFragment.kmscube`)
   - `wwn-iland/dependencies/generators/iland-gl-ldflags.nix`
   - `wwn-iland/dependencies/generators/iland-gl-android-ldflags.nix`
   - `Wawona/dependencies/wawona/mobile-platform-deps.nix` (`allowGpu` block)
   - `Wawona/src/platform/macos/WWNIlandPresenter.m` (`launchNestedKmscubeWithWidth:`)
   - `Wawona/src/platform/macos/ui/Settings/WWNWaypipeRunner.m` (`kmscube` special-case)
   - `Wawona/src/platform/android/android_jni.c` (`kmscube_stub_main` vs cube stubs)
3. Confirm catalog ids already exist (do not rename):
   - `opengl-cube`, `vkcube` in `WWNMachinesViewModel.swift`, `BundledClients.kt`,
     `bundled_clients.rs`, `bundled-clients-catalog.sh`.

**Done when:** you can point at every kmscube file you will clone.

---

## Phase 1 — Vendor vkcube + OpenGL Cube sources (`wwn-kmscube`)

### 1a. OpenGL Cube sources — DONE (2026-07-25)

Vendored under `upstream/opengl-cube/`: `opengl_cube.c` (the port), `matrix.h`
and `LICENSE` verbatim from upstream, `upstream-readme.md` for provenance.

The port replaces upstream's host, not its renderer. Geometry, colours, shader
bodies, `animation()` and `matrix.h` are upstream; everything below was forced
by the target:

| Upstream | Here | Why |
|---|---|---|
| GLFW window + context + `glfwSwapBuffers` | `gbm_surface` + `eglCreateWindowSurface` + `drmModePageFlip` | no windowing system inside the app |
| GLEW | ANGLE GLES3 headers | no desktop GL loader |
| GLSL `#version 450` | `#version 300 es` + `precision mediump float` | ES3 is what ANGLE exposes |
| shaders read from `vertex.glsl` / `fragment.glsl` | embedded string literals | no cwd beside a bundled binary |
| `glfwGetTime` | `CLOCK_MONOTONIC` | no GLFW |
| FPS in window title | FPS to stdout every 2s | no title bar |
| projection assumes its 800x800 window | scale matrix in front of the projection | a KMS mode is not square, so the cube would shear |

Also unlike kmscube: the EGL config must request `EGL_DEPTH_SIZE` (upstream
enables `GL_DEPTH_TEST`) and `EGL_OPENGL_ES3_BIT` (VAOs, `layout(location=)`).

The DRM/GBM/present scaffolding in `opengl_cube.c` is **duplicated** from
`kmscube.c` rather than shared. That is deliberate: kmscube is the proven
acceptance client and must not be refactored underneath itself mid-campaign.
Extracting a common `kms_host.[ch]` for both is follow-on work, not a blocker.

### 1b. Vendor krh/vkcube

```bash
cd /tmp
git clone --depth 1 https://github.com/krh/vkcube.git
# Copy into wwn-kmscube (preserve LICENSE / copyright headers):
#   main.c cube.c esTransform.c esUtil.h common.h
#   vkcube.vert vkcube.frag
#   vkcube.vert.spv.h.in vkcube.frag.spv.h.in  (or generate .spv.h at build)
mkdir -p ~/Wawona/wwn-kmscube/upstream/vkcube
cp -R ... ~/Wawona/wwn-kmscube/upstream/vkcube/
```

Delete or stop compiling the smoke stub `wwn-kmscube/upstream/vkcube.c`
(instance-create-only). Prefer sources under `upstream/vkcube/`.

### 1c. Compat layer for vkcube

Add `upstream/vkcube/vkcube_compat.h` (and/or small patch) mirroring
`kmscube_compat.h` + Android `iland_drm_open_compat.h`:

- Include `iland_drm_open_compat.h` so `/dev/dri/cardN` → virtual fd 42.
- Force KMS display mode for product argv (e.g. pass
  `{"vkcube", "--display-mode=kms", NULL}` from the presenter, or default
  `display_mode` to KMS when Wayland is compile-disabled).
- Compile with `-Dmain=vkcube_main`.
- Disable XCB (`-DENABLE_XCB` off). Disable Wayland (`ENABLE_WAYLAND` off) for
  Apple mobile / Android product archives initially.
- Embed SPIR-V via upstream `.spv.h.in` copy path if `glslangValidator` is
  unavailable in the Nix sandbox (krh/vkcube meson already supports this).

**Done when:** tree has `upstream/vkcube/*` real sources + compat; stub gone;
OpenGL still uses shared `kmscube.c`.

---

## Phase 2 — Nix recipes + registry (`wwn-kmscube`)

### 2a. OpenGL Cube recipes

Create `dependencies/clients/opengl-cube/` by copying kmscube recipes:

Done 2026-07-25. All compile `opengl-cube/opengl_cube.c` (not `kmscube.c`), with
`-I$iland/include/GLES3` added and no `esUtil.c`:

| File | State |
|------|-------|
| `apple-mobile.nix` | present; `-Dmain=opengl_cube_main` → `libopengl_cube.a` + `opengl_cube.h` |
| `macos.nix` | present; also `bin/opengl-cube`. Note the binary is linked as `opengl_cube_bin` and renamed on install — `-o opengl-cube` would collide with the `opengl-cube/` source dir |
| `android.nix` | rewritten off `kmscube.c`; force-includes `iland_drm_open_compat.h` directly (it no longer borrows kmscube's build) |
| `ios.nix` `ipados.nix` `visionos.nix` | `args: import ./apple-mobile.nix args` |
| `wearos.nix` | `args: import ./android.nix args` |
| `tvos.nix` `watchos.nix` | **absent by design** — registry maps them to `null` rather than re-exporting `ios.nix` (as kmscube does), so a deps mistake cannot link ANGLE into a target that forbids it |

### 2b. Vulkan Cube recipes

Create `dependencies/clients/vkcube/` full platform set (replace Android-only):

- Depend on `iland` (+ Vulkan headers from toolchain / nixpkgs as used elsewhere).
- Compile `upstream/vkcube/*.c` (+ generated SPIR-V headers) with
  `-Dmain=vkcube_main` and compat include.
- Install `libvkcube.a` + `include/vkcube.h`.
- macOS: optional `bin/vkcube` linked against iland + Vulkan loader/ICD path
  consistent with Wawona MoltenVK bundling.

### 2c. `flake.nix` registry

Expand both fragments to match `kmscube` platform keys (not Android-only):

```nix
vkcube = withPlatformVariants {
  android = ./dependencies/clients/vkcube/android.nix;
  wearos = ./dependencies/clients/vkcube/wearos.nix;
  ios = ./dependencies/clients/vkcube/ios.nix;
  # ... same keys as kmscube
  macos = ./dependencies/clients/vkcube/macos.nix;
};
"opengl-cube" = withPlatformVariants { /* same */ };
```

Add packages:

```nix
opengl-cube-ios = tc.buildForIOS "opengl-cube" { };
opengl-cube-macos = tc.buildForMacOS "opengl-cube" { };
vkcube-ios = tc.buildForIOS "vkcube" { };
vkcube-macos = tc.buildForMacOS "vkcube" { };
```

Update `wwn-kmscube/README.md` registry table.

### 2d. Build smoke (repo-local)

```bash
cd ~/Wawona/wwn-kmscube
nix build .#opengl-cube-ios .#opengl-cube-macos .#vkcube-ios .#vkcube-macos -L
# Expect: result/lib/libopengl_cube.a, result/lib/libvkcube.a, headers
nm -gU result/lib/libopengl_cube.a | grep opengl_cube_main
nm -gU result/lib/libvkcube.a | grep vkcube_main
```

**Done when:** both clients build for iOS + macOS from the flake; symbols exist.

---

## Phase 3 — Link into the app (`wwn-iland` + `Wawona`)

### 3a. Apple ldflags (`wwn-iland`)

Edit `dependencies/generators/iland-gl-ldflags.nix`:

- Accept `deps."opengl-cube"` and `deps.vkcube`.
- Append lib paths + `-Wl,-u,_opengl_cube_main -lopengl_cube` and
  `-Wl,-u,_vkcube_main -lvkcube` (same **non**-`-force_load` pattern as
  kmscube beside static ANGLE).

Android helper already has optional hooks — keep them; ensure symbols match
(`opengl_cube_main`, `vkcube_main`).

### 3b. Apple deps (`Wawona`)

In `dependencies/wawona/mobile-platform-deps.nix` under `allowGpu`:

```nix
"opengl-cube" = buildFn "opengl-cube" { inherit simulator; };
vkcube = buildFn "vkcube" { inherit simulator; };
```

Do **not** add these under tv/watch variants.

### 3c. xcodegen / macos product

In `dependencies/generators/xcodegen.nix` and `dependencies/wawona/macos.nix`:

- Pass new deps into `ilandGlLdflags { deps = … }`.
- Add include paths for the new headers (same place kmscube includes are added).
- macOS: `require_bin` + copy `bin/opengl-cube` and `bin/vkcube` next to
  kmscube under `Contents/Resources/bin` (and MacOS if kmscube does).

### 3d. Android product

In `dependencies/wawona/android.nix`:

```nix
openglCubeAndroid = buildModule.buildForAndroid "opengl-cube" { };
vkcubeAndroid = buildModule.buildForAndroid "vkcube" { };
# androidDeps += "opengl-cube" "vkcube"
ilandGlLdflags = import ilandGlAndroidLdflagsNix {
  deps = {
    iland = ilandAndroid;
    angle = angleAndroid;
    kmscube = kmscubeAndroid;
    "iland-gl-clients" = kmscubeAndroid;
    "opengl-cube" = openglCubeAndroid;
    vkcube = vkcubeAndroid;
  };
};
```

**Done when:** a product/link dry-run pulls all three archives on GPU targets;
tv/watch still omit them.

---

## Phase 4 — Launch path (Machines → presenter)

### 4a. Generalize Apple presenter

Today only `kmscube_main` is launched from:

- `WWNIlandPresenter` (macOS + iOS)
- `WWNCompositorBridge` `-launchNestedKmscubeOnPrimaryView`
- `WWNWaypipeRunner` special-case for `@"kmscube"`

**Implement** a small table (name bikeshed OK; behavior locked):

| clientId | entry |
|----------|-------|
| `kmscube` | `kmscube_main` |
| `opengl-cube` | `opengl_cube_main` |
| `vkcube` | `vkcube_main` |

Suggested API shape:

- `-launchNestedIlandGpuClient:(NSString *)clientId width:height:` on presenter
- Bridge: `-launchNestedIlandGpuClientOnPrimaryView:(NSString *)clientId`
- Keep `-launchNestedKmscubeOnPrimaryView` as a thin wrapper for back-compat

Weak-import all three symbols. Prepare virtual DRM fd once (existing
`wwn_prepare_iland_virtual_drm_fd`). For `vkcube`, argv must select KMS mode.

In `WWNWaypipeRunner.m`, for both iOS and macOS GPU branches:

```objc
if ([clientId isEqualToString:@"kmscube"] ||
    [clientId isEqualToString:@"opengl-cube"] ||
    [clientId isEqualToString:@"vkcube"]) {
  // refuse if !WWNPlatformAllowsGpuStack (already partially present)
  // ensureIlandPresentationView + launchNestedIlandGpuClientOnPrimaryView:clientId
  return;
}
```

Log modules: `opengl-cube` → `KMSCUBE` (or `OPENGL_CUBE`); `vkcube` → `VKCUBE`
(already partially mapped in `WWNBundledClientLogModule`).

### 4b. Android presenter parity

Change `opengl_cube_stub_main` / `vkcube_stub_main` to mirror
`kmscube_stub_main`:

- Prefer `wwn_iland_presenter_android_launch_*` helpers (extend Android
  presenter to accept client id / entry, or add
  `launch_opengl_cube` / `launch_vkcube` clones of kmscube launch).
- Do not call `*_main` on a bare thread without present/init.

### 4c. Catalog copy

Update descriptions so the three cubes are distinct:

- KMS Cube — DRM/KMS smoke via iland + ANGLE
- OpenGL Cube — GLES spinning cube (mesa kmscube) / distinct Machines id
- Vulkan Cube — krh/vkcube KMS spinning cube via iland + Vulkan ICD

Files: `WWNMachinesViewModel.swift`, `BundledClients.kt`, `bundled_clients.rs`.

**Done when:** Start on macOS + iOS for both new ids hits the presenter (no
“Unknown bundled client id”, no missing `Resources/bin` fallback as the
product path).

---

## Phase 5 — Verify on device

### 5a. Link proofs

```bash
# After product build / xcodegen link, confirm undefined-force symbols resolve:
nm -gU path/to/Wawona | grep -E 'opengl_cube_main|vkcube_main|kmscube_main'
# Android:
nm -D path/to/libwawona.so | grep -E 'opengl_cube_main|vkcube_main'
```

### 5b. Runtime

For each of `kmscube`, `opengl-cube`, `vkcube` on **macOS** and **iOS sim/device**
(and Android):

1. Machines → pick client → Start.
2. Expect animated cube frames on Metal / Android overlay.
3. Logs under `[KMSCUBE]` / `[VKCUBE]`, never `[WESTON]` for these Starts.
4. tvOS/watchOS: client hidden; if forced, refuse.

Use agent-device for iOS when available (`agent-device --version`,
`Wawona/agent-device.json`, prepare + dismiss system UI). Capture screenshots
under `Wawona/.agent-device/test-artifacts/`.

### 5c. Matrix

Clear known fail cell `android/vkcube` once green
(`docs/testing/bundled-clients-matrix-gate.md`). Confirm catalog skip still
lists `kmscube|opengl-cube|vkcube|weston-simple-egl` for tvOS/watchOS.

**Done when:** all checklist boxes below are checked with evidence.

---

## Checklist

- [x] Vendor krh/vkcube under `wwn-kmscube/upstream/vkcube/`; remove smoke stub
- [x] Vendor c2d7fa/opengl-cube under `wwn-kmscube/upstream/opengl-cube/`, ported
      off GLFW/GLEW (supersedes "compile mesa kmscube sources as
      `opengl_cube_main`", which produced a duplicate client)
- [x] `registryFragment` for `opengl-cube` + `vkcube` covers kmscube's platform
      keys, with `tvos`/`watchos` deliberately `null`
- [x] `nix build` `opengl-cube-{ios,ios-sim,macos}` and `vkcube-{ios,macos}` succeed
- [x] `iland-gl-ldflags` (+ Android) pull both archives; product deps wired
      (`_kmscube_main`, `_opengl_cube_main`, `_vkcube_main` all in the macOS binary)
- [x] Presenter/WaypipeRunner Start generalized for three client ids
      (`kCubeClients` table + `WWNIsIlandGpuCubeClientId`)
- [ ] Android Start parity for the two new ids (`opengl_cube_stub_main` still
      bypasses the presenter helpers that `kmscube_stub_main` uses)
- [ ] Machines Start shows **three visibly different** cubes on macOS + iOS + Android
      — vkcube and the old duplicate opengl-cube confirmed on macOS; the ported
      opengl-cube renderer is not yet observed
- [x] Log modules distinct (#112): `KMSCUBE` / `OPENGL_CUBE` / `VKCUBE`, never `WESTON`
- [ ] tvOS/watchOS gating re-proven after the deps change (those targets last
      built against a stale `wwn-kmscube` input)
- [ ] Matrix `android/vkcube` fail cleared; this doc + #113 kept in sync

## Out of scope

- Wayland-EGL / `weston-simple-egl` unstub on Apple
- Shipping GLFW/GLEW (c2d7fa upstream is in scope; its GLFW host is not)
- Mode B desktop dylib for these clients
- tvOS/watchOS GPU
- LunarG Vulkan-Tools cube
- Extracting a shared `kms_host.[ch]` out of `kmscube.c` + `opengl_cube.c`

## Implementation order (short)

1. Phase 1 vendor/compat (`wwn-kmscube`)
2. Phase 2 recipes + flake build
3. Phase 3 ldflags + Wawona deps
4. Phase 4 launch generalization
5. Phase 5 device verify + matrix

Prefer **one PR per repo** (`wwn-kmscube` first, then `wwn-iland` ldflags if
needed, then `Wawona` integration), or a coordinated stack with
`wwn-kmscube` mergeable alone via flake input bump.
