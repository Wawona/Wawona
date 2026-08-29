# Virtual keyboard resize (`resizeDisplayForVirtualKeyboard`)

When the soft keyboard is visible, Wawona can shrink the Wayland `wl_output`
height so clients lay out above the IME instead of sitting under it:

```
outputHeight = hostVisibleHeight - hostImeHeight - wawonaExtraKeyboardHeight
```

## Pref

| Key | Type | Default |
|-----|------|---------|
| `resizeDisplayForVirtualKeyboard` | bool | `true` |

Forced off while a hardware keyboard is active (no soft IME).

### Implementations

| Platform | Status |
|----------|--------|
| **iOS** | Implemented. `WWNCompositorView_ios` reports IME overlap + accessory reserve; `WWNSceneDelegate` subtracts from output height (clamp ≥ 120). Settings: Input → “Resize Display for Virtual Keyboard”. |
| **Android** | Implemented. Compositor bottom padding = IME inset + accessory bar; prefs key matches. |
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
