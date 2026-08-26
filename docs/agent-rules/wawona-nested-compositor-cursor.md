# Nested compositor cursor (all targets)

A **compositor client** draws `wl_pointer` (and tablet) itself. Wawona must
**hide the host pointer and grab it** while that client is focused. Do not
draw a virtual overlay or the real macOS/Android/iOS cursor on top.

This is **not** Swinging Bridge. Not Desktop Replacement itself.

## Who draws the cursor

| Focused client | Host / virtual cursor | What to do |
|---|---|---|
| Nested Wayland compositor (`weston --backend=wayland`, `niri` nested) | **No** | Hide + grab host pointer. Nested compositor paints its cursor |
| Compositor on **wwn-iland DRM** (`weston --backend=drm`, `niri` `NIRI_BACKEND=tty`, Classic insert) | **No** | Same. iland present does not add a host pointer |
| Non-compositor Wayland client (`weston-terminal`, `foot`, cubes, gtk, …) | **Yes**, if Show Virtual Cursor is on | Host overlay or real pointer. Client may also set `wp_cursor_shape` / cursor surface |

Classify with `profileIndicatesNestedCompositor` / Swift
`nestedCompositorDrawsOwnCursor` (niri, weston compositor, custom nested:
sway, labwc, …). Read `bundledAppID` then `NativeClientId`
(`resolvedNativeIdentityForProfile:`). **Not**
`MachineProfile.isNestedCompositorClient` (Swinging Bridge weston-only).
kmscube / gbm-es2 / vkcube are **not** compositors. Host cursor is allowed.

## Host hide + grab (per target)

While the pointer is over the compositor surface (and restore on leave /
unfocus / Stop):

- **macOS:** hide `NSCursor` (empty cursor rect or `NSCursor hide`). Grab:
  `CGAssociateMouseAndMouseCursorPosition(false)` so the Aqua pointer does
  not roam. Keep injecting seat events so niri/weston can draw.
- **iOS / iPadOS / visionOS / tvOS:** hide the Touchpad `_cursorLayer`
  overlay. Touchpad mode still injects `wl_pointer` so the nested compositor
  can draw. It must **not** show the host arrow. Show Virtual Cursor and
  Nested Compositor Cursor do not unhide it.
- **Android:** hide the virtual-pointer overlay (Touchpad Mode).
- **watchOS:** no host pointer. Nothing to hide.
- **Linux:** hide the GDK/widget cursor on the nested compositor widget.

Still deliver `wl_pointer` / `wl_touch` into the nested compositor. Hide is
**chrome**, not a seat dropout.

## Why Show Virtual Cursor looks like a no-op on weston/niri

`NestedCompositorCursor` defaults to `virtual`. Honoring that on a compositor
machine draws Wawona's overlay on top of weston/niri's own cursor (double
cursor). The leftover pref is **ignored** for nested compositors.
`resolvedShowHostCursorActive` and `resolvedShowVirtualPointerActive` return
NO. Toggling Show Virtual Cursor must hide `_cursorLayer` immediately, not
wait for the next pointer image.

## Hard rejects

- Host overlay or macOS arrow on nested niri/weston
- `NestedCompositorCursor=host` or `=virtual` as a way to put a Wawona
  pointer on a compositor. Ignore it. Do not add new UI that chooses host vs
  virtual for weston/niri.
- Show Virtual Cursor on a compositor machine unhiding `_cursorLayer`
- Drawing Wawona's cursor because the compositor uses iland DRM / Metal
  present (`WWNIlandPresenter`)
- Confusing Multi-Touch (required for many client taps) with "show a
  virtual cursor on niri"

## Code

- Nested compositors: `resolvedShowHostCursorActive` /
  `resolvedShowVirtualPointerActive` are **NO**, even if Show Virtual Cursor
  is on. `WWNView resetCursorRects` takes the hide+grab path.
- iOS family: `_syncHostCursorOverlay` / `_ensureTouchpadCursorVisible` /
  `updateCursorImage` in `src/platform/ios/WWNCompositorView_ios.m`. Observe
  `NSUserDefaultsDidChangeNotification`. Do not leave `_cursorLayer` visible
  after a toggle or after leaving Touchpad.
- Do not apply bitmap/`wp_cursor_shape` host cursors from
  `WWNCompositorBridge` `_applyBitmapCursorFromScene` /
  `handleCursorShapeChanged` onto a compositor toplevel.
- Settings leftovers: `RenderMacOSPointer`, `NestedCompositorCursor` in
  `WWNPreferences.m` / `WWNMachineEditorView.swift` /
  `MachineSettingsView.swift`. Non-compositor only. iOS Settings omit Nested
  Compositor Cursor.

Cursor rule: `wawona-nested-compositor-cursor`. See also
`wawona-compositor-backend`, `wawona-agent-device-multitouch`,
`wawona-native-compositors`.
