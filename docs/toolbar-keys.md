# ToolbarKeys (Terminal + compositor)

L3′ crate: `github.com/Wawona/ToolbarKeys`. Layout document, `apple/Keyboard`
UIKit drawing, and `android/com/wawona/toolbarkeys` Compose chrome. Wawona
owns the Wayland / PTY bridge only. Do not keep a second Toolbar Keys UI tree
in the app.

## Hosts (required)

| Surface | iOS / iPadOS | Android |
|---------|--------------|---------|
| Compositor soft-keyboard focus | `WWNCompositorView_ios.inputAccessoryView` → `WWNKeyboardAccessoryView` | `ToolbarKeysBar` + `ToolbarKeyChrome` (from ToolbarKeys overlay) |
| Wawona Terminal (Start) | `WWNTerminalToolbarHost` first responder + same accessory; shell → PTY | Same bar drawn **above** `GuestConsoleOverlay`; printable echoes into Terminal until Focus |
| Settings / rearrange | `KeyboardToolbarSettingsView` as `.pageSheet` (Done + Edit) | `ToolbarKeysSettingsSheet` ModalBottomSheet (Done + Edit) |
| Global Settings → Input | Same sheet via Customize + docking/appearance toggles | Same sheet + Input section prefs (`wawona_prefs`) |

tvOS / visionOS may omit some UIKit materials. Watch unchanged.

## Host options (Rootshell `Settings.KeyboardToolbar`)

Shared UserDefaults / `wawona_prefs` keys (Rust `ToolbarOptions`):

| Key | Meaning |
|-----|---------|
| `persistentToolbar` | Keep dock when software keyboard dismisses |
| `showToolbarWithHardwareKeyboard` | Keep dock while external keyboard connected |
| `toolbarThemeAware` | Glass follows light/dark (default on) |
| `toolbarChromeStyle` | `flat` / `sculpted` / `steampunk` / `phosphor` / `beige-box` / `neon-grid` / `circuit-board` |
| `arrowJoystickMode` | `joystick` / `cluster` |

Hardware + option off: hide accessory (iOS `inputAccessoryView` nil; Android
`HIDDEN_EXTERNAL`). Hardware + option on: accessory-only dock (`ACCESSORY_ONLY`).

## Rules

- iOS deployment floor **13.0**. Post-13 APIs in `apple/Keyboard` stay `#available`-gated.
- Do not copy ToolbarKeys Swift or Compose into Wawona as a second tree.
  Overlay from flake input `toolbar-keys` (Nix) or sibling `ToolbarKeys/android`
  (Studio `sourceSets`).
- Bridge file: `Sources/WawonaUI/Keyboard/WWNKeyboardAccessoryView.swift`.
- Printable text → `zwp_text_input_v3` (`WWNCoreTextInputCommit` / `nativeCommitText`).
- Esc / Tab / arrows → seat `inject_key` (compositor) or PTY bytes (shell).
- Hardware keyboard docking follows `showToolbarWithHardwareKeyboard` (Rootshell).
- Android chrome must match ToolbarKeys UIKit plate geometry: glass plate, clear
  keys, equal-fill main row, lock bar. No Material `TextButton` chips
  (`ToolbarKeyChrome.kt`). Key faces stay **symbols** (not Ctrl/Alt text):
  ⎋ ⌃ ⌥ ⇧ ◆ (Meta for catalog `cmd`). Never Win ⊞, never Mac ⌘ on Android.
- Ellipsis drawer: UIKit grows `drawerContainer` **above** the main row
  (`main.top = drawer.bottom`). Android Compose must `Column`-stack the same
  way. Never put drawer + main as siblings of a `Box` (that overlays keys).
- Settings: popup sheet like the machine editor (iOS `pageSheet`, Android
  `ModalBottomSheet`). Trailing **Edit** rearranges (iOS EditButton /
  Android drag handles). Sheet dismiss is system (Done leading on iOS;
  swipe handle on Android). Global Settings Input owns docking + chrome;
  Customize opens the same sheet.

## RAG

Indexed summary: `wwn-mcp/knowledge/wawona/toolbar-keys.md`.
