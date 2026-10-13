# ToolbarKeys (Terminal + compositor)

L3′ crate: `github.com/Wawona/ToolbarKeys`. Layout document + `apple/Keyboard`
UIKit drawing. Wawona owns the Wayland / PTY bridge only.

## Hosts (required)

| Surface | iOS / iPadOS | Android |
|---------|--------------|---------|
| Compositor soft-keyboard focus | `WWNCompositorView_ios.inputAccessoryView` → `WWNKeyboardAccessoryView` | `ModifierAccessoryBar` in session UI |
| Wawona Terminal (Start) | `WWNTerminalToolbarHost` first responder + same accessory; shell → PTY | Same bar drawn **above** `GuestConsoleOverlay`; printable echoes into Terminal until Focus |

tvOS / visionOS omit ToolbarKeys UIKit (haptics / material). Watch unchanged.

## Rules

- iOS deployment floor **13.0**. Post-13 APIs in `apple/Keyboard` stay `#available`-gated.
- Do not copy ToolbarKeys Swift into `Sources/WawonaUI` as a second tree.
- Bridge file: `Sources/WawonaUI/Keyboard/WWNKeyboardAccessoryView.swift`.
- Printable text → `zwp_text_input_v3` (`WWNCoreTextInputCommit` / `nativeCommitText`).
- Esc / Tab / arrows → seat `inject_key` (compositor) or PTY bytes (shell).
- Hardware keyboard: accessory-only (hide OSK), same idea as Android `ACCESSORY_ONLY`.

## RAG

Indexed summary: `wwn-mcp/knowledge/wawona/toolbar-keys.md`.
