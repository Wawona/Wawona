# Android GuestTerm extract (Phase 4)

Status: **done** for the process-wide VT session + Guest Console host
extract. Do not giant-refactor the rest of `MainActivity` Compose chrome
in the same PR.

## Today

| File | Owns |
|------|------|
| `android/.../GuestTermSession.kt` | `WawonaGuestTerm` (PTY pump, window attach, `feedKeys`) |
| `android/.../TerminalGuestHost.kt` | `GuestConsoleOverlay`, `WawonaAndroidTerm`, key/IME helpers |
| `android/.../TerminalActivity.kt` | New-window Activity shell only |
| `Terminal/android/.../WawonaTerminalText.kt` | Compose VT text (sourced via Gradle `kotlin.directories`) |

`MainActivity`, `WawonaInputConnection`, and `TerminalActivity` all call
`WawonaGuestTerm`. Paint uses `WawonaTerminalText` from the Terminal tree.

## Do not (yet)

- Restructure `MainActivity` Compose tree around Terminal chrome beyond this
  extract
- Invent a second Android VT beside the existing UniFFI / native term
- Claim GPU Terminal present on Android from Watch SpriteKit work

## Cross-link

Watch Terminal Sprite present:
`Sources/WawonaWatch/WatchTerminalSpritePresent.swift` (CoreText →
`SKTexture`). Android present stays Compose / OpenGL path per product gates.

Linux sibling split: `src/linux/ui/terminal/` (`session`, `view`, `keys`,
`paint`).
