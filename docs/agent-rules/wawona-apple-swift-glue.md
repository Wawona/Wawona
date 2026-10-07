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

## Hard rejects

- New `.m` / `.mm` product classes. CI allowlist is empty
  (`scripts/verify-no-objc-glue.py`).
- New `.swift` under `src/platform/{macos,ios,watchos}`.
- `Sources/WawonaApple` files over 400 lines.
- Policy engines duplicated in Swift (prefs, profiles, launch argv).

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
| `Darwin/` | `@main` process entry |
| `src/platform/{macos,ios,watchos}` | Thin `.h` / plain `.c` stubs only |

Android Kotlin/Compose and Linux GTK are unchanged. Upstream C ports
(Weston, Niri, cairo, …) stay C. `chess-for-linux` is out of this gate.

Canonical rules: `wawona-rust-first`, `wawona-uniffi-domain`,
`docs/2026-SOURCE-LAYOUT-RULES.md`.
