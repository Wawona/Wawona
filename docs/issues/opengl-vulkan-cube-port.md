# OpenGL Cube + Vulkan Cube port (mirror kmscube)

## Status

- Open — tracking issue [#113](https://github.com/Wawona/Wawona/issues/113)
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
| `opengl-cube` | [c2d7fa/opengl-cube](https://github.com/c2d7fa/opengl-cube) (GLFW learning demo) | **mesa/kmscube** sources already in `wwn-kmscube/upstream/` (`kmscube.c`, `esUtil.c`, `kmscube_compat.h`) with `-Dmain=opengl_cube_main` |
| `vkcube` | LunarG Vulkan-Tools cube (not preferred here); current `upstream/vkcube.c` stub | **[krh/vkcube](https://github.com/krh/vkcube)** vendored under `wwn-kmscube/upstream/vkcube/` |

**Present path (locked):**

- OpenGL Cube = iland **DRM/GBM/EGL + ANGLE** (same as KMS Cube). Not Wayland-EGL.
- Vulkan Cube = krh/vkcube **KMS/GBM** against iland virtual DRM (`/dev/dri/card0` → fd 42) + host Vulkan ICD (MoltenVK Apple; device Vulkan / SwiftShader Android).
- Apple mobile **cannot** use `wl_egl_window` / `EGL_PLATFORM_WAYLAND_KHR` (see `wwn-weston/.../simple-egl-apple-mobile-stub.c`). Nested GL goes through `WWNIlandPresenter`.
- tvOS / watchOS: **never** link or show these clients (`allowsGpuStack == false`).

**Prerequisite:** wwn-iland supplies OpenGL (ANGLE) + Vulkan + software-fallback for DRM/GBM bind. This issue owns **client packaging + launch wiring**, not a new iland graphics architecture.

## Delivery model

| Platform | Artifact | Launch |
|----------|----------|--------|
| **macOS** | `libopengl_cube.a` / `libvkcube.a` + `bin/opengl-cube` / `bin/vkcube` | Product Start = **in-process** iland presenter (bins for local/debug) |
| **iOS / iPadOS / visionOS** | archives only (`*_main`) | in-process via Machines → WaypipeRunner → iland presenter |
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

- Do **not** vendor c2d7fa/opengl-cube or GLFW/GLEW.
- Do **not** implement Wayland-EGL for these cubes on Apple mobile.
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

### 1a. OpenGL Cube sources

Reuse existing upstream files — **no new GLES cube code**:

- `upstream/kmscube.c`, `upstream/esUtil.c`, `upstream/esUtil.h`, `upstream/kmscube_compat.h`

Recipes will compile them with `-Dmain=opengl_cube_main` (same as today’s
Android-only `opengl-cube/android.nix`, but with full ANGLE includes like
`kmscube/android.nix`).

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

| File | Action |
|------|--------|
| `apple-mobile.nix` | Copy from `kmscube/apple-mobile.nix`; rename pname; `-Dmain=opengl_cube_main`; output `libopengl_cube.a` + `opengl_cube.h` |
| `macos.nix` | Same; also `bin/opengl-cube` |
| `android.nix` | Replace current thin recipe: match `kmscube/android.nix` includes (`iland` + `angle` + `iland_drm_open_compat.h`) |
| `ios.nix` | `args: import ./apple-mobile.nix args` |
| `ipados.nix` `visionos.nix` `tvos.nix` `watchos.nix` `wearos.nix` | Same re-export pattern as kmscube |
| `linux.nix` | Optional: null or note “same sources as kmscube” |

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

- [ ] Vendor krh/vkcube under `wwn-kmscube/upstream/vkcube/`; remove smoke stub
- [ ] OpenGL Cube recipes compile mesa kmscube sources as `opengl_cube_main` on all GPU platforms
- [ ] `registryFragment` for `opengl-cube` + `vkcube` matches kmscube platform keys
- [ ] `nix build` `opengl-cube-{ios,macos}` and `vkcube-{ios,macos}` succeed
- [ ] `iland-gl-ldflags` (+ Android) pull both archives; product deps wired
- [ ] Presenter/WaypipeRunner/Android Start generalized for three client ids
- [ ] Machines Start shows spinning cubes on macOS + iOS + Android
- [ ] Log modules correct (#112); tvOS/watchOS still gated
- [ ] Matrix `android/vkcube` fail cleared; this doc + #113 kept in sync

## Out of scope

- Wayland-EGL / `weston-simple-egl` unstub on Apple
- GLFW ports / c2d7fa upstream
- Mode B desktop dylib for these clients
- tvOS/watchOS GPU
- LunarG Vulkan-Tools cube

## Implementation order (short)

1. Phase 1 vendor/compat (`wwn-kmscube`)
2. Phase 2 recipes + flake build
3. Phase 3 ldflags + Wawona deps
4. Phase 4 launch generalization
5. Phase 5 device verify + matrix

Prefer **one PR per repo** (`wwn-kmscube` first, then `wwn-iland` ldflags if
needed, then `Wawona` integration), or a coordinated stack with
`wwn-kmscube` mergeable alone via flake input bump.
