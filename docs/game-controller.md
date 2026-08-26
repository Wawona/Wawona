# Game Controller Support ([#46](https://github.com/Wawona/Wawona/issues/46))

Status of `GameController.framework` support on Apple (UIKit) platforms.

## Summary

Implemented. Hardware gamepads, `GCMouse`, and `GCKeyboard` presence are handled
by [`WWNGameControllerManager`](../src/platform/ios/WWNGameControllerManager.m),
which maps controller input onto the compositor's virtual pointer through
[`WWNCompositorView_ios`](../src/platform/ios/WWNCompositorView_ios.m). The
manager is started once at app init in
[`main.m`](../src/platform/macos/main.m) (the shared UIKit app delegate used by
the iOS / tvOS / Mac Catalyst targets).

## Input mapping

| Source | Action |
|--------|--------|
| Gamepad A / B | left / right virtual-pointer click |
| Gamepad left stick | move cursor (per-frame sampling via `CADisplayLink`, `kStickCursorSpeed`) |
| Gamepad right stick | scroll (`kStickScrollSpeed`) |
| Gamepad D-pad | fine cursor nudge |
| Siri Remote clickpad / 1st-gen touch surface (`GCMicroGamepad` dpad) | relative virtual pointer (tvOS). Select/click is `UIPressTypeSelect`, not a second GameController click |
| Siri Remote Menu (`buttonMenu`) | same session-exit path as UIKit Menu |
| 1st-gen Siri Remote `GCMotion` | shake-to-exit from `userAcceleration` (no system shake event). 2nd/3rd-gen remotes and `GCProductCategoryControlCenterRemote` (iPhone Apple TV Remote) have no motion |
| `GCMouse` move / buttons / scroll | relative pointer move, left/right/middle click, wheel (API exists; Apple TV does not treat USB mice as a system cursor) |
| `GCKeyboard` | presence tracked only. Key events already flow through UIKit `pressesBegan`/`pressesEnded`, so they are **not** re-injected here (avoids double input) |

Analog sticks use a `kStickDeadzone` and are sampled every frame because
`valueChangedHandler` cannot express a stick held at constant deflection.

## Design notes

- Controller input is intentionally translated to the existing **virtual
  pointer** rather than a Wayland gamepad protocol, so unmodified Wayland
  clients benefit immediately without needing gamepad-aware apps.
- `GCMouse` handlers hop to the main queue before touching the view, since the
  framework may deliver on a background queue.
- The target view is the topmost visible `WWNCompositorView_ios`, so input
  follows the focused client window.

## Remaining gaps / follow-ups

- **Native gamepad protocol.** No Wayland gamepad/joystick protocol is exposed;
  games that expect a real controller (rather than pointer emulation) are not
  yet served. Track separately if a concrete client needs it.
- **AppKit-only macOS.** The manager depends on `WWNCompositorView_ios`
  (`UIView`). It covers the UIKit/Catalyst path; a hypothetical pure-AppKit
  macOS variant would need an `NSView` bridge for the same mappings.
- **Button remapping UI.** Mapping is fixed; no user-facing rebind surface.

## Verification

Connect an MFi/Xbox/DualSense controller (or a `GCMouse`) to an iOS device or
the Simulator's connected controller, open a compositor session, and confirm the
cursor moves and clicks. `WWNLog("GAMEPAD", …)` lines record connect/disconnect
and startup controller count.
