# Welcome alert (all products)

First-launch welcome is one **native alert / dialog** over Machines. Never a
full-screen Welcome page. Copy is identical on every product host.

## Required copy (exact)

| Field | String |
|---|---|
| Title | `Welcome to Wawona` |
| Message | `A Universal Wayland Compositor. Tap '+' to add a Machine.` |
| Dismiss | `Continue` |

Rust authority for the literals: `src/domain/welcome_copy.rs`. Export:

- C: `wawona_welcome_title` / `wawona_welcome_message` / `wawona_welcome_continue`
- UniFFI: `welcome_title` / `welcome_message` / `welcome_continue_label`
- Apple: `WelcomeCopy` via `WawonaDomainBridge` (literal fallback)
- Android: `WelcomeCopy.kt` (must match Rust)
- Linux: `maybe_show_welcome` reads `welcome_copy` directly

## Gate

Show when welcome is unseen **and** the Machines list is empty. Dismiss with
`Continue` only. Apple writes `wawona.pref.hasCompletedWelcome` plus legacy
aliases `HasSeenWelcome` / `hasSeenWelcome` / `hasCompletedWelcome`.

## Hosts

| Target | Host |
|---|---|
| macOS / iOS / iPadOS / tvOS / visionOS | SwiftUI `.alert` (`WelcomeView.swift`) |
| watchOS | SwiftUI `.alert` (`WawonaWatchApp.swift`) |
| Android | Material3 `AlertDialog` (`MainActivity.kt`) |
| Linux | GTK `MessageDialog` (`maybe_show_welcome` in `linux/ui/home.rs`) |

## Hard rejects

- Platform-specific welcome body text (wrist-only, Android-only, etc.)
- Full-screen Welcome route that replaces Machines
- Title or message that omits the `+` Machine cue
- Shipping a host without this alert when profiles are empty / unseen
- Divergent seen-flag keys that leave one host re-showing the alert forever

Canonical rule mirror: `.cursor/rules/wawona-welcome-alert.mdc`.
