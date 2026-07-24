# wwn-iland graphics stack — living progress + capability matrix

Source-of-truth progress tracker for the **wwn-iland unified graphics stack**
epic. Twin of the Cursor plan `wwn-iland graphics stack — prioritized phased
plan` and of GitHub epic **#122** (`Wawona/Wawona`). Updated every inner-loop
iteration (grades + repos touched + waypipe zero-copy impact).

- Plan: Cursor plan `wwn-iland graphics stack` (dual-loop, P0→P4).
- Canonical Mode A/B: [`iland-mode-a-b-desktop.md`](iland-mode-a-b-desktop.md).
- Repo layering: [`wwn-repo-dag.md`](wwn-repo-dag.md) (draft, this phase).
- Drivers cheat-sheet: [`drivers-how-to/`](drivers-how-to/README.md).
- Related issues: #58 (kmscube `/dev/dri/card0` open), #86 (IOSurface dmabuf
  zero-copy), #87 (macOS Mode B SkyLight replacement), #94 (purple tint +
  edge-to-edge sizing), #110 (nested-client launch umbrella).

> **Phase status:** P0 **RESEARCH-ONLY — in progress.** No product/registry/
> recipe code has been changed. All entries below are findings + grades against
> the local checkouts (`/Users/8amps/Wawona/*`). P1 code may not start until P0
> is closed and the GitHub epic reflects it.

---

## Status grades (locked vocabulary)

| Grade | Meaning |
|-------|---------|
| **MISSING** | No code path / not shipped on target |
| **STUB** | Symbol/pref exists; returns empty/ENOSYS/ENOENT/no-op — clients cannot succeed |
| **WIRED** | Code path connected; known broken or unproven (issue linked) |
| **FUCKUP** | Intended behavior wrong in practice (wrong present/format, ICD ignored, pixman on GPU host, …) — cite bug |
| **PROPER** | Acceptance client green on that target+mode; evidence logged (build + Agent-Device) |

"Compiles" alone ≠ PROPER. STUB / WIRED / FUCKUP are all **not done**.

---

## Living capability matrix (P0 baseline — honest)

One grade per cell. DRM (open/resources) and KMS (modeset/flip/present) tracked
separately. Evidence is `file:line` in the local tree or an issue.

