# Wawona Source Layout Rules

Wawona is organized around a strict ownership split:

- `src/core` contains compositor logic, Wayland protocol handling, scene/state management, and other shared Rust compositor behavior.
- `src/ffi` contains the public integration boundary that platform hosts call into.
- `src/platform/*` contains platform glue only: native host code, platform UI, platform settings bridges, and native rendering helpers that present Rust-managed state.
- `dependencies/clients` contains bundled clients, first-party shell code, and first-party diagnostic tools that are packaged through Nix instead of living in the compositor source tree.
- `src/resources` contains assets and bundle resources only.

## Guardrails

- Do not add new compositor logic in C, Objective-C, or Kotlin outside `src/platform/*`.
- Do not reintroduce `src/bin` or `src/launcher`; first-party tools and shell/client code belong under `dependencies/clients`.
- Do not reintroduce duplicate top-level folders that mirror `src/core` concepts. If code is native glue, place it under the relevant `src/platform/*` subtree.
- Keep build manifests that are genuinely required by Nix-backed builds, but remove dead standalone build files when they stop being authoritative.

## Current Ownership Map

- `src/platform/macos/ui` holds the shared Apple settings/about/helper UI layer currently reused by both macOS and iOS.
- `src/platform/android/rendering` is the Android-native rendering helper path.
- `dependencies/clients/wawona-shell` holds the first-party shell/launcher sources.
- `dependencies/clients/wawona-tools` holds first-party CLI and validation tools.
