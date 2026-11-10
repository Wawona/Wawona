# iOS Native Shell Start (Wawona Terminal, not a splash)

Authority for **Apple-mobile Native Shell → Terminal** Start. Product name:
**Wawona Terminal** (`wawona-shell`). Not foot. Not weston-terminal.

## Why Wawona Terminal exists (Apple)

On **every Apple platform** (iOS / iPadOS / macOS / tvOS / watchOS /
visionOS), Native Shell text must use **host-native selection**: press-and-hold
handles, magnifier, system Copy / Select All. On iOS / iPadOS / visionOS that
is a read-only **`UITextView`** (`WawonaTerminalSelectableText`), not SwiftUI
`Text` + `.textSelection` + `.contextMenu` (those steal long-press and fake a
duplicate highlight). Never a Wayland client surface.

Wayland has no glyph-box selection protocol. Drawing UIKit / AppKit selection
handles on weston-terminal / foot / GTK pixels is **forbidden**
(`host-edit-menu-clipboard`, port fidelity). So the product shell is Wawona
Terminal. Foot and weston-terminal stay optional Wayland software; they do
not replace Native Shell on Apple.

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
   real process; do not rely on `kill` alone. Join **off** the PTY drain
   GCD queue and keep the master pump alive until join returns. Joining on
   the drain queue deadlocks Done / Stop (`zexit`/`savehistfile` fills the
   socketpair while the pump is starved behind `pthread_join`).

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
streams launch output into the same Terminal chrome. **No** StartupLog
preview card.

### Terminal may start Wayland clients (hard)

Wawona Terminal can launch Wayland clients (`wasm chess`, weston, foot, …)
against the host compositor. When a client attaches:

1. Present (Metal / compositor view) opens **automatically**.
2. Terminal chrome is **parked** (hidden). The PTY / shell stays alive.
3. The user must **never** have to tap Done / Close / Focus just to see
   the client.

Done / Close still Focuses Present the same way (park, do not kill shell).
Stop tears down the shell. Mount the session surface on Native Shell Start
so SHM can drain before the first client maps.

**No** auto-dismiss of Terminal on an empty first compositor frame at Start
(that was the old StartupLog / Mode A SHM bug). Auto-reveal is tied to
**Wayland client count rising**, not to Metal present alone.

## Soft exit / visionOS window (2026-11-04)

PTY hangup must **not** toast **"Shell exited."** Host auto-restarts the
in-process shell; crash-loop (≥3 soft exits within 2s) paints
`[session ended]` (same string as Linux `ENDED_NOTICE`).

**visionOS:** Wawona Terminal for shell/SSH always opens a dedicated
terminal scene (`WWNSessionWindowPresenter`). Closing that window or Done
dismisses Terminal and leaves Machines alive. Never force overlay-only
shell on visionOS (system close would quit the only app window).

## Done hang: hist LOCK + main-thread join (2026-11-04, tvOS)

`SHARE_HISTORY` locks with `symlink("$HISTFILE.LOCK" → /pid-<getpid()>/…)`.
In-process zsh's `getpid()` is the Wawona host, so a leftover LOCK never
looks stale (`kill(host, 0)` succeeds). Done then blocks in
`wwn_pty_ios_stop_shell_session` → `pthread_join` while zsh spins in
`lockhistfile` / `savehistfile` (LLDB: main in `__ulock_wait`, shell in
`symlink`).

Required: clear `.zsh_history.LOCK` before stop; `stop(joinOffMain: true)`
from Done / Stop (never join on UI main); Apple-mobile `.zshrc` uses
`APPEND_HISTORY` and `unsetopt SHARE_HISTORY` (not `SHARE_HISTORY`).

## Hard rejects

- Guest console toast **"Shell exited."** on soft EOF / hangup
- visionOS shell/SSH forced `windowed=false` (closes whole app on window X)
- Guest console text **"Native Shell starting"** (or any static splash) as the
  Terminal Start UX
- `StartupLogOverlay` / `WWNStartupLogViewController` preview as Start UI
- Requiring Done / Close / Focus to see a Wayland client started from Terminal
- Killing the shell PTY when parking Terminal for Present (Done / client attach)
- Skipping `mountSessionSurface` on `wawona-shell` Start (clients cannot present)
- Auto-dismiss Terminal on an empty first compositor frame with no client
- `connectNative` no-op for `wawona-shell` while presenting that splash
- Calling `weston_terminal_main` / mobile fake terminal a real shell or a
  substitute for Wawona Terminal
- Replacing Apple Native Shell with foot / weston-terminal (or any Wayland
  terminal) and claiming native text selection
- Overlaying UIKit / AppKit selection handles on Wayland client glyphs to
  "fix" selection in a Wayland terminal
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

## Terminal Done freeze (tvOS, 2026-11-05)

Done froze the app. `IosShellSession.deinit` joined the zsh pthread on the
main thread while zsh was blocked on its history file lock. Rules:

- Never join the shell thread (or call `wwn_pty_ios_stop_shell_session`) on
  main. Teardown runs on a serial stop queue; `deinit` only schedules it.
- `wwn_pty_ios_stop_shell_session` is idempotent behind a mutex. Two stops
  (Done then deinit) must not double-free or double-join.
- zsh rootfs `.zshrc` sets `HIST_FCNTL_LOCK` (no `.zsh_history.LOCK` spin
  after a soft restart).
- tvOS has no on-screen keyboard for the grid. A focusable SwiftUI
  `TextField` (`WWNTvTerminalKeyboardField`) diffs edits into
  `wwn_ios_terminal_inject` bytes (new text, backspace `0x7f`, Return `\r`).
- Prove with 3 Start/Done cycles on a tip tvOS build.
