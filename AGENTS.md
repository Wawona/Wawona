# AGENTS.md — Wawona

Guidance for AI agents working in this repository.

## Use WWN-MCP for knowledge

Wawona's stack (Wayland/Smithay/Weston, Apple OS 26 + Liquid Glass, Android
Material 3 Expressive, the Vulkan/OpenGL paths, the Linux DRM/KMS/EGL/GBM display
stack that iland reimplements on Apple, macOS internals (Mach-O/dyld/Mach/XNU/
launchd) for reverse-engineering, App Store / Play Store compliance) is niche and
largely post-dates model training. A retrieval MCP
server, **`wwn-mcp`** (configured in `.cursor/mcp.json`, hosted at
`https://mcp.wawona.io/mcp`), indexes the authoritative sources plus this
repo's own source, docs, and the extracted `wwn-*` patched-software repos.

**Before answering or coding in these areas, query `wwn-mcp` and trust the
retrieved docs over your priors.** Key tools: `search`, `search_docs`,
`search_code`, `find_symbol`, `read_document`, `get_architecture`,
`list_protocols`/`get_protocol`, `list_patches`/`get_patch`.

See `.cursor/rules/wawona-context.mdc` for the always-applied context.

For **Nix/nixpkgs** facts (package/attribute names, options, `nix-darwin`,
`home-manager`, flakes, `noogle`, versions, binary-cache status), query the
companion **`nixos`** MCP server (utensils/mcp-nixos, co-hosted by WWN-MCP) via
its `nix` / `nix_versions` tools instead of guessing. Use WWN-MCP's `get_patch`
for Wawona's own recipes/patches; use `nixos` for upstream nixpkgs.

For **building/running/testing the Apple (iOS/macOS) Xcode projects** — including
simulators, devices, and log capture — use the **`xcodebuild`** MCP server
(getsentry/XcodeBuildMCP) instead of raw `xcodebuild` shell commands. It runs
locally and requires **macOS + Xcode 16+** (not the hosted endpoint). Wawona's
Xcode projects are generated (xcodegen via Nix), so regenerate before building.

For **CI / prebuilt distribution** (Wawona v2.5+ Fastlane beta lanes), read
`wwn-mcp/knowledge/wawona/fastlane.md` and use `scripts/sync-github-secrets.sh`
+ `scripts/bootstrap-apple-signing.sh`. Query **Fastlane** (`project=fastlane`)
and **GitHub Actions** (`project=github-actions`) via wwn-mcp for upstream syntax.

## Non-negotiable facts

- **FFI**: production bridge is hand-written C `WWNCore*` (`src/ffi/c_api.rs`)
  wrapped by ObjC (`WWNCompositorBridge.m`) / JNI (`android_jni.c`), polling
  model. Do NOT use `objc2`/`cocoa`/`jni`/`ndk` Rust crates or UniFFI callbacks.
- **Smithay** `0.7`, `wayland_frontend` only.
- **iland (wwn-iland) — two modes** (do not conflate):
  - **Mode A (default, App Store–safe):** static `libiland_userland.a`, in-window
    present via `iland_drm_set_present_callback` → `WWNIlandPresenter`. Used on
    macOS/iOS/iPadOS/visionOS/Android (tvOS/watchOS stubs). No SIP, no dylib inject.
  - **Mode B (optional, macOS desktop-host only):** ship `libwayland-mac.dylib`,
    load with `DYLD_INSERT_LIBRARIES` + Dobby when SIP allows
    (`WWNSipStatus`: Disabled or PartiallyDisabled) **and** Settings → Desktop →
    Enable Desktop Replacement is on. Package `.#wawona-macos-desktop-host` only;
    never in `.#wawona-macos` / iOS / Android. Canonical doc:
    `docs/iland-mode-a-b-desktop.md`; Cursor rule `wawona-iland-mode-b-desktop`.
  - Query `project=macos-internals` for Mach-O/dyld/Mach/XNU/launchd details.
- **Rust backend builds via crate2nix** (per-crate Nix derivations, `Cargo.nix`)
  for isolated/incremental rebuilds — not a monolithic `buildRustPackage`. Query
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
- **ASC IPA Swift Support (ITMS-90426):** watch-bearing IPAs (iOS +
  `Watch/*.app`) need legacy Swift packaging — `SwiftSupport/{iphoneos,watchos}`
  Apple-signed toolchain originals mirrored by re-signed `Frameworks/libswift*`
  copies per bundle; watchless IPAs (tvOS/visionOS) must ship *without*
  `SwiftSupport/`. Export with `method: app-store-connect` (explicit
  ExportOptions.plist; do not let gym rewrite deprecated `app-store`). Never
  re-zip `Payload/` alone. Assert before upload (`assert_ipa_has_swift_support!`).
  altool success ≠ ASC acceptance. See `.cursor/rules/wawona-asc-swift-support.mdc`
  and `docs/ci.md`.
- **Virtualization**: Wawona iOS will host on-device, JIT-less VMs inside Wawona
  (not UTM) only to run Wayland compositors. Containers only on macOS (maybe
  Android); other Apple platforms = VMs or native only.

## Conventions

- **Repo DAG (acyclic L0–L4; never invert):** `wwn-toolchain` (L0 substrate:
  cairo/pango/pixman/libwayland/…) → `wwn-iland` (L1 complete graphics stack:
  iland + ANGLE/ICDs after P2) → `wwn-kmscube` (L2) → `wwn-weston` (L3) →
  Wawona (L4). `wwn-waypipe`/`wwn-anowaW`/`wwn-vms` are L3′ (→ toolchain). Never
  add a `wwn-*` flake input to `wwn-toolchain`, never put graphics keys in its
  `baseRegistry`, never make `wwn-iland` depend on weston/kmscube/waypipe, and
  never make Wawona an input of any `wwn-*`. Canonical: `docs/wwn-repo-dag.md`;
  workspace rule `wawona-repo-dag`.
- Builds are Nix-based; see `docs/compilation.md` and `docs/2026-nix-build-system.md`.
- Don't commit secrets; `WWN_MCP_TOKEN` is provided via the environment.
- **Desktop / LockScreen / anowaW / SIP** — macOS + Android only (see
  `.cursor/rules/wawona-platform-targets.mdc`). Never wire onto iOS family.
- Mode B dylib presence: assert with
  `.github/scripts/verify-iland-mode-b-bundle.sh`.
