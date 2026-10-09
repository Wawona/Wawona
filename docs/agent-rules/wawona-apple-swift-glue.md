# Apple glue: Rust plus Swift (zero ObjC)

Wawona-owned Apple product code has three layers only:

1. **Rust** owns compositor, profiles, prefs, launch, session, wasm,
   VM/container policy, keymap, shell dispatch.
2. **Swift / SwiftUI** owns AppKit, UIKit, WatchKit, Metal, SpriteKit,
   CarPlay, ScreenCaptureKit, OpenDirectory. Lives in `Sources/WawonaUI`,
   `Sources/WawonaWatch`, `Sources/WawonaApple`, and `Darwin/` (`@main`).
3. **C poll ABI** (`WWNCore*` in `src/ffi/c_api.rs`) stays the compositor
   bridge. Swift calls those symbols. UniFFI owns the product domain only.
   Do not move the frame loop onto UniFFI callbacks.

## Done means (do not claim early)

`scripts/verify-no-objc-glue.py` exits 0 with an **empty allowlist and zero
scanned `.m` files**. An empty allowlist file alone is not done if product
`.m` files still exist on disk. Prior agents overclaimed this cutover.

Darwin CLI argv policy lives in Rust `src/domain/darwin_cli.rs`. Swift
Lifecycle (`WawonaDarwinCLI`, `WawonaLaunchMode`, menubar Desktop row)
applies host ops. Prefer Nix-staged UniFFI (`scripts/stage-uniffi-swift.sh`,
`.nix-deps/uniffi`) and fall back to C trampolines (`WawonaDomainBridge`).

## Hard rejects

- New `.m` / `.mm` product classes. CI allowlist is empty
  (`scripts/verify-no-objc-glue.py`). Claiming done while `.m` remain.
- New `.swift` under `src/platform/{macos,ios,watchos}`.
- `Sources/WawonaApple` files over 400 lines.
- Policy engines duplicated in Swift (prefs, profiles, launch argv,
  client catalog, capability matrix).

## Allowed C

A few-line **C** file is allowed only where the ABI is C (dyld constructor,
CGRect packing, XCTest `@try` trampoline compiled as ObjC dialect). That
file is not an ObjC class (`@interface` / `@implementation` forbidden).

## Layout

| Path | Role |
|---|---|
| `Sources/WawonaUI` | Machines, Welcome, Settings SwiftUI |
| `Sources/WawonaWatch` | Watch screens |
| `Sources/WawonaApple` | Present, Input, Lifecycle, Shell, ModeB, Runners, Settings glue |
| `Darwin/` | `@main` process entry on **macOS and Apple-mobile** app targets |
| `src/platform/{macos,ios,watchos}` | Thin `.h` / plain `.c` stubs only |

`Darwin/Sources/Main.swift` must be in `xcodegen` sources for iOS / iPadOS /
tvOS / visionOS as well as macOS. Mobile uses `UIApplicationMain` (iOS 13
floor). Never leave LC_MAIN to a bundled client archive. Full gate:
`wawona-ios-app-entry`.

Android Kotlin/Compose and Linux GTK are unchanged. Upstream C ports
(Weston, Niri, cairo, …) stay C. `chess-for-linux` is out of this gate.

Canonical rules: `wawona-rust-first`, `wawona-uniffi-domain`,
`wawona-ios-app-entry`, `docs/2026-SOURCE-LAYOUT-RULES.md`.
