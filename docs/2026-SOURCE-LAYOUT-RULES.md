# Wawona Source Layout Rules

Wawona is organized around a strict ownership split:

- `src/core` contains compositor logic, Wayland protocol handling, scene/state management, and other shared Rust compositor behavior.
- `src/ffi` contains the public integration boundary that platform hosts call into.
- `src/platform/*` contains platform glue only: native host code, platform UI, platform settings bridges, and native rendering helpers that present Rust-managed state.
- `Sources/WawonaModel` is a legacy migration seam whose domain models and
  session orchestration must move into Rust. Do not add business logic there.
- `Sources/WawonaUI` contains canonical Apple SwiftUI for machines (profiles + per-machine overrides), welcome, and settings **hosting** (`ObjCSettingsHostView` → native `WWNPreferences`).
- `Sources/WawonaWatch` contains watchOS companion UI (status + quick actions, no compositor rendering).
- `Darwin/` contains Apple app entrypoint (`Darwin/Sources/Main.swift`) and Xcode-facing app metadata.
- `dependencies/clients` contains bundled clients, first-party shell code, and first-party diagnostic tools that are packaged through Nix instead of living in the compositor source tree.
- `src/resources` contains assets and bundle resources only.

## Guardrails

- Do not add business or compositor logic in Swift, C, Objective-C, Kotlin, or
  Java. Native code under `src/platform/*` is presentation and platform glue
  only.
- Do not reintroduce `src/bin` or `src/launcher`; first-party tools and shell/client code belong under `dependencies/clients`.
- Do not reintroduce duplicate top-level folders that mirror `src/core` concepts. If code is native glue, place it under the relevant `src/platform/*` subtree.
- Keep build manifests that are genuinely required by Nix-backed builds, but remove dead standalone build files when they stop being authoritative.
- Do not add new SwiftUI feature work under `src/platform/macos/ui/*` unless it is unavoidable bridge code. New cross-platform UI goes under `Sources/WawonaUI`.

## Current Ownership Map

- `src/platform/macos/ui` is now bridge/deprecated UI that is being replaced incrementally by `Sources/WawonaUI`.
- Rust is the source of truth for machine/session/preferences state.
  `Sources/WawonaModel` is migration debt and may only adapt Rust-owned
  snapshots while it is being removed.
- `Sources/WawonaUI` is the source of truth for Machines and Welcome UI; global Wawona Settings UI lives in `src/platform/macos/ui/Settings` (ObjC + AppKit/UIKit).
- `Sources/WawonaWatch` is the watchOS companion app source.
- `src/platform/android/rendering` is the Android-native rendering helper path.
- `dependencies/clients/wawona-shell` holds the first-party shell/launcher sources.
- `dependencies/clients/wawona-tools` holds first-party CLI and validation tools.
