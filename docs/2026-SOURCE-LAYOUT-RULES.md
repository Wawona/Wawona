# Wawona Source Layout Rules

Wawona is organized around a strict ownership split:

- `src/core` contains compositor logic, Wayland protocol handling, scene/state management, and other shared Rust compositor behavior.
- `src/ffi` contains the public integration boundary that platform hosts call into.
- `src/platform/*` contains platform glue only: native host code, platform UI, platform settings bridges, and native rendering helpers that present Rust-managed state.
- `Sources/WawonaModel` contains the Apple-shared Swift wrapper for machine/session/preferences (`bridging: true`). Rust UniFFI is the intended schema owner (`docs/agent-rules/wawona-uniffi-domain.md`). Do not add new domain fields only in Swift. Generated UniFFI Swift/Kotlin are Nix `$out/uniffi` (`wawona-nix-generated`). Never commit them under `Sources/` or `android/`.
- `Sources/WawonaUI` contains canonical Apple SwiftUI for machines (profiles + per-machine overrides), welcome, and settings **hosting** (`ObjCSettingsHostView` → native `WWNPreferences`).
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
- `Sources/WawonaModel` is the Apple-shared Swift wrap for machine/session/preferences until the UniFFI lift. Rust is the intended source of truth.
- `Sources/WawonaUI` is the source of truth for Machines and Welcome UI.
- Global Settings + Machines share one SwiftUI sidebar (`WawonaMainWindowView`)
  on macOS, iOS, iPadOS, tvOS, and visionOS. Watch uses `GlobalSettingsCatalog`.
  Android Compose and Linux GTK use the same section order. ObjC
  `WWNPreferences` remains the inventory builder and compositor glue.
- `Sources/WawonaWatch` is the watchOS companion app source.
- `src/platform/android/rendering` is the Android-native rendering helper path.
- `dependencies/clients/wawona-shell` holds the first-party shell/launcher sources.
- `dependencies/clients/wawona-tools` holds first-party CLI and validation tools.
