---
name: wawona-host-keymap
description: Pointer for Wawona keyboard / IME / xkb. Open the host-keymap-bridge rule. Never add a Settings layout picker or a char-to-linux matrix.
---

# Host keymap (pointer)

Open rule `wawona-host-keymap-bridge`. Prose:
`docs/agent-rules/wawona-host-keymap-bridge.md`,
`docs/keyboard-layouts.md`.

## When

Editing `src/core/input/`, `wl_keyboard`, `zwp_text_input_v3`, iOS/Android
OSK inject, Watch keymap, or `xkeyboard-config` packaging.

## Hard rejects (one line)

- Do not add AZERTY/Dvorak/CJK tables in ObjC/C/Kotlin
- Do not add a locale-to-RMLVO table (`KeyboardLayouts.fromLocale`)
- Do not add Settings Keyboard layout
- Do not invent `zwp_wawona_keymap`
- Do not compile a second xkb machine beside Smithay
- Do not dual-register custom TI/IM globals beside Smithay delegates.
  Host IME is the in-process IM-v2 stand-in (`host_im.rs`).
- Do not broadcast custom `wl_touch` while Smithay `TouchHandle` owns the seat
- Do not synthesize `wl_pointer.axis` from Multi-Touch one-finger or two-finger
  drag. Apps get `wl_touch.motion`. Pointer + `BTN_LEFT` only for nested
  weston/niri chrome (or the off-by-default pointer-emulation pref)

Query `wwn-mcp` first.
