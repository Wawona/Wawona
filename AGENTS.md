# AGENTS.md: Wawona

Guidance for AI agents working in this repository.

**No em dashes** (U+2014) or word-joining en dashes in docs, UI, comments, or rules. Use a period, comma, colon, or parentheses. See `docs/agent-rules/wawona-no-em-dash.md` and `.cursor/rules/wawona-no-em-dash.mdc`.

## Use WWN-MCP for knowledge

Wawona's stack (Wayland/Smithay/Weston/Niri, Apple OS 26 + Liquid Glass, Android
Material 3 Expressive, the Vulkan/OpenGL paths, the Linux DRM/KMS/EGL/GBM display
stack that iland reimplements on Apple, macOS internals (Mach-O/dyld/Mach/XNU/
launchd) for reverse-engineering, App Store / Play Store compliance) is niche and
largely post-dates model training. A retrieval MCP server, **`wwn-mcp`**
(configured in `.cursor/mcp.json` as a **stdio** command. Same host model as
`uvx mcp-nixos`; there is no `mcp.wawona.io`), indexes the authoritative sources
plus this repo's own source, docs, and the extracted `wwn-*` patched-software
repos.

**Human contributors using AI:** follow
https://wawona.io/docs/contributor/wwn-mcp/ (install, host config, agent loop,
companion MCPs). Keep this `AGENTS.md` and Cursor rules loaded; still query MCP
for facts.

**Before answering or coding in these areas, query `wwn-mcp` and trust the
retrieved docs over your priors.** Key tools: `search`, `search_docs`,
`search_code`, `find_symbol`, `read_document`, `get_architecture`,
`list_repos` / `where_to_edit` / `get_capability`,
`list_protocols`/`get_protocol`, `list_patches`/`get_patch`.

See `.cursor/rules/wawona-context.mdc` for the always-applied context.

For **Nix/nixpkgs** facts (package/attribute names, options, `nix-darwin`,
`home-manager`, flakes, `noogle`, versions, binary-cache status), query the
companion **`nixos`** MCP server (utensils/mcp-nixos via `uvx mcp-nixos`) via
its `nix` / `nix_versions` tools instead of guessing. Use WWN-MCP's `get_patch`
for Wawona's own recipes/patches; use `nixos` for upstream nixpkgs.

For **building/running/testing the Apple (iOS/macOS) Xcode projects**. Including
simulators, devices, and log capture. Use the **`xcodebuild`** MCP server
(getsentry/XcodeBuildMCP) instead of raw `xcodebuild` shell commands. It runs
locally and requires **macOS + Xcode 16+**. Wawona's Xcode projects are
generated (xcodegen via Nix), so regenerate before building.

For **CI / prebuilt distribution** (Wawona v2.5+ Fastlane beta lanes), read
`wwn-mcp/knowledge/wawona/fastlane.md` and use `scripts/sync-github-secrets.sh`
+ `scripts/bootstrap-apple-signing.sh`. Query **Fastlane** (`project=fastlane`)
and **GitHub Actions** (`project=github-actions`) via wwn-mcp for upstream syntax.

## Non-negotiable facts

- **Wawona-owned code is Rust.** New daemons, helpers, and product logic are
  Rust. C/ObjC/JNI/UniFFI is glue for native UI and ABI only (dylib
  constructors, `WWNCore*` trampolines). Do not write a new Wawona program in C.
  Upstream ports stay in their upstream language. See
  `.cursor/rules/wawona-rust-first.mdc` and `docs/agent-rules/wawona-rust-first.md`.
- **Wayland protocols: newest stable + version negotiation.** Do not maintain
  duplicate implementations of the same interface for legacy clients. Older
  *named* interfaces (e.g. text-input v1 vs v3) only with a demonstrated client
  need. Policy: `docs/PROTOCOLS.md`; rule `wawona-wayland-protocol-compat`;
  checklist in `CONTRIBUTING.md`.
- **FFI**: production compositor bridge is hand-written C `WWNCore*` (`src/ffi/c_api.rs`)
  wrapped by ObjC (`WWNCompositorBridge.m`) / JNI (`android_jni.c`), polling
  model. Do NOT use `objc2`/`cocoa`/`jni`/`ndk` Rust crates or UniFFI callbacks.
