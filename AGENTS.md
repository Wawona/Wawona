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

For **CI / prebuilt distribution** (Wawona v0.2.4+ Fastlane beta lanes), read
`wwn-mcp/knowledge/wawona/fastlane.md` and use `scripts/sync-github-secrets.sh`
+ `scripts/bootstrap-apple-signing.sh`. Query **Fastlane** (`project=fastlane`)
and **GitHub Actions** (`project=github-actions`) via wwn-mcp for upstream syntax.

## Non-negotiable facts

- **FFI**: production bridge is hand-written C `WWNCore*` (`src/ffi/c_api.rs`)
  wrapped by ObjC (`WWNCompositorBridge.m`) / JNI (`android_jni.c`), polling
  model. Do NOT use `objc2`/`cocoa`/`jni`/`ndk` Rust crates or UniFFI callbacks.
- **Smithay** `0.7`, `wayland_frontend` only.
- **iland (macOS)**: replaces WindowServer/SkyLight by injecting `.dylib`s
  (`DYLD_INSERT_LIBRARIES` + Dobby, SIP off) onto a custom IOSurface/Metal
  framebuffer that mimics DRM/KMS/EGL/GBM — not AppKit windows. Query
  `project=macos-internals` for Mach-O/dyld/Mach/XNU/launchd details.
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
  permissive. macOS is exempt and its limits never propagate to other platforms.
  Default to the Apple-strict answer when platform is ambiguous.
- **Virtualization**: Wawona iOS will host on-device, JIT-less VMs inside Wawona
  (not UTM) only to run Wayland compositors. Containers only on macOS (maybe
  Android); other Apple platforms = VMs or native only.

## Conventions

- Builds are Nix-based; see `docs/compilation.md` and `docs/2026-nix-build-system.md`.
- Don't commit secrets; `WWN_MCP_TOKEN` is provided via the environment.