| Target | Mode | OpenGL / GLES | Vulkan | DRM | KMS | Desktop Repl. DRM/KMS |
|--------|------|---------------|--------|-----|-----|------------------------|
| macOS 3rd-party product | A | WIRED (ANGLE dlopen; `OpenGLDriver` pref **never applied** — STUB selection) | WIRED (MVK/KK ICD set at launch only, not on connect) | WIRED (stock `/dev/dri/cardN` redirect is store-safe and shared by product consumers) | WIRED (fourcc contract enforced; page-flip→callback remains immediate synthetic cadence) | N/A (Desktop tweak = desktop-host B) |
| macOS desktop-host | A (toggle off) | WIRED (same as product) | WIRED | WIRED | WIRED | N/A |
| macOS desktop-host | B (SIP partial + toggle) | WIRED | WIRED | WIRED (Dobby `open`/`ioctl` hooks real) | WIRED→FUCKUP (framebufferd present real; **vsync TODO** `drm_linux.c:708`; no CI proof) | WIRED (engage path real, not CI-proven; #87) |
| iOS / iPadOS / visionOS | A | WIRED (ANGLE present path; target runtime/tint evidence remains pending) | STUB→WIRED (MVK intended; ICD apply-on-connect missing) | WIRED (Mode-A open shim landed — `iland_drm_open_card` + `iland_drm_open_compat.h`; #58 open path fixed, device render unproven) | WIRED (preferred-mode host wiring + fourcc contract landed; scene/multi-window runtime evidence pending) | N/A |
| tvOS / watchOS | A soft | N/A (empty `libiland_userland.a`; correct) | N/A | N/A | N/A | N/A |
| Android Play / Home Desktop | A (no root) | STUB (system/ANGLE `.so` present; `OpenGLDriver` pref has **no consumer**) | WIRED (system/SwiftShader/Turnip ICD via `VK_ICD_FILENAMES` at instance create) | WIRED (userland `drm_linux.c`; heap "IOSurface", no AHB) | WIRED (present callback; zero-copy forced off) | WIRED (Home = rootless Mode A launcher/VD; no dylib) |
| Android power | B (root FB) | STUB | WIRED (+ optional Turnip) | WIRED | WIRED | WIRED (root FB optional; not Play-required) |

**Never** mark Desktop-Replacement DRM/KMS PROPER on macOS **product Mode A**
(Desktop tweak is desktop-host Mode B only), or require root to mark Android
Home Desktop / App Store cells PROPER.

---

## P1 progress log

**#58 Mode-A device open (landed in `wwn-iland`):** added `iland_drm_open_card()`
in `drm_linux.c` + a reusable force-include header
`shims/drm/drm/include/iland_drm_open_compat.h` that redirects a stock client's
raw `open("/dev/dri/cardN")` to the in-process virtual DRM fd (non-DRM paths
defer to libc `open`, incl. `O_CREAT` mode). Store-safe: no DYLD interpose, no
`/dev/dri`, no privilege. Wired the force-include into iland's own GL-clients
recipes (`gl-clients-macos.nix`, `gl-clients-ios.nix`) and installed the header
in `macos.nix` / `ios.nix` / `android.nix`. **Verified (macOS, 4 levels):** (1) `clang -fsyntax-only` on `drm_linux.c` clean;
(2) macro-routing compile/run test — `/dev/dri/*` → shim (fd 42), 2-arg + 3-arg
passthrough opens compile; (3) **`nix build .#iland-macos` green** — archive
compiles, exports `_iland_drm_open_card` (`nm`), ships `iland_drm_open_compat.h`;
(4) **integration** — the real `test/kmscube.c` (`open("/dev/dri/card0")` at
`:237`) compiles against the built artifact with the force-include applied.
**Grade: WIRED** (build + integration proven; in-app kmscube *render* → PROPER
pending full Wawona app build + Agent-Device). **waypipe zero-copy impact: none.**

**#94 format contract + stock-consumer wiring (landed on `development`):**
`wwn-iland` [`eedd2e5`](https://github.com/Wawona/wwn-iland/commit/eedd2e5cf2e62256c048f5a532e8eda50e1314bf)
now records each GBM BO's DRM fourcc, allocates only the matching IOSurface
pixel format (`XRGB8888`/`ARGB8888` → BGRA; supported 10-bit formats → `l10r`),
and makes `drmModeAddFB2` reject unsupported or mismatched backing rather than
claiming successful channel-swapped presentation. `wwn-kmscube`
[`cfb0449`](https://github.com/Wawona/wwn-kmscube/commit/cfb0449) replaces its
private `open()` implementation with the installed iland compatibility header
for Apple and Android; `wwn-weston`
[`5a8fc72`](https://github.com/Wawona/wwn-weston/commit/5a8fc72) force-includes
the same header in Apple DRM compositor builds. Verified: `nix build
.#iland-macos`, `.#kmscube-macos`, and `.#weston-compositor-ios`. This moves the
format implementation from **FUCKUP** to **WIRED**, not **PROPER**: no
product-shaped iOS/iPadOS/visionOS or Android runtime capture has yet proved
the target frame and Android still uses the CPU compatibility surface instead
of an AHardwareBuffer zero-copy backend.

**Apple IOSurface dmabuf bridge (#86, landed):** `wwn-iland`
[`dec66e5`](https://github.com/Wawona/wwn-iland/commit/dec66e5) makes GBM export
the existing waypipe IOSurface modifier convention (high bit + IOSurface ID),
supplies the protocol placeholder fd, and imports that modifier with
`IOSurfaceLookup` without copying pixels. Both `nix build .#iland-macos` and
`nix build .#iland-ios` pass. This proves ABI/build parity with waypipe's
transport contract; cross-process runtime/Mach-port evidence is still required
for **PROPER**, and Android AHardwareBuffer remains a separate open path.

**Remaining to close #58 for the product (next P1 steps):**
1. Preferred-mode set before first connector enumerate on every Apple/Android
   target; re-set on resize.
2. Nix build target variants + Agent-Device kmscube in-app on iOS-shaped build.
3. Replace Android's CPU compatibility surface with an AHardwareBuffer-backed
   BO/FB path and prove waypipe remains zero-copy (#86).

**Android GPU compositor correction (working tree; verification pending):**
the product dependency in `dependencies/wawona/android.nix` now selects
`weston-compositor-drm`, and the nested launch in
`src/platform/android/android_jni.c` explicitly requests `--renderer=gl`.
This follows R10's short path (Wayland backend + Weston GL → host EGL) while
retaining the non-DRM compositor as the explicit pixman fallback. Do not grade
this above **WIRED** until the Android product builds and Agent-Device captures
the renderer/backend logs from the Play/Home session.

**Android AHardwareBuffer conversion (inner loop in progress):** the prior
Android `iosurface_compat` object was only a heap allocation and forced the
EGL→presenter→Vulkan path through repeated CPU copies. The P1 implementation
now allocates `AHardwareBuffer` objects with GPU color-output/sampled-image
usage plus a CPU-mappable fallback, exposes the native buffer to the product
presenter, and synchronizes iland's preferred mode when the Android swapchain
resizes. The next code step is EGL native-buffer rendering plus Vulkan external
memory import; until that lands, the existing mapped fallback remains active
and Android zero-copy is **not** complete. The Android Nix build is the current
inner-loop gate.

## R1 — Mode A fail point (#58) + Apple KMS / IOSurface map

**#58 root cause (confirmed):** kmscube logs `could not open drm device
/dev/dri/card0` / `failed to initialize DRM`. The Mode A archive
(`libiland_userland.a`) links the userland `drmMode*` implementation but **does
not interpose `open("/dev/dri/card*")` or `ioctl`** — those hooks live only in
the Mode B dylib (`upstream/shims/drm/.../wayland-mac.c:85-109`, Dobby). Stock
clients therefore fail at the raw card open before any `drmMode*` call.
`wwn-kmscube` works around it with `-include kmscube_compat.h`
(`kmscube_compat.h:21-50`); weston / other clients need the same shim or a
Mode-A-safe open path inside iland.

**Linked libdrm surface is substantially REAL** (all in
`dependencies/libs/iland/upstream/shims/drm/drm/src/drm_linux.c`):

| Symbol | file:line | Grade |
|--------|-----------|-------|
| `drmOpen`/`drmOpenWithType` | `234-244` | REAL (returns virtual fd 42) |
| `drmModeGetResources` | `275-301` | REAL (1 CRTC/1 connector/1 encoder) |
| `drmModeGetConnector` | `315-346` | REAL (fake DP connected; `init_modes()`) |
| `drmModeGetEncoder`/`GetCrtc` | `360-403` | REAL |
| `drmModeCreateDumbBuffer` | `448-495` | REAL (→ IOSurface via DisplaySurface) |
| `drmModeAddFB` | `573-614` | REAL (dumb + GBM handle registry) |
| `drmModeAddFB2`/`WithModifiers` | `616-628`,`1635-1647` | **PARTIAL/BROKEN — `(void)pixel_format`; fourcc ignored** |
| `drmModeSetCrtc` | `656-671` | PARTIAL (records state; no present until flip) |
| `drmModePageFlip` | `673-716` | REAL Mode A (→ `g_present_cb`); else Mode B IPC |
| `drmHandleEvent` | `718-750` | PARTIAL (immediate pipe byte; no vblank timing) |
| `drmIoctl` | `754-759` | STUB (`ENOSYS`) |
| `drmModeGetPlaneResources`/`GetPlane` | `1308-1375` | PARTIAL (primary plane 1 only) |
| `drmModeAtomicCommit` | `1419-1526` | PARTIAL (applies props; immediate flip event) |
| `drmModeSetCursor`/`MoveCursor` | `1541-1554` | STUB (`ENOTSUP`) |
| `drmPrimeHandleToFD`/`FDToHandle` | `1608-1631` | STUB (fake fd/handle) |
| `iland_drm_set_present_callback` | `30-34` | REAL (Mode A gate) |
| `iland_drm_set_preferred_mode` | `59-66` | REAL (**required on iOS/Android**) |

**Apple KMS ↔ IOSurface mapping (as-built):** connector/CRTC/encoder are fixed
fakes (`init_modes()` `89-182`). Mode source priority: (1) `iland_drm_set_preferred_mode`
→ exact host pixels; (2) macOS WindowServer plist `116-157`; (3) default
**1920×1080** `171-181`. Present callback carries **only** `(crtc, fb,
IOSurfaceRef, flags)` — no width/height/format (`iland_present.h:37-41`); host
queries the IOSurface. **Per-target gap:** iOS/iPadOS/visionOS/Android have no
plist, so without a preferred mode they get 1920×1080 then Metal stretch — the
#94 edge-to-edge/sizing class. macOS Mode A product may also skip preferred
mode (windowed host ≠ desktop res).

**GBM↔FB allocator is unified** (single IOSurface shared via a handle registry:
`gbm.m:60-61` `drm_register_gbm_buffer`, `drm_linux.c:581-591` FB lookup), **but**
the format argument is ignored at alloc (always BGRA) → advertised-vs-physical
format lie (#94).

## R2 — Mode B reality (macOS desktop-host)

Engage path is **real and gated** but not a CI-proven finished product.

- SIP detect `WWNSipStatus.m:6-38`; allow-gate `:55-57`; toggle hard-reject when
  SIP blocks `WWNPreferences.m:4041-4049`; toggle also requires bundled dylib
  `:4051-4067` (store-safe builds cannot arm Mode B). — REAL
- `shouldEngageModeB` `WWNDesktopReplacementController.m:53-62`; dylib discovery
  `:77-94`; privileged insert + `weston --backend=drm` `:187-258`; connect hook
  `WWNMachineSessionBridge.m:150-168`. — REAL
- Dylib constructor (root-gated, Dobby hooks, extracts framebufferd/inputd)
  `wayland-mac.c:259-337`; framebufferd CAWindowServer present
  `framebufferd/src/main.m:267-303`. — REAL (upstream-derived)
- **Remaining gaps:** flip completion still signals when the Mach surface message
  is accepted rather than at a display-vblank (`drm_linux.c` page-flip); **no CI
  job builds/runs `wawona-macos-desktop-host`**; and
  `verify-iland-mode-b-bundle.sh` is **not invoked by any workflow** (only an
  inline Nix assert), while `docs/ci.md:51-52` overstates coverage. Tracked by
  #87.

### P3 Mode B hardening — in progress

Mode B remains **macOS desktop-host only**: root + SIP debugging restrictions
disabled/partially-disabled + explicit Desktop Replacement preference. No
mobile/Android/store artifact is changed by this work.

**Lifecycle implementation:** `wayland-mac.c` now records the PIDs of the
root-owned `framebufferd`, `inputd`, and `caffeinate` processes it launches
under `/tmp/libwayland-support/`. Its dylib destructor stops only those
helpers, in reverse startup order, and removes the PID records; it deliberately
does not touch helpers when a pre-existing Mode B Mach service belongs to
another owner. Failed helper extraction/spawn now fails the constructor instead
of falling into an unbounded service-wait loop. The desktop controller now
stops the root-owned injected Weston through the same administrator boundary
that launched it, waits for normal destructor cleanup, and only then escalates;
the escalation consumes the root-owned PID records to prevent orphaned helpers.

**Why:** the old controller used unprivileged `kill(SIGTERM)` on a root process,
so it could silently fail with `EPERM`; it also had no helper teardown
ownership. The new lifecycle closes that leak without adding any Mode B symbol
or package to Mode A/store outputs.

**Acceptance still pending:** build `iland-baremetal-macos`; static/syntax
checks; desktop-host package bundle test (`--mode present`) plus product/mobile
absence checks; a manually authorized SIP-eligible desktop-host smoke proving
Weston → page flip → framebufferd, and a shutdown smoke proving no owned helper
PIDs survive. **waypipe zero-copy impact: none** (the IOSurface Mach-port
handoff remains unchanged).

**Build evidence (macOS arm64):** `nix build .#iland-baremetal-macos` is green
after repairing the recipe's coherent Xcode compiler/SDK selection, ANGLE header
path, and `codesign` invocation without leaking BSD `find`/`cut` into Nix
fixup. The artifact is an ad-hoc-signed arm64
`libwayland-mac.dylib`, exports `drmModePageFlip` and `wayland_mac_init`, and
passes both `verify-iland-mode-b-bundle.sh --mode present` (desktop-host-shaped
fixture) and `--mode absent` (store-shaped fixture). This verifies packaging
and compile/link ownership; it does **not** claim a SIP/root live desktop smoke
or vblank-correct flips. Grade remains **WIRED**, not PROPER.

## R3 — External stacks (reuse cheat-sheet)

- **UTM** (`UTM/Documentation/Graphics.md:6-81`): reusable patterns for Mode A =
  ANGLE Metal backend (`ANGLE_DEFAULT_PLATFORM=metal`), IOSurface as zero-copy
  present substrate, CocoaSpice-style CAMetalLayer + vblank present, ICD select
  via `VK_DRIVER_FILES`/`VK_ICD_FILENAMES`. **VM-only, must not leak into Mode A:**
  virtio-gpu, virglrenderer, Venus, gfxstream (stay in `wwn-vms`/UTM engine;
  confirmed `wwn-vms/README.md:9-11,40`).
- **Local packaging inventory:** ANGLE — macOS `pkgs.angle`
  (`wwn-toolchain/.../angle/macos.nix:16`), iOS prebuilt (XCSoar + jeremyfa) +
  GN source path, Android prebuilt (kubuszok) + GN; MoltenVK — `pkgs.moltenvk`
  (Wawona `macos.nix`); SwiftShader — `google/swiftshader` Android/Wear only
  (`registry.nix:58-63`, ios/macos = null); **KosmicKrisp — no recipe** (docs +
  runtime ICD select only); **Turnip — not packaged** (settings point at
  `/data/local/tmp/freedreno_icd.json`).
- **Termux/Android:** rootless = system Vulkan + OEM Adreno ICD, GLES via system
  EGL or bundled ANGLE; Turnip generally needs root/privileged install (KGSL +
  loadable ICD). Wawona's rootless Play path uses system/ANGLE/SwiftShader.
- **Minimal-layers verdict:** one hop per API — Apple GLES→ANGLE→Metal,
  Vulkan→MVK|KK→Metal; Android GLES→ANGLE|system, Vulkan→system|Turnip|SwiftShader.
  Reject GLES→Zink→Vulkan→MVK→Metal.

## R4 — Pref apply gap

| Pref | Saved | Applied on connect? | Grade |
|------|-------|---------------------|-------|
| VulkanDriver (macOS) | global `WWNPreferencesManager.m:32,782-788` + per-machine keys `WWNMachineProfileStore.m:131-134` | ICD `setenv` **launch-time only** `main.m:1119-1162`; connect (`applyMachineToRuntimePrefs` `WWNMachineSessionBridge.m:114`) rewrites defaults but **does not re-`setenv`** | PARTIAL |
| OpenGLDriver (macOS) | global `:33,791-799` | read by `WWNSettings_GetOpenGLDriver` `WWNSettings.m:87-94` but **no `setenv`/ANGLE selection site** | STUB |
| VulkanDriver (Android) | `WawonaSettings.kt:62-81`→JNI | REAL at instance create `android_jni.c:1022-1047` (`VK_ICD_FILENAMES`) | PARTIAL (global real; per-machine ad-hoc) |
| OpenGLDriver (Android) | same | stored `android_jni.c:2428-2430`, **no consumer** | STUB |
| DriverSelector abstraction | — | — | **MISSING** |

**Hook point:** a `machine>global>default` resolver called from both `main.m`
launch and after `applyMachineToRuntimePrefs` (`WWNMachineSessionBridge.m:114`),
before Mode B engage / WaypipeRunner launch, that re-`setenv`s ICD/ANGLE. Swift
`resolvedSettings` also hardcodes `"moltenvk"` fallback instead of global
(`WawonaPreferences.swift:289`) — inconsistent, fix in P2.

## R5 — Flake DAG (edges)

Actual flake-input edges match L0→L4 with **no inversions**: toolchain (none),
iland (→toolchain), kmscube (→toolchain,iland), weston (→toolchain,iland,kmscube;
`ilandSrc` source-injection only), waypipe/anowaW/vms (→toolchain; no iland
input), Wawona (→ all). Registry merge is `baseRegistry // fragment` (iland
`flake.nix:96`, kmscube `74`, weston `83`, Wawona `222-240`). **Lock skew** (not
a cycle): weston pins toolchain `7e00ad…` vs iland/kmscube `b0bc81…`; re-lock in
land loop.

## R6 — Ranked stub-replacement list (Mode A, iOS-store-shaped)

1. **Card open without Dobby** — Mode-A-safe `open("/dev/dri/card*")` path inside
   iland (or a shared client shim) so stock kmscube/weston open the virtual fd.
   Root cause of #58. (`wayland-mac.c` is Mode B only.)
2. **`drmModeAddFB2` format honor + GBM format→pixelFormat map** — stop ignoring
   fourcc (`drm_linux.c:623-627`); root of #94 format lie.
3. **Present metadata / size sync** — carry format/size or keep preferred mode ≡
   host drawable; host queries IOSurface today (`iland_present.h:37-41`).
4. **Real vsync / flip completion** — replace immediate pipe byte
   (`drm_linux.c:708-713`).
5. **`drmIoctl`→dispatch** — currently ENOSYS; stock libdrm ioctl clients fail.
6. **Planes/atomic completeness** — only primary plane; SetCursor ENOTSUP;
   modifiers off; PRIME fake.
7. **udev(+epoll) in Mode A link set** — `udev.c` enumerates fake `card0` but is
   **not compiled into** the Mode A `.a`; weston needs it.
8. **Android present plumbing** — no AHB/GPU zero-copy; zerocopy forced off.
9. **EGL Android** — dlopen `libEGL.so` + CPU swap, not Metal IOSurface zero-copy.
10. tvOS/watchOS — intentionally empty; do not add GL.

Store builds confirmed to contain **zero** Mode B dylib / inject paths (see R7).

## R7 — Universal A/B + store-matrix audit

Gating is real: `.#wawona-macos` sets `ilandBaremetal = null` (`flake.nix:982-983`)
and `macos.nix:1366-1370` fails the build if the dylib is present; desktop-host
includes it (`flake.nix:987-1000`). iOS/tv/watch/vision xcodegen targets exclude
SIP/Desktop controllers; tv/watch use `finalCxxLdflagsNoIokit` and skip
ANGLE/MVK embed (`xcodegen.nix:1576-1606,2546`; `mobile-platform-deps.nix:38-39,64-68`).
Apple mobile SSH is libssh2-only (`mobile-platform-deps.nix:20-30`). Cargo
`compile_error` blocks `iland-baremetal` on mobile/Android (`src/lib.rs:27-44`).

**Leak vectors to guard (P1 compliance checklist):** manual packaging copying the
dylib (verify script not in CI); sharing iOS GPU post-build phases onto tv/watch;
adding IOKit ldflags to tv/watch; linking OpenSSH into mobile OTHER_LDFLAGS;
shared Settings sections without `#if` platform guards; enabling `desktopHost`
on the wrong flake attr.

**Android Home Desktop = rootless Mode A** (HOME role + nested weston,
`DesktopReplacement.kt:14-24`); anowaW baseline = MediaProjection/own VD
(`AnowawSession.kt:24-28`); power tier (Shizuku/root) only for arbitrary-app
embed, auto-falls back (`:64-76`). No SIP, no dylib on Android.

## R8 — Capability matrix

See "Living capability matrix" above (filled with grades + evidence). This is the
baseline the dual loop updates every iteration.

## R9 — Verify model (draft)

Adopt the closed input→output contract per layer so failures localize to the
first broken seam (bindings ABI → Wayland wire → solved ICD/EGL → iland
DRM/KMS/GBM → present). Authoritative clients: stock **kmscube**,
**weston-simple-egl**, **vkcube** (never a homegrown cube). ANGLE/MVK/KK are
black-box dependencies, not systems-under-test. "Bit-by-bit" = for a pinned
client revision + pinned ICD/ANGLE, the binding/protocol seam matches upstream
symbol-for-symbol and message-for-message; Mode A golden = present-callback
`(width,height,fourcc,frame ids)` sequence for one vsync. **Custom code to
delete/avoid:** homegrown GL init, `iland_open()` client rewrite, "IOSurface
instead of GBM" dual worlds, hand-rolled Rust GL/VK drivers.

## R10 — Compositor backend audit (pixman vs GPU)

GPU-capable Apple defaults now select `iland-drm-gl`; tvOS/watchOS retain the
required software default. Android product wiring selects the DRM/GL archive
and explicitly starts Weston's GL renderer. macOS still lacks a product
`weston-compositor-drm` recipe, so this cross-cutting item remains open.

| Target | Build renderer/backend | Runtime default | Verdict |
|--------|------------------------|-----------------|---------|
| iOS / iPadOS | DRM+GL compiled in (`enableIlandDrm=true`, `mobile-platform-deps.nix:54-57`) | `iland-drm-gl` (GPU-target default) | WIRED; runtime evidence pending |
| visionOS | same | `iland-drm-gl` | WIRED; runtime evidence pending |
| tvOS / watchOS | `renderer-gl=false`, `allowGpu=false` | pixman | correct (no GPU) |
| macOS | `weston-compositor.macos=null`; `backend-drm=false`,`renderer-gl=false` (`macos.nix:57-66`) | requests `iland-drm-gl`, then falls back if `weston_main` is absent | FUCKUP (build gap) |
| Android | product selects `weston-compositor-drm` | `--backend=wayland --renderer=gl` | WIRED; build/device evidence pending |

Remaining fix: add and package a macOS compositor-drm recipe; then verify each
GPU target logs the GL renderer while explicit software mode and tv/watch stay
pixman.

## R11 — DAG / cycle watch list

Flake edges are acyclic (R5). The real smell: **`angle` and `swiftshader` live in
L0 `baseRegistry`** (`wwn-toolchain/.../registry.nix:280-290,58-63`) — they are
graphics-stack keys that belong in L1 `wwn-iland.registryFragment` (P2 move).
`moltenvk` is `pkgs.moltenvk` (nixpkgs), `kosmickrisp` has no recipe (orphan) —
both to be owned/wired under L1 in P2. `pixman` correctly stays L0 (cairo depends
on it `cairo/ios.nix:24`); moving it to iland would force cairo→iland (cycle).
In-toolchain `freetype↔harfbuzz↔cairo` disable edges are intentional one-way
(`freetype/ios.nix:4-5`, `harfbuzz/ios.nix:6-7`) — keep. `ffmpeg`/`spirv-tools`
in L0 are borderline but not iland/weston; leave unless proven graphics-only.

**Cycle-risk watch list** (full table in [`wwn-repo-dag.md`](wwn-repo-dag.md)):
pixman/cairo/pango into iland (forbidden); angle left owned by toolchain after
move; iland→weston/kmscube/waypipe flake edges; toolchain baseRegistry absorbing
fragments; kmscube→weston; Wawona as input of any wwn-*; MVK/KK recipe pulling
full mesa+iland headers; Android Turnip packaged in toolchain instead of L1.

---

## Minimal-layer canonical paths (locked)

```text
Apple (macOS/iOS/iPadOS/visionOS) — parallel, not stacked:
  GLES/OpenGL → EGL → ANGLE(Metal) → IOSurface/Metal present
  Vulkan      → loader → MoltenVK OR KosmicKrisp → Metal present
  DRM/KMS/GBM → iland userland → same present callback (no extra GL/VK hop)
Android:
  GLES → EGL → ANGLE OR system GLES → Surface present
  Vulkan → loader → system OR Turnip OR SwiftShader
tvOS/watchOS: software/pixman only (no GPU translate stack)
```

Reject: GLES→Zink→Vulkan→MVK→Metal; virgl/Venus in Mode A; pixman nested on
GPU-capable Apple/Android; two active Vulkan ICDs in one process.

## waypipe-rs zero-copy (cross-cutting)

#86 target: iland GBM/FB IOSurface exported as `zwp_linux_dmabuf`, importable by
`wwn-waypipe` and nested clients without CPU blit when DmabufEnabled. waypipe
does **not** take iland as a flake input today (`wwn-waypipe/flake.nix` →
toolchain + ssh only) — GPU wiring is via env/ICD, keep it that way (no L1→L3'
inversion). Every buffer-touching change must log **waypipe zero-copy impact:
none | preserved | broken→fix**. P0 impact: **none** (research-only).

## Repos touched this phase

P0 (docs-only, `Wawona`): this progress doc, draft `wwn-repo-dag.md`, GitHub epic.
No `wwn-*` recipe edits; no flake.lock bumps.

P1 (in progress):
- `Wawona`: Mode A/B store matrix + portable-KMS model in `iland-mode-a-b-desktop.md`;
  workspace `wawona-repo-dag.mdc` Cursor rule; AGENTS.md DAG stub (on disk).
- `wwn-iland`: `iland_drm_open_card` + `iland_drm_open_compat.h` (#58 Mode-A open
  shim); header install in `macos.nix`/`ios.nix`/`android.nix`; force-include in
  `gl-clients-macos.nix`/`gl-clients-ios.nix`; AGENTS/README DAG layer identity.
- `wwn-toolchain`: AGENTS.md (new) + README DAG layer identity (on disk).
**waypipe zero-copy impact: none.**

## P1 entry criteria (written; P1 not started)

1. #58 fix design chosen: Mode-A-safe card-open shim inside iland vs shared client
   `kmscube_compat.h`-style include (prefer iland-internal so weston benefits).
2. Format path: single `DRM_FORMAT_XRGB8888`/BGRA reality first; `AddFB2` honors
   fourcc; GBM format map.
3. Preferred-mode set on every mobile/Apple target before first connector enumerate;
   re-set on resize.
4. Present callback size/format contract decided (extend callback vs host-queries-IOSurface).
5. Compositor default flip to GPU (`iland-drm-gl`) staged for iOS/iPadOS/visionOS/
   macOS/Android product sessions; tv/watch stay pixman.
6. waypipe zero-copy regression check defined for #86.
7. Store-compliance checklist (R7 leak vectors) ready to assert per build.