- **Smithay** `0.7`, `wayland_frontend` only.
- **iland (wwn-iland). Two modes** (do not conflate):
  - **Mode A (default, App Store-safe):** static `libiland_userland.a`, in-window
    present via `iland_drm_set_present_callback` → `WWNIlandPresenter`. Used on
    macOS/iOS/iPadOS/visionOS/Android (tvOS/watchOS stubs). No SIP, no dylib inject.
    **macOS Mode A is mandatory:** SIP may stay enabled; DRM/KMS still renders
    inside a Cocoa window. Mode B work must never break this. See
    `wawona-macos-mode-a` and `docs/agent-rules/wawona-macos-mode-a.md`.
  - **Mode B (optional, macOS desktop-host only, planned):** ship
    `libwayland-mac.dylib`, load with `DYLD_INSERT_LIBRARIES` + Dobby when SIP
    allows (`WWNSipStatus`: SIP fully disabled via `csrutil disable`) **and** Settings →
    Desktop → Enable Desktop Replacement is on. Package
    `.#wawona-macos-desktop-host` only; never in `.#wawona-macos` / iOS /
    Android. Desktop/LockScreen are **coming soon**. Canonical doc:
    `docs/iland-mode-a-b-desktop.md`; Cursor rule `wawona-iland-mode-b-desktop`.
    **macOS 26:** never Take Over or LLDB-attach `watchdogd` (SIGTRAP panic).
    See `docs/agent-rules/wawona-mode-b-watchdog-safety.md` and Cursor rule
    `wawona-mode-b-watchdog-safety`.
    Wawona Swinging Bridge is separate (`docs/swinging-bridge.md`, `wawona-swinging-bridge`).
  - Query `project=macos-internals` for Mach-O/dyld/Mach/XNU/launchd details.
- **Rust backend builds via crate2nix** (per-crate Nix derivations, `Cargo.nix`)
  for isolated/incremental rebuilds. Not a monolithic `buildRustPackage`. Query
  `project=crate2nix` for `tools.nix`/`defaultCrateOverrides`/strategy questions.
- **Apple = OS 26 / Liquid Glass**; **Material 3 Expressive = Android 16+ only**.
- **Patched software lives in `wwn-*` repos** (Wawona org): the cross-compile
  framework + common libraries + `wawona-pty` are in `wwn-toolchain`; the patched
  apps are in `wwn-zsh`, `wwn-weston` (+ `weston-simple-shm`), `wwn-iland`,
  `wwn-waypipe`, `wwn-coreutils`, `wwn-foot`. Wawona is an **integration layer**:
  `flake.nix` adds them as inputs, builds toolchains via
  `wwn-toolchain.lib.mkToolchains`, and merges each repo's `registryFragment`
  over `baseRegistry`. Edit a patched recipe in its `wwn-*` repo, not in Wawona.
- **Weston + Niri ship natively everywhere:** bundle real target-native
  compositor archives in macOS, iOS, iPadOS, tvOS, watchOS, visionOS, and
  Android products. Never substitute success-shaped entry-point stubs or omit
  either compositor. tvOS/watchOS use constrained non-GL fallbacks; this does
  not permit ANGLE/Vulkan, VMs, or containers on those targets. See
  workspace rule `wawona-bundled-compositors`.
- **In-process cairo:** Apple mobile and Android link `weston_compositor_main`
  in one process with terminals and pango. Do not call
  `cairo_debug_reset_static_data` / `cleanup_after_cairo` on nested weston
  destroy (SIGABRT). Toytoolkit `window.c` skip is not enough. See
  `docs/agent-rules/wawona-inprocess-cairo.md` and rule `wawona-inprocess-cairo`.
- **Nested compositor cursor:** weston/niri draw `wl_pointer`. Hide the host
  overlay on every target, including iOS Touchpad. Ignore Show Virtual Cursor
  and `NestedCompositorCursor` for compositor machines. Classify with
  `bundledAppID` then `NativeClientId`, not Swinging Bridge
  `isNestedCompositorClient`. See `docs/agent-rules/wawona-nested-compositor-cursor.md`.
- **macOS weston/niri backends:** Aqua Machines Start nests them on Wawona
  (`--backend=wayland`, `NIRI_BACKEND=nested`) or runs weston in-process on
  wwn-iland when Display Backend is `drm`. Classic Take Over (WindowServer
  down) always uses iland userspace DRM; nested Wayland is refused. Detect
  Classic by WindowServer gone, never by leaked `WWN_MODEB_TTY`. Never
  `sudo niri`. See `wawona-compositor-backend` and
  `docs/agent-rules/wawona-compositor-backend.md`.
