# Keyboard layouts and IME

Wawona does not ship a layout picker. Typing uses the **host** keyboard and
IME, bridged onto Wayland.

Rule: `wawona-host-keymap-bridge`. User copy: wawona.io `/docs/user/keyboard/`.
Epic #60 is closed. Leftover IME proof is #171. #141 stays open for Android OSK spawn.

## What clients see

| Event | Protocol |
|-------|----------|
| Hardware key position (kVK, HID, AKEYCODE) | `wl_keyboard.key` via Smithay |
| Host layout for terminals | `wl_keyboard.keymap` XKB v1 from `HostKeymapBridge` |
| Letters, swipe, CJK, emoji | `zwp_text_input_v3` commit / preedit |
| Enter / Tab / Backspace (TI-unaware terminals) | compositor `inject_key` |
| Nested weston / niri RMLVO | trimmed `XKB_CONFIG_ROOT` (us/evdev) |

## Phase 1 vs last phase

Phase 1: `generate_from_host()` may return the built-in US `MINIMAL_KEYMAP`.
Host IME characters are already correct via TI v3.

Last phase (macOS + Android): regenerate XKB from TIS / `UCKeyTranslate` /
`KeyCharacterMap` when the host layout changes. iOS / iPadOS / visionOS /
tvOS / watchOS have no public TIS dump, so those seats stay on the US
fallback; OSK letters still go through TI v3. Full IME preedit. Still no
Settings list.

## Do not

- Add a language or layout enum in Settings
- Restore `charToLinuxKeycode` / `char_to_linux_keycode`
- Copy all of `xkeyboard-config` into the app for Wawona's own seat
- Treat UI l10n (translated chrome, RTL) as the keymap

## Code

- Trait: `src/core/input/host_keymap.rs`
- Seat: `src/core/wayland/mod.rs` (`set_keymap_from_string`)
- Nested data: `dependencies/libs/xkb-trimmed.nix`
- TI v3: `src/core/wayland/ext/text_input.rs` (StoreSafeCore, Partial)
