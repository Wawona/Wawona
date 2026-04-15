# Wawona Source Layout Rules

Wawona is organized around a strict ownership split:

- `src/core` contains compositor logic, Wayland protocol handling, scene/state management, and other shared Rust compositor behavior.
- `src/ffi` contains the public integration boundary that platform hosts call into.
- `src/platform/*` contains platform glue only: native host code, platform UI, platform settings bridges, and native rendering helpers that present Rust-managed state.
- `Sources/WawonaModel` contains shared Swift domain models and session orchestration (`bridging: true`).
- `Sources/WawonaUI` contains canonical Apple SwiftUI views for machines/settings/welcome flows.
- `Sources/WawonaWatch` contains watchOS companion UI (status + quick actions, no compositor rendering).
- `Darwin/` contains Apple app entrypoint (`Darwin/Sources/Main.swift`) and Xcode-facing app metadata.
- `dependencies/clients` contains bundled clients, first-party shell code, and first-party diagnostic tools that are packaged through Nix instead of living in the compositor source tree.
- `src/resources` contains assets and bundle resources only.

## Guardrails

- Do not add new compositor logic in C, Objective-C, or Kotlin outside `src/platform/*`.
- Do not reintroduce `src/bin` or `src/launcher`; first-party tools and shell/client code belong under `dependencies/clients`.
- Do not reintroduce duplicate top-level folders that mirror `src/core` concepts. If code is native glue, place it under the relevant `src/platform/*` subtree.
- Keep build manifests that are genuinely required by Nix-backed builds, but remove dead standalone build files when they stop being authoritative.
- Do not add new SwiftUI feature work under `src/platform/macos/ui/*` unless it is unavoidable bridge code. New cross-platform UI goes under `Sources/WawonaUI`.

## Current Ownership Map

- `src/platform/macos/ui` is now bridge/deprecated UI that is being replaced incrementally by `Sources/WawonaUI`.
- `Sources/WawonaModel` is the source of truth for machine/session/preferences state.
- `Sources/WawonaUI` is the source of truth for Settings, Machines, and Welcome UI.
- `Sources/WawonaWatch` is the watchOS companion app source.
- `src/platform/android/rendering` is the Android-native rendering helper path.
- `dependencies/clients/wawona-shell` holds the first-party shell/launcher sources.
- `dependencies/clients/wawona-tools` holds first-party CLI and validation tools.
