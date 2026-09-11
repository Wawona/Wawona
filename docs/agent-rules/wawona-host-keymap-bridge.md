# Host keymap bridge

Wawona does not own keyboard layouts. It **bridges** the host keymap into
Wayland using existing protocols and existing OS frameworks.

Cursor rule: `wawona-host-keymap-bridge` (`alwaysApply`). Skill pointer:
`wawona-host-keymap`. Product doc: `docs/keyboard-layouts.md`. Site:
wawona.io `/docs/user/keyboard/`.

## Architecture

```text
Host IME / TIS / KeyCharacterMap / HID
  -> HostKeymapBridge
       keymap_xkb_v1()     -> Smithay set_keymap_from_string (wl_keyboard)
       physical_key()      -> inject_key evdev+8
       text (FFI)          -> zwp_text_input_v3 commit / preedit
```

Smithay `Seat::add_keyboard` / `KeyboardHandle::input` is the only seat.
Do not reimplement `xkb_state` or keymap fds in `KeyboardState`.

## Hard rejects

- A Wawona-specific Wayland keymap protocol
- Settings "Keyboard layout" as the source of truth
- Hand-rolled QWERTY matrices (`charToLinuxKeycode`, `char_to_linux_keycode`,
  Kotlin `charToLinuxKeycode`, `WWNWatchKeymap.h`)
- IBus / Fcitx / Maliit as the Apple or Android IME
- Sealing the seat API to a `MINIMAL_KEYMAP` constant (fallback is OK;
  `generate_from_host()` is the type)
- Growing a Wawona enum of languages
- A locale-to-RMLVO table (`KeyboardLayouts.fromLocale`)
- Dual-registering custom TI/IM globals beside Smithay delegates.
  Host IME is the in-process IM-v2 stand-in (`src/core/wayland/host_im.rs`).

## Keep

- HID / macOS kVK / Android AKEYCODE **position** maps (layout-independent)
- `SwapCmdWithAlt` (Apple adapter remap, not an XKB group)
- Touch Input Type / Touchpad Mode (input mode, not layout)
- Trimmed `xkeyboard-config` tree for **nested** weston/niri only
  (`XKB_CONFIG_ROOT`). Wawona's seat does not compile RMLVO from that tree
  as the product path.
- `zwp_text_input_v1` for stock weston-keyboard (named v1 vs v3)
- `zwp_virtual_keyboard_v1` / `zwp_input_method_v2` DesktopOnly on store
  Apple/Android (Linux IBus/Fcitx later)

## Phases

1. **Phase 1:** bridge trait, Smithay seat, delete matrices, trimmed data
   tree, TI v3 catalog Partial/StoreSafeCore. `generate_from_host()` may
   return US `MINIMAL_KEYMAP`.
2. **Last phase:** live regenerate from TIS / `UCKeyTranslate` /
   `KeyCharacterMap` on host layout change (`WWNApplyHostKeyLevels` then
   `WWNCoreReloadHostKeymap`). iOS family has no public TIS dump (US
   fallback). Full IME preedit. No Settings picker. No locale-to-RMLVO
   table.

## Words (do not merge)

- **IME / multilingual input:** typing CJK, Arabic, Indic, dead keys
- **i18n:** compositor accepts any host keymap without a new Wawona table
- **l10n:** Machines/Settings chrome follows host locale. Not a keymap
