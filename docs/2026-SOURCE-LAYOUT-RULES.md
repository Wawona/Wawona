# Wawona Source Layout Rules

Wawona is organized around a strict ownership split:

- `src/core` contains compositor logic, Wayland protocol handling, scene/state management, and other shared Rust compositor behavior.
- `src/domain` contains profiles, prefs, gates, and launch policy (UniFFI).
- `src/ffi` contains the public C poll ABI (`WWNCore*`) that platform hosts call into. Split by job: `poll`, `input`, `present`, `launch` (plus legacy `c_api` re-exports during cutover).
- `src/platform/android` contains Android JNI glue only.
- `src/linux` contains Linux GTK UI.
- `Sources/WawonaModel` contains the Apple-shared Swift wrapper for machine/session/preferences until UniFFI Swift is imported (`bridging: true`). Rust UniFFI is the schema owner (`docs/agent-rules/wawona-uniffi-domain.md`). Do not add new domain fields only in Swift. Generated UniFFI Swift/Kotlin are Nix `$out/uniffi` (`wawona-nix-generated`). Never commit them under `Sources/` or `android/`.
- `Sources/WawonaUI` contains canonical Apple SwiftUI for machines, welcome, and settings on macOS, iOS, iPadOS, tvOS, and visionOS.
- `Sources/WawonaWatch` contains watchOS SwiftUI screens.
- `Sources/WawonaApple` contains framework glue that is not a screen: Metal/SpriteKit present, seat forward, keymap, lifecycle, shell, Mode B helpers, runners. Calls Rust. No Objective-C classes.
- `Darwin/` contains Apple app `@main` entry and Xcode-facing app metadata.
- `dependencies/clients` contains bundled clients, first-party shell code, and first-party diagnostic tools packaged through Nix.
- `src/resources` contains assets and bundle resources only.

## Guardrails

- Do not add new compositor logic in C, Objective-C, or Kotlin outside `src/platform/android` (JNI) or `src/linux` (GTK).
- Do not reintroduce `src/bin` or `src/launcher`; first-party tools and shell/client code belong under `dependencies/clients`.
- Do not reintroduce duplicate top-level folders that mirror `src/core` concepts.
- Do not add new SwiftUI feature work under `src/platform/macos/ui/*`. New cross-platform UI goes under `Sources/WawonaUI`.
- Do not add new `.swift` under `src/platform/{macos,ios,watchos}`. New Apple glue goes under `Sources/WawonaApple`.
- Do not add Objective-C `.m` / `.mm` product glue. CI `scripts/verify-no-objc-glue.py` ratchets the allowlist downward.
- `Sources/WawonaApple` files stay under 400 lines.

## Current Ownership Map

- Apple product UI and glue: `Sources/WawonaUI`, `Sources/WawonaWatch`,
  `Sources/WawonaApple`, and `Darwin/` (`@main`). No Objective-C classes.
- `src/platform/{macos,ios,watchos}` may keep thin `.h` / plain `.c` ABI stubs
  (bridging header, link stubs). No `.m` / `.mm` and no new `.swift` there.
- `Sources/WawonaModel` wraps machine/session/preferences until the UniFFI lift finishes.
- `Sources/WawonaUI` is the source of truth for Machines and Welcome UI.
- Global Settings + Machines share one SwiftUI sidebar (`WawonaMainWindowView`)
  on macOS, iOS, iPadOS, tvOS, and visionOS. Watch uses `GlobalSettingsCatalog`.
  Android Compose and Linux GTK use the same section order from Rust
  `settings_catalog`.
- `Sources/WawonaWatch` is the watchOS companion app source.
- `src/platform/android/rendering` is the Android-native rendering helper path.
- `dependencies/clients/wawona-shell` holds the first-party shell/launcher sources
  (Swift `NSWorkspace` scanner; no ObjC).
- `dependencies/clients/wawona-tools` holds first-party CLI and validation tools.

## How a change finds a file

- Pref, profile, gate, launch argv: `src/domain/`.
- Pixel present or a gesture: `Sources/WawonaApple/Present` or `Input`.
- Machine card, settings row, welcome: `Sources/WawonaUI/` (Watch: `Sources/WawonaWatch/`).
- Android widget: `android/` or `src/platform/android/`.
- Linux window: `src/linux/`.
- Wayland protocol: `src/core/wayland/`.