- **Graphics stays runtime-only:** iland virtualizes DRM/KMS/GBM in userland.
  Never open real `/dev/dri` or `/dev/kgsl`, forward real DRM/KMS/KGSL ioctls,
  ship kernel code, or require kernel patches. Mode B `baremetal` remains
  userland SkyLight/Mach IPC. Direct Turnip/KGSL is forbidden.
- **Patched upstreams**: query `get_patch` before assuming upstream behavior. The
  patch anchors are checked in each repo's CI (`verify-weston-ios-patches.py` in
  `wwn-weston`, `verify-zsh-ios-patches.py` in `wwn-zsh`); Wawona keeps the
  Wayland/Android maintainability checks under `.github/scripts/`.
- **zsh on iOS**: static `libwawona-zsh.a` (`wawona_zsh_main`) run **in-process
  on a pthread**, NO fork/exec/posix_spawn/dlopen; external commands dispatched
  in-process to uutils coreutils (safe subset). NOT ios_system; multicall
  coreutils is macOS/Android-only. Filesystem = `wawona-rootfs` (sandbox +
  Application Support, no chroot); "iOS containers" = app sandbox, not
  Containerization.framework. Query `project=ios-shell`.
- **Store-rule asymmetry**: Apple non-macOS platforms = strict (App Store 2.5.2:
  no post-bundle executable code, no JIT, no fork/exec). Android (Play) is more
  permissive. Default to the Apple-strict answer when platform is ambiguous.
- **macOS is NEVER App Store constrained (hard rule)**: never limit any macOS
  artifact by App Store / App Review / TestFlight rules, and never "make macOS
  compliant". macOS may freely use fork/exec/posix_spawn, dlopen, JIT,
  `DYLD_INSERT_LIBRARIES` (iland Mode B dylib), SIP-gated WindowServer
  replacement, private frameworks, OpenSSH/`socat`, and the most capable native
  path. Never reuse an Apple-mobile store-safe shim on macOS when a fuller native
  path exists (e.g. macOS waypipe = native IOSurface/Mach, not the mobile
  `--socket-fds`/no-`socat` path). macOS freedoms never propagate to other Apple
  platforms; mobile store-safety never propagates onto macOS. See
  `.cursor/rules/wawona-macos-no-appstore.mdc`.
- **ASC IPA Swift Support (ITMS-90426/90429/90433):** the proven trigger is
  loose (non-framework-wrapped) non-Swift `.dylib` files under any bundle's
  `Frameworks/`. Forbidden by TN2435; ASC's validator misreads them as
  pre-ABI Swift runtime dylibs and rejects the ipa with rotating Swift
  Support errors regardless of SwiftSupport content (builds 60-120). Ship
  such libs only as `.framework` bundles (ANGLE: `libEGL.framework`/
  `libGLESv2.framework`; flat copies are simulator-only). Canonical accepted
  shape, watch or not: ABI-stable. No `SwiftSupport/`, no
  `Frameworks/libswift*` (`WAWONA_WATCH_LEGACY_SWIFT_SUPPORT=1` is the legacy
  escape hatch). Export with `method: app-store-connect` (explicit
  ExportOptions.plist; do not let gym rewrite deprecated `app-store`). Never
  re-zip `Payload/` alone. Assert before upload (`assert_no_loose_dylibs!`,
  `assert_ipa_has_swift_support!`). altool success ≠ ASC acceptance. Poll
  the ASC `buildUploads` API. See
  `.cursor/rules/wawona-asc-swift-support.mdc` and `docs/ci.md`.
- **Virtualization**: Wawona iOS will host on-device, JIT-less VMs inside Wawona
  (not UTM) only to run Wayland compositors. Containers only on macOS (maybe
  Android); other Apple platforms = VMs or native only.

## Local before CI (do not burn the queue)

Gate: packages / Gate: products often sit **queued 15-40+ minutes**. When a
change can fail at eval, configure, **link**, or package, prove it **locally
first**, then push. Do not use CI to discover `ld: duplicate symbols`,
missing patch anchors, meson version floors, or `Cargo.lock` skew.

- Link / `*Ldflags` / stubs / second Rust staticlib beside niri → build the
  **affected app target** (e.g. `nix build .#wawona-watchos-app-sim`). Parse
  or attr eval is not enough.
