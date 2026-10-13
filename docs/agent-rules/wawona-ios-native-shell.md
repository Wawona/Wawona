# iOS Native Shell Start (Wawona Terminal, not a splash)

Authority for **Apple-mobile Native Shell → Terminal** Start. Product name:
**Wawona Terminal** (`wawona-shell`). Not foot. Not weston-terminal.

Canonical backends: `wawona-apple-mobile-mode-a-backends`. Machines kinds:
`wawona-machine-types`. Skill: `wawona-ios-native-shell`.

## Required Start path (iOS / iPadOS / visionOS; same class on tvOS/watch when shell runs)

1. Install / refresh rootfs (`WWNRootfsManager.ensureRootfsInstalled`).
2. `applyShellEnvironment` and set `WAWONA_ZSH_IN_PROCESS=1`,
   `WAWONA_SHELL=/usr/bin/zsh`, `SHELL`, `TERM`.
3. Start in-process shell via `wwn_pty_session_start` (pty forces `-zsh -i`).
4. Pump master → `wwn_term_feed` → `wwn_term_export` → host draw
   (`WawonaTerminalView` / styled lines). Face: bundled DejaVuSansM Nerd Font Mono.
5. Soft keyboard → `wwn_ios_terminal_inject` (not `write` to the master socket).
6. Stop → `wwn_pty_ios_stop_shell_session` then destroy. Fake_pid is not a
   real process; do not rely on `kill` alone.

Code today: `Sources/WawonaApple/Shell/GuestConsoleView.swift` (`IosShellSession`),
`Sources/WawonaUI/Machines/Catalog/WWNIosGuestConsole.swift`. Guest console
notification: `WWNRelayGuestConsoleNeededNotification` with `source=shell`.

## What users confuse

| UI / habit | Reality |
|---|---|
| "weston terminal" on iOS | Often Native Shell → Wawona Terminal. Splash title was "Wawona Terminal". |
| `weston_terminal_main` in the tip binary | `mobile-weston-terminal.c`: fake SHM chrome + cursor block. **No PTY. No zsh.** |
| `launchBundledExecutable` for weston-terminal on iOS | Returns "macOS-only client". Does not start a shell. |

Real weston-terminal (patched `terminal.c` + pty) is optional software / deb path,
not the store Native Shell product.

## Start UI (all machine kinds)

Every machine Start presents **Wawona Terminal** first (`$ argv` + CLI /
host logs). Native Shell uses a live zsh PTY. Waypipe / wasm / client Start
streams launch output into the same Terminal chrome. Close / Done reveals
the compositor (Focus). **No** StartupLog preview card. **No** auto-dismiss
on first frame.

## Hard rejects

- Guest console text **"Native Shell starting"** (or any static splash) as the
  Terminal Start UX
- `StartupLogOverlay` / `WWNStartupLogViewController` preview as Start UI
- Auto-dismiss Terminal on first compositor frame
- `connectNative` no-op for `wawona-shell` while presenting that splash
- Calling `weston_terminal_main` / mobile fake terminal a real shell or a
  substitute for Wawona Terminal
- Writing keyboard bytes only to the PTY master on Apple mobile (use inject)
- Omitting `WAWONA_ZSH_IN_PROCESS` before `wwn_pty_session_start`
- Shipping Terminal UI that cannot show a prompt after Start on a linked tip
  that already exports `wawona_zsh_main` / `wwn_pty_session_start` / `wwn_term_new`
- Putting new shell session types only in brand-new Swift files under
  `Sources/` without proving xcodegen membership (prefer extend an already
  compiled Shell / GuestConsole file). Link contract: `wawona-ios-link-contract`
- iOS 13 API slips in that UI (`Font.TextStyle.caption2` is iOS 14+)

## Incident (2026-10-11)

STARDUST: user started what they called weston terminal; app showed
"Wawona Terminal / Native Shell starting" forever. Cause: stub
`WWNIosGuestConsole` + `wawona-shell` early return. Fix: wire pty + term +
inject; install tip. Device Locked can block launch after install.

## Related

`wawona-optional-software`, `wawona-apple-mobile-mode-a-backends`,
`docs/ios-local-shell/ARCHITECTURE.md`, `wwn-toolchain` `wawona-pty`.
