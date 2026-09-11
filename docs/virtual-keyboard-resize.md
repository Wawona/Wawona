# Virtual keyboard resize (`resizeDisplayForVirtualKeyboard`)

When the soft keyboard is visible, Wawona can shrink the Wayland `wl_output`
height so clients lay out above the IME instead of sitting under it:

```
outputHeight = hostVisibleHeight - hostImeHeight - wawonaExtraKeyboardHeight
```

On iOS and iPadOS this also **offsets the present plate** into that exclusive
zone (postmarketOS / Phosh style). The client sits above the OSK. It is not
drawn full-bleed under the keyboard.

## Pref

| Key | Type | Default | Scope |
|-----|------|---------|-------|
| `resizeDisplayForVirtualKeyboard` | bool | `true` | Global Settings → Input |
| `runtimeOverrides.resizeDisplayForVirtualKeyboard` | bool? | inherit global | Per-machine |

Forced off while a hardware keyboard is active (no soft IME).

When the option is **on**: shrink `wl_output` and layout Wayland / Metal layers
in the remaining rect above the OSK (top-aligned exclusive zone).

When the option is **off**: keep full output size. The OSK overlays the client.

### Implementations

| Platform | Status |
|----------|--------|
| **iOS / iPadOS** | Implemented. `WWNCompositorView_ios` reports IME overlap + accessory reserve; `WWNSceneDelegate` subtracts from output height (clamp ≥ 120) using the **per-machine** override when set. Present layers (`_waylandLayer`, `_contentLayer`, `_waylandFrameView`) use the same usable bounds so the UI moves with the OSK. Machine Settings / editor: Input → “Resize Display for Virtual Keyboard”. |
| **Android** | Implemented. Compositor bottom padding = IME inset + accessory bar. Per-machine override via `SettingsOverrides` / `SessionExitSettings.resolvedResizeDisplayForVirtualKeyboard` (machine editor Input toggle). |
| **Linux mobile** | Deferred. Stub/doc only (see below). |

## Linux mobile (deferred)

No Linux code in the current campaign beyond reading a synced pref if present.
Future OSK hooks by stack:

| Stack | OSK | Future hook |
|-------|-----|-------------|
| Phosh | squeekboard / stevia | layer-shell exclusive zone / output configure |
| Plasma Mobile | Maliit | IM geometry from KWin/Maliit |
| SXMO | spawn/kill wvkbd-class OSK | process lifetime → reserved height |
| Ubuntu Touch | Maliit lineage | same IM-geometry approach |