- Prefer lazy `-lfoo` + `-Wl,-u,_foo_main` after niri's `-force_load` when
  another Rust `staticlib` embeds std (waypipe precedent). Never
  double-force-load std archives.
- nixpkgs / `pkgs.*.src` / anchor patches → build the drifted package on the
  tip (`.#zsh-ios`, `.#fontconfig-android`, …).
- CalVer bumps → sync `Cargo.lock` (and any linux-ui `cargoLock` consumers)
  before push.

Full rule: workspace `.cursor/rules/wawona-local-before-ci.mdc`.

## agent-device: Multi-Touch for Wayland clients

Drive app/UI with agent-device (`../.cursor/rules/wawona-agent-device.mdc`).
Before tapping **Wayland client** content (Weston panel, nested compositors,
terminals, cubes), set **Multi-Touch**. IOS `TouchInputType=Multi-Touch`,
Android Touchpad Mode **Off**. Touchpad / virtual-pointer left-clicks often
no-op even when `press`/`click` succeed. Prefer `press` / `gesture`; do not
`click --button …` on the compositor surface. Nested niri/weston draw their
own cursor: hide the host pointer even when Touchpad / Show Virtual Cursor
is on (`wawona-nested-compositor-cursor`). Full rule:
`../.cursor/rules/wawona-agent-device-multitouch.mdc`.

## Conventions

- **Repo DAG (acyclic L0-L4; never invert):** `wwn-toolchain` (L0 substrate:
  cairo/pango/pixman/libwayland/…) → `wwn-iland` (L1 complete graphics stack:
  iland + ANGLE/ICDs after P2) → `wwn-kmscube` (L2) → `wwn-weston` (L3) →
  Wawona (L4). `wwn-waypipe`/`Wawona-Swinging-Bridge` / flake `wwn-swinging-bridge`/`wwn-vms` are L3′ (→ toolchain). Never
  add a `wwn-*` flake input to `wwn-toolchain`, never put graphics keys in its
  `baseRegistry`, never make `wwn-iland` depend on weston/kmscube/waypipe, and
  never make Wawona an input of any `wwn-*`. Canonical: `docs/wwn-repo-dag.md`;
  workspace rule `wawona-repo-dag`.
- Builds are Nix-based; see `docs/compilation.md` and `docs/2026-nix-build-system.md`.
- Don't commit secrets.
- **GitHub Sponsors.** Every `github.com/Wawona/*` repo must ship the same
  `.github/FUNDING.yml` as `Wawona/Wawona` (`github` / `ko_fi`:
  `aspauldingcode`). Copy the file when creating a repo. See
  `docs/agent-rules/wawona-github-funding.md` and rule `wawona-github-funding`.
- **Desktop / LockScreen**. MacOS + Android **planned**; iOS/iPadOS via
  **TrollStore** (IOMobileFramebuffer own-display) and **Sileo** (`repo.wawona.io`,
  ElleKit tweaks). Forbidden in App Store Apple-mobile apps (never mention
  jailbreak / TrollStore / JIT there). See `wawona-platform-targets`,
  `wawona-ios-mode-b-channels`, `docs/mode-a-b.md`, `docs/iland-mode-a-b-desktop.md`,
  `docs/linux-dmabuf-zero-copy.md`.
- **Wawona Swinging Bridge**. MacOS/Android Mode A+B planned; iOS/iPadOS
  **Sileo Mode B only** (not TrollStore; forbidden in store IPA). See
  `wawona-swinging-bridge`, `docs/swinging-bridge.md`.
- **Binary filenames**. GitHub Release
  `Wawona-{calver}-{platform}-{arch}.{ext}` plus Mode B
  `.tipa` / `…-rootless.deb` / `…-rootful.deb`; store uploads add `-{build}` before
  the extension (TestFlight IPA / Play AAB). product-build may keep short names
  until a ship boundary. See `docs/ci.md`, `docs/agent-rules/wawona-release-assets.md`,
  rule `wawona-release-assets`.
- Mode B **iland** dylib presence: assert with
  `.github/scripts/verify-iland-mode-b-bundle.sh`. Store IPA Mode B absence:
  `scripts/verify-ios-mode-b-absent.sh`.

## Product map (agents)

See `docs/agent-rules/wawona-product-map.md` and `docs/agent-rules/wawona-product-integration.md` (Swinging Bridge, Desktop/LockScreen, VMs, containers, Wasm Runtime. Do not conflate).
