# Android GuestTerm extract (Phase 4 note)

Status: **note only**. Do not giant-refactor `MainActivity` until Watch
Terminal Sprite present is green and a follow-up PR owns the move.

## Today

`WawonaGuestTerm` lives inside
`android/app/src/main/java/com/aspauldingcode/wawona/TerminalActivity.kt`
(process-wide VT + shell PTY pump). `MainActivity`, `WawonaInputConnection`,
and `TerminalActivity` all call it.

## Goal

Promote `WawonaGuestTerm` (+ `WawonaAndroidTerm` paint) into a dedicated
module / file pair, e.g.:

- `android/.../guestterm/WawonaGuestTerm.kt`
- Keep JNI / UniFFI VT JSON shared with Apple Watch Terminal lines path

## Do not (yet)

- Restructure `MainActivity` Compose tree around Terminal chrome
- Invent a second Android VT beside the existing UniFFI / native term
- Claim GPU Terminal present on Android from this Watch SpriteKit work

## Cross-link

Watch Terminal Sprite present:
`Sources/WawonaWatch/WatchTerminalSpritePresent.swift` (CoreText →
`SKTexture`). Android present stays Compose / OpenGL path per product gates.
